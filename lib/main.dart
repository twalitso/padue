import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:padue/features/auth/screens/provider_signup_screen.dart';
import 'package:padue/features/auth/screens/user_signup_screen.dart';
import 'package:padue/features/roadside/screens/browse_providers_map_screen.dart';
import 'package:padue/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Add this for caching
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/utils.dart';
import 'package:padue/features/auth/screens/user_login_screen.dart';
import 'package:padue/features/auth/screens/welcome_screen.dart';
import 'package:padue/features/auth/screens/provider_login_screen.dart';
import 'package:padue/features/roadside/screens/browse_providers_screen.dart';
import 'package:padue/features/roadside/screens/chat_screen.dart';
import 'package:padue/features/roadside/screens/create_post_screen.dart';
import 'package:padue/features/roadside/screens/forum_screen.dart';
import 'package:padue/features/roadside/screens/post_detail_screen.dart';
import 'package:padue/features/roadside/screens/provider_profile_screen.dart';
import 'package:padue/features/roadside/screens/request_screen.dart';
import 'package:padue/features/roadside/screens/provider_dashboard.dart';
import 'package:padue/features/roadside/screens/request_status.dart';
import 'package:padue/features/auth/screens/profile_screen.dart';
import 'package:padue/features/roadside/screens/subscription_screen.dart';
import 'package:padue/features/roadside/screens/search_screen.dart';
import 'package:padue/screens/splash_screen.dart';
import 'package:package_info_plus/package_info_plus.dart'; // NEW
import 'package:url_launcher/url_launcher.dart'; // NEW
import 'package:pub_semver/pub_semver.dart'; // NEW
import 'package:firebase_remote_config/firebase_remote_config.dart'; 
import 'package:flutter_dotenv/flutter_dotenv.dart';


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  //await Firebase.initializeApp();
}



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

   FirebaseMessaging.instance.requestPermission();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidInitializationSettings android =
    AndroidInitializationSettings('@mipmap/ic_launcher');

const DarwinInitializationSettings ios = DarwinInitializationSettings(
  requestAlertPermission: true,
  requestBadgePermission: true,
  requestSoundPermission: true,
);

const InitializationSettings initializationSettings = InitializationSettings(
  android: android,
  iOS: ios,           // ← This was missing
);

await flutterLocalNotificationsPlugin.initialize(
  const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,   // request later
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  ),
);



// After await flutterLocalNotificationsPlugin.initialize(...);

if (defaultTargetPlatform == TargetPlatform.iOS) {
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
}
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  try {
    final String oneSignalAppId =
        dotenv.env['ONESIGNAL_APP_ID'] ??
        'aa6821d3-e2ec-45d5-828f-fcae178accf7';

    OneSignal.initialize(oneSignalAppId);
    OneSignal.Notifications.requestPermission(true);
  } catch (e) {
    debugPrint('OneSignal failed: $e');
  }

  runApp(const PadueApp());

  Future.microtask(_warmupApp);
}

// FIRE-AND-FORGET: All heavy work
Future<void> _warmupApp() async {
  try {
    // Parallel: Ads + FCM + OneSignal
    await Future.wait([
      MobileAds.instance.initialize(),
      _setupOneSignalHandlersSafe(),
      _saveTokensIfLoggedIn(),
       _setupRemoteConfig(),
    ], eagerError: true);
  } catch (e) {
    debugPrint('Warmup failed: $e');
  }
}

// NEW: Setup Remote Config with safe defaults
Future<void> _setupRemoteConfig() async {
  final remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.setConfigSettings(RemoteConfigSettings(
    fetchTimeout: const Duration(minutes: 1),
    minimumFetchInterval: const Duration(hours: 1),
  ));

  await remoteConfig.setDefaults(const {
    "minimum_version": "15.0.0",
    "latest_version": "17.0.0",
    "force_update": false,
    "update_title": "Update Available",
    "update_message":
        "A new update is available with new features and bug fixes.",
  });

  // Best-effort fetch on app start
  await remoteConfig.fetchAndActivate();
}


// NEW: App Update Checker
Future<void> checkForAppUpdate(BuildContext context) async {
  try {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.fetchAndActivate(); // Refresh if possible

    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final Version currentVersion = Version.parse(packageInfo.version);

    final Version minVersion =
        Version.parse(remoteConfig.getString('minimum_version'));
    final Version latestVersion =
        Version.parse(remoteConfig.getString('latest_version'));
    final bool forceUpdate = remoteConfig.getBool('force_update');
    final String title = remoteConfig.getString('update_title');
    final String message = remoteConfig.getString('update_message');

    final bool needsForceUpdate = currentVersion < minVersion;
    final bool needsOptionalUpdate =
        currentVersion < latestVersion || forceUpdate;

    if (needsForceUpdate || (forceUpdate && needsOptionalUpdate)) {
      // Force update - blocking
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text("$message\n\nPlease update to continue using the app."),
          actions: [
            TextButton(
              onPressed: _launchStore,
              child: const Text('Update Now'),
            ),
          ],
        ),
      );
    } else if (needsOptionalUpdate) {
      // Optional update
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text("$message\n\nWould you like to update now?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: _launchStore,
              child: const Text('Update'),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    debugPrint('Update check failed: $e');
    // Silent failure - never block the app due to update check
  }
}

