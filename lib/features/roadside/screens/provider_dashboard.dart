
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:latlong2/latlong.dart';
import 'package:lottie/lottie.dart'hide Marker;
import 'package:padue/core/notification_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:padue/core/admob_config.dart';
import 'package:padue/core/osm_navigation_service.dart';
import 'package:padue/core/utils.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/roadside/screens/banner_ad_widget.dart';
import 'package:padue/features/roadside/screens/forum_screen.dart';
import 'package:padue/features/roadside/screens/notifications_screen.dart';
import 'package:padue/features/roadside/screens/provider_analytics_screen.dart';
import 'package:padue/features/roadside/screens/provider_bottom_nav_bar.dart';

import '../../../core/firestore_service.dart';
import '../../roadside/models/provider.dart';
import 'chat_screen.dart';
import 'inbox_screen.dart';
import 'provider_profile_screen.dart';
import 'user_profile_screen.dart';
import 'package:dart_geohash/dart_geohash.dart';
import 'package:timeago/timeago.dart' as timeago;

FlutterTts _tts = FlutterTts();

class ProviderDashboard extends StatefulWidget {
  const ProviderDashboard({super.key});
  @override
  _ProviderDashboardState createState() => _ProviderDashboardState();
}

class _ProviderDashboardState extends State<ProviderDashboard> with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  Provider? _provider;
  Position? _providerPosition;
  Map<String, bool> _acceptingRequests = {};
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoaded = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  double _searchRadius = 50.0;
  bool _showAllNewRequests = false;
  bool _showClosedRequests = true;
  bool _isAdFree = false;
  bool _isLoadingProfile = true;
  String? profilePicUrl;
  bool _isOffline = false;
   int _currentInstructionIndex = 0;
  Timer? _instructionTimer;
  bool _voiceNavigationActive = false;

  // Caches
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, bool> _canRateCache = {};
  final Map<String, Map<String, dynamic>?> _routeCache = {};

  // Map state
  bool _showMap = false;
  LatLng? _mapCenter;
  List<LatLng> _polylinePoints = [];
  double? _etaMinutes;
  double? _routeDistance;
  Directory? _cacheDir;
Timer? _rerouteTimer;
StreamSubscription? _connectivitySub;
LatLng? _lastProviderPos;
//final cache = MemoryCacheStore();



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 1. Show UI instantly using cache
    _loadFromCacheAndShowUI();

    // 2. Then start background warmup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmupEverythingInBackground();
    });
  }

 bool computeAdFree({
  Timestamp? priorityUntil,
  Timestamp? subscriptionEnd,
}) {
  final now = DateTime.now();

  final priorityActive =
      priorityUntil != null && priorityUntil.toDate().isAfter(now);

  final subscriptionActive =
      subscriptionEnd != null && subscriptionEnd.toDate().isAfter(now);

  return priorityActive || subscriptionActive;
}



 Future<void> _loadFromCacheAndShowUI() async {
    final prefs = await SharedPreferences.getInstance();

    final cachedProfile = prefs.getString('cached_provider_profile');
    final cachedLoc = prefs.getString('cached_provider_location');

    if (cachedProfile != null) {
      try {
        final data = jsonDecode(cachedProfile);
        setState(() {
          _provider = Provider.fromMap(data);
          _isAdFree = data['adFree'] ?? false;
        });
      } catch (e) {
        debugPrint('Failed to parse cached profile: $e');
      }
    }

    if (cachedLoc != null) {
      try {
        final loc = jsonDecode(cachedLoc);
        _providerPosition = Position(
          latitude: loc['lat'],
          longitude: loc['lng'],
          timestamp: DateTime.now(),
          accuracy: 10,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      } catch (e) {
        debugPrint('Failed to parse cached location: $e');
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _warmupEverythingInBackground() async {
    final futures = <Future>[
      _refreshProviderProfileAndCache(),
      _updateLocationInBackground(),
      _saveTokensAndLastActive(),
      _initCache(),
    ];

    await Future.wait(futures).catchError((e) {
      debugPrint('Warmup error: $e');
    });

    _checkConnectivity();
  }

Future<void> _refreshProviderProfileAndCache() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('providers')
        .doc(user.uid)
        .get();

    if (!doc.exists) return;

    final data = doc.data()!;

    final Timestamp? priorityUntil = data['priorityUntil'] as Timestamp?;
    final Timestamp? subscriptionEnd = data['subscriptionEnd'] as Timestamp?;
    final bool currentAdFree = data['adFree'] == true;

    final now = DateTime.now();
    Map<String, dynamic>? updates;

    // These represent what SHOULD be active after cleanup
    Timestamp? effectivePriority = priorityUntil;
    Timestamp? effectiveSubscription = subscriptionEnd;

    // 🔹 Expired priority
    if (priorityUntil != null && priorityUntil.toDate().isBefore(now)) {
      updates ??= {};
      updates['priorityUntil'] = FieldValue.delete();
      effectivePriority = null;
    }

    // 🔹 Expired subscription
    if (subscriptionEnd != null && subscriptionEnd.toDate().isBefore(now)) {
      updates ??= {};
      updates['subscriptionEnd'] = FieldValue.delete();
      effectiveSubscription = null;
    }

    // 🔹 Recompute adFree AFTER expiry cleanup
    final bool shouldBeAdFree = computeAdFree(
      priorityUntil: effectivePriority,
      subscriptionEnd: effectiveSubscription,
    );

    // 🔹 Always keep Firebase truthful
    if (currentAdFree != shouldBeAdFree) {
      updates ??= {};
      updates['adFree'] = shouldBeAdFree;
    }

    // 🔹 Apply updates if needed
    if (updates != null) {
      await doc.reference.update(updates);
    }

    // 🔹 Build provider model
    final provider = Provider.fromFirestore(doc);

    // 🔹 Cache provider safely (JSON-serializable)
    final Map<String, dynamic> cacheMap = provider.toMap();

    cacheMap.forEach((key, value) {
      if (value is Timestamp) {
        cacheMap[key] = value.millisecondsSinceEpoch;
      } else if (value is GeoPoint) {
        cacheMap[key] = {
          'latitude': value.latitude,
          'longitude': value.longitude,
        };
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cached_provider_profile',
      jsonEncode(cacheMap),
    );

    if (mounted) {
      setState(() {
        _provider = provider;
        _isAdFree = shouldBeAdFree;
      });
    }
  } catch (e) {
    debugPrint('Profile refresh failed: $e');

    // Fallback: allow UI to render even if refresh fails
    if (mounted && _provider == null) {
      setState(() {});
    }
  }
}






Future<void> _updateLocationInBackground() async {
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permission permanently denied');
      return;
    }

    if (permission == LocationPermission.denied) {
      debugPrint('Location permission denied');
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 20),
    );

    // Generate geohash (precision 9 ≈ 150 meters accuracy — perfect for 10–50km radius)
    final GeoHasher geoHasher = GeoHasher();
final String geohash = geoHasher.encode(position.longitude, position.latitude, precision: 6);

    if (mounted) {
      setState(() => _providerPosition = position);

      if (_provider != null) {
        await FirebaseFirestore.instance
            .collection('providers')
            .doc(_provider!.id)
            .update({
          'location': GeoPoint(position.latitude, position.longitude),
          'geohash': geohash,                    // ← NEW: Add geohash
          'lastActive': FieldValue.serverTimestamp(),
        });
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_provider_location',
        jsonEncode({
          'lat': position.latitude,
          'lng': position.longitude,
          'geohash': geohash,  // Optional: cache geohash too
        }),
      );
    }
  } catch (e) {
    debugPrint('Location fetch failed: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not get location. Please enable GPS.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
  Future<void> _initCache() async {
    final dir = await getTemporaryDirectory();
    if (mounted) setState(() => _cacheDir = dir);
  }

 void _checkConnectivity() {
  _connectivitySub?.cancel();

  _connectivitySub =
      Connectivity().onConnectivityChanged.listen(
    (result) {
      if (!mounted) return;

      setState(() {
        _isOffline =
            result == ConnectivityResult.none;
      });
    },
  );
}



  Future<void> _saveTokensAndLastActive() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    unawaited(saveProviderFcmToken());
    unawaited(saveProviderOneSignalSubscriptionId(user.uid));
    unawaited(updateProviderLastActive());
  }

 
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_warmupEverythingInBackground()); // Non-blocking!
    }
  }

 @override
