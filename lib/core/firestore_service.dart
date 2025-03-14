import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:padue/main.dart';
import 'dart:io';
import '../features/auth/models/user_profile.dart';
import '../features/roadside/models/provider.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final geo = Geoflutterfire();

  Future<void> storeDeviceToken(String token) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set({'deviceToken': token}, SetOptions(merge: true));
      await _db.collection('providers').doc(user.uid).set({'deviceToken': token}, SetOptions(merge: true));
    }
  }
Future<void> createRequest(Map<String, dynamic> requestData) async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    bool hasAdFree = await isAdFree(user.uid); // Rename to avoid conflict
    bool hasRewardedPriority = await hasTemporaryPriority(user.uid);
    GeoPoint location = requestData['location'] as GeoPoint;
    GeoFirePoint point = geo.point(latitude: location.latitude, longitude: location.longitude);
    requestData['geohash'] = point.hash;
    requestData['geo'] = point.data;
    requestData['createdAt'] = FieldValue.serverTimestamp();
    requestData['isPriority'] = hasAdFree || hasRewardedPriority; // Use resolved booleans
    var docRef = await _db.collection('requests').add(requestData);
    await _db.collection('analytics').doc('requests').collection('records').doc(docRef.id).set({
      'requestId': docRef.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

  Stream<QuerySnapshot> getOptions() {
    return _db.collection('options').snapshots();
  }

  Stream<List<Map<String, dynamic>>> getNearbyRequests(
      String providerId, Position providerLocation,
      {double radiusInKm = 10.0}) {
    GeoFirePoint center = geo.point(
      latitude: providerLocation.latitude,
      longitude: providerLocation.longitude,
    );
    return geo
        .collection(collectionRef: _db.collection('requests'))
        .within(
          center: center,
          radius: radiusInKm,
          field: 'geo',
          strictMode: true,
        )
        .map((snapshot) {
      var requests = snapshot
          .where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'open')
          .map((doc) => {
                'id': doc.id,
                ...doc.data() as Map<String, dynamic>,
              })
          .toList();
      requests.sort((a, b) => (b['isPriority'] ?? false) ? 1 : (a['isPriority'] ?? false) ? -1 : 0);
      return requests;
    });
  }

  Future<String> uploadMedia(File file, String path) async {
    UploadTask task = _storage.ref(path).putFile(file);
    TaskSnapshot snapshot = await task;
    return await snapshot.ref.getDownloadURL();
  }

  Future<void> updateUserProfile(String uid, UserProfile profile) async {
    await _db.collection('users').doc(uid).set(profile.toMap(), SetOptions(merge: true));
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) return UserProfile.fromMap(doc.data() as Map<String, dynamic>);
    return null;
  }

  Future<void> updateProviderProfile(String providerId, Map<String, dynamic> data) async {
    await _db.collection('providers').doc(providerId).set(data, SetOptions(merge: true));
  }

  Future<Provider?> getProviderProfile(String providerId) async {
    DocumentSnapshot doc = await _db.collection('providers').doc(providerId).get();
    if (doc.exists) return Provider.fromMap(doc.data() as Map<String, dynamic>);
    return null;
  }

  Future<String> uploadProviderDocument(String providerId, File document) async {
    String path = 'provider_documents/$providerId/${DateTime.now().toIso8601String()}';
    return await uploadMedia(document, path);
  }

  Future<void> sendMessage(String requestId, String senderId, String text) async {
    User? user = FirebaseAuth.instance.currentUser;
    bool isPriority = user != null && (await isAdFree(user.uid) || await hasTemporaryPriority(user.uid));
    await _db.collection('requests').doc(requestId).collection('messages').add({
      'senderId': senderId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'isPriority': isPriority,
    });
    var requestDoc = await _db.collection('requests').doc(requestId).get();
    var requestData = requestDoc.data() as Map<String, dynamic>;
    String recipientId = senderId == requestData['userId'] ? requestData['providerId'] : requestData['userId'];
    var recipientDoc = await _db.collection(senderId == requestData['userId'] ? 'providers' : 'users').doc(recipientId).get();
    String? token = recipientDoc.data()?['deviceToken'];
    if (token != null) {
      await FirebaseMessaging.instance.sendMessage(
        to: token,
        data: {'title': 'New Message', 'body': text},
      );
      await flutterLocalNotificationsPlugin.show(
        0,
        'New Message',
        text,
        const NotificationDetails(android: AndroidNotificationDetails('channel_id', 'Messages')),
      );
    }
  }

  Stream<QuerySnapshot> getMessages(String requestId) {
    return _db
        .collection('requests')
        .doc(requestId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> submitRating(String requestId, String userId, String providerId, int rating) async {
    await _db.collection('ratings').add({
      'requestId': requestId,
      'userId': userId,
      'providerId': providerId,
      'rating': rating,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<double> getProviderAverageRating(String providerId) async {
    var ratingsSnapshot = await _db
        .collection('ratings')
        .where('providerId', isEqualTo: providerId)
        .get();
    if (ratingsSnapshot.docs.isEmpty) return 0.0;
    var total = ratingsSnapshot.docs.fold<int>(0, (sum, doc) => sum + (doc['rating'] as int));
    return total / ratingsSnapshot.docs.length;
  }

  Future<void> submitReport(String reporterId, String targetId, String reason, String type) async {
    var docRef = await _db.collection('reports').add({
      'reporterId': reporterId,
      'targetId': targetId,
      'reason': reason,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await _db.collection('analytics').doc('reports').collection('records').doc(docRef.id).set({
      'reportId': docRef.id,
      'reporterId': reporterId,
      'targetId': targetId,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>> getProviderAnalytics(String providerId) async {
    var requests = await _db
        .collection('analytics')
        .doc('requests')
        .collection('records')
        .where('acceptedAt', isNotEqualTo: null)
        .where('providerId', isEqualTo: providerId)
        .get();
    var responseTimes = requests.docs.map((doc) {
      var data = doc.data();
      var createdAt = (data['createdAt'] as Timestamp).toDate();
      var acceptedAt = (data['acceptedAt'] as Timestamp).toDate();
      return acceptedAt.difference(createdAt).inMinutes;
    }).toList();
    double avgResponseTime = responseTimes.isEmpty ? 0 : responseTimes.reduce((a, b) => a + b) / responseTimes.length;

    var completedRequests = await _db
        .collection('analytics')
        .doc('requests')
        .collection('records')
        .where('completedAt', isNotEqualTo: null)
        .where('providerId', isEqualTo: providerId)
        .get();
    var serviceTimes = completedRequests.docs.map((doc) {
      var data = doc.data();
      var acceptedAt = (data['acceptedAt'] as Timestamp).toDate();
      var completedAt = (data['completedAt'] as Timestamp).toDate();
      return completedAt.difference(acceptedAt).inMinutes;
    }).toList();
    double avgServiceTime = serviceTimes.isEmpty ? 0 : serviceTimes.reduce((a, b) => a + b) / serviceTimes.length;

    var reports = await _db
        .collection('analytics')
        .doc('reports')
        .collection('records')
        .where('targetId', isEqualTo: providerId)
        .get();
    int reportCount = reports.docs.length;

    return {
      'avgResponseTime': avgResponseTime,
      'avgServiceTime': avgServiceTime,
      'reportCount': reportCount,
    };
  }

  Future<void> sendNotification(String userId, String title, String body) async {
    var userDoc = await _db.collection('users').doc(userId).get();
    String? token = userDoc.data()?['deviceToken'];
    if (token != null) {
      await FirebaseMessaging.instance.sendMessage(
        to: token,
        data: {'title': title, 'body': body},
      );
      await flutterLocalNotificationsPlugin.show(
        0,
        title,
        body,
        const NotificationDetails(android: AndroidNotificationDetails('channel_id', 'Notifications')),
      );
    }
  }

  Future<bool> isAdFree(String uid) async {
    var userDoc = await _db.collection('users').doc(uid).get();
    var providerDoc = await _db.collection('providers').doc(uid).get();
    bool userAdFree = userDoc.data()?['adFree'] ?? false;
    bool providerAdFree = providerDoc.data()?['adFree'] ?? false;
    return userAdFree || providerAdFree;
  }

  Future<void> setAdFree(String uid, bool adFree) async {
    await _db.collection('users').doc(uid).set({'adFree': adFree}, SetOptions(merge: true));
    await _db.collection('providers').doc(uid).set({'adFree': adFree}, SetOptions(merge: true));
  }

  Future<bool> hasTemporaryPriority(String uid) async {
    var userDoc = await _db.collection('users').doc(uid).get();
    var priorityUntil = userDoc.data()?['priorityUntil'] as Timestamp?;
    if (priorityUntil == null) return false;
    return priorityUntil.toDate().isAfter(DateTime.now());
  }

  Future<void> grantTemporaryPriority(String uid) async {
    var expiry = Timestamp.fromDate(DateTime.now().add(Duration(hours: 24)));
    await _db.collection('users').doc(uid).set({'priorityUntil': expiry}, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> searchProviders(
    String query,
    Position userLocation, {
    double minRating = 0.0,
    bool verifiedOnly = false,
  }) async {
    var providersSnapshot = await _db.collection('providers').get();
    List<Map<String, dynamic>> providers = [];

    for (var doc in providersSnapshot.docs) {
      var data = doc.data();
      double avgRating = await getProviderAverageRating(doc.id);
      providers.add({
        'id': doc.id,
        'name': data['name'],
        'type': data['type'],
        'isVerified': data['isVerified'] ?? false,
        'adFree': data['adFree'] ?? false,
        'location': data['lastKnownLocation'] != null
            ? GeoPoint(data['lastKnownLocation']['latitude'], data['lastKnownLocation']['longitude'])
            : null,
        'avgRating': avgRating,
      });
    }

    // Apply filters
    providers = providers
        .where((provider) => provider['type'].toString().toLowerCase().contains(query.toLowerCase()))
        .where((provider) => provider['avgRating'] >= minRating)
        .where((provider) => !verifiedOnly || provider['isVerified'])
        .toList();

    // Calculate distance and sort
    providers.forEach((provider) {
      if (provider['location'] != null) {
        provider['distance'] = Geolocator.distanceBetween(
          userLocation.latitude,
          userLocation.longitude,
          provider['location'].latitude,
          provider['location'].longitude,
        ) / 1000; // Distance in km
      } else {
        provider['distance'] = double.infinity;
      }
    });

    providers.sort((a, b) {
      if (a['adFree'] == true && b['adFree'] != true) return -1;
      if (a['adFree'] != true && b['adFree'] == true) return 1;
      return a['distance'].compareTo(b['distance']);
    });

    return providers;
  }
}