// NEW: Launch Play Store / App Store
void _launchStore() async {
  const String packageName = 'com.twalitso.padue'; // <<< CHANGE TO YOUR ACTUAL PACKAGE NAME
  final Uri androidUrl =
      Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
  // Optional: Add your iOS App ID for better iOS experience
  final Uri iosUrl = Uri.parse('https://apps.apple.com/app/idYOUR_APPLE_ID');

  final Uri url = defaultTargetPlatform == TargetPlatform.android
      ? androidUrl
      : iosUrl;

  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}


Future<void> _setupOneSignalHandlersSafe() async {
  try {
    setupOneSignalHandlers();
  } catch (_) {}
}

Future<void> _saveTokensIfLoggedIn() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final fcm = await FirebaseMessaging.instance.getToken();
  final oneSignalId = OneSignal.User.pushSubscription.id;

 /**  if (fcm != null) {
    unawaited(FirestoreService().storeDeviceToken(fcm));
  }*/
 /**  if (oneSignalId != null && oneSignalId.isNotEmpty) {
    unawaited(_saveOneSignalId(user.uid, oneSignalId));
  }*/
}





class PadueApp extends StatefulWidget {
  const PadueApp({super.key});

  @override
  _PadueAppState createState() => _PadueAppState();
}

class _PadueAppState extends State<PadueApp> with WidgetsBindingObserver {
  Timer? _lastActiveTimer;
  final _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Start periodic last active update after init (non-blocking)
   /** _lastActiveTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      try {
        await updateLastActive();
      } catch (e) {
        // Silent fail
      }
    });*/

    // Defer initial last active to post-frame (already in main, but ensure)
  //  WidgetsBinding.instance.addPostFrameCallback((_) => updateLastActive());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FirebaseMessaging.instance.getToken().then((token) {
        if (token != null) _firestore.storeDeviceToken(token);
      });
    //  updateLastActive(); // Update on resume
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lastActiveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
       navigatorKey: navigatorKey,
      title: 'Padue',
      theme: ThemeData(
  primaryColor: const Color(0xFFFF6200), // Orange
  scaffoldBackgroundColor: Colors.white, // White background
  colorScheme: const ColorScheme.light(
    primary: Color(0xFFFF6200), // Orange for primary elements
    onPrimary: Colors.white, // White text/icons on primary
    secondary: Color(0xFF000000), // Black for secondary elements
    onSecondary: Colors.white, // White text/icons on secondary
    surface: Colors.white, // White for cards and surfaces
    onSurface: Colors.black, // Black text on surfaces
    error: Colors.redAccent, // Standard error color
  ),
  textTheme: GoogleFonts.poppinsTextTheme(
    const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFFF6200)), // Orange for titles
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.black), // Black for subtitles
      bodyLarge: TextStyle(fontSize: 16, color: Colors.black), // Black for body text
      bodyMedium: TextStyle(fontSize: 14, color: Colors.black87), // Slightly lighter black for smaller text
      labelMedium: TextStyle(fontSize: 12, color: Colors.black54), // Subtle black for labels
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFFF6200)), // Orange border
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.black12), // Subtle black for enabled state
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFFF6200), width: 2), // Orange when focused
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    filled: true,
    fillColor: Colors.white, // White input background
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    prefixIconColor: const Color(0xFFFF6200), // Orange icons
    labelStyle: const TextStyle(color: Colors.black54),
    hintStyle: const TextStyle(color: Colors.black38),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFFF6200), // Orange buttons
      foregroundColor: Colors.white, // White text/icons on buttons
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFFFF6200), // Orange for outlined button text/icons
      side: const BorderSide(color: Color(0xFFFF6200), width: 2), // Orange border
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: const Color(0xFFFF6200), // Orange for text buttons
      textStyle: GoogleFonts.poppins(fontSize: 14),
    ),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.white, // White app bar
    elevation: 1,
    shadowColor: Colors.black.withOpacity(0.1),
    centerTitle: true,
    titleTextStyle: GoogleFonts.poppins(
      fontSize: 22,
      fontWeight: FontWeight.bold,
      color: const Color(0xFFFF6200), // Orange title text
    ),
    iconTheme: const IconThemeData(color: Color(0xFFFF6200)), // Orange icons
  ),
  dialogTheme: DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    backgroundColor: Colors.white,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: Colors.black87,
    contentTextStyle: GoogleFonts.poppins(color: Colors.white),
    actionTextColor: const Color(0xFFFF6200), // Orange for snackbar actions
  ),
),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const UserLoginScreen(),
        '/welcome': (context) =>  WelcomeScreen(),
        '/profile': (context) =>  ProfileScreen(),
        '/signup': (context) => const UserSignUpScreen(),
        '/request': (context) => const RequestScreen(),
        '/provider_login': (context) => const ProviderLoginScreen(),
         '/provider_signup': (context) => const ProviderSignUpScreen(),
        '/provider_dashboard': (context) => const ProviderDashboard(),
        '/provider_profile': (context) => const ProviderProfileScreen(),
        '/request_status': (context) => const RequestStatusScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
        '/search': (context) => const SearchScreen(),
        '/browse_providers': (context) => const BrowseProvidersScreen(),