void dispose() {

  _connectivitySub?.cancel();

  _bannerAd?.dispose();
  _interstitialAd?.dispose();

  _rerouteTimer?.cancel();
  _instructionTimer?.cancel();

  _tts.stop();

  WidgetsBinding.instance.removeObserver(this);

  super.dispose();
}


 

  void _initAds() {
    _initBannerAd();
    _initInterstitialAd();
  }

  

  Future<void> _initTTS() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.8);
    await _tts.setVolume(1.0);
  }



Future<void> _prewarmUserCache() async {
  final snap = await FirebaseFirestore.instance.collection('requests').limit(20).get();
/** final userIds = snap.docs
    .map((d) => d.data())
    .map((data) => data['userId'] as String?)
    .where((id) => id != null)
    .cast<String>()
    .toSet()
    .toList();*/
    final userIds =
    extractValidUserIds(snap.docs);

Future.microtask(() {
   _batchFetchUsers(userIds);
});
 // await _batchFetchUsers(userIds);
}

   // NEW: Generate instructions from route
  List<String> _generateInstructions(List<LatLng> points) {
    if (points.length < 3) return ["Follow the route."];
    List<String> instructions = [];
    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];
      String dir = _getDirection(prev, curr, next);
      instructions.add("$dir in ${(_distance(curr, next) / 1000).toStringAsFixed(1)} km");
    }
    return instructions;
  }

  String _getDirection(LatLng prev, LatLng curr, LatLng next) {
    double bearingToNext = _bearing(curr, next);
    double bearingFromPrev = _bearing(prev, curr);
    double turn = (bearingToNext - bearingFromPrev + 360) % 360;
    if (turn < 45 || turn > 315) return "Straight";
    if (turn < 135) return "Turn left";
    if (turn < 225) return "Turn around";
    return "Turn right";
  }

  double _bearing(LatLng from, LatLng to) {
    double lat1 = from.latitude * (pi / 180);
    double lon1 = from.longitude * (pi / 180);
    double lat2 = to.latitude * (pi / 180);
    double lon2 = to.longitude * (pi / 180);
    double dLon = lon2 - lon1;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double brng = atan2(y, x);
    return ((brng * 180 / pi) + 360) % 360;
  }

  double _distance(LatLng p1, LatLng p2) {
    return Geolocator.distanceBetween(p1.latitude, p1.longitude, p2.latitude, p2.longitude);
  }

 void _startVoiceNavigation(List<Map<String, dynamic>> steps) async {
  _instructionTimer?.cancel();
  _currentInstructionIndex = 0;

  for (var step in steps) {
    final dist = step['distance'] as double;
    final instruction = step['instruction'] as String;
    final text = dist < 100
        ? '$instruction in ${dist.toStringAsFixed(0)} meters'
        : '$instruction in ${(dist / 1000).toStringAsFixed(1)} km';

    await _tts.speak(text);
    await Future.delayed(Duration(seconds: (step['duration'] as double).toInt().clamp(5, 60)));
  }

  _tts.speak('You have arrived at your destination.');
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
          setState(() {});
        } else if (data['type'] == 'message') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => InboxScreen(isProvider: true)));
        }
      },
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _showNotification(RemoteMessage message) {
    final n = message.notification!;
    _notificationsPlugin.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails('high_importance_channel', 'High Importance Notifications'),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _initBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdmobConfig().banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdLoaded = true),
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    )..load();
  }

  void _initInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdmobConfig().interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (_) => _initInterstitialAd(),
          );
        },
        onAdFailedToLoad: (_) => _isInterstitialAdLoaded = false,
      ),
    );
  }




