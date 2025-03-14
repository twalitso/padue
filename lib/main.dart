import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/features/auth/screens/user_login_screen.dart';
import 'package:padue/features/auth/screens/provider_login_screen.dart';
import 'package:padue/features/roadside/screens/request_screen.dart';
import 'package:padue/features/roadside/screens/provider_dashboard.dart';
import 'package:padue/features/roadside/screens/request_status.dart';
import 'package:padue/features/auth/screens/profile_screen.dart';
import 'package:padue/features/roadside/screens/subscription_screen.dart';
import 'package:padue/features/roadside/screens/search_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Background message: ${message.data}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FirebaseMessaging.instance.requestPermission();
  String? token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    await FirestoreService().storeDeviceToken(token);
  }

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const PadueApp());
}

class PadueApp extends StatelessWidget {
  const PadueApp({super.key});

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
          headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87), // Replaced headline5
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
      initialRoute: '/login',
      routes: {
        '/login': (context) => const UserLoginScreen(),
        '/profile': (context) =>  ProfileScreen(),
        '/request': (context) =>  RequestScreen(),
        '/provider_login': (context) => const ProviderLoginScreen(),
        '/provider_dashboard': (context) =>  ProviderDashboard(),
        '/request_status': (context) => RequestStatusScreen(),
        '/subscription': (context) =>  SubscriptionScreen(),
        '/search': (context) =>  SearchScreen(),
      },
    );
  }
}