import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static const double maxDistanceKm = 10.0; // Adjust as needed

  static const String _oneSignalApiUrl = 'https://onesignal.com/api/v1/notifications';

  // Load from .env
  static String _appId = dotenv.env['ONESIGNAL_APP_ID']!;
  static String _restApiKey = dotenv.env['ONESIGNAL_REST_API_KEY']!;

  /// Send notification to nearby providers when a new request is created
  static Future<void> sendNewRequestNotification({
    required String requestId,
    required String service,
    required GeoPoint userLocation,
    required String locationDescription,
    required String userName,
  }) async {
    try {
      final providersSnap = await FirebaseFirestore.instance
          .collection('providers')
          .where('acceptingRequests', isEqualTo: true)
          .where('services', arrayContains: service)
          .get();

      final List<String> targetSubscriptionIds = [];

      for (var doc in providersSnap.docs) {
        final data = doc.data();
        final GeoPoint? provLoc = data['location'] as GeoPoint?;
        final String? subscriptionId = data['oneSignalSubscriptionId'] as String?;

        if (provLoc == null || subscriptionId == null || subscriptionId.isEmpty) {
          continue;
        }

        final distanceKm = Geolocator.distanceBetween(
              userLocation.latitude,
              userLocation.longitude,
              provLoc.latitude,
              provLoc.longitude,
            ) /
            1000;

        if (distanceKm <= maxDistanceKm) {
          targetSubscriptionIds.add(subscriptionId);
        }
      }

      if (targetSubscriptionIds.isEmpty) return;

      await sendToSubscriptionIds(
        subscriptionIds: targetSubscriptionIds,
        title: 'New $service Request Nearby',
        body: '$userName needs help at $locationDescription',
        data: {
          'type': 'new_request',
          'requestId': requestId,
          'service': service,
        },
      );
    } catch (e) {
      print('❌ Error sending request notification: $e');
    }
  }

  /// Generic helper to send notification using subscription IDs
  static Future<void> sendToSubscriptionIds({
    required List<String> subscriptionIds,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    if (subscriptionIds.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(_oneSignalApiUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $_restApiKey',
        },
        body: jsonEncode({
          'app_id': _appId,
          'include_subscription_ids': subscriptionIds, // OneSignal still uses this field name in API
          'headings': {'en': title},
          'contents': {'en': body},
          'data': data,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ Notification sent to ${subscriptionIds.length} providers');
      } else {
        print('❌ OneSignal API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('🔥 Notification HTTP error: $e');
    }
  }

  /// Send to a specific user by fetching their subscription ID
  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final subscriptionId = doc.data()?['oneSignalSubscriptionId'] as String?;
      if (subscriptionId != null && subscriptionId.isNotEmpty) {
        await sendToSubscriptionIds(
          subscriptionIds: [subscriptionId],
          title: title,
          body: body,
          data: data,
        );
      }
    } catch (e) {
      print('Error sending to user $userId: $e');
    }
  }

  /// Send to a specific provider
  static Future<void> sendToProvider({
    required String providerId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('providers').doc(providerId).get();
      final subscriptionId = doc.data()?['oneSignalSubscriptionId'] as String?;
      if (subscriptionId != null && subscriptionId.isNotEmpty) {
        await sendToSubscriptionIds(
          subscriptionIds: [subscriptionId],
          title: title,
          body: body,
          data: data,
        );
      }
    } catch (e) {
      print('Error sending to provider $providerId: $e');
    }
  }

  /// Initialize local notifications
  static Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: iOS);
    await _notifications.initialize(settings: settings);
  }

  /// Show local notification
  static Future<void> showNotification(String title, String body, String payload) async {
    const androidDetails = AndroidNotificationDetails(
      'forum_channel',
      'Forum Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iOSDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iOSDetails);
  await _notifications.show(
  id: 0,
  title: title,
  body: body,
  notificationDetails: details,     // ← This was the problem
  payload: payload,
);
  }

  /// Listen for new notifications in Firestore and show locally
  static Future<void> listenForNotifications() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Listen to user notifications
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('type', whereIn: ['comment', 'request', 'like'])
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data() as Map<String, dynamic>;
          showNotification(
            data['title'] ?? 'New Notification',
            data['body'] ?? '',
            change.doc.id,
          );
        }
      }
    });

    // Listen to provider notifications (if applicable)
    FirebaseFirestore.instance
        .collection('providers')
        .doc(user.uid)
        .collection('notifications')
        .where('type', whereIn: ['comment', 'request', 'like'])
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data() as Map<String, dynamic>;
          showNotification(
            data['title'] ?? 'New Notification',
            data['body'] ?? '',
            change.doc.id,
          );
        }
      }
    });
  }
}