Future<void> _loadProviderData() async {
  if (!mounted) return;

  setState(() => _isLoadingProfile = true);

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoadingProfile = false);
      return;
    }

    // Step 1: Get raw provider document
    final docRef = FirebaseFirestore.instance.collection('providers').doc(user.uid);
    final doc = await docRef.get();

    if (!doc.exists) {
      setState(() => _isLoadingProfile = false);
      return;
    }

    final data = doc.data()!;
    final priorityUntil = data['priorityUntil'] as Timestamp?;
    final subscriptionEnd = data['subscriptionEnd'] as Timestamp?;
    final currentAdFree = data['adFree'] as bool? ?? false;

    // Step 2: AUTO-EXPIRY LOGIC – Check and update if expired
    final now = DateTime.now();
    bool shouldBeAdFree = currentAdFree;
    Map<String, dynamic>? updateFields;

    if (priorityUntil != null && priorityUntil.toDate().isBefore(now)) {
      shouldBeAdFree = false;
      updateFields ??= {};
      updateFields['priorityUntil'] = FieldValue.delete();
      updateFields['adFree'] = false;
    }

    if (subscriptionEnd != null && subscriptionEnd.toDate().isBefore(now)) {
      shouldBeAdFree = false;
      updateFields ??= {};
      updateFields['subscriptionEnd'] = FieldValue.delete();
      updateFields['adFree'] = false;
    }

    // Apply update if needed
    if (updateFields != null) {
      await docRef.update(updateFields);
      debugPrint('Provider adFree expired → reset to false');
    }

    // Step 3: Load fresh profile data (after possible update)
    final profile = await _firestore.getProviderProfile(user.uid);
    final provider = Provider.fromFirestore(doc);

    if (mounted) {
      setState(() {
        _provider = provider;
        _isAdFree = shouldBeAdFree; // Use corrected value
        profilePicUrl = profile?.profilePicUrl;
        _isLoadingProfile = false;
      });
    }

    // Step 4: Update location (only if still mounted)
    if (mounted) await _updateLocation();

  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading profile: $e')),
      );
      setState(() => _isLoadingProfile = false);
    }
  }
}




 Future<void> _updateLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);

      // Use Geolocator.distanceBetween instead of distanceTo
      final distance = _providerPosition == null
          ? 100.0
          : Geolocator.distanceBetween(
              _providerPosition!.latitude,
              _providerPosition!.longitude,
              position.latitude,
              position.longitude,
            );

      if (distance > 50) {
        _providerPosition = position;
        if (_provider != null) {
          await FirebaseFirestore.instance.collection('providers').doc(_provider!.id).update({
            'location': GeoPoint(position.latitude, position.longitude),
            'lastActive': FieldValue.serverTimestamp(),
          });
        }
      }
    }catch(e){

 debugPrint(
     'Location error $e');

}
  }




