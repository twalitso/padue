import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/roadside/models/provider.dart';
import 'package:padue/features/roadside/screens/bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/chat_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class ViewProviderProfileScreen extends StatefulWidget {
  final String providerId;
  const ViewProviderProfileScreen({required this.providerId, super.key});

  @override
  State<ViewProviderProfileScreen> createState() => _ViewProviderProfileScreenState();
}

class _ViewProviderProfileScreenState extends State<ViewProviderProfileScreen> with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  Provider? _provider;
  UserProfile? _userProfile;
  Position? _userLocation;
  String? _locationName;
  double? _distance;
  bool _isLoading = true;
  bool _canRate = false;
  int? _selectedRating;
  final _reviewController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAllData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAllData();
    }
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadProvider(),
      _loadUserProfile(),
      _getUserLocation(),
      _checkCanRate(),
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _loadProvider() async {
    final provider = await _firestore.getProviderProfile(widget.providerId);
    if (mounted) setState(() => _provider = provider);
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final profile = await _firestore.getUserProfile(user.uid);
      if (mounted) setState(() => _userProfile = profile);
    }
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return;
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;

      setState(() => _userLocation = position);

      if (_provider?.location != null) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          _provider!.location.latitude,
          _provider!.location.longitude,
        ) / 1000;

        try {
          final placemarks = await placemarkFromCoordinates(
            _provider!.location.latitude,
            _provider!.location.longitude,
          );
          final city = placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? 'Nearby';
          if (mounted) {
            setState(() {
              _distance = distance;
              _locationName = city;
            });
          }
        } catch (_) {
          if (mounted) setState(() => _locationName = 'Nearby');
        }
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _checkCanRate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('requests')
        .where('providerId', isEqualTo: widget.providerId)
        .where('userId', isEqualTo: user.uid)
        .where('status', whereIn: ['closed', 'canceled'])
        .limit(1)
        .get();

    if (mounted) setState(() => _canRate = snapshot.docs.isNotEmpty);
  }

  Future<void> _submitRating() async {
    if (_selectedRating == null || _reviewController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating and write a review')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Add review
      await FirebaseFirestore.instance.collection('provider_reviews').add({
        'providerId': widget.providerId,
        'userId': user.uid,
        'userName': _userProfile?.name ?? 'Anonymous',
        'userPhoto': _userProfile?.profilePicUrl,
        'rating': _selectedRating,
        'review': _reviewController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update provider average
      final reviews = await FirebaseFirestore.instance
          .collection('provider_reviews')
          .where('providerId', isEqualTo: widget.providerId)
          .get();

      if (reviews.docs.isNotEmpty) {
        final total = reviews.docs.fold(0, (sum, doc) => sum + (doc['rating'] as int));
        final average = total / reviews.docs.length;

        await FirebaseFirestore.instance
            .collection('providers')
            .doc(widget.providerId)
            .update({
          'rating': average,
          'reviewCount': reviews.docs.length,
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Thank you! Review submitted'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Clear form & refresh page
      _reviewController.clear();
      setState(() => _selectedRating = null);
      _loadAllData(); // This refreshes everything cleanly
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit review: $e')),
      );
    }
  }

  void _launchMaps() async {
    if (_provider?.location == null) return;
    final lat = _provider!.location.latitude;
    final lng = _provider!.location.longitude;
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openChat() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    var existing = await FirebaseFirestore.instance
        .collection('chat_requests')
        .where('providerId', isEqualTo: widget.providerId)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'accepted'])
        .limit(1)
        .get();

    String chatId;
    if (existing.docs.isNotEmpty) {
      chatId = existing.docs.first.id;
    } else {
      // Create new chat request
    final doc = await FirebaseFirestore.instance.collection('chat_requests').add({
      'providerId': widget.providerId,
      'userId': userId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadCount': 1, // new chat counts as 1 unread
    });
    chatId = doc.id;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(requestId: chatId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _provider == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFFF6200),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBarWidget(
        title: _provider!.name,
        profilePicUrl: _userProfile?.profilePicUrl,
        showNotifications: true,
        isProvider: false,
       
      ),
      drawer: AppBarWidget.buildDrawer(context: context, isProvider: false),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF6200), Color(0xFFFF8A50)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Hero Avatar
                Hero(
                  tag: 'provider-${widget.providerId}',
                  child: CircleAvatar(
                    radius: 70,
                    backgroundImage: _provider!.profilePicUrl != null
                        ? CachedNetworkImageProvider(_provider!.profilePicUrl!)
                        : const AssetImage('assets/default_provider.png') as ImageProvider,
                  ),
                ).animate().scale(duration: 800.ms, curve: Curves.elasticOut),

                const SizedBox(height: 20),
                Text(
                  _provider!.name,
                  style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 28),
                    const SizedBox(width: 8),
                    Text(
                      _provider!.rating != null ? _provider!.rating!.toStringAsFixed(1) : 'No ratings',
                      style: GoogleFonts.poppins(fontSize: 20, color: Colors.white),
                    ),
                 //   Text(' (${_provider!.reviewCount ?? 0} reviews)', style: GoogleFonts.poppins(color: Colors.white70)),
                  ],
                ),

                const SizedBox(height: 20),

                // Info Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Column(
                    children: [
                      if (_provider!.description != null) ...[
                        Text(_provider!.description!, style: GoogleFonts.poppins(fontSize: 16)),
                        const SizedBox(height: 20),
                      ],

                      _infoRow(Icons.build, 'Service', _provider!.type),
                      _infoRow(Icons.verified, 'Status', _provider!.isVerified ? 'Verified Provider' : 'Unverified', color: _provider!.isVerified ? Colors.green : Colors.orange),
                      _infoRow(Icons.location_on, 'Location', _locationName ?? 'Loading...', suffix: _distance != null ? ' • ${_distance!.toStringAsFixed(1)} km away' : ''),

                      if (_provider!.address != null)
                        _infoRow(Icons.home, 'Address', _provider!.address!),

                      const SizedBox(height: 20),

                      // Map
                      if (_provider!.location != null) ...[
                        Container(
                          height: 200,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: LatLng(_provider!.location.latitude, _provider!.location.longitude),
                                initialZoom: 15,
                              ),
                              children: [
                                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                                MarkerLayer(markers: [
                                  Marker(
                                    point: LatLng(_provider!.location.latitude, _provider!.location.longitude),
                                    width: 60,
                                    height: 60,
                                    child: const Icon(Icons.location_pin, color: Colors.red, size: 50),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _launchMaps,
                          icon: const Icon(Icons.directions, color: Color(0xFFFF6200)),
                          label: const Text('Get Directions', style: TextStyle(color: Color(0xFFFF6200))),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Services
                      Wrap(
                        spacing: 8,
                        children: _provider!.servicesOffered.map((s) => Chip(
                          label: Text(s, style: const TextStyle(color: Colors.white)),
                          backgroundColor: const Color(0xFFFF6200),
                        )).toList(),
                      ),

                      const SizedBox(height: 30),

                      // Action Buttons
                      ElevatedButton.icon(
                        onPressed: _openChat,
                        icon: const Icon(Icons.chat_bubble, size: 28),
                        label: Text('Chat with ${_provider!.name.split(' ').first}', style: GoogleFonts.poppins(fontSize: 18)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6200),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3),

                const SizedBox(height: 20),

                // Reviews Section - NOW WORKS PERFECTLY
                _buildReviewsSection(),

                const SizedBox(height: 20),

                // Rating Form
                if (_canRate) _buildRatingForm(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 2, isProvider: false),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {String suffix = '', Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color ?? const Color(0xFFFF6200)),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.black87),
                children: [
                  TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: value),
                  TextSpan(text: suffix, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Reviews', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('provider_reviews')
                  .where('providerId', isEqualTo: widget.providerId)
                  .orderBy('timestamp', descending: true)
                  .limit(10)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Text('No reviews yet. Be the first!', style: TextStyle(color: Colors.grey));
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                    final timeAgo = timestamp != null ? timeago.format(timestamp) : 'Just now';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: data['userPhoto'] != null
                            ? NetworkImage(data['userPhoto'])
                            : const AssetImage('assets/default_profile.png') as ImageProvider,
                      ),
                      title: Text(data['userName'] ?? 'Anonymous', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: List.generate(5, (i) => Icon(
                              i < (data['rating'] as int) ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 16,
                            )),
                          ),
                          Text(data['review'] ?? ''),
                          Text(timeAgo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ).animate().fadeIn(delay: (index * 100).ms);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingForm() {
    return Card(
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Rate Your Experience', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => IconButton(
                icon: Icon(
                  i < (_selectedRating ?? 0) ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 40,
                ),
                onPressed: () => setState(() => _selectedRating = i + 1),
              )),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reviewController,
              decoration: InputDecoration(
                hintText: 'Share your experience...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _submitRating,
              icon: const Icon(Icons.send),
              label: const Text('Submit Review'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _reviewController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}