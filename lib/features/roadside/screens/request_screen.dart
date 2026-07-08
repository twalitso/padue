
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/notification_service.dart';
import 'package:padue/core/utils.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/roadside/models/provider.dart';
import 'package:padue/features/roadside/screens/bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/inbox_screen.dart';
import 'package:padue/features/roadside/screens/notifications_screen.dart';
import 'package:padue/features/roadside/screens/view_provider_profile_screen.dart';
import 'package:padue/features/roadside/screens/browse_providers_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_geohash/dart_geohash.dart';
import 'package:http/http.dart' as http;  

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> with WidgetsBindingObserver {
  final FirestoreService _firestore = FirestoreService();
  UserProfile? _profile;
  String? _selectedService;
  Position? _userLocation;
  String? _locationName;
  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  bool _isBannerAdLoaded = false;
  bool _isInterstitialAdLoaded = false;
  bool _isAdFree = false;
  bool _isSubmitting = false;
  List<String> _availableServices = [];
  final TextEditingController _locationDescriptionController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Show UI instantly with cache
    _loadFromCacheFirst();

    // Background warmup after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
   //     _getCurrentDeviceLocation();
      _warmupInBackground();
    });
  }
Future<void> _getCurrentDeviceLocation() async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services')),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission required to request help')),
        );
      }
      return;
    }

    // Get fresh position
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );

    String? locationName = 'Your Location';
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        locationName = [
          place.street,
          place.locality,
          place.subAdministrativeArea,
        ].where((e) => e != null && e.isNotEmpty).join(', ');
      }
    } catch (_) {
      // Ignore reverse geocoding errors
    }

    // Update state
    if (mounted) {
      setState(() {
        _userLocation = position;
        _locationName = locationName;
      });

      // Optional: Cache it
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_user_location',
        jsonEncode({
          'lat': position.latitude,
          'lng': position.longitude,
          'name': locationName,
        }),
      );
    }
  } catch (e) {
    debugPrint('Failed to get current location: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not get your location. Tap "Retry" to try again.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
  Future<void> _loadFromCacheFirst() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedProfile = prefs.getString('cached_user_profile');
    final cachedLocation = prefs.getString('cached_user_location');

    if (cachedProfile != null) {
      final data = jsonDecode(cachedProfile);
      setState(() {
        _profile = UserProfile.fromMap(data);
      });
    }

    if (cachedLocation != null) {
      final loc = jsonDecode(cachedLocation);
      _userLocation = Position(
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
      _locationName = loc['name'] ?? 'Your Location';
    }

    if (mounted) setState(() {});
  }

  Future<void> _warmupInBackground() async {
    unawaited(Future.wait([
      _refreshUserProfileAndLocation(),
      _loadAvailableServices(),
      _loadBannerAd(),
      _loadInterstitialAd(),
      _setupNotifications(),
      saveUserOneSignalSubscriptionId(FirebaseAuth.instance.currentUser!.uid),
      saveFcmToken(),
      updateUserLocation(),
    ], eagerError: true));
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




Future<void> _refreshUserProfileAndLocation() async {
  if (!mounted) return;

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await userRef.get();
    if (!doc.exists) return;

    final data = doc.data()!;

    Timestamp? priorityUntil = data['priorityUntil'] as Timestamp?;
    Timestamp? subscriptionEnd = data['subscriptionEnd'] as Timestamp?;
    final bool currentAdFree = data['adFree'] == true;

    final now = DateTime.now();
    Map<String, dynamic>? updates;

    // -------- Expiry cleanup --------
    if (priorityUntil != null && priorityUntil.toDate().isBefore(now)) {
      updates ??= {};
      updates['priorityUntil'] = FieldValue.delete();
      priorityUntil = null;
    }

    if (subscriptionEnd != null && subscriptionEnd.toDate().isBefore(now)) {
      updates ??= {};
      updates['subscriptionEnd'] = FieldValue.delete();
      subscriptionEnd = null;
    }

    // -------- Recompute truth --------
    final bool shouldBeAdFree = computeAdFree(
      priorityUntil: priorityUntil,
      subscriptionEnd: subscriptionEnd,
    );

    // -------- Sync Firebase only if needed --------
    if (currentAdFree != shouldBeAdFree) {
      updates ??= {};
      updates['adFree'] = shouldBeAdFree;
    }

    if (updates != null) {
      await userRef.update(updates);
    }

    // -------- Profile --------
    final profile = await _firestore.getUserProfile(user.uid);

    // -------- Location (best effort) --------
    Position? position;
    String? name;

    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      final places = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (places.isNotEmpty) {
        name = '${places.first.street}, ${places.first.locality}';
      }
    } catch (_) {}

    // -------- Cache --------
    final prefs = await SharedPreferences.getInstance();

    if (position != null) {
      await prefs.setString(
        'cached_user_location',
        jsonEncode({
          'lat': position.latitude,
          'lng': position.longitude,
          'name': name ?? 'Location',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    }

    if (profile != null) {
      final map = profile.toMap();

      map.forEach((k, v) {
        if (v is Timestamp) {
          map[k] = v.millisecondsSinceEpoch;
        } else if (v is GeoPoint) {
          map[k] = {
            'latitude': v.latitude,
            'longitude': v.longitude,
          };
        }
      });

      await prefs.setString('cached_user_profile', jsonEncode(map));
    }

    // -------- UI --------
    if (mounted) {
      setState(() {
        _profile = profile;
        _isAdFree = shouldBeAdFree;

        if (position != null) {
          _userLocation = position;
          _locationName = name ?? 'Location';
        }
      });
    }
  } catch (e) {
    debugPrint('User refresh failed: $e');
  }
}



  Future<void> _refreshUserProfileAndLocationold() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final profile = await _firestore.getUserProfile(user.uid);
      final isAdFree = await _firestore.isAdFree(user.uid);
      _profile = profile;
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      ).catchError((_) => null);

      String? name;
      if (position != null) {
        List<Placemark> places = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        name = places.isNotEmpty
            ? '${places.first.street}, ${places.first.locality}'
            : 'Location';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_location',
            jsonEncode({'lat': position.latitude, 'lng': position.longitude, 'name': name}));
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _isAdFree = isAdFree;
          if (position != null) {
            _userLocation = position;
            _locationName = name ?? 'Location';
          }
        });
      }

      // Cache profile
      if (profile != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_profile', jsonEncode(profile.toMap()));
      }
    } catch (e) {
      debugPrint('User refresh failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_warmupInBackground());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _locationDescriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableServices() async {
    try {
      var options = await FirebaseFirestore.instance.collection('services').get();
      var availableServices = options.docs
          .where((doc) => doc.data().containsKey('name') && doc['name'] is String && doc['name'].isNotEmpty)
          .map((doc) => doc['name'] as String)
          .toList();
      setState(() {
        _availableServices = availableServices;
      });
    } catch (e) {
      print('Error loading services: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load services: $e')),
        );
      }
    }
  }

  Future<void> updateUserLocation() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
          print('Location permission denied');
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      GeoPoint geoPoint = GeoPoint(position.latitude, position.longitude);

      await _firestore.updateUserLocation(user.uid, geoPoint);

      print('Updated location for UID: ${user.uid} to ${geoPoint.latitude}, ${geoPoint.longitude}');
    } catch (e) {
      print('Error updating user location: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _profile = await _firestore.getUserProfile(user.uid);
      _isAdFree = await _firestore.isAdFree(user.uid);
      setState(() {});
    }
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled')),
        );
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return;
      }
      _userLocation = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (_userLocation != null) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            _userLocation!.latitude,
            _userLocation!.longitude,
          );
          if (placemarks.isNotEmpty) {
            String location = placemarks.first.street != null && placemarks.first.street!.isNotEmpty
                ? '${placemarks.first.street}, ${placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? 'Unknown'}'
                : placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? 'Unknown';
            setState(() => _locationName = location);
          } else {
            setState(() => _locationName = 'Unknown');
          }
        } catch (e) {
          setState(() => _locationName = 'Unknown');
        }
      }
      setState(() {});
    } catch (e) {
      setState(() => _locationName = 'Unknown');
    }
  }

  Future<void> _loadBannerAd() async {
    _bannerAd = BannerAd(
      adUnitId: AdmobConfig().banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          setState(() => _isBannerAdLoaded = false);
        },
      ),
    );
    await _bannerAd!.load();
  }

  Future<void> _loadInterstitialAd() async {
    InterstitialAd.load(
      adUnitId: AdmobConfig().interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => _loadInterstitialAd(),
            onAdFailedToShowFullScreenContent: (ad, error) => _loadInterstitialAd(),
          );
        },
        onAdFailedToLoad: (error) => _isInterstitialAdLoaded = false,
      ),
    );
  }

  Future<void> _setupNotifications() async {
    const channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
    );
    await _notificationsPlugin.initialize(
     settings:  const InitializationSettings(
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

  void _showNotification(RemoteMessage message) {
    final notification = message.notification!;
    _notificationsPlugin.show(
      id : notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
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

  void _showServicePicker() {
    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.99,
        minChildSize: 0.5,
        maxChildSize: 0.99,
        builder: (_, controller) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFFFF5252),Color(0xFFFF5252) ]),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select a Service', style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search services...',
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFFF5252) ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                    ),
                    onChanged: (value) => setModalState(() => searchQuery = value.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore.getServiceOptions(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      var services = snapshot.data!.docs
                          .map((doc) => doc.data() as Map<String, dynamic>)
                          .where((service) => service['name'] != null && service['name'] is String && service['name'].toString().isNotEmpty)
                          .toList();
                      if (services.isEmpty) return const Center(child: Text('No services available'));
                      var filteredServices = services.where((service) => service['name'].toLowerCase().contains(searchQuery)).toList();
                      return ListView.builder(
                        controller: controller,
                        itemCount: filteredServices.length,
                        itemBuilder: (context, index) {
                          var service = filteredServices[index];
                          String name = service['name'] as String;
                          String category = service['category'] as String? ?? 'Uncategorized';
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                            elevation: 0,
                            color: Colors.white.withOpacity(0.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFFF5252) .withOpacity(0.1),
                                child: const Icon(Icons.build, color: Color(0xFFFF5252) ),
                              ),
                              title: Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                              subtitle: Text(category, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                              onTap: () {
                                setState(() => _selectedService = name);
                                Navigator.pop(context);
                                _showRequestEmergencyDialog();
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


Future<void> _submitRequest() async {
  if (!mounted || _isSubmitting || _selectedService == null) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a service first')),
      );
    }
    return;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to continue')),
      );
    }
    return;
  }

  setState(() => _isSubmitting = true);

  try {
    // 1. Location services & permission
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const _UserFriendlyException('Location services are turned off. Please enable them.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const _UserFriendlyException('Location permission is required to submit a request.');
    }

    // 2. Get current position
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 12),
    );

    // 3. Geohash for server-side geo-query
    final geoHasher = GeoHasher();
    final geohash = geoHasher.encode(position.longitude, position.latitude, precision: 6);

    // 4. Create request document
    final requestRef = await FirebaseFirestore.instance.collection('requests').add({
      'userId': user.uid,
      'service': _selectedService,
      'location': GeoPoint(position.latitude, position.longitude),
      'geohash': geohash,
      'locationDescription': _locationDescriptionController.text.trim(),
      'notes': _notesController.text.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
    });

    final requestId = requestRef.id;

    // 5. Notify backend → it should find nearby providers & send pushes
    final response = await http.post(
      Uri.parse('https://padue-backend.twalitso.deno.net/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'requestId': requestId,
        'service': _selectedService,
        'userLocation': {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        'locationDescription': _locationDescriptionController.text.trim(),
        'userName': _profile?.name ?? 'A user',
        'geohash': geohash,           // helpful for server debugging/logging
      }),
    ).timeout(const Duration(seconds: 12));

    // 6. Handle backend response
    if (response.statusCode == 200) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request submitted! Service Providers will be notified.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushReplacementNamed(context, '/request_status');
      }
    } else {
      // You might want to log the error server-side or send it to Crashlytics
      debugPrint('Backend responded with ${response.statusCode}: ${response.body}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.statusCode == 503 || response.statusCode >= 500
                  ? 'Service is temporarily unavailable. Please try again soon.'
                  : 'Could not notify Service providers right now. Your request is still saved.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
        // Still go to status screen — request exists
        if (mounted) Navigator.pushReplacementNamed(context, '/request_status');
      }
    }
  } on _UserFriendlyException catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.orange),
      );
    }
  } on TimeoutException {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request sent, but notification is taking longer than expected.'),
          duration: Duration(seconds: 4),
        ),
      );
      if (mounted) Navigator.pushReplacementNamed(context, '/request_status');
    }
  } catch (e, stack) {
    debugPrint('Submit request failed: $e\n$stack');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Your request may still have been saved.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isSubmitting = false);
    }
  }
}

  Future<void> _submitRequestold() async {
    if (!mounted || _isSubmitting || _selectedService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a service')));
      }
      return;
    }
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not logged in')));
      }
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          throw Exception('Location permission denied');
        }
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

     


      // CHANGE HERE: Use .add() to get the reference
    final requestRef = await FirebaseFirestore.instance.collection('requests').add({
      'userId': user.uid,
      'service': _selectedService,
      'location': GeoPoint(position.latitude, position.longitude),
      'locationDescription': _locationDescriptionController.text.trim(),
      'notes': _notesController.text.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': DateTime.now(),
    });

    final String requestId = requestRef.id; // ← Now we have the ID!

    // SEND NOTIFICATION TO NEARBY PROVIDERS
    await NotificationService.sendNewRequestNotification(
      requestId: requestId,
      service: _selectedService!,
      userLocation: GeoPoint(position.latitude, position.longitude),
      locationDescription: _locationDescriptionController.text.trim(),
      userName: _profile?.name ?? 'A user',
    );
    
      if (mounted) Navigator.pushReplacementNamed(context, '/request_status');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  void _showRequestEmergencyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Request Emergency Service', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 20)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: _showServicePicker,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFFF5252),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                //  padding: const EdgeInsets.symmetric(vertical: 12 , horizontal: 12),
                ),
                child: Text(_selectedService ?? 'Select Service', style: GoogleFonts.poppins(fontSize: 16)),
              ),
              if (_selectedService != null) ...[
                const SizedBox(height: 8),
                Chip(
                  label: Text(_selectedService!, style: GoogleFonts.poppins(fontSize: 14)),
                  backgroundColor: const Color(0xFF26A69A).withOpacity(0.2),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => setState(() => _selectedService = null),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _locationDescriptionController,
                decoration: InputDecoration(
                  labelText: 'Location Description',
                  hintText: 'e.g., Near Main St.',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                ),
                maxLines: 2,
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Additional Notes (Optional)',
                  hintText: 'e.g., Urgent issue',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                ),
                maxLines: 3,
                style: GoogleFonts.poppins(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey, fontSize: 14)),
          ),
          ElevatedButton(
            onPressed: _isSubmitting ? null : () async {
              await _submitRequest();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF5252),
              // const Color(0xFF26A69A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const CircularProgressIndicator(color: Colors.white)
                : Text('Submit', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  void _postToForum() {
    Navigator.pushNamed(context, '/forum');
  }

  void _navigateToBrowseProviders(String service) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BrowseProvidersScreen(initialService: service),
      ),
    );
  }


