// lib/features/roadside/screens/request_status_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:lottie/lottie.dart' hide Marker;
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/core/notification_service.dart';
import 'package:padue/features/roadside/screens/request_details_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/utils.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/roadside/screens/bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/inbox_screen.dart';
import 'package:padue/features/roadside/screens/notifications_screen.dart';
import '../../../core/firestore_service.dart';
import '../../roadside/models/provider.dart';
import 'chat_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class RequestStatusScreen extends StatefulWidget {
  const RequestStatusScreen({super.key});
  @override
  _RequestStatusScreenState createState() => _RequestStatusScreenState();
}

class _RequestStatusScreenState extends State<RequestStatusScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _firestore = FirestoreService();
  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  bool _isAdFree = false;
  bool _isBannerAdLoaded = false;
  UserProfile? _profile;
  bool _isLoading = true;

  // Tabs
  late TabController _tabController;
  int _currentTab = 0;

  // Live Tracking
  bool _showMap = false;
  LatLng? _userPos;
  LatLng? _providerPos;
  List<LatLng> _polyline = [];
  double? _eta;
  
  Timer? _autoCloseTimer;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() => _currentTab = _tabController.index));
  //  _initCache();
    _loadAd();
    _loadInterstitialAd();
    _checkAdFreeStatus();
    updateLastActive();
    _loadUserProfile();
    updateUserLocation();
    
  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAd();
      _loadInterstitialAd();
      _checkAdFreeStatus();
      updateLastActive();
      _loadUserProfile();
      updateUserLocation();
    }
  }




 



  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> updateUserLocation() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final geo = GeoPoint(pos.latitude, pos.longitude);
      await _firestore.updateUserLocation(user.uid, geo);
      setState(() => _userPos = LatLng(pos.latitude, pos.longitude));
    } catch (e) {
      print('Location error: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _profile = await _firestore.getUserProfile(user.uid);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkAdFreeStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _isAdFree = await _firestore.isAdFree(user.uid);
      if (mounted) setState(() {});
    }
  }

  Stream<int> _getUnreadCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('chat_requests')
        .where('userId', isEqualTo: user.uid)
        .where('status', whereIn: ['pending', 'accepted'])
        .snapshots()
        .asyncMap((snapshot) async {
          int unreadCount = 0;
          for (var chat in snapshot.docs) {
            var messages = await FirebaseFirestore.instance
                .collection('chat_requests')
                .doc(chat.id)
                .collection('messages')
                .where('senderId', isNotEqualTo: user.uid)
                .where('read', isEqualTo: false)
                .get();
            unreadCount += messages.docs.length;
          }
          unreadCount += snapshot.docs.where((doc) => doc['status'] == 'pending').length;
          return unreadCount;
        }).handleError((e) => 0);
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
        .handleError((e) => 0);
  }

  Future<void> _confirmRequest(String providerId, String requestId) async {
    await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
    });

     final providerDoc = await FirebaseFirestore.instance
        .collection('providers')
        .doc(providerId)
        .get();
   
 final String subscriptionId = providerDoc.data()?['oneSignalSubscriptionId'] as String;


 
        await NotificationService.sendToSubscriptionIds(
 subscriptionIds: [subscriptionId],
 
        title: 'Request Closed',
        body: 'The user has confirmed your service as completed',
        data: {'type': 'Request_Closed', 'requestId': requestId},
      );
    
    await _firestore.sendNotification(providerId, 'Request Closed', 'The user has confirmed your service as completed.');
    _showRatingDialog(providerId, requestId);
    if (!_isAdFree && _interstitialAd != null) await _interstitialAd!.show();
  }

  Future<void> _disputeRequest(String providerId, String requestId) async {
    final _reasonController = TextEditingController();
    bool? shouldDispute = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dispute Completion', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Why isn’t this request complete?', style: TextStyle(color: Colors.grey[600])),
            SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'Reason for Dispute',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Submit'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
    if (shouldDispute == true && _reasonController.text.trim().isNotEmpty) {
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
        'status': 'accepted',
        'disputeReason': _reasonController.text.trim(),
        'disputedAt': FieldValue.serverTimestamp(),
      });
      await _firestore.sendNotification(providerId, 'Request Disputed', 'The user has disputed your completion: ${_reasonController.text.trim()}');
      _showSnack('Dispute submitted.');
    }
  }

  Future<void> _completeRequest(String providerId, String requestId) async {
    await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
      'status': 'closed',
      'completedAt': FieldValue.serverTimestamp(),
    });
    await _firestore.sendNotification(providerId, 'Service Completed', 'The user has marked the request as completed.');
    _showRatingDialog(providerId, requestId);
    if (!_isAdFree && _interstitialAd != null) await _interstitialAd!.show();
  }

  void _showRatingDialog(String providerId, String requestId) {
    int? _rating;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rate Your Experience', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('How was the service?', style: TextStyle(color: Colors.grey[600])),
            SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setState) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(index < (_rating ?? 0) ? Icons.star : Icons.star_border, color: Colors.amber, size: 32),
                    onPressed: () => setState(() => _rating = index + 1),
                  );
                }),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Skip')),
          ElevatedButton(
            onPressed: () async {
              if (_rating != null) {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await _firestore.submitRating(requestId, user.uid, providerId, _rating!);
                  Navigator.pop(context);
                  _showSnack('Thanks for your feedback!');
                }
              }
            },
            child: Text('Submit'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(String providerId) {
    final _reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report Provider', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
        content: TextField(
          controller: _reasonController,
          decoration: InputDecoration(
            labelText: 'Reason for Reporting',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey[100],
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null && _reasonController.text.trim().isNotEmpty) {
                await _firestore.submitReport(user.uid, providerId, _reasonController.text.trim(), 'provider');
                Navigator.pop(context);
                _showSnack('Report submitted.');
              }
            },
            child: Text('Submit'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: AdmobConfig().banner,
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdLoaded = true),
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    );
    _bannerAd!.load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdmobConfig().interstitial,
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
          );
        },
        onAdFailedToLoad: (error) => print('Interstitial ad failed: $error'),
      ),
    );
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

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(requestId: chatId)),
    );
  }

  Future<void> _callProvider(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      _showSnack('Could not launch phone call.');
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _tabController.dispose();
    _autoCloseTimer?.cancel();
    _locationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBarWidget(title: 'My Requests', isProvider: false),
        body: Center(child: Text('Please sign in.', style: TextStyle(fontSize: 18))),
      );
    }

    return Scaffold(
      appBar: AppBarWidget(
        title: 'My Requests',
        profilePicUrl: _profile?.profilePicUrl,
        showNotifications: true,
        isProvider: false,
      ),
      drawer: AppBarWidget.buildDrawer(context: context, isProvider: false),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.blue[50]!, Colors.purple[50]!], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Column(
          children: [
      
Container(
  margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
  decoration: BoxDecoration(
    color: Colors.white,
    //borderRadius: BorderRadius.circular(30),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  child: TabBar(
    controller: _tabController,
    labelColor: Colors.white,
    unselectedLabelColor: Colors.grey[700],
    labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
    indicatorSize: TabBarIndicatorSize.tab,
    indicator: const BoxDecoration(
      color: Color(0xFFFF6200),
    //  borderRadius: BorderRadius.all(Radius.circular(30)),
    ),
    dividerColor: Colors.transparent,
    tabs: const [
      Tab(text: '   Active   '),   // spacing for beauty
      Tab(text: '   History   '),
    ],
  ),
),




            /**Container(
              margin: EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[600],
                indicator: BoxDecoration(
                  //borderRadius: BorderRadius.circular(12),
                  color: _currentTab == 0 ? Color(0xFFFF6200) : Color(0xFFFF6200),
                ),
                tabs: [Tab(text: 'Active'), Tab(text: 'History')],
              ),
            ),*/
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildActiveTab(user.uid), _buildHistoryTab(user.uid)],
              ),
            ),
            if (!_isAdFree && _isBannerAdLoaded && _bannerAd != null)
              Container(
                width: double.infinity,
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(currentIndex: 1),
    );
  }



  Widget _buildActiveTab(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('userId', isEqualTo: uid)
          .where('status', whereIn: ['open', 'accepted', 'provider_completed'])
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _emptyState('No active requests', Icons.hourglass_empty);
        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) => _buildRequestCard(docs[i]),
        );
      },
    );
  }

  Widget _buildHistoryTab(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('userId', isEqualTo: uid)
          .where('status', whereIn: ['closed', 'canceled'])
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _emptyState('No past requests', Icons.history);
        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) => _buildRequestCard(docs[i], isHistory: true),
        );
      },
    );
  }




 Widget _buildRequestCard(DocumentSnapshot doc, {bool isHistory = false}) {
  final data = doc.data() as Map<String, dynamic>;
  final status = data['status'] as String;
  final providerId = data['providerId'] as String?;
  final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

  return Card(
    margin: EdgeInsets.only(bottom: 12),
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RequestDetailsScreen(requestId: doc.id),
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: _statusColor(status), child: Icon(_statusIcon(status), color: Colors.white)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['issue'] ?? 'Service Request', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(_formatDate(createdAt), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
                Chip(
                  label: Text(status.replaceAll('_', ' '), style: TextStyle(color: Colors.white, fontSize: 10)),
                  backgroundColor: _statusColor(status),
                ),
              ],
            ),
            if (providerId != null && !isHistory) ...[
              Divider(height: 24),
              FutureBuilder<Provider?>(
                future: _firestore.getProviderProfile(providerId),
                builder: (context, snap) {
                  if (!snap.hasData) return SizedBox();
                  final p = snap.data!;
                  return Row(
                    children: [
                      CircleAvatar(radius: 20, backgroundImage: NetworkImage(p.profilePicUrl ?? '')),
                      SizedBox(width: 8),
                      Text(p.name ?? 'Provider', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      Spacer(),
                      // ETA removed from list – now shown in details
                    ],
                  );
                },
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton.icon(
                    icon: Icon(Icons.chat, size: 16),
                    label: Text('Chat'),
                    onPressed: () => _openOrCreateChat(providerId, FirebaseAuth.instance.currentUser!.uid),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: StadiumBorder()),
                  ),
                  if (status == 'provider_completed')
                    ElevatedButton.icon(
                      icon: Icon(Icons.check, size: 16),
                      label: Text('Confirm'),
                      onPressed: () => _confirmRequest(providerId, doc.id),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: StadiumBorder()),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

  Color _statusColor(String status) {
    switch (status) {
      case 'open': return Colors.orange;
      case 'accepted': return Colors.blue;
      case 'provider_completed': return Colors.purple;
      case 'closed': return Colors.green;
      case 'canceled': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'open': return Icons.hourglass_empty;
      case 'accepted': return Icons.directions_car;
      case 'provider_completed': return Icons.flag;
      case 'closed': return Icons.check_circle;
      case 'canceled': return Icons.cancel;
      default: return Icons.help;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  Widget _emptyState(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(text, style: TextStyle(fontSize: 18, color: Colors.grey[600])),
        ],
      ),
    );
  }
}