Future<void> _batchFetchUsers(
    List<String> userIds) async {

  final missing =
      userIds.where(
          (id)=>!_userCache.containsKey(id))
      .toList();

  if(missing.isEmpty) return;

  try {

    for(int i=0;
        i<missing.length;
        i+=10){

      final chunk =
          missing.skip(i).take(10).toList();

      final snap =
          await FirebaseFirestore.instance
          .collection('users')
          .where(
              FieldPath.documentId,
              whereIn: chunk)
          .get();

      for(final doc in snap.docs){

        _userCache[doc.id] =
            doc.data();
      }
    }

  } catch(e){

    debugPrint(
        'User batch fetch error $e');
  }
}

   Future<void> _acceptRequest(String requestId) async {
    setState(() => _acceptingRequests[requestId] = true);
    try {
      if (_provider == null) return;

      final requestRef = FirebaseFirestore.instance.collection('requests').doc(requestId);
      final requestSnap = await requestRef.get();
      if (!requestSnap.exists) return;

      final data = requestSnap.data()!;
      final userId = data['userId'] as String?;
      final issue = data['issue'] ?? data['service'] ?? 'service';

      await requestRef.update({
        'providerId': _provider!.id,
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      if (userId != null) {
        await NotificationService.sendToUser(
          userId: userId,
          title: "Request Accepted",
          body: "${_provider!.name} is on the way to help with your $issue!",
          data: {"type": "request", "requestId": requestId},
        );
      }
    } catch (e) {
      debugPrint('Accept request failed: $e');
    }finally {

 if(!mounted) return;

 setState(() {

   _acceptingRequests[
      requestId]=false;

 });

}
  }


  Future<void> _closeRequest(String requestId, String status, String userId, String issue) async {
    setState(() => _acceptingRequests[requestId] = true);
    try {
      final update = {
        'status': status == 'completed' ? 'provider_completed' : 'canceled',
        status == 'completed' ? 'providerCompletedAt' : 'canceledAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update(update);
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
     

      
 await _firestore.addUserNotification(
         // recipientUid: userId,
          userId:userId,
          title: status == 'completed' ? 'Service Completed' : 'Request Canceled',
          body: status == 'completed'
              ? 'Your request for $issue has been completed by ${_provider!.name}.'
              : 'Your request for $issue has been canceled by ${_provider!.name}.',
          type: 'request',
          id: requestId,
        );


final subscriptionId =
 userDoc.data()?[
 'oneSignalSubscriptionId'
 ] as String?;

if(subscriptionId == null){
   return;
}

 
        await NotificationService.sendToSubscriptionIds(
 subscriptionIds: [subscriptionId],
  title: status == 'completed' ? "Service Completed" : "Request Canceled",
  body: status == 'completed'
      ? "${_provider!.name} marked your request as completed."
      : "${_provider!.name} canceled the request.",
  data: {"type": "request", "requestId": requestId},
);

  }  catch (e) {
      debugPrint('Accept request failed: $e');
    } finally {

 if(!mounted) return;

 setState(() {

   _acceptingRequests[
      requestId]=false;

 });

}
  }

  void _showCloseRequestDialog(String requestId, String userId, String issue) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Close Request'),
        content: const Text('How would you like to close this request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await _closeRequest(requestId, 'completed', userId, issue);
              Navigator.pop(context);
            },
            child: const Text('Completed'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
          ElevatedButton(
            onPressed: () async {
              await _closeRequest(requestId, 'canceled', userId, issue);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          ),
        ],
      ),
    );
  }

Widget _infoBadge(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blue[700]),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue[700])),
        ],
      ),
    );

Widget _miniButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}

void _showMapBottomSheet(LatLng end, String requestId, Map<String, dynamic> userData, List<Map<String, dynamic>> steps) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.85,   // Start BIG
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Stack(
          children: [
            // FULL MAP
            Positioned.fill(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: _cacheDir == null
                    ? const Center(child: CircularProgressIndicator())
                    : FlutterMap(
                        mapController: MapController(),
                        options: MapOptions(
                          center: _mapCenter,
                          zoom: 15.5,
                          interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c'],
                            tileProvider: NetworkTileProvider(),
                          ),
                          PolylineLayer(
                            polylines: [Polyline(points: _polylinePoints, color: Colors.blueAccent, strokeWidth: 6)],
                          ),
                          MarkerLayer(markers: [
                            // PROVIDER: Floating Toolbox
                            Marker(
                              point: _mapCenter!,
                              width: 80,
                              height: 80,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SvgPicture.asset('assets/icons/toolbox.svg', width: 36, height: 36, colorFilter: const ColorFilter.mode(Colors.green, BlendMode.srcIn)),
                                    const Text('Me', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                                  ],
                                ),
                              ),
                            ),
                            // USER: Floating Avatar
                            Marker(
                              point: end,
                              width: 80,
                              height: 90,
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: Colors.white,
                                    child: CircleAvatar(
                                      radius: 20,
                                      backgroundImage: userData['profilePicUrl'] != null
                                          ? NetworkImage(userData['profilePicUrl'])
                                          : const AssetImage('assets/default_profile.png') as ImageProvider,
                                    ),
                                  ),
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                                    child: Text(
                                      userData['name'].toString().split(' ').first,
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ],
                      ),
              ),
            ),

            // TOP BAR (Compact)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.navigation_rounded, color: Colors.blue, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      'Live Navigation',
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    _infoBadge(Icons.access_time, '${_etaMinutes!.toStringAsFixed(0)} min'),
                    const SizedBox(width: 8),
                    _infoBadge(Icons.straighten, '${_routeDistance!.toStringAsFixed(1)} km'),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        _rerouteTimer?.cancel();
                        _instructionTimer?.cancel();
                         _cleanupNavigation(requestId); // <-- ADD THIS
    
                        _tts.stop();
                        setState(() => _showMap = false);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // FLOATING VOICE BUTTON
            Positioned(
              bottom: 100,
              right: 16,
              child: FloatingActionButton(
                heroTag: 'voice',
                backgroundColor: Colors.orange,
                child: const Icon(Icons.volume_up, color: Colors.white),
                onPressed: () => _startVoiceNavigation(steps),
              ),
            ),

            // BOTTOM ACTION BAR (Compact)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _miniButton(
                        icon: Icons.map,
                        label: 'Google',
                        color: Colors.green,
                        onTap: () => _launchGoogleMaps(GeoPoint(end.latitude, end.longitude)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniButton(
                        icon: Icons.message,
                        label: 'ETA',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pop(context);
                          _sendQuickReply(requestId, 'On my way! ETA: ${_etaMinutes!.toStringAsFixed(0)} min');
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}


void _showNavigationMap(GeoPoint destination, String requestId) async {
  // ── VALIDATE REQUEST ─────────────────────────────────────
  final doc = await FirebaseFirestore.instance
      .collection('requests')
      .doc(requestId)
      .get();

  final data = doc.data();
  if (data == null) {
    _showSnack('Request not found.');
    return;
  }

  final status = data['status'] as String?;
  final providerId = data['providerId'] as String?;

  if (status != 'accepted' || providerId != _provider!.id) {
    _showSnack('You can only navigate to requests you have accepted.');
    return;
  }

  final end = LatLng(destination.latitude, destination.longitude);
  final userId = data['userId'] as String;
  final userData = _userCache[userId] ?? {'name': 'User', 'profilePicUrl': null};

  // ── INITIAL ROUTE & SHOW MAP ─────────────────────────────
  final route = await _fetchAndShowRoute(end, requestId, userData, isInitial: true);
  if (route == null) {
    _showSnack('Failed to calculate route. Check your connection.');
    return;
  }

  // ── FIX: extract steps **after** we know route != null ───
  final List<Map<String, dynamic>> steps = route['steps'] as List<Map<String, dynamic>>;

  // ── START LIVE REROUTING & VOICE NAV ─────────────────────
  _rerouteTimer?.cancel();
  _instructionTimer?.cancel();
  _tts.stop();

  _lastProviderPos = LatLng(_providerPosition!.latitude, _providerPosition!.longitude);

  // start voice
  _startVoiceTurnByTurn(steps, end);

  // start rerouting
  _rerouteTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
    final currentPos = LatLng(_providerPosition!.latitude, _providerPosition!.longitude);
    final moved = Geolocator.distanceBetween(
      _lastProviderPos!.latitude,
      _lastProviderPos!.longitude,
      currentPos.latitude,
      currentPos.longitude,
    );

    if (moved > 40 || _routeCache[requestId] == null) {
      final newRoute = await OSMNavigationService.getRoute(currentPos, end);
      if (newRoute != null) {
        _routeCache[requestId] = newRoute;
        _lastProviderPos = currentPos;

        // update map if it is still open
        if (_showMap && mounted) {
          setState(() {
            _polylinePoints = newRoute['points'];
            _etaMinutes = newRoute['duration_min'];
            _routeDistance = newRoute['distance_km'];
          });
        }

        // update voice
        _instructionTimer?.cancel();
        final newSteps = newRoute['steps'] as List<Map<String, dynamic>>;
        _startVoiceTurnByTurn(newSteps, end);
      }
    }

    // ── ARRIVAL DETECTION ───────────────────────────────────
    final distToDest = Geolocator.distanceBetween(
      currentPos.latitude,
      currentPos.longitude,
      end.latitude,
      end.longitude,
    );

    if (distToDest < 80) {
      _cleanupNavigation(requestId);
      _tts.speak('You have arrived at the destination.').then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You have arrived!'), backgroundColor: Colors.green),
          );
        }
      });
    }
  });
}

