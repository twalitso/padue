import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:animations/animations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/features/roadside/screens/provider_profile_screen.dart';
import 'dart:io';
import '../../../core/firestore_service.dart';
import '../../roadside/models/provider.dart';
import 'chat_screen.dart';

class ProviderDashboard extends StatefulWidget {
  @override
  _ProviderDashboardState createState() => _ProviderDashboardState();
}

class _ProviderDashboardState extends State<ProviderDashboard> {
  final _firestore = FirestoreService();
  Provider? _provider;
  File? _document;
  Position? _providerLocation;
  double? _averageRating;
  Map<String, dynamic>? _analytics;
  BannerAd? _bannerAd;
  String? _profilePicUrl;


  bool _isAdFree = false;

  @override
  void initState() {
    super.initState();
    _loadProvider();
    _getProviderLocation();
     _loadProfilePic();
    _loadAd();
  }

 // In ProviderDashboard._loadProvider
Future<void> _loadProvider() async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    _provider = await _firestore.getProviderProfile(user.uid);
    _averageRating = await _firestore.getProviderAverageRating(user.uid);
    _analytics = await _firestore.getProviderAnalytics(user.uid);
    _isAdFree = await _firestore.isAdFree(user.uid);
    if (_providerLocation != null) {
      await _firestore.updateProviderProfile(user.uid, {
        'lastKnownLocation': {'latitude': _providerLocation!.latitude, 'longitude': _providerLocation!.longitude},
      });
    }
    setState(() {});
  }
}

  Future<void> _getProviderLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enable location services')));
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    _providerLocation = await Geolocator.getCurrentPosition();
    setState(() {});
  }

  Future<void> _pickDocument() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _document = File(pickedFile.path));
      await _uploadDocument();
    }
  }

  Future<void> _uploadDocument() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && _document != null) {
      String documentUrl = await _firestore.uploadProviderDocument(user.uid, _document!);
      final updatedProfile = {
        'id': user.uid,
        'name': _provider!.name,
        'type': _provider!.type,
        'documentUrl': documentUrl,
        'isVerified': false,
      };
      await _firestore.updateProviderProfile(user.uid, updatedProfile);
      _provider = await _firestore.getProviderProfile(user.uid);
      setState(() {});
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
        'providerId': user.uid,
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance
          .collection('analytics')
          .doc('requests')
          .collection('records')
          .doc(requestId)
          .update({
        'providerId': user.uid,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      var requestDoc = await FirebaseFirestore.instance.collection('requests').doc(requestId).get();
      var userId = requestDoc.data()!['userId'] as String;
      await _firestore.sendNotification(
        userId,
        'Request Accepted',
        'Your request for ${requestDoc.data()!['issue']} has been accepted by ${_provider!.name}.',
      );
      setState(() {});
    }
  }

  void _showReportDialog(String userId) {
    final _reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report User', style: Theme.of(context).textTheme.headlineMedium),
        content: TextField(
          controller: _reasonController,
          decoration: InputDecoration(
            labelText: 'Reason for reporting',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              User? user = FirebaseAuth.instance.currentUser;
              if (user != null && _reasonController.text.trim().isNotEmpty) {
                await _firestore.submitReport(
                  user.uid,
                  userId,
                  _reasonController.text.trim(),
                  'user',
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Report submitted!')),
                );
              }
            },
            child: Text('Submit'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Test banner ID
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() {}),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          print('Ad failed to load: $error');
        },
      ),
    );
    _bannerAd!.load();
  }
    // Load the profile picture from Firestore
  Future<void> _loadProfilePic() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _profilePicUrl = await _firestore.getProfilePicUrl(user.uid);
      setState(() {});
    }
  }
 // Function to open the Profile screen
  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProviderProfileScreen()),
    );
  }
  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Provider Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.monetization_on),
            onPressed: () => Navigator.pushNamed(context, '/subscription'),
            tooltip: 'Manage Subscription',
          ),
        ],
      ),
      body: _provider == null || _providerLocation == null
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Welcome, ${_provider!.name}', style: Theme.of(context).textTheme.headlineMedium),
                               SizedBox(height: 20),
            
            // Profile Picture (Placeholder if not available)
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _profilePicUrl != null
                    ? NetworkImage(_profilePicUrl!)
                    : AssetImage('assets/default_profile.png') as ImageProvider,
                child: _profilePicUrl == null ? Icon(Icons.person, size: 50) : null,
              ),
            ),
                                SizedBox(height: 8),
                                Text('Type: ${_provider!.type}', style: Theme.of(context).textTheme.bodyMedium),
                                Text('Verification: ${_provider!.isVerified ? "Verified" : "Unverified"}',
                                    style: Theme.of(context).textTheme.bodySmall),
                                Text('Average Rating: ${_averageRating?.toStringAsFixed(1) ?? "No ratings yet"} / 5',
                                    style: Theme.of(context).textTheme.bodyMedium),
                                if (!_provider!.isVerified) ...[
                                 SizedBox(height: 20),

            // Button to navigate to the Profile screen
            ElevatedButton(
              onPressed: _navigateToProfile,
              child: Text('View Profile'),
            ),
                                  SizedBox(height: 16),
                                  ScaleTransition(
                                    scale: CurvedAnimation(
                                      parent: ModalRoute.of(context)!.animation!,
                                      curve: Curves.easeInOut,
                                    ),
                                    child: ElevatedButton.icon(
                                      icon: Icon(Icons.upload),
                                      label: Text('Upload Verification Document'),
                                      onPressed: _pickDocument,
                                    ),
                                  ),
                                  if (_provider!.documentUrl != null)
                                    Text('Document uploaded, awaiting approval',
                                        style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Performance Analytics', style: Theme.of(context).textTheme.headlineMedium),
                                SizedBox(height: 8),
                                if (_analytics == null)
                                  CircularProgressIndicator()
                                else ...[
                                  Text(
                                    'Avg Response Time: ${_analytics!['avgResponseTime'].toStringAsFixed(1)} mins',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  Text(
                                    'Avg Service Time: ${_analytics!['avgServiceTime'].toStringAsFixed(1)} mins',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  Text(
                                    'Reports Against You: ${_analytics!['reportCount']}',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: _analytics!['reportCount'] > 0 ? Colors.red : Colors.black87,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        Text('Open Requests Nearby (10 km)', style: Theme.of(context).textTheme.headlineMedium),
                        SizedBox(height: 8),
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _firestore.getNearbyRequests(_provider!.id, _providerLocation!),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                            var requests = snapshot.data!;
                            if (requests.isEmpty) {
                              return Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No open requests within 10 km',
                                    style: Theme.of(context).textTheme.bodyMedium),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              itemCount: requests.length,
                              itemBuilder: (context, index) {
                                var request = requests[index];
                                var requestId = request['id'] as String;
                                var userId = request['userId'] as String;
                                bool isAccepted = request['providerId'] == _provider!.id && request['status'] == 'accepted';
                                var requestLocation = request['location'] as GeoPoint;
                                bool isPriority = request['isPriority'] ?? false;
                                double distanceInKm = Geolocator.distanceBetween(
                                  _providerLocation!.latitude,
                                  _providerLocation!.longitude,
                                  requestLocation.latitude,
                                  requestLocation.longitude,
                                ) / 1000;
                                return Card(
                                  margin: EdgeInsets.symmetric(vertical: 8),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  color: isPriority ? Colors.orange[50] : null,
                                  child: ListTile(
                                    title: Text(
                                      request['issue'],
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontWeight: isPriority ? FontWeight.bold : FontWeight.normal,
                                          ),
                                    ),
                                    subtitle: Text(
                                      'Location: ${request['locationDescription'] ?? "N/A"} (${distanceInKm.toStringAsFixed(1)} km)${isPriority ? " - Priority" : ""}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isAccepted) ...[
                                          ScaleTransition(
                                            scale: CurvedAnimation(
                                              parent: ModalRoute.of(context)!.animation!,
                                              curve: Curves.easeInOut,
                                            ),
                                            child: ElevatedButton.icon(
                                              icon: Icon(Icons.chat),
                                              label: Text('Chat'),
                                              onPressed: () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => ChatScreen(requestId: requestId),
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          ScaleTransition(
                                            scale: CurvedAnimation(
                                              parent: ModalRoute.of(context)!.animation!,
                                              curve: Curves.easeInOut,
                                            ),
                                            child: ElevatedButton.icon(
                                              icon: Icon(Icons.report),
                                              label: Text('Report'),
                                              onPressed: () => _showReportDialog(userId),
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                            ),
                                          ),
                                        ] else
                                          ScaleTransition(
                                            scale: CurvedAnimation(
                                              parent: ModalRoute.of(context)!.animation!,
                                              curve: Curves.easeInOut,
                                            ),
                                            child: ElevatedButton.icon(
                                              icon: Icon(Icons.check),
                                              label: Text('Accept'),
                                              onPressed: () => _acceptRequest(requestId),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_isAdFree && _bannerAd != null)
                  Container(
                    alignment: Alignment.center,
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
              ],
            ),
    );
  }
}