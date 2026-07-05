import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/core/browse_providers_state.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/roadside/models/provider.dart' as provider_model;
import 'package:padue/features/roadside/screens/bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/browse_providers_map_screen.dart';
import 'package:padue/features/roadside/screens/inbox_screen.dart';
import 'package:padue/features/roadside/screens/view_provider_profile_screen.dart';
import 'package:padue/features/roadside/screens/chat_screen.dart';
import 'package:padue/core/native_ad_widget.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class BrowseProvidersScreen extends StatefulWidget {
  final String? initialService;
  const BrowseProvidersScreen({super.key, this.initialService});

  @override
  _BrowseProvidersScreenState createState() => _BrowseProvidersScreenState();
}

class _BrowseProvidersScreenState extends State<BrowseProvidersScreen> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BrowseProvidersState(),
      child: _BrowseProvidersScreenContent(initialService: widget.initialService),
    );
  }
}

class _BrowseProvidersScreenContent extends StatefulWidget {
  final String? initialService;
  const _BrowseProvidersScreenContent({Key? key, this.initialService}) : super(key: key);

  @override
  _BrowseProvidersScreenContentState createState() => _BrowseProvidersScreenContentState();
}

class _BrowseProvidersScreenContentState extends State<_BrowseProvidersScreenContent>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final FirestoreService _firestore = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoaded = false;
  DateTime? _lastInterstitialAdTime;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  Position? _lastKnownLocation;
  Timer? _debounceTimer;
  String? _pendingCategory;
  bool _isInitialized = false;
 final ValueNotifier<List<NativeAd?>> _nativeAds = ValueNotifier<List<NativeAd?>>([]);
  final ValueNotifier<bool> _isNativeAdsLoading = ValueNotifier<bool>(false);


  @override
  void initState() {
    super.initState();
    print('=== INIT STATE CALLED ===');
    WidgetsBinding.instance.addObserver(this);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isInitialized) {
        _isInitialized = true;
        print('=== POST FRAME CALLBACK - STARTING INITIALIZATION ===');
        final state = Provider.of<BrowseProvidersState>(context, listen: false);
        print('Initial state - isLoading: ${state.isLoading}');
        state.updateCategory(widget.initialService == 'All' || widget.initialService == null ? null : widget.initialService);
        _initializeScreen();
      }
    });
    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null && mounted) {
        _showNotification(message);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _getUserLocation();
      _loadInterstitialAd();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _interstitialAd?.dispose();
    _debounceTimer?.cancel();
    Provider.of<BrowseProvidersState>(context, listen: false).resetNativeAds();
    super.dispose();
  }



 Future<void> _initializeScreen() async {
    final state = Provider.of<BrowseProvidersState>(context, listen: false);
    try {
      print('Starting initialization...');
      // Step 1: Load critical items (providers) and set isLoading to false ASAP
      await _loadInitialProviders(state).timeout(const Duration(seconds: 15), onTimeout: () {
        print('Providers load timed out - setting empty list');
        state.updateState(cachedProviders: []);
      });
      state.updateState(isLoading: false);  // Critical: Set loading to false after providers
      print('Providers loaded, isLoading set to false. Cached providers: ${state.cachedProviders.length}');

      // Step 2: Background-load non-critical items (don't block the UI)
      _loadUserProfile().catchError((e) => print('User profile load failed: $e'));
      _getUserLocation().catchError((e) => print('Location load failed: $e'));
      _setupNotifications().catchError((e) => print('Notifications setup failed: $e'));
      _loadAvailableServices().catchError((e) => print('Available services load failed: $e'));
      _initializeAds().catchError((e) => print('Ads initialization failed: $e'));
    } catch (e, stackTrace) {
      print('Initialization error: $e');
      print('Stack trace: $stackTrace');
      state.updateState(isLoading: false, cachedProviders: []);  // Ensure loading stops
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Initialization failed: $e')));
      }
    }
  }

  // Updated _loadInitialProviders with better error handling
  Future<void> _loadInitialProviders(BrowseProvidersState state) async {
    try {
      print('Loading initial providers for category: ${widget.initialService ?? 'All'}');
      QuerySnapshot snapshot;
      if (widget.initialService != null && widget.initialService != 'All') {
        snapshot = await _firestore.getProvidersByService(widget.initialService!);
      } else {
        snapshot = await _firestore.getAllProviders();
      }
      print('Firestore returned ${snapshot.docs.length} documents');

      final providers = <provider_model.Provider>[];
      for (var doc in snapshot.docs) {
        try {
          final provider = provider_model.Provider.fromFirestore(doc);
          providers.add(provider);
        } catch (parseError) {
          print('Error parsing provider ${doc.id}: $parseError. Skipping...');
        }
      }
      print('Valid providers parsed: ${providers.length}');
      state.updateState(cachedProviders: providers);
    } catch (e, stackTrace) {
      print('Error loading initial providers: $e');
      print('Stack trace: $stackTrace');
      state.updateState(cachedProviders: []);
      rethrow;  // Let the caller handle it
    }
  }



  Future<void> _loadProvidersSimple(BrowseProvidersState state) async {
    try {
      print('=== LOADING PROVIDERS ===');
      print('Widget initialService: ${widget.initialService}');
      
      // Try to load ALL providers first, regardless of category
      print('Fetching ALL providers from Firestore...');
      final snapshot = await FirebaseFirestore.instance
          .collection('providers')
          .limit(100)
          .get()
          .timeout(const Duration(seconds: 15));

      print('Raw Firestore response - docs count: ${snapshot.docs.length}');
      
      if (snapshot.docs.isEmpty) {
        print('WARNING: Firestore returned 0 documents!');
        print('Check if:');
        print('1. Collection name is "providers"');
        print('2. Documents exist in Firestore');
        print('3. Firestore rules allow read access');
        state.updateState(cachedProviders: []);
        return;
      }
      
      print('Processing ${snapshot.docs.length} documents...');
      final providers = <provider_model.Provider>[];
      int successCount = 0;
      int errorCount = 0;
      
      for (var doc in snapshot.docs) {
        try {
          print('Processing doc ${doc.id}...');
          final data = doc.data();
          print('Doc ${doc.id} keys: ${data.keys.join(", ")}');
          
          final provider = provider_model.Provider.fromFirestore(doc);
          providers.add(provider);
          successCount++;
          print('✓ Success: ${provider.name} (${provider.type})');
        } catch (e, stackTrace) {
          errorCount++;
          print('✗ Error parsing doc ${doc.id}: $e');
          print('Stack: $stackTrace');
        }
      }

      print('=== PARSING COMPLETE ===');
      print('Success: $successCount, Errors: $errorCount, Total: ${providers.length}');
      state.updateState(isLoading: false);
      state.updateState(cachedProviders: providers);
      print('State updated with ${providers.length} providers');
      
    } catch (e, stackTrace) {
      print('=== CRITICAL ERROR IN _loadProvidersSimple ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      state.updateState(cachedProviders: []);
      rethrow;
    }
  }

  Future<void> _loadUserProfile() async {
    final state = Provider.of<BrowseProvidersState>(context, listen: false);
    final user = _auth.currentUser;
    if (user != null) {
      try {
        print('Loading user profile for UID: ${user.uid}');
        final profile = await _firestore.getUserProfile(user.uid);
        final isAdFree = await _firestore.isAdFree(user.uid);
        state.updateState(profile: profile, isAdFree: isAdFree);
        print('Profile loaded successfully');
      } catch (e) {
        print('Error loading profile: $e');
      }
    } else {
      print('No user logged in');
    }
  }

  Future<void> _getUserLocation() async {
    final state = Provider.of<BrowseProvidersState>(context, listen: false);
    try {
      print('Checking location services...');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services disabled');
        state.updateState(locationName: 'Unknown');
        return;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        print('Location permission denied');
        state.updateState(locationName: 'Unknown');
        return;
      }
      
      print('Getting current position...');
      final newLocation = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));
      
      _lastKnownLocation = newLocation;
      state.updateState(userLocation: newLocation);
      print('Location obtained: ${newLocation.latitude}, ${newLocation.longitude}');
      
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          newLocation.latitude,
          newLocation.longitude,
        ).timeout(const Duration(seconds: 5));
        
        if (placemarks.isNotEmpty) {
          String town = placemarks.first.locality ?? 
                       placemarks.first.subAdministrativeArea ?? 
                       'Unknown';
          state.updateState(locationName: town);
          print('Location name: $town');
        }
      } catch (e) {
        print('Error geocoding: $e');
        state.updateState(locationName: 'Unknown');
      }
    } catch (e) {
      print('Error getting location: $e');
      state.updateState(locationName: 'Unknown');
    }
  }

  Future<void> _loadAvailableServices() async {
    final state = Provider.of<BrowseProvidersState>(context, listen: false);
    try {
      print('Loading available services...');
      var options = await FirebaseFirestore.instance
          .collection('services')
          .get()
          .timeout(const Duration(seconds: 10));
      
      var availableServices = options.docs
          .where((doc) => doc.data().containsKey('name') && 
                        doc['name'] is String && 
                        doc['name'].toString().isNotEmpty)
          .map((doc) => doc['name'] as String)
          .toList();
      
      print('Available services: $availableServices');
      state.updateState(availableServices: ['All', ...availableServices]);
    } catch (e) {
      print('Error loading services: $e');
      state.updateState(availableServices: ['All']);
    }
  }

