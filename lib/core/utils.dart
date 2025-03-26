import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:padue/core/firestore_service.dart'; // Assuming this is where getUserRole lives
import 'package:googleapis_auth/auth_io.dart';


import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:padue/core/firestore_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> updateLastActive() async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final firestore = FirestoreService();
  try {
    final role = await firestore.getUserRole(user.uid);
    print('Updating lastActive for UID: ${user.uid}, role: $role');

    if (role == 'user') {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'lastActive': FieldValue.serverTimestamp(),
      });
      print('Updated lastActive in users collection');
    } else if (role == 'provider') {
      await FirebaseFirestore.instance.collection('providers').doc(user.uid).update({
        'lastActive': FieldValue.serverTimestamp(),
      });
      print('Updated lastActive in providers collection');
    } else {
      print('No valid role found, skipping lastActive update');
    }
  } catch (e) {
    print('Error updating lastActive: $e');
  }
}

Future<void> saveFcmToken() async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final messaging = FirebaseMessaging.instance;
  final token = await messaging.getToken();
  if (token == null) return;

  final firestore = FirestoreService();
  final role = await firestore.getUserRole(user.uid);

  if (role == 'user') {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  } else if (role == 'provider') {
    await FirebaseFirestore.instance.collection('providers').doc(user.uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  }
}


Future<String> getAccessToken() async {
  final serviceAccountJson = '''
 {
  "type": "service_account",
  "project_id": "twalitso",
  "private_key_id": "590e1125dbb6b65c2655a990559f88cf49d912a0",
  "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC+TsY9WjCOIm7z\\ncelcqpAqKhF1QhZasu29wmbUdYuAvA025QKnOt7PmAzt1KWrey9nUB8FxHenxK2c\\n03ooztd81Of+JogNUgmmrlQcNGDHj9KDv9mzzEiGqFMUn/H+9krXoI9Ev/o7Gn+1\\nS3pHsXBBvRrmGHg/akJSQK1v4HuzMSMDnL4widpdSy7+5ojN2YgtPN7xBddMwIAj\\ndX7g92hZFwpwaCYbO3cObKOeCNFyXeRNmd0m/yLgnnK6E8cdLd0TafpTGX4ZXL+p\\n1aya5kMTZzVOp34Zvkob+tVDd6dWeJ6Tr5F5u9u6HBerSquulp1t88Vq7nFMPEfy\\nigtzu5JhAgMBAAECggEACnLEfUaT+x++l/DRe0AVi20VGYsb81WWyifv0ZsVAkfA\\n0XpcDY6kwEDEt/OId3xbR0ittVk6qQw6LG2ra61khRLi3FAlANc31q4ESeqhxB8c\\nM5XPR+jvs+3upsebx4/h3soOx5tjK4bKS2u2DlTaeQ9++DJQesnUk5O/ufBZFkbE\\nSPU+B7KL5mKvZEMicOYyB280iGCsq99JphuPPfPMrY5fs0TQlC0aPLpoWpgsJWSZ\\nzcd38LZ6voeQgOGUyYWWYA2kcdjNg2BnM9Ia1uzlYvB8DJIYbBsMAcF/92ygRl08\\n2Me+iEJ4kCSEpWbv4DOdlXwwuJ8fqbTo+USr3FcM2QKBgQD7LzmZYxamTLDWpOop\\nCDRvCUtJS9dXxvdK+uEn9OFo/SJYGmh+Lm6rMj9PE4v85C47C5zGMEpjZpBSMTd6\\nDFIangCkCS4LVuIpwOoKBVq0yhM6uUWe7gsuWdwvgowT15hztt2MjdJWmR09/GMR\\niwQTJ0ZIMKLiRr1JXEj6c7pmqQKBgQDB9MaJ4baAq2pPLVjuq7XpfRNflaOIi9Pc\\nT5AN/pcj0vKNhj60PkBx578CWM55NtxlGPPMU0RBweAFTnfzzZsMfLh/mZREIs9+\\nzCVVcIpMI6V/Z4IVp+ijsSaAnqENVCHrhYqymAvKXaJ4dwVSgCwg86w4cyB8IoKs\\nJiruHmr4+QKBgHN9ujkZg0+BUYnPl8639AvdtR0FXwT/+bIi+iV6Ba5VPVZPBh6G\\nUOIsH0nHjgUAEXWamEHT8FAV12PDN2PJiHKulVLW2bHjB+f0yGdFIPihNQg6KZWy\\nk7eDH6dEmg2BgpopyWIXz0975SMcCZ0GUyBPXZRRsILjzaKOaQum7FzJAoGAF6e7\\n4yslMBI3+Aom040btatshnbgqBGtuCv3/Mz1MAhVTs91rFP/ViUWlbmxDPWU8buW\\nWHA7Xe3AXcVROen0pBQ+CEn53EmGlwdc8ku0gk7Cq4Q7SFrfM7+yW3N9XvvI20nB\\nPcDvhzHeU+ToQESjnS067vOTnbAz0b0h9UK+dzkCgYEAooA2yBBwwQlQ5sBvzDvE\\nse3HcSVecvXtCxFybzdfqdnFlEUR+cOKZrTb+5yX2WkHlBcxQd+QJxS3VQdR7Zls\\nCmuhqD3JSNo+kgRJGVrorYEZjav1LYLqB3at6WqVaq8AP+wqfC4/JFR+jKr+GZie\\ncZprrWKFWnG6unBGUNxRumY=\\n-----END PRIVATE KEY-----\\n",
  "client_email": "firebase-adminsdk-8wtoq@twalitso.iam.gserviceaccount.com",
  "client_id": "101494599036070216189",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-8wtoq%40twalitso.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}

  ''';

  final accountCredentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
  final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
  final client = await clientViaServiceAccount(accountCredentials, scopes);
  final accessToken = client.credentials.accessToken.data;
  client.close();
  return accessToken;
}

Future<void> sendFcmNotificationV1({
  required String token,
  required String title,
  required String body,
  required String type,
  String? id,
   required String recipientUid, // Add this to know who the notification is for
}) async {
  final accessToken = await getAccessToken();
  const String projectId = 'twalitso'; // From JSON file
  final String fcmUrl = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $accessToken',
  };

  final payload = {
    'message': {
      'token': token,
      'notification': {
        'title': title,
        'body': body,
      },
      'data': {
        'type': type,
        'id': id ?? '',
      },
      'time_to_live': 2419200, // 28 days
    },
  };

 // Store in Firestore first
  final firestore = FirebaseFirestore.instance;
  final role = await FirestoreService().getUserRole(recipientUid);
  final collection = role == 'user' ? 'users' : 'providers';
  
  await firestore
      .collection(collection)
      .doc(recipientUid)
      .collection('notifications')
      .add({
    'title': title,
    'body': body,
    'type': type,
    'id': id ?? '',
    'timestamp': FieldValue.serverTimestamp(),
    'read': false, // Track if the user has seen it
  });
  final response = await http.post(
    Uri.parse(fcmUrl),
    headers: headers,
    body: jsonEncode(payload),
  );

  print('Response: ${response.statusCode} - ${response.body}');
}