void _startVoiceTurnByTurn(List<Map<String, dynamic>> steps, LatLng destination) async {
  if (steps.isEmpty) return;


 _voiceNavigationActive = true;
  _instructionTimer?.cancel();
  _currentInstructionIndex = 0;

 /**  if (steps.isEmpty) {
    _tts.speak('Follow the route to your destination.');
    return;
  }*/

  for (int i = 0; i < steps.length; i++) {
    final step = steps[i];
    final instruction = step['instruction'] as String;
    final distance = step['distance'] as double;
    final duration = (step['duration'] as double).toInt();

    // Format distance
    final distText = distance < 1000
        ? '${distance.toStringAsFixed(0)} meters'
        : '${(distance / 1000).toStringAsFixed(1)} kilometers';

    // Natural phrasing
    final text = switch (instruction.toLowerCase()) {
      'turn left' => 'In $distText, turn left.',
      'turn right' => 'In $distText, turn right.',
      'sharp left' => 'In $distText, make a sharp left.',
      'sharp right' => 'In $distText, make a sharp right.',
      'straight' => 'Continue straight for $distText.',
      'u-turn' => 'In $distText, make a U-turn.',
      'arrive' => 'You will arrive at your destination.',
      _ => '$instruction in $distText.',
    };

    if (!_voiceNavigationActive) break;

    await _tts.speak(text);

    if (!_voiceNavigationActive) break;

    final waitSeconds = (duration * 0.75).clamp(4, 50).toInt();
    await Future.delayed(Duration(seconds: waitSeconds));
  }

 if (_voiceNavigationActive) {
    await _tts.speak('Approaching destination. Get ready to stop.');
  }
}

// --- HELPER: CLEANUP WHEN MAP CLOSES OR ARRIVED ---
void _cleanupNavigation(String requestId) {
  _rerouteTimer?.cancel();
  _rerouteTimer = null;
  _instructionTimer?.cancel();
  _instructionTimer = null;
   _voiceNavigationActive = false;  
  _tts.stop();
  _routeCache.remove(requestId);
  if (mounted) setState(() => _showMap = false);
}

// --- HELPER: SHOW SNACKBAR ---
void _showSnack(String message) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}



