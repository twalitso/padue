import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/utils.dart';
import 'package:padue/features/auth/screens/user_login_screen.dart';
import 'package:padue/features/roadside/screens/inbox_screen.dart';
import 'package:padue/features/roadside/screens/notifications_screen.dart';
import '../../../core/firestore_service.dart';

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});

  @override
  _RequestScreenState createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  String? _selectedService;
  String _locationDescription = '';
  String _notes = '';
  InterstitialAd? _interstitialAd;
  BannerAd? _bannerAd;
  bool _isAdFree = false;
  bool _isSubmitting = false;
  bool _isBannerAdLoaded = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserStatus();
    _loadInterstitialAd();
    _loadBannerAd();
    updateLastActive();
   _setupNotifications();
    saveFcmToken(); // From utils.dart
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null && mounted) {
        _showNotification(message);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('App resumed, reloading data in RequestScreen...');
      _loadUserStatus();
      _loadInterstitialAd();
      _loadBannerAd();
      updateLastActive();
      saveFcmToken(); // From utils.dart
      if (mounted) setState(() {});
    }
  }




  Future<void> _setupNotifications() async {
    const channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
    );
    await _notificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (details) {
        final data = jsonDecode(details.payload ?? '{}');
        if (data['type'] == 'request') {
          Navigator.pushNamed(context, '/request_status');
        } else if (data['type'] == 'message') {
          Navigator.push(context, MaterialPageRoute(builder: (context) => InboxScreen(isProvider: false)));
        }
      },
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
 Stream<int> _getUnreadNotificationsCount() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(0);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('notifications')
      .where('read', isEqualTo: false)
      .where('type', isNotEqualTo: 'message')
      .orderBy('type')
      .snapshots()
      .map((snapshot) => snapshot.docs.length)
      .handleError((e) {
        print('Error in unread notifications count: $e');
        return 0;
      });
}

  void _showNotification(RemoteMessage message) {
    final notification = message.notification!;
    _notificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }
  Future<void> _loadUserStatus() async {
    if (!mounted) return;
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _isAdFree = await _firestore.isAdFree(user.uid);
        if (mounted) setState(() {});
      }
    } catch (e) {
      print('Error loading user status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load user status: $e')));
      }
    }
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdmobConfig().getAdUnitId('interstitial') ?? 'ca-app-pub-3940256099942544/1033173712',
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad
          ..fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
          ),
        onAdFailedToLoad: (error) => print('Interstitial ad failed: $error'),
      ),
    );
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdmobConfig().getAdUnitId('banner') ?? 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdLoaded = true),
        onAdFailedToLoad: (ad, error) {
          print('Banner ad failed to load: $error');
          ad.dispose();
        },
      ),
    );
    _bannerAd!.load();
  }

  Future<void> _submitRequest() async {
    if (!mounted || _isSubmitting || _selectedService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select a service')),
        );
      }
      return;
    }
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User not logged in')));
      }
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services disabled');
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          throw Exception('Location permission denied');
        }
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await _firestore.createRequest({
        'userId': user.uid,
        'service': _selectedService,
        'location': GeoPoint(position.latitude, position.longitude),
        'locationDescription': _locationDescription.trim(),
        'notes': _notes.trim(),
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'lastActive': DateTime.now(),
      });

      if (!_isAdFree && _interstitialAd != null) await _interstitialAd!.show();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/request_status');
      }
    } catch (e) {
      print('Failed to submit request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        // Retry once after delay
        await Future.delayed(Duration(seconds: 2));
        if (!_isSubmitting) _submitRequest();
      }
    }
    if (mounted) setState(() => _isSubmitting = false);
  }
 Stream<int> _getUnreadCount() {
  final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('chat_requests')
        .where('providerId', isEqualTo: user!.uid)
        .where('status', whereIn: ['pending', 'accepted'])
        .snapshots()
        .asyncMap((snapshot) async {
          int unreadCount = 0;
          for (var chat in snapshot.docs) {
            var messages = await FirebaseFirestore.instance
                .collection('chat_requests')
                .doc(chat.id)
                .collection('messages')
                .where('senderId', isNotEqualTo: user!.uid)
                .where('read', isEqualTo: false)
                .get();
            unreadCount += messages.docs.length;
          }
          unreadCount += snapshot.docs.where((doc) => doc['status'] == 'pending').length;
          return unreadCount;
        }).handleError((e) {
          print('Error in unread count stream: $e');
          return 0;
        });
  }

  void _showServicePicker() {
    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.blue, Colors.blueAccent]),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select a Service', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search services...',
                      prefixIcon: Icon(Icons.search, color: Colors.blue),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    onChanged: (value) => setModalState(() => searchQuery = value.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore.getServiceOptions(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                      if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                      var services = snapshot.data!.docs
                          .map((doc) => doc.data() as Map<String, dynamic>)
                          .where((service) => service['name'] != null)
                          .toList();
                      if (services.isEmpty) return Center(child: Text('No services available'));
                      var filteredServices = services.where((service) => service['name'].toLowerCase().contains(searchQuery)).toList();
                      return ListView.builder(
                        controller: controller,
                        itemCount: filteredServices.length,
                        itemBuilder: (context, index) {
                          var service = filteredServices[index];
                          String name = service['name'] as String;
                          String category = service['category'] as String? ?? 'Uncategorized';
                          return Card(
                            margin: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: CircleAvatar(backgroundColor: Colors.blue[100], child: Icon(Icons.build, color: Colors.blue)),
                              title: Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(category),
                              trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                              onTap: () {
                                if (mounted) setState(() => _selectedService = name);
                                Navigator.pop(context);
                              },
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
        ),
      ),
    );
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    _bannerAd?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back button from logging out
      child: Scaffold(
        appBar: AppBar(
          title: Text('Request Immediate Assistance'),
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue, Colors.blueAccent])),
          ),
          actions: [
           
           StreamBuilder<int>(
              stream: _getUnreadCount(),
              builder: (context, snapshot) {
                int unreadCount = snapshot.data ?? 0;
                return Badge(
                  label: Text(unreadCount.toString()),
                  isLabelVisible: unreadCount > 0,
                  child: IconButton(
                    icon: const Icon(Icons.message),
                     onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => InboxScreen(isProvider: false))),
            
                  ),
                );
              },
            ),


            StreamBuilder<int>(
              stream: _getUnreadNotificationsCount(),
              builder: (context, snapshot) {
                int unreadCount = snapshot.data ?? 0;
                return Badge(
                  label: Text(unreadCount.toString()),
                  isLabelVisible: unreadCount > 0,
                  child: IconButton(
                    icon: Icon(Icons.notifications),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NotificationsScreen(isProvider: false))),
                    tooltip: 'Notifications',
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.monetization_on),
              onPressed: () => Navigator.pushNamed(context, '/subscription'),
              tooltip: 'Manage Subscription',
            ),
            IconButton(
              icon: Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => UserLoginScreen()));
                }
              },
              tooltip: 'Logout',
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue[50]!, Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Submit a Service Request',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue[800]),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Please provide the necessary details below.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _showServicePicker,
                        child: Text(_selectedService ?? 'Select Service'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[100],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      if (_selectedService != null) ...[
                        SizedBox(height: 8),
                        Chip(
                          label: Text(_selectedService!),
                          backgroundColor: Colors.blue[50],
                          deleteIcon: Icon(Icons.close, size: 18),
                          onDeleted: () => setState(() => _selectedService = null),
                        ),
                      ],
                      SizedBox(height: 16),
                      TextField(
                        onChanged: (value) => _locationDescription = value,
                        decoration: InputDecoration(
                          labelText: 'Location Description',
                          hintText: 'e.g., Near Main St.',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
                        maxLines: 2,
                      ),
                      SizedBox(height: 16),
                      TextField(
                        onChanged: (value) => _notes = value,
                        decoration: InputDecoration(
                          labelText: 'Additional Notes (Optional)',
                          hintText: 'e.g., Urgent leak',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
                        maxLines: 3,
                      ),
                      SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitRequest,
                        child: _isSubmitting
                            ? CircularProgressIndicator(color: Colors.white)
                            : Text('Submit Request', style: TextStyle(fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                      SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/browse_providers'),
                        child: Text('Or Browse Available Providers', style: TextStyle(color: Colors.blue[700])),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isAdFree && _isBannerAdLoaded && _bannerAd != null)
              Container(
                width: double.infinity,
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            BottomNavigationBar(
              items: [
                BottomNavigationBarItem(icon: Icon(Icons.request_page), label: 'Requests'),
                BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Browse'),
                BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
              ],
              currentIndex: 0,
              selectedItemColor: Colors.blue,
              onTap: (index) {
                if (index == 1) Navigator.pushNamed(context, '/browse_providers');
                if (index == 2) Navigator.pushNamed(context, '/profile');
                if (index == 0) Navigator.pushNamed(context, '/request_status');
              },
            ),
          ],
        ),
      ),
    );
  }
}