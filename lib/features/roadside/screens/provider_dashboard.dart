import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/utils.dart';
import 'package:padue/features/roadside/screens/notifications_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/firestore_service.dart';
import '../../roadside/models/provider.dart';
import 'chat_screen.dart';
import 'provider_profile_screen.dart';
import 'inbox_screen.dart';
import 'user_profile_screen.dart';

class ProviderDashboard extends StatefulWidget {
  @override
  _ProviderDashboardState createState() => _ProviderDashboardState();
}

class _ProviderDashboardState extends State<ProviderDashboard> with SingleTickerProviderStateMixin , WidgetsBindingObserver  {
  final _firestore = FirestoreService();
  Provider? _provider;
  Position? _providerPosition;
  bool _isAccepting = false;
  late TabController _tabController;
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoaded = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _loadProviderData();
    updateLastActive();
    _initBannerAd();
    _getUnreadNotificationsCount();
    _initInterstitialAd();
   /**  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['title'] == 'New Message' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New message: ${message.data['body']}'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _showInterstitialAdThenNavigate(
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => InboxScreen(isProvider: true))),
              ),
            ),
          ),
        );
      }
    });*/
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
      // Refresh data or resources
 print('App resumed, reloading data...');
    _loadProviderData(); // Ensure provider data is fresh
    _updateLocation();   // Explicitly call location update
    updateLastActive();
    _initBannerAd();
    _getUnreadNotificationsCount();
    _initInterstitialAd();
    saveFcmToken();
    if (mounted) setState(() {});    // Force UI refresh
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
          _tabController.animateTo(0); // Switch to Nearby Requests tab
        } else if (data['type'] == 'message') {
          Navigator.push(context, MaterialPageRoute(builder: (context) => InboxScreen(isProvider: true)));
        }
      },
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
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
  void _initBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdmobConfig().getAdUnitId('banner') ?? 'ca-app-pub-3940256099942544/6300978111', // Test ID
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdLoaded = true),
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    )..load();
  }
 // Add this method for unread notifications count
  Stream<int> _getUnreadNotificationsCount() {
  if (_provider == null) return Stream.value(0);
  return FirebaseFirestore.instance
      .collection('providers')
      .doc(_provider!.id)
      .collection('notifications')
      .where('read', isEqualTo: false) // Only unread notifications
      .where('type', isNotEqualTo: 'message') // Exclude message notifications
      .orderBy('type') // Required for composite index with isNotEqualTo
      .snapshots()
      .map((snapshot) => snapshot.docs.length)
      .handleError((e) {
        print('Error in unread notifications count: $e');
        return 0;
      });
}
  void _initInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdmobConfig().getAdUnitId('interstitial')?? 'ca-app-pub-3940256099942544/1033173712', // Test ID
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => _initInterstitialAd(),
            onAdFailedToShowFullScreenContent: (ad, error) => _initInterstitialAd(),
          );
        },
        onAdFailedToLoad: (error) => _isInterstitialAdLoaded = false,
      ),
    );
  }

  void _showInterstitialAdThenNavigate(VoidCallback navigation) {
    if (_isInterstitialAdLoaded && _interstitialAd != null) {
      _interstitialAd!.show().then((_) => navigation()).catchError((_) => navigation());
    } else {
      navigation();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


Future<void> _loadProviderData() async {
  if (!mounted) return;
  try {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var doc = await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _provider = Provider.fromFirestore(doc);
        });
        await _updateLocation(); // Ensure location updates after provider loads
      } else {
        print('No provider data found for UID: ${user.uid}');
      }
    }
  } catch (e) {
    print('Error loading provider data: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load data: $e')));
    }
  }
}
 Future<void> _openOrCreateChat(String providerId, String userId) async {
    var existingChat = await FirebaseFirestore.instance
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
      var newChat = await FirebaseFirestore.instance.collection('chat_requests').add({
        'providerId': providerId,
        'userId': userId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      chatId = newChat.id;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(requestId: chatId)),
    );
  }

  Future<void> _updateLocation() async {
    if (!mounted) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enable location services')));
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location permission required')));
          return;
        }
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _providerPosition = position;
      if (_provider != null && mounted) {
        GeoPoint geoPoint = GeoPoint(position.latitude, position.longitude);
        await FirebaseFirestore.instance.collection('providers').doc(_provider!.id).update({
          'location': geoPoint,
          'availability': true,
        });
        setState(() {});
      }
    } catch (e) {
      print('Failed to update location: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location update failed: $e')));
      await Future.delayed(Duration(seconds: 2));
      if (mounted) _updateLocation(); // Retry
    }
  }


  Future<Map<String, dynamic>> _fetchUserDetails(String userId) async {
    var doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return doc.data() ?? {'name': 'Unknown', 'phoneNumber': 'N/A'};
  }

  Future<bool> _canRateUser(String userId) async {
    if (_provider == null) return false;
    var completedOrCanceled = await FirebaseFirestore.instance
        .collection('requests')
        .where('providerId', isEqualTo: _provider!.id)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['provider_completed', 'canceled'])
        .limit(1)
        .get();
    return completedOrCanceled.docs.isNotEmpty;
  }

  Stream<int> _getUnreadCount() {
    if (_provider == null) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('chat_requests')
        .where('providerId', isEqualTo: _provider!.id)
        .where('status', whereIn: ['pending', 'accepted'])
        .snapshots()
        .asyncMap((snapshot) async {
          int unreadCount = 0;
          for (var chat in snapshot.docs) {
            var messages = await FirebaseFirestore.instance
                .collection('chat_requests')
                .doc(chat.id)
                .collection('messages')
                .where('senderId', isNotEqualTo: _provider!.id)
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


  Future<void> _acceptRequest(String requestId) async {
    setState(() => _isAccepting = true);
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && _provider != null) {
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
        'providerId': _provider!.id,
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      var requestDoc = await FirebaseFirestore.instance.collection('requests').doc(requestId).get();
      var userId = requestDoc['userId'] as String;
      var issue = requestDoc['issue'] as String? ?? requestDoc['service'] as String;
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      var token = userDoc.data()?['fcmToken'] as String?;
      if (token != null) {
        await sendFcmNotificationV1( // From utils.dart
          token: token,
          title: 'Request Accepted',
          body: 'Your request for $issue has been accepted by ${_provider!.name}.',
          type: 'request',
          id: requestId,
         recipientUid:  userId,
        );
      }
    }
    setState(() => _isAccepting = false);
  }

  Future<void> _closeRequest(String requestId, String status, String userId, String issue) async {
    setState(() => _isAccepting = true);
    if (_provider != null) {
      Map<String, dynamic> updateData = {
        'status': status == 'completed' ? 'provider_completed' : 'canceled',
        status == 'completed' ? 'providerCompletedAt' : 'canceledAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update(updateData);
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      var token = userDoc.data()?['fcmToken'] as String?;
      if (token != null) {
        await sendFcmNotificationV1( // From utils.dart
          token: token,
          title: status == 'completed' ? 'Service Completed' : 'Request Canceled',
          body: status == 'completed'
              ? 'Your request for $issue has been marked completed by ${_provider!.name}.'
              : 'Your request for $issue has been canceled by ${_provider!.name}.',
          type: 'request',
          id: requestId,
          recipientUid:  userId,
        );
      }
    }
    setState(() => _isAccepting = false);
  }

  void _showCloseRequestDialog(String requestId, String userId, String issue) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close Request'),
        content: Text('How would you like to close this request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await _closeRequest(requestId, 'completed', userId, issue);
              Navigator.pop(context);
            },
            child: Text('Completed'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
          ElevatedButton(
            onPressed: () async {
              await _closeRequest(requestId, 'canceled', userId, issue);
              Navigator.pop(context);
            },
            child: Text('Cancel'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          ),
        ],
      ),
    );
  }

  void _openMap(GeoPoint location) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
  }
 // Add this method to handle back button press
  Future<bool> _onWillPop() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Exit'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pop(context, true);
            },
            child: const Text('Logout'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    return shouldLogout ?? false;
  }
  void _callUser(String phoneNumber) async {
    final url = 'tel:$phoneNumber';
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
  }

   @override
  Widget build(BuildContext context) {
    if (_provider == null || _providerPosition == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Provider Dashboard')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      onWillPop: _onWillPop, // Prevent logout on back button
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_provider!.name}'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue, Colors.purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          actions: [
            
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () => _showInterstitialAdThenNavigate(
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProviderProfileScreen())),
              ),
            ),
            StreamBuilder<int>(
              stream: _getUnreadCount(),
              builder: (context, snapshot) {
                int unreadCount = snapshot.data ?? 0;
                return Badge(
                  label: Text(unreadCount.toString()),
                  isLabelVisible: unreadCount > 0,
                  child: IconButton(
                    icon: const Icon(Icons.message),
                    onPressed: () => _showInterstitialAdThenNavigate(
                      () => Navigator.push(context, MaterialPageRoute(builder: (context) => InboxScreen(isProvider: true))),
                    ),
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
                    icon: const Icon(Icons.notifications),
                    onPressed: () => _showInterstitialAdThenNavigate(
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const NotificationsScreen(isProvider: true)),
                      ),
                    ),
                  ),
                );
              },
            ),
           IconButton(
  icon: const Icon(Icons.logout),
  onPressed: () async {
    // Show confirmation dialog
    bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), // Cancel
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true), // Confirm
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    // Proceed with logout if confirmed
    if (confirmLogout == true) {
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacementNamed(context, '/login');
    }
  },
),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'Nearby Requests'),
              Tab(text: 'Chat Requests'),
            ],
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[50]!, Colors.purple[50]!],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildNearbyRequestsTab(),
                    _buildChatRequestsTab(),
                  ],
                ),
              ),
              if (_isBannerAdLoaded && _bannerAd != null)
                Container(
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNearbyRequestsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _firestore.getNearbyRequests(_provider!.id, _providerPosition!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        var requests = snapshot.data!;
        if (requests.isEmpty) {
          return Center(
            child: Card(
              elevation: 8,
              margin: EdgeInsets.all(16),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No nearby requests'),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            var request = requests[index];
            var requestId = request['id'] as String;
            var userId = request['userId'] as String;
            bool isAccepted = request['providerId'] == _provider!.id && request['status'] == 'accepted';
            var requestLocation = request['location'] as GeoPoint;
            bool isPriority = request['isPriority'] ?? false;
            double distanceInKm = Geolocator.distanceBetween(
              _providerPosition!.latitude,
              _providerPosition!.longitude,
              requestLocation.latitude,
              requestLocation.longitude,
            ) / 1000;

            return FutureBuilder<Map<String, dynamic>>(
              future: _fetchUserDetails(userId),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) return SizedBox.shrink();
                var userDetails = userSnapshot.data!;
                return Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: EdgeInsets.symmetric(vertical: 8),
                  color: isPriority ? Colors.orange[50] : Colors.white,
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundImage: userDetails['profilePicUrl'] != null
                          ? NetworkImage(userDetails['profilePicUrl'])
                          : AssetImage('assets/default_profile.png') as ImageProvider,
                    ),
                    title: Text(userDetails['name']),
                    subtitle: Text('${request['issue'] ?? request['service']} • ${distanceInKm.toStringAsFixed(1)} km'),
                    trailing: isAccepted
                        ? Icon(Icons.check_circle, color: Colors.green)
                        : _isAccepting
                            ? CircularProgressIndicator()
                            : ElevatedButton(
                                onPressed: () => _acceptRequest(requestId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text('Accept'),
                              ),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isPriority) Chip(label: Text('Priority'), backgroundColor: Colors.orange),
                            SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.map),
                                  onPressed: isAccepted ? () => _openMap(requestLocation) : null,
                                  color: isAccepted ? Colors.blue : Colors.grey,
                                ),
                                IconButton(
                                  icon: Icon(Icons.phone),
                                  onPressed: () => _callUser(userDetails['phoneNumber']),
                                  color: Colors.blue,
                                ),
                                IconButton(
                                  icon: Icon(Icons.chat),
                                  onPressed: () => _openOrCreateChat(_provider!.id, userId), 
                                    
                                  
                                  color: Colors.blue,
                                ),
                                FutureBuilder<bool>(
                                  future: _canRateUser(userId),
                                  builder: (context, snapshot) {
                                    bool canRate = snapshot.data ?? false;
                                    return IconButton(
                                      icon: Icon(Icons.person),
                                      onPressed: canRate
                                          ? () => _showInterstitialAdThenNavigate(
                                                () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (context) => UserProfileScreen(userId: userId)),
                                                ),
                                              )
                                          : null,
                                      color: canRate ? Colors.blue : Colors.grey,
                                    );
                                  },
                                ),
                                if (isAccepted)
                                  IconButton(
                                    icon: Icon(Icons.close),
                                    onPressed: () => _showCloseRequestDialog(requestId, userId, request['issue'] ?? request['service']),
                                    color: Colors.red,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildChatRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chat_requests')
          .where('providerId', isEqualTo: _provider!.id)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        var chats = snapshot.data!.docs;
        if (chats.isEmpty) {
          return Center(
            child: Card(
              elevation: 8,
              margin: EdgeInsets.all(16),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No pending chat requests'),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: chats.length,
          itemBuilder: (context, index) {
            var chat = chats[index];
            var userId = chat['userId'] as String;
            return FutureBuilder<Map<String, dynamic>>(
              future: _fetchUserDetails(userId),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) return SizedBox.shrink();
                var userDetails = userSnapshot.data!;
                return Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: userDetails['profilePicUrl'] != null
                          ? NetworkImage(userDetails['profilePicUrl'])
                          : AssetImage('assets/default_profile.png') as ImageProvider,
                    ),
                    title: Text('Chat from ${userDetails['name']}'),
                    trailing: ElevatedButton(
                      onPressed: () => _showInterstitialAdThenNavigate(
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ChatScreen(requestId: chat.id)),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Open'),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}