Future<Map<String, dynamic>?> _fetchAndShowRoute(LatLng end, String requestId, Map<String, dynamic> userData, {required bool isInitial}) async {
  final start = LatLng(_providerPosition!.latitude, _providerPosition!.longitude);
  final route = await OSMNavigationService.getRoute(start, end);
  if (route == null) return null;

  _routeCache[requestId] = route;

  setState(() {
    _mapCenter = start;
    _polylinePoints = route['points'];
    _etaMinutes = route['duration_min'];
    _routeDistance = route['distance_km'];
  });

  if (isInitial) {
    _showMapBottomSheet(end, requestId, userData, route['steps']);
  }
   return route; // 🚀 RETURN IT
}

 

  void _launchGoogleMaps(GeoPoint dest) async {
    final url = 'https://www.google.com/maps/dir/?api=1'
        '&origin=${_providerPosition!.latitude},${_providerPosition!.longitude}'
        '&destination=${dest.latitude},${dest.longitude}'
        '&travelmode=driving';
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
  }

  Future<void> _sendQuickReply(String requestId, String message) async {
    final chatSnap = await FirebaseFirestore.instance
        .collection('chat_requests')
        .where('providerId', isEqualTo: _provider!.id)
        .where('userId', isEqualTo: requestId)
        .limit(1)
        .get();
    final chatId = chatSnap.docs.isNotEmpty ? chatSnap.docs.first.id : null;
    if (chatId != null) {

      
      await FirebaseFirestore.instance
          .collection('chat_requests')
          .doc(chatId)
          .collection('messages')
          .add({
        'text': message,
        'senderId': _provider!.id,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
    }
  }


 @override
  Widget build(BuildContext context) {
    if (_provider == null) {
      return const ProviderDashboardSkeleton();
    }

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBarWidget(
          title: 'Dashboard',
          profilePicUrl: _provider?.profilePicUrl,
          showNotifications: true,
          isProvider: true,
        ),
        drawer: AppBarWidget.buildDrawer(context: context, isProvider: true),
        body: Container(
          color: Colors.grey[50],
          child: Column(
            children: [
              if (_isOffline)
                Container(
                  color: Colors.orange,
                  padding: const EdgeInsets.all(10),
                  child: const Text("You are offline", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('Radius: ${_searchRadius.toStringAsFixed(0)} km'),
                        Expanded(
                          child: Slider(
                            min: 5,
                            max: 100,
                            value: _searchRadius,
                            onChanged: (v) => setState(() => _searchRadius = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildRequestsList()),
            ],
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isAdFree) const BannerAdWidget(),
            const ProviderBottomNavBar(currentIndex: 0),
          ],
        ),
      ),
    );
  }



List<String> extractValidUserIds(
    List<QueryDocumentSnapshot> docs) {

  return docs
      .map((d) =>
          d.data() as Map<String,dynamic>)
      .map(
          (data) => data['userId'] as String?)
      .where(
          (id) => id != null && id.isNotEmpty)
      .cast<String>()
      .toSet()
      .toList();
}


// Add this method inside _ProviderDashboardState class
GeoPoint? _extractGeoPoint(dynamic rawLocation) {
  if (rawLocation == null) return null;
  
  // If Firestore returns the correct type
  if (rawLocation is GeoPoint) return rawLocation;
  
  // If it's stored as a Map (manual serialization)
  if (rawLocation is Map) {
    try {
      final lat = (rawLocation['latitude'] as num?)?.toDouble();
      final lng = (rawLocation['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        return GeoPoint(lat, lng);
      }
    } catch (e) {
      debugPrint('Error parsing location: $e');
    }
  }
  return null;
}

Widget _buildRequestsList() {
  // Profile must be loaded
  if (_provider == null) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading your profile...'),
        ],
      ),
    );
  }

  final myId = _provider!.id;

  // Location status
  final bool hasLocation = _providerPosition != null;
  final bool locationPermissionDenied = /* we'll track this */ false; // optional later

  return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
        .collection('requests')
        .where('status', whereIn: ['open', 'accepted', 'provider_completed', 'canceled'])
        .orderBy('createdAt', descending: true)
        .limit(30)                    // ← Performance improvement
        .snapshots(),
  
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final docs = snapshot.data!.docs;
      if (docs.isEmpty) {
        return const Center(child: Text('No requests at the moment'));
      }

   

    final userIds =
    extractValidUserIds(docs);

Future.microtask(() {
   _batchFetchUsers(userIds);
});

      // Filter visible requests
      final List<QueryDocumentSnapshot> visible = [];

      for (final doc in docs) {
         final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        final providerId = data['providerId'] as String?;

        if (status == 'open') {
          visible.add(doc);
        } else if (providerId == myId) {
          visible.add(doc); // always show my history
        }
      }

      // Apply distance filter ONLY if we have location
      List<QueryDocumentSnapshot> filteredOpen = visible.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['status'] != 'open') return true;

        if (!hasLocation) return false; // Don't show ANY open requests without location

         final dynamic rawLoc = data['location'];
              final loc = _extractGeoPoint(rawLoc);
              if (loc == null) return false; // Skip if location invalid

        final distKm = Geolocator.distanceBetween(
              _providerPosition!.latitude,
              _providerPosition!.longitude,
              loc.latitude,
              loc.longitude,
            ) / 1000;

        return distKm <= _searchRadius || _showAllNewRequests;
      }).toList();

      final myHistory = visible.where((d) {
        final data = d.data() as Map<String, dynamic>;
        return data['providerId'] == myId && data['status'] != 'open';
      }).toList();

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('New Requests', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),

            // LOCATION PROMPT — Only show if no location yet
            if (!hasLocation)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Card(
                  color: Colors.blue[50],
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.location_searching, size: 48, color: Colors.blue),
                        const SizedBox(height: 12),
                        const Text(
                          'Location Needed',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'We need your location to show nearby requests.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () async {
                            // Trigger location request
                            await _updateLocationInBackground();
                            if (mounted) setState(() {}); // refresh UI
                          },
                          icon: const Icon(Icons.my_location),
                          label: const Text('Use Current Location'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Show requests only if we have location
            if (hasLocation) ...[
              if (filteredOpen.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No requests within your search radius'),
                  ),
                )
              else
              //  ...filteredOpen.map((doc) => _buildRequestTile(doc)).toList(),
              ...filteredOpen.map((doc) => _buildRequestTile(doc, section: 'new')).toList(),
            ],

            // My History (always shown)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Switch(
                    value: _showClosedRequests,
                    onChanged: (v) => setState(() => _showClosedRequests = v),
                  ),
                ],
              ),
            ),

            if (myHistory.isEmpty)
              const Center(child: Text('No completed requests yet'))
            else
             ...myHistory
    .where((_) => _showClosedRequests)
    .map((doc) => _buildRequestTile(doc, section: 'history'))
    .toList(),
          ],
        ),
      );
    },
  );
}