Future<void> _initializeAds() async {
  final state = Provider.of<BrowseProvidersState>(context, listen: false);
  if (state.isAdFree) {
    print('User is ad-free, skipping ad initialization');
    state.updateState(isNativeAdsLoading: false);
    return;
  }
  print('Initializing ads for non-ad-free user...');
  state.updateState(isNativeAdsLoading: true);
  try {
    await _loadNativeAds().timeout(const Duration(seconds: 20), onTimeout: () {
      print('Ad loading timed out');
      state.updateState(isNativeAdsLoading: false);
    });
  } catch (e) {
    print('Error initializing ads: $e');
    state.updateState(isNativeAdsLoading: false);
  }
  print('Ads initialization complete. Loaded ads: ${state.nativeAds.where((ad) => ad != null).length}');
}
  
Future<void> _loadNativeAds() async {
  final state = Provider.of<BrowseProvidersState>(context, listen: false);
  const int maxAds = 10;
  const int maxRetries = 10; // Increased retries for better reliability
  int retryCount = 0;
  List<NativeAd?> newAds = List.filled(maxAds, null); // Initialize with nulls

  while (retryCount <= maxRetries && mounted) {
    print('Loading native ads (attempt ${retryCount + 1}/${maxRetries + 1})...');
    List<Future> adFutures = [];
    int loadedAds = 0;

    for (int i = 0; i < maxAds; i++) {
      if (newAds[i] != null) continue; // Skip already loaded ads
      final nativeAd = NativeAd(
        adUnitId: AdmobConfig().native,
        factoryId: 'listTile',
        request: const AdRequest(),
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            print('Native ad $i loaded successfully (attempt ${retryCount + 1})');
            if (mounted) {
              newAds[i] = ad as NativeAd;
              loadedAds++;
            }
          },
          onAdFailedToLoad: (ad, error) {
            print('Native ad $i failed to load (attempt ${retryCount + 1}): $error');
            print('Error code: ${error.code}, Message: ${error.message}');
            ad.dispose();
            if (mounted) {
              newAds[i] = null;
            }
          },
        ),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.small,
          mainBackgroundColor: Colors.white,
          primaryTextStyle: NativeTemplateTextStyle(textColor: Colors.black),
          secondaryTextStyle: NativeTemplateTextStyle(textColor: Colors.black87),
          cornerRadius: 12.0,
        ),
      );
      adFutures.add(nativeAd.load());
    }

    await Future.wait(adFutures);

    if (mounted) {
      state.updateState(nativeAds: List.from(newAds));
      print('Updated state with ${newAds.where((ad) => ad != null).length} loaded ads');
    }

    if (loadedAds > 0 || retryCount == maxRetries) {
      print('Ad loading complete: $loadedAds ads loaded after ${retryCount + 1} attempts');
      break;
    }

    retryCount++;
    print('No ads loaded on attempt ${retryCount}. Retrying after 2 seconds...');
    await Future.delayed(const Duration(seconds: 2));
  }

  if (mounted && newAds.every((ad) => ad == null)) {
    print('All ad attempts failed. Check AdMob configuration and network connectivity.');
    state.updateState(isNativeAdsLoading: false);
  }
}

 
  Future<void> _loadInterstitialAd() async {
    final state = Provider.of<BrowseProvidersState>(context, listen: false);
    if (state.isAdFree) return;
    
    InterstitialAd.load(
      adUnitId: AdmobConfig().interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              _lastInterstitialAdTime = DateTime.now();
              _loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              _lastInterstitialAdTime = DateTime.now();
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isInterstitialAdLoaded = false;
        },
      ),
    );
  }

  bool _canShowInterstitialAd() {
    final state = Provider.of<BrowseProvidersState>(context, listen: false);
    if (state.isAdFree || !_isInterstitialAdLoaded || _interstitialAd == null) return false;
    if (_lastInterstitialAdTime == null) return true;
    return DateTime.now().difference(_lastInterstitialAdTime!).inSeconds >= 60;
  }

  Future<void> _showInterstitialAd(VoidCallback onAdComplete) async {
    if (_canShowInterstitialAd()) {
      _interstitialAd?.show().then((_) => onAdComplete()).catchError((e) {
        onAdComplete();
      });
    } else {
      onAdComplete();
    }
  }

  void _showFilterDialog(BuildContext context) {
    final state = Provider.of<BrowseProvidersState>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => FilterDialog(
        initialMaxDistance: state.maxDistance,
        initialShowVerifiedOnly: state.showVerifiedOnly,
        onApply: (maxDistance, showVerifiedOnly) {
          state.updateState(maxDistance: maxDistance, showVerifiedOnly: showVerifiedOnly);
          WidgetsBinding.instance.addPostFrameCallback((_) => _showInterstitialAd(() {}));
        },
      ),
    );
  }


  Future<void> _openOrCreateChat(String providerId, String userId) async {
    try {
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

      _showInterstitialAd(() {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ChatScreen(requestId: chatId)),
          );
        }
      });
    } catch (e) {
      print('Error opening chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error opening chat: $e')));
      }
    }
  }

  Future<void> _callProvider(String phoneNumber) async {
    try {
      final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
      if (await canLaunchUrl(phoneUri)) {
        _showInterstitialAd(() => launchUrl(phoneUri));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch phone call')),
          );
        }
      }
    } catch (e) {
      print('Error making call: $e');
    }
  }

