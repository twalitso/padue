import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:padue/core/utils.dart';
import 'package:padue/features/roadside/screens/view_provider_profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/firestore_service.dart';
import '../models/provider.dart';
import 'chat_screen.dart';
import 'provider_profile_screen.dart';

class BrowseProvidersScreen extends StatefulWidget {
  const BrowseProvidersScreen({super.key});

  @override
  _BrowseProvidersScreenState createState() => _BrowseProvidersScreenState();
}

class _BrowseProvidersScreenState extends State<BrowseProvidersScreen>  with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  String? _selectedCategory;
  Position? _userLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _getUserLocation();
    updateLastActive();
  }
 @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data or resources

  _getUserLocation();
    updateLastActive();
    }
  }

  @override
  void dispose() {
   
     WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location services are disabled')));
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return;
      }
      _userLocation = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() {});
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  void _callProvider(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No phone number available')));
      return;
    }
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot make call')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Browse Providers'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.blue, Colors.blueAccent]),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.getServiceOptions(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red));
                  }
                  if (!snapshot.hasData) {
                    return CircularProgressIndicator();
                  }
                  var categories = snapshot.data!.docs
                      .map((doc) => (doc.data() as Map<String, dynamic>)['category'] as String?)
                      .where((cat) => cat != null && cat.isNotEmpty)
                      .cast<String>()
                      .toSet()
                      .toList();
                  if (categories.isEmpty) {
                    categories = ['No categories found'];
                  } else {
                    categories.insert(0, 'All');
                  }
                  return DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    hint: Text('Filter by Category'),
                    items: categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                    onChanged: (value) => setState(() => _selectedCategory = value == 'All' ? null : value),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _selectedCategory == null
                    ? _firestore.getAllProviders()
                    : _firestore.getProvidersByCategory(_selectedCategory!),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.red)));
                  }
                  if (!snapshot.hasData) {
                    return Center(child: CircularProgressIndicator());
                  }
                  var providers = snapshot.data!.docs.map((doc) {
                    try {
                      return Provider.fromFirestore(doc);
                    } catch (e) {
                      print('Error parsing provider ${doc.id}: $e');
                      return null;
                    }
                  }).where((provider) => provider != null).cast<Provider>().toList();

                  if (providers.isEmpty) {
                    return Center(child: Text('No providers available', style: Theme.of(context).textTheme.bodyLarge));
                  }

                  if (_userLocation != null) {
                    providers.sort((a, b) {
                      double distA = Geolocator.distanceBetween(
                        _userLocation!.latitude,
                        _userLocation!.longitude,
                        a.location.latitude,
                        a.location.longitude,
                      );
                      double distB = Geolocator.distanceBetween(
                        _userLocation!.latitude,
                        _userLocation!.longitude,
                        b.location.latitude,
                        b.location.longitude,
                      );
                      return distA.compareTo(distB);
                    });
                  }

                  return ListView.builder(
                    itemCount: providers.length,
                    itemBuilder: (context, index) {
                      var provider = providers[index];
                      double distance = _userLocation != null
                          ? Geolocator.distanceBetween(
                                _userLocation!.latitude,
                                _userLocation!.longitude,
                                provider.location.latitude,
                                provider.location.longitude,
                              ) / 1000
                          : double.infinity;
                      return Card(
                        margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundImage: provider.profilePicUrl != null
                                    ? NetworkImage(provider.profilePicUrl!)
                                    : AssetImage('assets/default_profile.png') as ImageProvider,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      provider.name ?? 'Unnamed Provider',
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue[800],
                                          ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Distance: ${distance == double.infinity ? "Unknown" : "${distance.toStringAsFixed(1)} km"}',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    Text(
                                      'Rating: ${provider.rating?.toStringAsFixed(1) ?? "N/A"}',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    Text(
                                      'Verified: ${provider.isVerified ? "Yes" : "No"}',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.phone, color: Colors.green),
                                    onPressed: () => _callProvider(provider.phoneNumber),
                                    tooltip: 'Call Provider',
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.chat, color: Colors.blue),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatScreen(requestId: null, providerId: provider.id),
                                      ),
                                    ),
                                    tooltip: 'Chat with Provider',
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.person, color: Colors.blue),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ViewProviderProfileScreen(providerId: provider.id),
                                      ),
                                    ),
                                    tooltip: 'View Profile',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.request_page), label: 'Request'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Browse'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: 1,
        selectedItemColor: Colors.blue,
        onTap: (index) {
          if (index == 0) Navigator.pushNamed(context, '/request');
          if (index == 2) Navigator.pushNamed(context, '/profile');
        },
      ),
    );
  }
}