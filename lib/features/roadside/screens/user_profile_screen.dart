import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/roadside/models/provider.dart';
import 'package:padue/features/roadside/screens/bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/provider_bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/subscription_screen.dart';
import '../../../core/firestore_service.dart';
import 'chat_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
 

  const UserProfileScreen({required this.userId, super.key});

  @override
  _UserProfileScreenState createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  Map<String, dynamic>? _userDetails;
  double? _averageRating;
  int? _rating;
  final _reviewController = TextEditingController();
  Position? _userLocation;
  String? _profileLocationName;
   dynamic profile;
  String? profilePicUrl;
   bool _isProviderUser = false;
   
  double? _distance;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadUserDetails();
    _loadProfile();
    await _loadAverageRating();
    await _getUserLocation();
    setState(() => _isLoading = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadUserDetails();
      _loadAverageRating();
      _getUserLocation();
    }
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services disabled')));
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
          return;
        }
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() => _userLocation = position);
        if (_userDetails?['location'] != null) {
          await _calculateDistanceAndLocationName();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
      }
    }
  }

  Future<void> _calculateDistanceAndLocationName() async {
    if (_userLocation == null || _userDetails?['location'] == null) return;
    final GeoPoint location = _userDetails!['location'] as GeoPoint;
    final distance = Geolocator.distanceBetween(
      _userLocation!.latitude,
      _userLocation!.longitude,
      location.latitude,
      location.longitude,
    ) / 1000;

    try {
      final placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
      if (placemarks.isNotEmpty && mounted) {
        final city = placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? 'Unknown';
        setState(() {
          _distance = distance;
          _profileLocationName = city;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _profileLocationName = 'Unknown');
      }
    }
  }


 Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isLoading = true);
    final providerDoc =
        await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();
    if (providerDoc.exists && mounted) {
      final provider = Provider.fromFirestore(providerDoc);
      final providerProfile = await _firestore.getProviderProfile(user.uid);
      setState(() {
        _isProviderUser = true;
      //  _isAdFree = provider.adFree;
        _isLoading = false;
        profile = providerProfile;
        profilePicUrl = providerProfile?.profilePicUrl ?? provider.profilePicUrl;
      });
    } else {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userProfile = await _firestore.getUserProfile(user.uid);
      setState(() {
        _isProviderUser = false;
      //  _isAdFree = userDoc.exists ? (userDoc.data()?['adFree'] ?? false) : false;
        _isLoading = false;
        profile = userProfile;
        profilePicUrl = profile?.profilePicUrl;
      });
    }
  }

  Future<void> _loadUserDetails() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (doc.exists && mounted) {
        setState(() {
          _userDetails = doc.data();
        });
        if (_userLocation != null && _userDetails?['location'] != null) {
          await _calculateDistanceAndLocationName();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading user details: $e')));
      }
    }
  }

  Future<void> _loadAverageRating() async {
    try {
      final reviews = await FirebaseFirestore.instance
          .collection('user_reviews')
          .where('userId', isEqualTo: widget.userId)
          .get();
      if (reviews.docs.isNotEmpty && mounted) {
        final total = reviews.docs.fold<double>(0, (sum, doc) => sum + (doc['rating'] as num));
        setState(() {
          _averageRating = total / reviews.docs.length;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading rating: $e')));
      }
    }
  }

  Future<void> _submitRating() async {
    if (_rating == null || _reviewController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide a rating and review')));
      return;
    }

    try {
      final providerId = FirebaseAuth.instance.currentUser?.uid;
      if (providerId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not authenticated')));
        return;
      }

      await FirebaseFirestore.instance.collection('user_reviews').add({
        'userId': widget.userId,
        'providerId': providerId,
        'rating': _rating!,
        'review': _reviewController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      final reviews = await FirebaseFirestore.instance
          .collection('user_reviews')
          .where('userId', isEqualTo: widget.userId)
          .get();
      final total = reviews.docs.fold<double>(0, (sum, doc) => sum + (doc['rating'] as num));
      final newAverage = total / reviews.docs.length;

      await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
        'averageRating': newAverage,
        'reviewCount': reviews.docs.length,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Review submitted!')));
        setState(() => _averageRating = newAverage);
         Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => UserProfileScreen(   // ← CHANGE THIS TO YOUR ACTUAL SCREEN
        userId: widget.userId,
        // pass any other required params
      ),
    ),
  );
        //Navigator.pop(context);
        setState(() => _isLoading = false);
        
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit review: $e')));
      }
    }
  }

  Future<void> _openOrCreateChat(String providerId, String userId) async {
    try {
      final existingChat = await FirebaseFirestore.instance
          .collection('chat_requests')
          .where('providerId', isEqualTo: providerId)
          .where('userId', isEqualTo: userId)
          .where('status', whereIn: ['pending', 'accepted'])
          .limit(1)
          .get();

      String chatId;
      if (existingChat.docs.isNotEmpty) {
        chatId = existingChat.docs.first.id;
      } else {

         // Create new chat request
    final doc = await FirebaseFirestore.instance.collection('chat_requests').add({
      'providerId': providerId,
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
        Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(requestId: chatId)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to open chat')));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reviewController.dispose();
    super.dispose();
  }

  Widget _buildSubscriptionButton() {
    return Semantics(
      label: 'Go to Subscription',
      child: ElevatedButton.icon(
        icon: const Icon(Icons.star, color: Colors.white),
        label: Text(
          'Go Ad-Free',
          style: GoogleFonts.poppins(fontSize: 16, color: Colors.white),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF26A69A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shadowColor: Colors.black.withOpacity(0.3),
          elevation: 5,
        ),
      ).animate().fadeIn(duration: 600.ms).scale(duration: 800.ms, curve: Curves.bounceOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userDetails == null || _isLoading) {
      return Scaffold(
      
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF26A69A))),
      );
    }

    return Scaffold(

 appBar: AppBarWidget(
           title:  '${_userDetails!['name'] ?? 'User'}’s Profile',
        profilePicUrl: profile?.profilePicUrl,
        showNotifications: true,
       isProvider: _isProviderUser,
        ),
        drawer: AppBarWidget.buildDrawer(
        context: context,
        isProvider:_isProviderUser,
      ),

   //   appBar: _buildAppBar(context, '${_userDetails!['name'] ?? 'Unknown'}’s Profile'),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE6F0FA), Color(0xFFF3E8FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF26A69A).withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 60,
                          backgroundImage: _userDetails!['profilePicUrl'] != null
                              ? NetworkImage(_userDetails!['profilePicUrl'] as String)
                              : const AssetImage('assets/default_profile.png') as ImageProvider,
                          backgroundColor: Colors.grey[200],
                        ).animate().scale(duration: 800.ms, curve: Curves.bounceOut),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          _userDetails!['name'] as String? ?? 'Unknown',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1F2A44),
                          ),
                        ),
                      ).animate().fadeIn(duration: 400.ms),
                      const SizedBox(height: 8),
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 20),
                            const SizedBox(width: 4),
                            Text(
                              _averageRating != null ? _averageRating!.toStringAsFixed(1) : 'No ratings yet',
                              style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFF26A69A)),
                      const SizedBox(height: 12),
                      Semantics(
                        label: 'Phone Number',
                        child: Row(
                          children: [
                            const Icon(Icons.phone, color: Color(0xFF26A69A), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Phone: ${_userDetails!['phoneNumber'] as String? ?? 'Not provided'}',
                                style: GoogleFonts.poppins(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 150.ms),
                      const SizedBox(height: 12),
                      Semantics(
                        label: 'Location',
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Location: ${_profileLocationName ?? 'Fetching...'} ${_distance != null ? '(${_distance!.toStringAsFixed(1)} km away)' : ''}',
                                style: GoogleFonts.poppins(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                      const SizedBox(height: 20),
                      Semantics(
                        label: 'Chat with User',
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.chat, color: Colors.white),
                          label: Text('Chat', style: GoogleFonts.poppins(fontSize: 16, color: Colors.white)),
                          onPressed: () {
                            final providerId = FirebaseAuth.instance.currentUser?.uid;
                            if (providerId != null) {
                              _openOrCreateChat(providerId, widget.userId);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('User not authenticated')));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF5252),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 250.ms),
                    
                      const SizedBox(height: 20),
                      const Divider(color: Color(0xFF26A69A)),
                      const SizedBox(height: 12),
                      Text(
                        'Rate this User',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1F2A44),
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
                      const SizedBox(height: 8),
                      Semantics(
                        label: 'Rating Stars',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (index) {
                            return IconButton(
                              icon: Icon(
                                index < (_rating ?? 0) ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                                size: 32,
                              ),
                              onPressed: () => setState(() => _rating = index + 1),
                            );
                          }),
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 350.ms),
                      const SizedBox(height: 12),
                      Semantics(
                        label: 'Review Input',
                        child: TextField(
                          controller: _reviewController,
                          decoration: InputDecoration(
                            labelText: 'Your Review',
                            hintText: 'How was your interaction?',
                            prefixIcon: const Icon(Icons.comment, color: Color(0xFF26A69A)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          maxLines: 3,
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
                      const SizedBox(height: 20),
                      Semantics(
                        label: 'Submit Review',
                        child: Center(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.send, color: Colors.white),
                            label: Text('Submit Review', style: GoogleFonts.poppins(fontSize: 16, color: Colors.white)),
                            onPressed: _submitRating,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFFFF5252),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                            ),
                          ),
                        ),
                      ).animate().fadeIn(duration: 400.ms, delay: 450.ms),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
     //
     //
     //
     //  bottomNavigationBar: _isProviderUser ? const ProviderBottomNavBar(currentIndex: -1) : const BottomNavBar(currentIndex: -1,isProvider: false,),
    );
  }

  AppBar _buildAppBar(BuildContext context, String title) {
    return AppBar(
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
          fontSize: 22,
          color: Colors.white,
        ),
      ),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E3A8A), Color(0xFF7C3AED)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }
}