Future<void> _setupNotifications() async {
  const channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    importance: Importance.max,
  );

  await _notificationsPlugin.initialize(
    settings: const InitializationSettings(        // ← Add 'settings:' here
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (details) {
      final data = jsonDecode(details.payload ?? '{}');
      if (data['type'] == 'request' && mounted) {
        Navigator.pushNamed(context, '/request_status');
      } else if (data['type'] == 'message' && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const InboxScreen(isProvider: false)),
        );
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
    id: notification.hashCode,                    // ← Required named parameter
    title: notification.title,
    body: notification.body,
    notificationDetails: NotificationDetails(     // ← Changed from positional
      android: const AndroidNotificationDetails(
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

@override
Widget build(BuildContext context) {
  super.build(context);
  final state = Provider.of<BrowseProvidersState>(context);
  final user = _auth.currentUser;

  if (user == null) {
    return Scaffold(
      appBar: AppBarWidget(title: 'Browse Providers'),
      body: Center(child: Text('Please sign in', style: GoogleFonts.poppins(fontSize: 18))),
    );
  }

  return Scaffold(
    backgroundColor: Colors.grey[50],
    appBar: AppBarWidget(
      title: state.locationName != 'Unknown' ? state.locationName! : 'Find Help Nearby',
      profilePicUrl: state.profile?.profilePicUrl,
      showNotifications: true,
      isProvider: false,
  
    ),
    drawer: AppBarWidget.buildDrawer(context: context, isProvider: false),

    body: Column(
      children: [
        // Category Chips
        Container(
          height: 62,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: state.availableServices.length,
            itemBuilder: (context, i) {
              final category = state.availableServices[i];
              final isAll = category == 'All';
              final isSelected = (isAll && state.selectedCategory == null) ||
                  state.selectedCategory == category;

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: FilterChip(
                  label: Text(category, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  selected: isSelected,
                  selectedColor: const Color(0xFFFF6200),
                  checkmarkColor: Colors.white,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: isSelected ? const Color(0xFFFF6200) : Colors.grey[300]!, width: 1.5),
                  onSelected: (_) {
                    state.updateCategory(isAll ? null : category);
                  },
                ).animate().scale(duration: 300.ms),
              );
            },
          ),
        ),

        // Main List
        Expanded(
          child: Consumer<BrowseProvidersState>(
            builder: (context, state, _) {
              if (state.isLoading) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFFFF6200)),
                      const SizedBox(height: 24),
                      Text('Loading providers...', style: GoogleFonts.poppins(fontSize: 16)),
                    ],
                  ),
                );
              }

              var providers = List<provider_model.Provider>.from(state.cachedProviders);

              // Apply filters (same logic you had before)
              if (state.selectedCategory != null) {
                providers = providers.where((p) => p.type == state.selectedCategory).toList();
              }

              if (state.userLocation != null) {
                providers.sort((a, b) {
                  final distA = a.location != null
                      ? Geolocator.distanceBetween(
                          state.userLocation!.latitude,
                          state.userLocation!.longitude,
                          a.location!.latitude,
                          a.location!.longitude,
                        )
                      : double.infinity;
                  final distB = b.location != null
                      ? Geolocator.distanceBetween(
                          state.userLocation!.latitude,
                          state.userLocation!.longitude,
                          b.location!.latitude,
                          b.location!.longitude,
                        )
                      : double.infinity;
                  return distA.compareTo(distB);
                });

                if (state.maxDistance < 100.0) {
                  providers = providers.where((p) {
                    if (p.location == null) return false;
                    final distance = Geolocator.distanceBetween(
                          state.userLocation!.latitude,
                          state.userLocation!.longitude,
                          p.location!.latitude,
                          p.location!.longitude,
                        ) / 1000;
                    return distance <= state.maxDistance;
                  }).toList();
                }

                if (state.showVerifiedOnly) {
                  providers = providers.where((p) => p.isVerified).toList();
                }
              }

              if (providers.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off_rounded, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 24),
                      Text(
                        state.selectedCategory == null
                            ? 'No providers available'
                            : 'No ${state.selectedCategory} providers found',
                        style: GoogleFonts.poppins(fontSize: 18, color: Colors.grey[700]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _initializeScreen,
                        icon: const Icon(Icons.refresh),
                        label: Text('Refresh', style: GoogleFonts.poppins()),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF6200)),
                      ),
                    ],
                  ).animate().fadeIn(),
                );
              }

              // Build list with ads
              final List<Widget> items = [];
              for (int i = 0; i < providers.length; i++) {
                final provider = providers[i];
                final distance = state.userLocation != null && provider.location != null
                    ? Geolocator.distanceBetween(
                        state.userLocation!.latitude,
                        state.userLocation!.longitude,
                        provider.location!.latitude,
                        provider.location!.longitude,
                      ) / 1000
                    : double.infinity;

                items.add(
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _showInterstitialAd(() {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ViewProviderProfileScreen(providerId: provider.id)),
                        );
                      }),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Hero(
                              tag: 'provider-${provider.id}',
                              child: CircleAvatar(
                                radius: 34,
                                backgroundImage: provider.profilePicUrl?.isNotEmpty == true
                                    ? NetworkImage(provider.profilePicUrl!)
                                    : const AssetImage('assets/default_profile.png') as ImageProvider,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          provider.name ?? 'Provider',
                                          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      if (provider.isVerified)
                                        const Icon(Icons.verified, color: Color(0xFFFF6200), size: 20),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(provider.type ?? '', style: GoogleFonts.poppins(color: Colors.grey[600])),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Text(
                                        distance.isInfinite ? 'Distance unknown' : '${distance.toStringAsFixed(1)} km',
                                        style: GoogleFonts.poppins(fontSize: 13.5),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                   Row(
                    children: [
                      if (provider.rating != null && provider.rating! > 0) ...[
                        Row(
                          children: List.generate(5, (i) => Icon(
                            i < provider.rating!.round() ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 16,
                          )),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${provider.rating!.toStringAsFixed(1)}',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                    
                      ] else
                        Text(
                          'No ratings yet',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                                  Wrap(
                                    spacing: 6,
                                    children: (provider.servicesOffered ?? []).take(3).map((s) => Chip(
                                      label: Text(s, style: GoogleFonts.poppins(fontSize: 11)),
                                      backgroundColor: const Color(0xFFFF6200).withOpacity(0.12),
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    )).toList(),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                IconButton(onPressed: () => _openOrCreateChat(provider.id, user.uid), icon: const Icon(Icons.message_rounded, color: Color(0xFFFF6200))),
                                IconButton(
                                  onPressed: provider.phoneNumber != null ? () => _callProvider(provider.phoneNumber!) : null,
                                  icon: Icon(Icons.phone_rounded, color: provider.phoneNumber != null ? const Color(0xFFFF6200) : Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate().slideY(begin: 0.15, duration: 500.ms, delay: (70 * i).ms).fadeIn(),
                );

                // Insert Ad every 5 providers
                if (!state.isAdFree && (i + 1) % 5 == 0) {
                  final adIndex = (i + 1) ~/ 5 - 1;
                  if (adIndex < state.nativeAds.length && state.nativeAds[adIndex] != null) {
                    items.add(
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: NativeAdWidget(ad: state.nativeAds[adIndex]!),
                      ),
                    );
                  }
                }
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: items,
              );
            },
          ),
        ),
      ],
    ),

    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _showInterstitialAd(() => Navigator.push(context, MaterialPageRoute(builder: (_) => const BrowseProvidersMapScreen()))),
      backgroundColor: const Color(0xFFFF6200),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.map_rounded),
      label: Text('Map View', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
    ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),

    bottomNavigationBar: const BottomNavBar(currentIndex: 1),
  );
}


 /**  @override
  Widget build(BuildContext context) {
    super.build(context);
    print('=== BUILD CALLED ===');
    final state = Provider.of<BrowseProvidersState>(context);
    print('Build - isLoading: ${state.isLoading}, providers: ${state.cachedProviders.length}');
    
    final user = _auth.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBarWidget(title: 'Browse Providers',
        profilePicUrl: null,
        showNotifications: false,),
        body: Center(
          child: Text(
            'Please sign in to browse providers.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBarWidget(
           title: state.locationName != 'Unknown' ? '${state.locationName}' : 'Browse Providers',
        profilePicUrl: state.profile?.profilePicUrl,
        showNotifications: true,
        isProvider: false,
        ),
        drawer: AppBarWidget.buildDrawer(
        context: context,
        isProvider: false,
      ),
        body: Column(
          children: [
            // Category filter
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              height: 60,
              child: Consumer<BrowseProvidersState>(
                builder: (context, state, child) => ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.availableServices.length,
                  itemBuilder: (context, index) {
                    final category = state.availableServices[index];
                    final isSelected = state.selectedCategory == category ||
                        (category == 'All' && state.selectedCategory == null);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          final newCategory = category == 'All' ? null : category;
                          state.updateCategory(newCategory);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFF6200) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              category,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: isSelected ? Colors.white : Colors.black,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            
            // Main content
            Expanded(
              child: Consumer<BrowseProvidersState>(
                builder: (context, state, child) {
                  print('Consumer rebuild - isLoading: ${state.isLoading}, providers: ${state.cachedProviders.length}');
                  
                  if (state.isLoading) {
                    print('Showing loading indicator');
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            color: Color(0xFFFF6200),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Loading providers...',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    );
                  }
                  
                  if (state.cachedProviders.isEmpty) {
                    print('No providers - showing empty state');
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.info_outline, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('No providers available.', style: TextStyle(fontSize: 18)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              print('Retry button pressed');
                              _initializeScreen();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6200),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  var providers = List<provider_model.Provider>.from(state.cachedProviders);
                  print('Total providers before filtering: ${providers.length}');
                  
                  if (state.selectedCategory != null) {
                    providers = providers.where((p) => p.type == state.selectedCategory).toList();
                    print('After category filter: ${providers.length}');
                  }
                  
                  if (state.userLocation != null) {
                    providers.sort((a, b) {
                      double distA = double.infinity;
                      double distB = double.infinity;
                      if (a.location != null) {
                        distA = Geolocator.distanceBetween(
                          state.userLocation!.latitude,
                          state.userLocation!.longitude,
                          a.location!.latitude,
                          a.location!.longitude,
                        );
                      }
                      if (b.location != null) {
                        distB = Geolocator.distanceBetween(
                          state.userLocation!.latitude,
                          state.userLocation!.longitude,
                          b.location!.latitude,
                          b.location!.longitude,
                        );
                      }
                      return distA.compareTo(distB);
                    });
                    
                    if (state.maxDistance < 100.0) {
                      providers = providers.where((provider) {
                        if (provider.location == null) return false;
                        double distance = Geolocator.distanceBetween(
                          state.userLocation!.latitude,
                          state.userLocation!.longitude,
                          provider.location!.latitude,
                          provider.location!.longitude,
                        ) / 1000;
                        return distance <= state.maxDistance;
                      }).toList();
                      print('After distance filter: ${providers.length}');
                    }
                    
                    if (state.showVerifiedOnly) {
                      providers = providers.where((p) => p.isVerified).toList();
                      print('After verified filter: ${providers.length}');
                    }
                  }

                  if (providers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            'No providers found for ${state.selectedCategory ?? 'All'}.',
                            style: Theme.of(context).textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  List<Widget> listItems = [];
                  for (int i = 0; i < providers.length; i++) {
                    var provider = providers[i];
                    double distance = state.userLocation != null && provider.location != null
                        ? Geolocator.distanceBetween(
                            state.userLocation!.latitude,
                            state.userLocation!.longitude,
                            provider.location!.latitude,
                            provider.location!.longitude,
                          ) / 1000
                        : double.infinity;

                    listItems.add(
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.only(bottom: 16),
                        child: InkWell(
                          onTap: () {
                            _showInterstitialAd(() {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ViewProviderProfileScreen(providerId: provider.id),
                                ),
                              );
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    provider.profilePicUrl ?? 'https://placehold.co/60x60?text=Provider',
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 60,
                                      height: 60,
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.person, size: 30),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              provider.name ?? 'Unnamed Provider',
                                              style: Theme.of(context).textTheme.headlineSmall,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (provider.isVerified)
                                            const Icon(Icons.verified, color: Color(0xFFFF6200), size: 18),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                     Row(
                                             children: List.generate(5, (index) {
                                              return Icon(
                                                index < (provider.rating?.round() ?? 0)
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                color: Colors.amber,
                                                size: 16,
                                              );
                                            }),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            provider.rating != null
                                                ? '${provider.rating!.toStringAsFixed(1)}/5'
                                                : 'Not Rated',
                                            style: Theme.of(context).textTheme.bodyMedium,
                                          ),
                                      const SizedBox(height: 4),
                                      Text(
                                        provider.address ?? 'No address provided',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        provider.availability ? 'Available' : 'Unavailable',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: provider.availability ? const Color(0xFFFF6200) : Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            distance == double.infinity
                                                ? 'Distance: Unknown'
                                                : 'Distance: ${distance.toStringAsFixed(1)} km',
                                            style: Theme.of(context).textTheme.bodyLarge,
                                          ),
                                          const SizedBox(width: 8),
                                          Row(
                                           /**  children: List.generate(5, (index) {
                                              return Icon(
                                                index < (provider.rating?.round() ?? 0)
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                color: Colors.amber,
                                                size: 16,
                                              );
                                            }),*/
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            provider.rating != null
                                                ? '${provider.rating!.toStringAsFixed(1)}/5'
                                                : 'N/A',
                                            style: Theme.of(context).textTheme.bodyMedium,
                                          ),
                                        ],
                                      ),
                                      if (provider.servicesOffered != null &&
                                          provider.servicesOffered!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: provider.servicesOffered!
                                              .take(4)
                                              .map((service) => Chip(
                                                    label: Text(
                                                      service,
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                            color: Colors.white,
                                                          ),
                                                    ),
                                                    backgroundColor: const Color(0xFFFF6200),
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ))
                                              .toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.message, color: Color(0xFFFF6200)),
                                      onPressed: () => _openOrCreateChat(provider.id, user.uid),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.phone, color: Color(0xFFFF6200)),
                                      onPressed: () => provider.phoneNumber != null
                                          ? _callProvider(provider.phoneNumber!)
                                          : ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Phone number not available')),
                                            ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );


  if (!state.isAdFree && (i + 1) % 5 == 0) {
            final adIndex = (i + 1) ~/ 5 - 1;
            if (adIndex < state.nativeAds.length && state.nativeAds[adIndex] != null) {
              listItems.add(
                Semantics(
                  label: 'Advertisement',
                  child: NativeAdWidget(ad: state.nativeAds[adIndex]!).animate().fadeIn(
                        duration: const Duration(milliseconds: 400),
                        delay: Duration(milliseconds: 100 * (i + 1)),
                      ),
                ),
              );
            } else if (state.isNativeAdsLoading) {
              listItems.add(
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              );
            }
          }
        

                
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: listItems,
                  );
                },
              ),
            ),
          //  const BottomNavBar(currentIndex: 1),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            _showInterstitialAd(() {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const BrowseProvidersMapScreen()),
              );
            });
          },
          label: const Text('Map'),
          icon: const Icon(Icons.map),
          backgroundColor: const Color(0xFFFF6200),
        ),
         bottomNavigationBar: BottomNavBar(currentIndex: 1),
      ),
    );
  }*/

  AppBar _buildAppBar(BuildContext context, String title, {String? profilePicUrl}) {
    return AppBar(
      title: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      leading: IconButton(
        icon: CircleAvatar(
          radius: 16,
          backgroundImage: profilePicUrl != null && profilePicUrl.isNotEmpty
              ? NetworkImage(profilePicUrl)
              : const AssetImage('assets/default_profile.png') as ImageProvider,
        ),
        onPressed: () {
          _showInterstitialAd(() {
            Navigator.pushNamed(context, '/profile');
          });
        },
      ),
      actions: [
       
      
        IconButton(
          icon: const Icon(Icons.filter_list, color: Color(0xFFFF6200)),
          onPressed: () => _showFilterDialog(context),
          tooltip: 'Filter Providers',
        ),
        TextButton(
          onPressed: () async {
            bool? confirmLogout = await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text('Confirm Logout', style: Theme.of(context).textTheme.headlineMedium),
                content: Text('Are you sure you want to log out?', style: Theme.of(context).textTheme.bodyLarge),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Logout'),
                  ),
                ],
              ),
            );
            if (confirmLogout == true && mounted) {
              _showInterstitialAd(() async {
                await FirebaseAuth.instance.signOut();
                Navigator.pushReplacementNamed(context, '/login');
              });
            }
          },
          child: const Text('Logout', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}