@override
Widget build(BuildContext context) {
  final bool isLoading = _profile == null || _userLocation == null;

  return WillPopScope(
    onWillPop: () async => false,
    child: Scaffold(
      appBar: AppBarWidget(
        title: 'Roadside Assistance',
        profilePicUrl: _profile?.profilePicUrl,
        showNotifications: true,
        isProvider: false,
      ),
      drawer: AppBarWidget.buildDrawer(
        context: context,
        isProvider: false,
      ),
      body: Container(
        color: const Color(0xFFF5F5F5),
        child: Column(
          children: [
            // Show skeleton only while EITHER profile OR location is missing
            if (isLoading)
              const Expanded(child: RequestScreenSkeleton())
            else
              Expanded(child: _buildMainContent()),

            // Banner ad
            if (!_isAdFree && _isBannerAdLoaded && _bannerAd != null)
              SizedBox(
                width: double.infinity,
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),

            const BottomNavBar(currentIndex: 0),
          ],
        ),
      ),
    ),
  );
}


Widget _buildMainContent() {
  final bool hasLocation = _userLocation != null;

  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── LOCATION STATUS BANNER ─────────────────────────────────────
        if (!hasLocation)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[300]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_searching, color: Colors.orange, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Getting your current location...',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This is needed to request help nearby.',
                        style: GoogleFonts.poppins(fontSize: 14, color: Colors.orange[700]),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _getCurrentDeviceLocation,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),

        // ── EMERGENCY SERVICE BUTTON ───────────────────────────────────
        Semantics(
          label: 'Request Emergency Service',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: hasLocation
                        ? _showRequestEmergencyDialog
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Location required. Please wait or tap "Retry".'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration:  BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFF5252), Color(0xFFF97316)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.white)
                              .animate()
                              .scale(duration: 600.ms, curve: Curves.bounceOut),
                          const SizedBox(height: 8),
                          Text(
                            'Request Emergency Service',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Flat Tire, Towing, Appliance Repair, etc.',
                            style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                          if (!hasLocation) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Location required',
                              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 400.ms),
        ),

        const SizedBox(height: 16),

        // ── TOWING SERVICES ───────────────────────────────────────────
        Semantics(
          label: 'Towing Services',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _navigateToBrowseProviders('Towing'),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration:  BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(Icons.local_shipping, size: 32, color: Colors.white)
                              .animate()
                              .scale(duration: 600.ms, curve: Curves.bounceOut),
                          const SizedBox(height: 8),
                          Text(
                            'Towing Services',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
        ),

        const SizedBox(height: 16),

        // ── MECHANIC SERVICES ─────────────────────────────────────────
        Semantics(
          label: 'Mechanic Services',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _navigateToBrowseProviders('Mechanic'),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration:  BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF16A34A), Color(0xFF4ADE80)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(Icons.build, size: 32, color: Colors.white)
                              .animate()
                              .scale(duration: 600.ms, curve: Curves.bounceOut),
                          const SizedBox(height: 8),
                          Text(
                            'Mechanic Services',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
        ),

        const SizedBox(height: 16),

        // ── SECONDARY ACTIONS ─────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: 'View Nearby Service Providers',
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.8),
                        offset: const Offset(-4, -4),
                        blurRadius: 8,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        offset: const Offset(4, 4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => Navigator.pushNamed(context, '/browse_providers'),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(Icons.location_pin, size: 32, color:Color(0xFFFF5252) )
                                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                                .scale(duration: 800.ms, curve: Curves.easeInOut),
                            const SizedBox(height: 8),
                            Text(
                              'View Nearby Providers',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1F2A44),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'Find local experts',
                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ).animate().slideY(begin: 0.5, end: 0, duration: 600.ms, delay: 400.ms),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Semantics(
                label: 'Post to Forum',
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.8),
                        offset: const Offset(-4, -4),
                        blurRadius: 8,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        offset: const Offset(4, 4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _postToForum,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(Icons.forum, size: 32, color: Color(0xFFFF5252) )
                                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                                .scale(duration: 800.ms, curve: Curves.easeInOut),
                            const SizedBox(height: 8),
                            Text(
                              'Post to Forum',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1F2A44),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'Ask questions or share requests',
                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ).animate().slideY(begin: 0.5, end: 0, duration: 600.ms, delay: 500.ms),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

 Widget _buildMainContentold() {
 
    return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hero Section: Emergency Service
                      Semantics(
                        label: 'Request Emergency Service',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _showRequestEmergencyDialog,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFF5252), Color(0xFFF97316)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      children: [
                                        const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.white)
                                            .animate()
                                            .scale(duration: 600.ms, curve: Curves.bounceOut),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Request Emergency Service',
                                          style: GoogleFonts.poppins(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Flat Tire, Towing, Appliance Repair, etc.',
                                          style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ).animate().fadeIn(duration: 400.ms),
                      ),
                      const SizedBox(height: 16),
                      // Towing Services Button
                      Semantics(
                        label: 'Towing Services',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _navigateToBrowseProviders('Towing'),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      children: [
                                        const Icon(Icons.local_shipping, size: 32, color: Colors.white)
                                            .animate()
                                            .scale(duration: 600.ms, curve: Curves.bounceOut),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Towing Services',
                                          style: GoogleFonts.poppins(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                      ),
                      const SizedBox(height: 16),
                      // Mechanic Services Button
                      Semantics(
                        label: 'Mechanic Services',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _navigateToBrowseProviders('Mechanic'),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF16A34A), Color(0xFF4ADE80)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      children: [
                                        const Icon(Icons.build, size: 32, color: Colors.white)
                                            .animate()
                                            .scale(duration: 600.ms, curve: Curves.bounceOut),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Mechanic Services',
                                          style: GoogleFonts.poppins(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
                      ),
                      const SizedBox(height: 16),
                      // Secondary Actions
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              label: 'View Nearby Service Providers',
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.8),
                                      offset: const Offset(-4, -4),
                                      blurRadius: 8,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      offset: const Offset(4, 4),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: () => Navigator.pushNamed(context, '/browse_providers'),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        children: [
                                          const Icon(Icons.location_pin, size: 32, color: Color(0xFF26A69A))
                                              .animate(onPlay: (controller) => controller.repeat(reverse: true))
                                              .scale(duration: 800.ms, curve: Curves.easeInOut),
                                          const SizedBox(height: 8),
                                          Text(
                                            'View Nearby Providers',
                                            style: GoogleFonts.poppins(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF1F2A44),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          Text(
                                            'Find local experts',
                                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ).animate().slideY(begin: 0.5, end: 0, duration: 600.ms, delay: 400.ms),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Semantics(
                              label: 'Post to Forum',
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.8),
                                      offset: const Offset(-4, -4),
                                      blurRadius: 8,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      offset: const Offset(4, 4),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: _postToForum,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        children: [
                                          const Icon(Icons.forum, size: 32, color: Color(0xFF26A69A))
                                              .animate(onPlay: (controller) => controller.repeat(reverse: true))
                                              .scale(duration: 800.ms, curve: Curves.easeInOut),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Post to Forum',
                                            style: GoogleFonts.poppins(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF1F2A44),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          Text(
                                            'Ask questions or share requests',
                                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ).animate().slideY(begin: 0.5, end: 0, duration: 600.ms, delay: 500.ms),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
  }


  AppBar _buildAppBar(BuildContext context, String title, {String? profilePicUrl}) {
    return AppBar(
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
          fontSize: 22,
          color: Colors.white,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
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
      leading: IconButton(
        icon: CircleAvatar(
          radius: 16,
          backgroundImage: profilePicUrl != null && profilePicUrl.isNotEmpty
              ? NetworkImage(profilePicUrl)
              : const AssetImage('assets/default_profile.png') as ImageProvider,
          backgroundColor: Colors.white,
        ).animate().scale(duration: 800.ms, curve: Curves.easeInOut),
        onPressed: () => Navigator.pushNamed(context, '/profile'),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            bool? confirmLogout = await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.white.withOpacity(0.9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text('Confirm Logout', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                content: Text('Are you sure you want to log out?', style: GoogleFonts.poppins(fontSize: 16)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Logout', style: GoogleFonts.poppins(color: Colors.white)),
                  ),
                ],
              ),
            );
            if (confirmLogout == true) {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            }
          },
          child: Text(
            'Logout',
            style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 14),
          ).animate(onPlay: (controller) => controller.repeat(reverse: true)).scale(duration: 1000.ms, curve: Curves.easeInOut),
        ),
      ],
    );
  }
}

class RequestScreenSkeleton extends StatelessWidget {
  const RequestScreenSkeleton({super.key});
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Loading your location...', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
}
// Small helper for better UX
class _UserFriendlyException implements Exception {
  final String message;
  const _UserFriendlyException(this.message);
}



