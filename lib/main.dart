import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'; // For compute
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/utils.dart';
import 'package:padue/features/auth/screens/user_login_screen.dart';
import 'package:padue/features/auth/screens/provider_login_screen.dart';
import 'package:padue/features/roadside/screens/browse_providers_screen.dart';
import 'package:padue/features/roadside/screens/provider_profile_screen.dart';
import 'package:padue/features/roadside/screens/request_screen.dart';
import 'package:padue/features/roadside/screens/provider_dashboard.dart';
import 'package:padue/features/roadside/screens/request_status.dart';
import 'package:padue/features/auth/screens/profile_screen.dart';
import 'package:padue/features/roadside/screens/subscription_screen.dart';
import 'package:padue/features/roadside/screens/search_screen.dart';
import 'package:padue/screens/splash_screen.dart'; // New splash screen

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();


Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase first
  await Firebase.initializeApp();

  // Initialize AdMob
  await MobileAds.instance.initialize();

  // Firebase Messaging setup
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FirebaseMessaging.instance.requestPermission();
  String? token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    // Use FirestoreService after Firebase is initialized, avoid compute here
    await FirestoreService().storeDeviceToken(token);
  }

  // Local notifications setup
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher'); // Or 'app_icon' if updated
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Initial last active update
  await updateLastActive();

  // Periodic update with error handling
  Timer.periodic(Duration(minutes: 2), (timer) async {
    try {
      await updateLastActive(); // Run directly, Firebase is already initialized
    } catch (e) {
      print('Periodic update failed: $e');
    }
  });

  runApp(const PadueApp());
}

class PadueApp extends StatefulWidget {
  const PadueApp({super.key});

  @override
  _PadueAppState createState() => _PadueAppState();
}

class _PadueAppState extends State<PadueApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FirebaseMessaging.instance.getToken().then((token) {
        if (token != null) FirestoreService().storeDeviceToken(token);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Padue',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
        colorScheme: const ColorScheme.light(
          primary: Colors.blue,
          secondary: Colors.orange,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.black,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
          headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
          bodySmall: TextStyle(fontSize: 12, color: Colors.grey),
          labelMedium: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIconColor: Colors.grey,
          labelStyle: TextStyle(color: Colors.black54),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.blue,
          ),
        ),
        dialogTheme: DialogTheme(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      home: AuthWrapper(), // Replace initialRoute with home for dynamic navigation
      routes: {
        '/login': (context) => const UserLoginScreen(),
        '/profile': (context) => ProfileScreen(),
        '/request': (context) => RequestScreen(),
        '/provider_login': (context) => const ProviderLoginScreen(),
        '/provider_dashboard': (context) => ProviderDashboard(),
        '/provider_profile': (context) => ProviderProfileScreen(),
        '/request_status': (context) => RequestStatusScreen(),
        '/subscription': (context) => SubscriptionScreen(),
        '/search': (context) => const SearchScreen(),
        '/browse_providers': (context) => const BrowseProvidersScreen(),
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  final _firestore = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        if (snapshot.hasData) {
          return FutureBuilder<String?>(
            future: _firestore.getUserRole(snapshot.data!.uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const SplashScreen();
              }
              final role = roleSnapshot.data;
              if (role =='provider') {
                  return ProviderDashboard();
              } else if (role == 'user') {
                return RequestScreen(); // Assuming this is the user home page
              }
              return const UserLoginScreen(); // Fallback to user login if no role
            },
          );
        }
        return const UserLoginScreen();
      },
    );
  }
}

// Splash Screen (create in lib/screens/splash_screen.dart)
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icon.png', width: 100, height: 100),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            const SizedBox(height: 10),
            Text('Loading...', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}