class FilterDialog extends StatefulWidget {
  final double initialMaxDistance;
  final bool initialShowVerifiedOnly;
  final void Function(double, bool) onApply;

  const FilterDialog({
    super.key,
    required this.initialMaxDistance,
    required this.initialShowVerifiedOnly,
    required this.onApply,
  });

  @override
  _FilterDialogState createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  late double _tempMaxDistance;
  late bool _tempShowVerifiedOnly;

  @override
  void initState() {
    super.initState();
    _tempMaxDistance = widget.initialMaxDistance;
    _tempShowVerifiedOnly = widget.initialShowVerifiedOnly;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Filter Providers', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Text(
              'Max Distance: ${_tempMaxDistance.toStringAsFixed(1)} km',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            Slider(
              value: _tempMaxDistance,
              min: 5.0,
              max: 100.0,
              divisions: 19,
              label: _tempMaxDistance.toStringAsFixed(1),
              activeColor: const Color(0xFFFF6200),
              onChanged: (value) => setState(() => _tempMaxDistance = value),
            ),
            Row(
              children: [
                Checkbox(
                  value: _tempShowVerifiedOnly,
                  activeColor: const Color(0xFFFF6200),
                  onChanged: (value) => setState(() => _tempShowVerifiedOnly = value ?? false),
                ),
                Text('Verified Only', style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onApply(_tempMaxDistance, _tempShowVerifiedOnly);
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}