Widget _buildNearbyRequestsTab() {
  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('requests')
        .where('status', whereIn: ['open', 'pending', 'accepted', 'provider_completed', 'canceled'])
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

      final requests = snapshot.data!.docs;
      if (requests.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset('assets/lottie/no_requests.json', width: 200),
              const Text("No requests nearby", style: TextStyle(fontSize: 18)),
              ElevatedButton.icon(
                onPressed: () => setState(() => _searchRadius = 100),
                icon: const Icon(Icons.zoom_out_map),
                label: const Text("Expand Search"),
              ),
            ],
          ).animate().fadeIn(),
        );
      }

      return StatefulBuilder(
        builder: (context, setStateInner) {
        /**  final userIds = requests
    .map((d) => d.data() as Map<String,dynamic>)
    .map((data) => data['userId'] as String?)
    .where((id) => id != null)
    .cast<String>()
    .toSet()*/
final userIds =
    extractValidUserIds(requests);

Future.microtask(() {
   _batchFetchUsers(userIds);
});

          // -------------------------------------------------
          //  NEW FILTERING LOGIC
          // -------------------------------------------------
          final myId = _provider!.id;

          final List<QueryDocumentSnapshot> visible = [];

          for (final doc in requests) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] as String;
            final providerId = data['providerId'] as String?;

            // 1. Open → show to everyone
            if (status == 'open') {
              visible.add(doc);
              continue;
            }

            // 2. Accepted by someone else → hide
            if (status == 'accepted' && providerId != null && providerId != myId) {
              continue;
            }

            // 3. Anything that *I* have touched (accepted, completed, canceled)
            if (providerId == myId &&
                (status == 'accepted' ||
                 status == 'provider_completed' ||
                 status == 'canceled')) {
              visible.add(doc);
              continue;
            }
          }

          // Respect radius for **open** requests only
          final openWithinRadius = _showAllNewRequests
              ? visible.where((d) => (d.data() as Map)['status'] == 'open').toList()
              : visible
                  .where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    if (data['status'] != 'open') return true; // my own → always show
                     final loc = _extractGeoPoint(data['location']);
                    if (loc == null) return false; // Skip if location invalid
                    
                    final dist = Geolocator.distanceBetween(
                      _providerPosition!.latitude,
                      _providerPosition!.longitude,
                      loc.latitude,
                      loc.longitude,
                    ) / 1000;
                    return dist <= _searchRadius;
                  })
                  .where((d) => (d.data() as Map)['status'] == 'open')
                  .toList();

          final newReqs = openWithinRadius;

          final history = visible.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final status = data['status'] as String;
            return (status == 'accepted' ||
                status == 'provider_completed' ||
                status == 'canceled') &&
                data['providerId'] == myId;
          }).toList();

          // -------------------------------------------------
          //  UI RENDERING (unchanged)
          // -------------------------------------------------
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('New Requests', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                if (newReqs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('No new requests'),
                  ),
                ...newReqs.map((doc) => _buildRequestTile(doc)).toList(),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Switch(
                        value: _showClosedRequests,
                        onChanged: (v) {
                          setState(() => _showClosedRequests = v);
                          setStateInner(() {});
                        },
                      ),
                    ],
                  ),
                ),
                if (history.isEmpty || !_showClosedRequests)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('No history'),
                  ),
                ...history
                    .where((d) => _showClosedRequests)
                    .map((doc) => _buildRequestTile(doc))
                    .toList(),
              ],
            ),
          );
        },
      );
    },
  );
}

 
Widget _buildRequestTile(QueryDocumentSnapshot doc, {String section = 'default'}) {
 final data = doc.data() as Map<String, dynamic>;
    final requestId = doc.id;
 final userId =
    data['userId'] as String?;

 final location = _extractGeoPoint(data['location']);

if(
 userId == null ||
 location == null ||
 _providerPosition == null ||
 _provider == null
){

 debugPrint(
  'Bad request ${doc.id}'
 );

 return const SizedBox.shrink();
}
final provider =
    _provider!;

final providerPos =
    _providerPosition!;

    final status = data['status'] as String? ?? 'open';
    final providerId = data['providerId'] as String?;
    final issue = (data['issue'] ?? data['service'] ?? 'Service Request') as String;
    final locationDesc = data['locationDescription'] as String?;
    final notes = data['notes'] as String?;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();


   
  final isAccepted = status == 'accepted' && data['providerId'] == _provider!.id;
  final isClosed = ['provider_completed', 'canceled'].contains(status);
 
  final isPriority = data['isPriority'] as bool? ?? false;


  final distance = Geolocator.distanceBetween(
        providerPos.latitude,
       providerPos.longitude,
        location.latitude,
        location.longitude,
      ) / 1000;

  final user = _userCache[userId] ?? {'name': 'Loading...', 'profilePicUrl': null};
  final name = user['name']?.toString() ?? 'Unknown';
  final pic = user['profilePicUrl']?.toString();

  // NEW: Extract fields
 

  final timeText = createdAt != null
      ? timeago.format(createdAt, locale: 'en_short')
      : 'just now';

  return Slidable(
    key: ValueKey('$requestId-$section'),
    endActionPane: ActionPane(
      motion: const DrawerMotion(),
      children: [
        if (!isClosed && !isAccepted)
          SlidableAction(
            onPressed: (_) => _acceptRequest(requestId),
            backgroundColor: Colors.green,
            icon: Icons.check,
            label: 'Accept',
          ),
        if (isAccepted)
          SlidableAction(
            onPressed: (_) => _showCloseRequestDialog(requestId, userId, data['issue'] ?? 'Service'),
            backgroundColor: Colors.orange,
            icon: Icons.close,
            label: 'Close',
          ),
      ],
    ),
    child: Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Avatar + Name + Distance
            Row(
              children: [


               GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                     builder: (_) => UserProfileScreen(userId: userId),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundImage: pic != null
                        ? CachedNetworkImageProvider(pic)
                        : const AssetImage('assets/default_profile.png') as ImageProvider,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfileScreen(userId: userId),
                          ),
                        ),
                        child: Text(
                          name,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            '${distance.toStringAsFixed(1)} km',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                           Text(
                            timeText,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _statusChip(status),
                          if (isPriority) _priorityChip(),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_acceptingRequests[requestId] == true)
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                else if (isAccepted)
                  const Icon(Icons.check_circle, color: Colors.green)
                else if (isClosed)
                  const Icon(Icons.done_all, color: Colors.grey),
              ],
            ),

            const SizedBox(height: 8),

            // Issue
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.build, size: 16, color: Colors.purple),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      data['issue'] ?? data['service'] ?? 'Service',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Location Description
            if (locationDesc != null && locationDesc.isNotEmpty)
              _detailRow(
                icon: Icons.pin_drop,
                label: 'Location',
                value: locationDesc,
                color: Colors.blue,
              ),

            // Notes
            if (notes != null && notes.isNotEmpty)
              _detailRow(
                icon: Icons.note,
                label: 'Notes',
                value: notes,
                color: Colors.orange,
              ),

            const SizedBox(height: 8),

            // Tap to Navigate
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                  icon: const Icon(Icons.navigation, size: 16),
                label: const Text('Navigate', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(foregroundColor: Colors.blue),
                 onPressed: () async {
  final isAcceptedByMe = status == 'accepted' && data['providerId'] == _provider!.id;

  if (isAcceptedByMe) {
    _showNavigationMap(location, requestId);
  } else if (status == 'open') {
    // Show Accept/Cancel dialog
    final accepted = await _showAcceptDialog(
      context: context,
      userName: name,
      issue: data['issue'] ?? data['service'] ?? 'Service',
      distance: distance,
    );
    if (accepted == true && mounted) {
      await _acceptRequest(requestId);
      if (mounted) {
        _showNavigationMap(location, requestId);
      }
    }
  } else {
    // Already accepted by someone else
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This request has already been accepted by another provider.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
},//() => _showNavigationMap(location, requestId),
              
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.1),
  );
}