'/browse_providers_map': (context) => BrowseProvidersMapScreen(),
        '/forum': (context) =>  ForumScreen(),
        '/create_post': (context) => const CreatePostScreen(),
        '/post_detail': (context) => PostDetailScreen(
              postId: ModalRoute.of(context)!.settings.arguments as String,
            ),
        '/chat': (context) => const ChatScreen(),
      },
    );
  }
}


// ────────────────────────────────────────────────────────────────
// ONE SIGNAL HANDLERS (Critical!)
// ────────────────────────────────────────────────────────────────
void setupOneSignalHandlers() {
  // Foreground notification received (app open)
  OneSignal.Notifications.addForegroundWillDisplayListener((event) {
    // Prevent default display if you want custom handling
    // event.preventDefault();

    // Always display the system notification
    event.notification.display();

    // Optional: Show in-app toast/snackbar
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(event.notification.body ?? 'New notification'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  });

  // Notification clicked (app in background, terminated, or foreground)
 OneSignal.Notifications.addClickListener((event) {
  final data = event.notification.additionalData;
  if (data == null) return;

  final String? type = data['type'] as String?;
  final String? requestId = data['requestId'] as String?;
  final String? chatId = data['chatId'] as String?;
  final String? postId = data['postId'] as String?;

  // Delay ensures AuthWrapper + Navigator are ready
  Future.delayed(const Duration(milliseconds: 800), () {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    switch (type) {
      case 'message':
        if (chatId != null) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(requestId: chatId),
            ),
          );
        }
        break;

      case 'new_request':
         nav.push(
            MaterialPageRoute(
              builder: (_) => ProviderDashboard( ),
            ),
          );
      break;
      case 'request_cancel':
      case 'status_update':
        if (requestId != null) {
          nav.pushNamed(
            '/request_status',
            arguments: requestId,
          );
        }
        break;

      case 'comment':
      case 'like':
        if (postId != null) {
          nav.pushNamed(
            '/post_detail',
            arguments: postId,
          );
        }
        break;

      case 'profile_update':
        nav.pushNamed('/profile');
        break;

      case 'payment':
        nav.pushNamed('/subscription');
        break;

      default:
        debugPrint('Unknown notification type: $type');
    }
  });
});

}

// Map notification type → route
String _getRouteForType(String? type) {
  return switch (type) {
    'request' => '/request_status',
    'status_update' => '/request_status',
    'profile_update' => '/profile',
    'payment' => '/subscription',
    'comment' => '/post_detail',
    'like' => '/post_detail',
    _ => '/notifications',
  };
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _firestore = FirestoreService();
  String? _cachedRole;
   bool? _hasSeenWelcome;

  @override
  void initState() {
    super.initState();
    _loadCachedRole(); // Load cached role immediately
  }

  // Cache role locally for faster startup
  Future<void> _loadCachedRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cachedRole = prefs.getString('user_role');
       _hasSeenWelcome = prefs.getBool('has_seen_welcome') ?? false;
    });
  }

  Future<void> _cacheRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    setState(() {
      _cachedRole = role;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser ; // Sync check - faster than StreamBuilder

       // Check if welcome screen should be shown
    if (_hasSeenWelcome == false) {
      return const WelcomeScreen();
    }

    if (user == null) {
      // No user: Go to login immediately (no wait)
      return const UserLoginScreen();
    }

    // User exists: Check role (use cache if available, else fetch async)
    if (_cachedRole != null) {
      // Use cached role - instant
      return _buildHomeBasedOnRole(_cachedRole!);
    }

    // No cache: Show splash while fetching (parallel, non-blocking)
    return FutureBuilder<String?>(
      future: _firestore.getUserRole(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        final role = snapshot.data ?? 'user'; // Default to user
        _cacheRole(role); // Cache for next startup
        return _buildHomeBasedOnRole(role);
      },
    );
  }

  Widget _buildHomeBasedOnRole(String role) {
    switch (role) {
      case 'provider':
        return const ProviderDashboard();
      case 'user':
      default:
        return const RequestScreen();
    }
  }
}

// Enhanced Splash Screen (add animation for better UX)
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Image.asset('assets/icon.png', width: 200, height: 200),
            const SizedBox(height: 20),
            Text(
              'Loading...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}