Future<bool?> _showAcceptDialog({
  required BuildContext context,
  required String userName,
  required String issue,
  required double distance,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.help_outline, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text('Accept Request?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('User: $userName', style: GoogleFonts.poppins()),
          const SizedBox(height: 4),
          Text('Issue: $issue', style: GoogleFonts.poppins()),
          const SizedBox(height: 4),
          Text('Distance: ${distance.toStringAsFixed(1)} km', style: GoogleFonts.poppins()),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('Accept', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
Widget _detailRow({
  required IconData icon,
  required String label,
  required String value,
  required Color color,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
              children: [
                TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: value),
              ],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

  Widget _statusChip(String status) {
    final map = {
      'open': (Colors.blue, 'Open'),
      'accepted': (Colors.green, 'Accepted'),
      'provider_completed': (Colors.purple, 'Done'),
      'canceled': (Colors.red, 'Canceled'),
    };
    final (color, label) = map[status] ?? (Colors.grey, status);
    return Chip(label: Text(label, style: const TextStyle(fontSize: 10)), backgroundColor: color.withOpacity(0.2));
  }

  Widget _priorityChip() => Chip(
        label: const Text('Priority', style: TextStyle(fontSize: 10)),
        backgroundColor: Colors.orange.withOpacity(0.2),
      );
}


class ProviderDashboardSkeleton extends StatelessWidget {
  const ProviderDashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loading Dashboard...')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}