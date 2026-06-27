import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:padue/main.dart';
import 'dart:io';
import 'package:cloudinary_public/cloudinary_public.dart'; // Use this instead
import '../features/auth/models/user_profile.dart';
import '../features/roadside/models/provider.dart';
import 'package:path/path.dart' as p;
import 'package:retry/retry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final geo = Geoflutterfire();

  // Initialize Cloudinary
  static final CloudinaryPublic _cloudinary = CloudinaryPublic('dkltwubbb', 'ml_default'); 
  

Future<void> updateUserLocation(String uid, GeoPoint location) async {
  try {
    await _db.collection('users').doc(uid).set(
      {'location': location},
      SetOptions(merge: true),
    );
  } catch (e) {
    throw Exception('Failed to update user location: $e');
  }
}

Stream<QuerySnapshot> getProvidersByServiceold(String service) {
  return _db.collection('providers').where('servicesOffered', arrayContains: service).snapshots();
}

  Future<List<Map<String, dynamic>>> searchProviders(
    String query,
    Position userLocation, {
    double minRating = 0.0,
    bool verifiedOnly = false,
    String? category,
    String sortBy = 'distance',
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    query = query.toLowerCase().trim();
    List<Map<String, dynamic>> results = [];

    // Build base query
    Query<Map<String, dynamic>> firestoreQuery = FirebaseFirestore.instance.collection('providers');

    if (category != null) {
      firestoreQuery = firestoreQuery.where('servicesOffered', arrayContains: category);
    } else {
      // Search across multiple fields
      var queries = [
        firestoreQuery
            .where('name', isGreaterThanOrEqualTo: query)
            .where('name', isLessThanOrEqualTo: '$query\uf8ff'),
        firestoreQuery.where('servicesOffered', arrayContains: query),
        firestoreQuery
            .where('type', isGreaterThanOrEqualTo: query)
            .where('type', isLessThanOrEqualTo: '$query\uf8ff'),
      ];

      Map<String, Map<String, dynamic>> uniqueProviders = {};
      for (var q in queries) {
        var snapshot = await q.limit(limit).get();
        for (var doc in snapshot.docs) {
          uniqueProviders[doc.id] = doc.data()..['id'] = doc.id..['doc'] = doc;
        }
      }
      results = uniqueProviders.values.toList();
    }

    if (startAfter != null && category != null) {
      // Handle pagination for category search
      var snapshot = await firestoreQuery
          .orderBy('name')
          .startAfterDocument(startAfter)
          .limit(limit)
          .get();
      results = snapshot.docs.map((doc) => doc.data()..['id'] = doc.id..['doc'] = doc).toList();
    } else if (startAfter != null) {
      // Handle pagination for multi-field search
      var snapshot = await firestoreQuery
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .orderBy('name')
          .startAfterDocument(startAfter)
          .limit(limit)
          .get();
      results = snapshot.docs.map((doc) => doc.data()..['id'] = doc.id..['doc'] = doc).toList();
    }

    // Apply filters
    results = results.where((provider) {
      double avgRating = (provider['rating'] as num?)?.toDouble() ?? 0.0;
      bool isVerified = provider['isVerified'] ?? false;
      return avgRating >= minRating && (!verifiedOnly || isVerified);
    }).toList();

    // Calculate distances
    for (var provider in results) {
      if (provider['location'] != null) {
        GeoPoint providerLocation = provider['location'] as GeoPoint;
        provider['distance'] = Geolocator.distanceBetween(
          userLocation.latitude,
          userLocation.longitude,
          providerLocation.latitude,
          providerLocation.longitude,
        ) / 1000; // Convert to km
      } else {
        provider['distance'] = double.infinity;
      }
    }

    // Sort results
    results.sort((a, b) {
      if (sortBy == 'distance') {
        double distA = a['distance'] ?? double.infinity;
        double distB = b['distance'] ?? double.infinity;
        return distA.compareTo(distB);
      } else if (sortBy == 'rating') {
        double ratingA = (a['rating'] as num?)?.toDouble() ?? 0.0;
        double ratingB = (b['rating'] as num?)?.toDouble() ?? 0.0;
        return ratingB.compareTo(ratingA);
      } else if (sortBy == 'availability') {
        bool availA = a['availability'] ?? false;
        bool availB = b['availability'] ?? false;
        if (availA == availB) return 0;
        return availA ? -1 : 1;
      }
      return 0;
    });

    return results;
  }
Future<void> createPost({
  required String content,
  required List<File> mediaFiles,
  required GeoPoint? location,
  required String posterId,
  required String posterType,
  required String posterName,
  required String? posterProfilePicUrl,
}) async {
  List<String> mediaUrls = [];
  if (mediaFiles.isNotEmpty) {
    for (var file in mediaFiles) {
      String path = 'posts/$posterId/${DateTime.now().toIso8601String()}';
      String url = await uploadMedia(file, path);
      mediaUrls.add(url);
    }
  }

  await _db.collection('posts').add({
    'content': content,
    'mediaUrls': mediaUrls,
    'location': location,
    'posterId': posterId,
    'posterType': posterType,
    'posterName': posterName,
    'posterProfilePicUrl': posterProfilePicUrl,
    'timestamp': FieldValue.serverTimestamp(),
    'status': 'active',
    'likeCount': 0,
    'category': 'general', // Default category
    'type': 'post', // Default type
  });
}


 // Get comments for a post
  Stream<QuerySnapshot> getComments(String postId) {
    return _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> addComment({
    required String postId,
    required String commenterId,
    required String commenterName,
    required String text,
  }) async {
    await _db.collection('posts').doc(postId).collection('comments').add({
      'commenterId': commenterId,
      'commenterName': commenterName,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    required String id,
  }) async {
    var collection = await _db.collection('users').doc(userId).get().then((doc) => doc.exists)
        ? 'users'
        : 'providers';
    await _db.collection(collection).doc(userId).collection('notifications').add({
      'title': title,
      'body': body,
      'type': type,
      'id': id,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });
  }


 Future<void> addUserNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    required String id,
  }) async {
  
    await _db.collection('users').doc(userId).collection('notifications').add({
      'title': title,
      'body': body,
      'type': type,
      'id': id,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

    Future<void> addProviderNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    required String id,
  }) async {
   
    await _db.collection('Providers').doc(userId).collection('notifications').add({
      'title': title,
      'body': body,
      'type': type,
      'id': id,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  Stream<List<Map<String, dynamic>>> getPosts({
    GeoPoint? center,
    double radius = 10.0,
  }) {
    Query<Map<String, dynamic>> query = _db.collection('posts').where('status', isEqualTo: 'active');

    if (center != null) {
      GeoFirePoint geoCenter = geo.point(latitude: center.latitude, longitude: center.longitude);
      return geo
          .collection(collectionRef: query)
          .within(
            center: geoCenter,
            radius: radius,
            field: 'geo',
            strictMode: true,
          )
          .map((snapshot) => snapshot.map((doc) => {'postId': doc.id, ...?doc.data()}).toList());
    }

    return query.snapshots().map((snapshot) => snapshot.docs.map((doc) => {'postId': doc.id, ...doc.data()}).toList());
  }

  Future<void> incrementPostViewCount(String postId) async {
    await _db.collection('post_analytics').doc('records').collection('posts').doc(postId).update({
      'viewCount': FieldValue.increment(1),
    });
  }


  // Compress image before upload
  Future<File> compressImage(File file) async {
    final filePath = file.path;
    final lastIndex = filePath.lastIndexOf(RegExp(r'.jp'));
    final outPath = '${filePath.substring(0, lastIndex)}_compressed.jpg';
    final compressedFile = await FlutterImageCompress.compressAndGetFile(
      filePath,
      outPath,
      quality: 85,       // Adjust quality (0-100, lower = smaller size)
      minWidth: 800,     // Resize to max 800px width
      minHeight: 800,    // Resize to max 800px height
    );
    return File(compressedFile!.path);
  }

Future<void> storeDeviceToken(String token) async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    // Always store token in users collection
    
    // Only store in providers collection if user is a provider
    String? role = await getUserRole(user.uid);
    if (role == 'provider') {
      await _db.collection('providers').doc(user.uid).set(
          {'deviceToken': token},
          SetOptions(merge: true)
      );
      print('Stored device token for provider UID: ${user.uid}'); // Debugging
    } else {

        await _db.collection('users').doc(user.uid).set(
        {'deviceToken': token},
        SetOptions(merge: true)
    );
    }
  }
}

  // Create a request with geolocation and priority
  Future<void> createRequest(Map<String, dynamic> requestData) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      bool hasAdFree = await isAdFree(user.uid);
      bool hasRewardedPriority = await hasTemporaryPriority(user.uid);
      GeoPoint location = requestData['location'] as GeoPoint;
      GeoFirePoint point = geo.point(latitude: location.latitude, longitude: location.longitude);
      requestData['geohash'] = point.hash;
      requestData['geo'] = point.data;
      requestData['createdAt'] = FieldValue.serverTimestamp();
      requestData['isPriority'] = hasAdFree || hasRewardedPriority;
      var docRef = await _db.collection('requests').add(requestData);
      await _db.collection('analytics').doc('requests').collection('records').doc(docRef.id).set({
        'requestId': docRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Get dynamic service options
  Stream<QuerySnapshot> getServiceOptions() {
    return _db.collection('services').snapshots();
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
          .where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return data['status'] == 'open' || (data['status'] == 'accepted' && data['providerId'] == providerId);
          })
          .map((doc) => {
                'id': doc.id,
                ...doc.data() as Map<String, dynamic>,
              })
          .toList();
      requests.sort((a, b) {
        if (a['isPriority'] == true && b['isPriority'] != true) return -1;
        if (a['isPriority'] != true && b['isPriority'] == true) return 1;
        if (a['status'] == 'open' && b['status'] == 'accepted') return -1;
        if (a['status'] == 'accepted' && b['status'] == 'open') return 1;
        return 0;
      });
      return requests;
    });
  }

  // Get profile picture URL
  Future<String?> getProfilePicUrl(String uid) async {
    var providerDoc = await _db.collection('providers').doc(uid).get();
    return providerDoc.data()?['profilePicUrl'] as String?;
  }

/**  Future<String> uploadMedia(File file, String path) async {
    try {
      // Validate file
      if (file == null || !file.existsSync()) {
        throw Exception('Invalid file: File is null or does not exist');
      }

      final response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          resourceType: CloudinaryResourceType.Image, // Ensure correct type
          folder: path, // e.g., "profiles/user123"
        ),
      );

      if (response.secureUrl.isEmpty) {
        throw Exception('Upload failed: No secure URL returned');
      }

      return response.secureUrl;
    } catch (e) {
      print('Failed to upload media: $e');
      rethrow; // Propagate the error for debugging
    }
  } */
  // Generic media upload method using Cloudinary with compression
 Future<String> uploadMedia(File file, String path) async {
  try {
    if (file == null || !file.existsSync()) {
      throw Exception('Invalid file: File is null or does not exist');
    }
     // Determine resource type based on file extension
      final extension = p.extension(file.path).toLowerCase();
      CloudinaryResourceType resourceType;
      switch (extension) {
        case '.jpg':
        case '.jpeg':
        case '.png':
        case '.gif':
          resourceType = CloudinaryResourceType.Image;
          break;
        case '.mp4':
        case '.mov':
        case '.avi':
          resourceType = CloudinaryResourceType.Video;
          break;
        case '.pdf':
        case '.txt':
        case '.zip':
          resourceType = CloudinaryResourceType.Raw;
          break;
        default:
          throw Exception('Unsupported file type: $extension');
      }

  
    final response = await _cloudinary.uploadFile(
      CloudinaryFile.fromFile(
        file.path,
        resourceType: resourceType,
        folder: path,
      ),
    );
    if (response.secureUrl.isEmpty) {
      throw Exception('Upload failed: No secure URL returned');
    }
    
    return response.secureUrl;
  } catch (e) {
    if (e is CloudinaryException) {
      
    }
    
    throw Exception('Failed to upload media: $e');
  }
}




  Future<List<Map<String, dynamic>>> getSubscriptionPackages() async {
    try {
      QuerySnapshot snapshot = await _db.collection('subscriptions').get();
      return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    } catch (e) {
      throw Exception('Failed to fetch subscription packages: $e');
    }
  }

  // Get user profile
  Future<UserProfile?> getUserProfile(String uid) async {
    DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) return UserProfile.fromMap(doc.data() as Map<String, dynamic>);
    return null;
  }

  // Update user profile
  Future<void> updateUserProfile(String uid, UserProfile profile) async {
    await _db.collection('users').doc(uid).set(profile.toMap(), SetOptions(merge: true));
  }

  // Update provider profile
  Future<void> updateProviderProfile(String providerId, Map<String, dynamic> data) async {
    await _db.collection('providers').doc(providerId).set(data, SetOptions(merge: true));
  }

  // Get provider profile
  Future<Provider?> getProviderProfile(String providerId) async {
    DocumentSnapshot doc = await _db.collection('providers').doc(providerId).get();
    if (doc.exists) return Provider.fromFirestore(doc);
    return null;
  }

  // Upload provider document using Cloudinary
  Future<String?> uploadProviderDocument(String providerId, File document) async {
    String path = 'provider_documents/$providerId/verification_${DateTime.now().toIso8601String()}';
    String url = await uploadMedia(document, path);
    await _db.collection('providers').doc(providerId).update({'documentUrl': url, 'isVerified': false});
    return url;
  }

  // Upload provider profile picture using Cloudinary
  Future<String?> uploadProviderProfilePicture(String providerId, File profilePicture) async {
    String path = 'provider_images/$providerId/profile_${DateTime.now().toIso8601String()}';
    String url = await uploadMedia(profilePicture, path);
    await _db.collection('providers').doc(providerId).update({'profilePicUrl': url});
    return url;
  }

  // Send message
  Future<void> sendMessage(String chatId, String senderId, String text) async {
    User? user = FirebaseAuth.instance.currentUser;
    bool isPriority = user != null && (await isAdFree(user.uid) || await hasTemporaryPriority(user.uid));
    await _db.collection('chat_requests').doc(chatId).collection('messages').add({
      'senderId': senderId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'isPriority': isPriority,
      'read': false,
    });
    var chatDoc = await _db.collection('chat_requests').doc(chatId).get();
    var chatData = chatDoc.data() as Map<String, dynamic>?;
    if (chatData == null) return;

    String recipientId = senderId == chatData['userId'] ? chatData['providerId'] : chatData['userId'];
    var recipientDoc = await _db
        .collection(senderId == chatData['userId'] ? 'providers' : 'users')
        .doc(recipientId)
        .get();

    if (!recipientDoc.exists) {
      
      return;
    }

    String? token = recipientDoc.data()?['deviceToken'];
    if (token != null && token.isNotEmpty) {
      try {
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
      } catch (e) {
        
      }
    } else {
      
    }
  }

  // Get messages for a chat
  Stream<QuerySnapshot> getMessages(String chatId) {
    return _db
        .collection('chat_requests')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Submit a rating
  Future<void> submitRating(String requestId, String userId, String providerId, int rating) async {
    await _db.collection('reviews').add({
      'requestId': requestId,
      'userId': userId,
      'providerId': providerId,
      'rating': rating,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Get provider average rating
  Future<double> getProviderAverageRating(String providerId) async {
    var reviewsSnapshot = await _db.collection('reviews').where('providerId', isEqualTo: providerId).get();
    if (reviewsSnapshot.docs.isEmpty) return 0.0;
    var total = reviewsSnapshot.docs.fold<double>(0, (sum, doc) => sum + (doc['rating'] as int));
    return total / reviewsSnapshot.docs.length;
  }

  // Send notification
  Future<void> sendNotification(String userId, String title, String body) async {
    await _db.collection('notifications').add({
      'to': userId,
      'title': title,
      'body': body,
      'timestamp': FieldValue.serverTimestamp(),
    });
    var userDoc = await _db.collection('users').doc(userId).get();
    String? token = userDoc.data()?['deviceToken'];
    if (token != null) {
      await FirebaseMessaging.instance.sendMessage(
        to: token,
        data: {'title': title, 'body': body},
      );
    }
  }

  // Submit a report
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

  // Get provider analytics
  Future<Map<String, dynamic>> getProviderAnalytics(String providerId) async {
    var requests = await _db
        .collection('analytics')
        .doc('requests')
        .collection('records')
        .where('providerId', isEqualTo: providerId)
        .where('acceptedAt', isNotEqualTo: null)
        .get();
    var responseTimes = requests.docs.map((doc) {
      var data = doc.data();
      var createdAt = data['createdAt'] as Timestamp?;
      var acceptedAt = data['acceptedAt'] as Timestamp?;
      if (createdAt == null || acceptedAt == null) return 0;
      return acceptedAt.toDate().difference(createdAt.toDate()).inMinutes;
    }).toList();
    double avgResponseTime = responseTimes.isEmpty ? 0 : responseTimes.reduce((a, b) => a + b) / responseTimes.length;

    var completedRequests = await _db
        .collection('analytics')
        .doc('requests')
        .collection('records')
        .where('providerId', isEqualTo: providerId)
        .where('completedAt', isNotEqualTo: null)
        .get();
    var serviceTimes = completedRequests.docs.map((doc) {
      var data = doc.data();
      var acceptedAt = data['acceptedAt'] as Timestamp?;
      var completedAt = data['completedAt'] as Timestamp?;
      if (acceptedAt == null || completedAt == null) return 0;
      return completedAt.toDate().difference(acceptedAt.toDate()).inMinutes;
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

  // Check ad-free status
  Future<bool> isAdFree(String uid) async {
    try {
      return await retry(
        () async {
          var userDoc = await _db.collection('users').doc(uid).get();
          var providerDoc = await _db.collection('providers').doc(uid).get();
          bool userAdFree = userDoc.data()?['adFree'] ?? false;
          bool providerAdFree = providerDoc.data()?['adFree'] ?? false;
          return userAdFree || providerAdFree;
        },
        maxAttempts: 3,
        delayFactor: const Duration(seconds: 1),
        randomizationFactor: 0.25,
        maxDelay: const Duration(seconds: 5),
        onRetry: (error) {
          print('Retrying isAdFree due to error: $error');
        },
      );
    } catch (e) {
      print('Failed to check ad-free status: $e');
      return false; // Fallback to false to allow app to proceed
    }
  }

  // Set ad-free status
  Future<void> setAdFree(String uid, bool adFree) async {
    await _db.collection('users').doc(uid).set({'adFree': adFree}, SetOptions(merge: true));
    await _db.collection('providers').doc(uid).set({'adFree': adFree}, SetOptions(merge: true));
  }

  // Check temporary priority
  Future<bool> hasTemporaryPriority(String uid) async {
    var userDoc = await _db.collection('users').doc(uid).get();
    var priorityUntil = userDoc.data()?['priorityUntil'] as Timestamp?;
    if (priorityUntil == null) return false;
    return priorityUntil.toDate().isAfter(DateTime.now());
  }

Future<void> saveFcmToken() async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final messaging = FirebaseMessaging.instance;
  final token = await messaging.getToken();
  if (token == null) return;

  final firestore = FirebaseFirestore.instance;
  final role = await FirestoreService().getUserRole(user.uid);

  if (role == 'user') {
    await firestore.collection('users').doc(user.uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  } else if (role == 'provider') {
    await firestore.collection('providers').doc(user.uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  }
}


Future<void> clearAllCache() async {
  try {
    // 1. SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Removes role, welcome, etc.

    // 2. CachedNetworkImage
   // await CachedNetworkImage.evictAll();

    // 3. FlutterMap / Default Cache Manager (tiles)
   // await DefaultCacheManager().emptyCache();

    // 4. Firestore offline persistence (optional but safe)
  //  await FirebaseFirestore.instance.clearPersistence();

    print('All cache cleared on logout');
  } catch (e) {
    print('Cache clear error: $e');
  }
}

  // Grant temporary priority
  Future<void> grantTemporaryPriority(String uid) async {
    var expiry = Timestamp.fromDate(DateTime.now().add(Duration(hours: 24)));
    await _db.collection('users').doc(uid).set({'priorityUntil': expiry}, SetOptions(merge: true));
  }
  Future<String?> getUserRole(String uid) async {
    try {
      // Check 'users' collection first for explicit role
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        final role = userData?['role'] as String?;
        if (role == 'user') {
          return 'user'; // Explicit user role
        }
        // If no role or role != 'users', check providers
      }

      // Check 'providers' collection
      final providerDoc = await _db.collection('providers').doc(uid).get();
      if (providerDoc.exists) {
        return 'provider'; // Presence in providers = provider role
      }

      // If in 'users' with no role and not in 'providers', assume no valid role
      return null; // UID not found as a valid user or provider
    } catch (e) {
      throw Exception('Failed to determine user role: $e');
    }
  }


  Future<QuerySnapshot<Map<String, dynamic>>> getProvidersByService(String service) {
  return FirebaseFirestore.instance
      .collection('providers')
      .where('service', isEqualTo: service)
      .get();
}

Future<QuerySnapshot<Map<String, dynamic>>> getAllProviders() {
  return FirebaseFirestore.instance.collection('providers').get();
}

  // Get all providers
  Stream<QuerySnapshot> getAllProvidersold() {
    return _db.collection('providers').snapshots();
  }

  // Get providers by category
  Stream<QuerySnapshot> getProvidersByCategory(String category) {
    return _db.collection('providers').where('servicesOffered', arrayContains: category).snapshots();
  }

 Future<List<Map<String, dynamic>>> searchProvidersold(
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
      'location': data['location'] != null
          ? GeoPoint(data['location']['latitude'], data['location']['longitude'])
          : null,
      'avgRating': avgRating,
      'servicesOffered': List<String>.from(data['servicesOffered'] ?? []),
      'profilePicUrl': data['profilePicUrl'],
      'availability': data['availability'] ?? true,
      'address': data['address'], // Added
    });
  }

  providers = providers
      .where((provider) =>
          provider['name'].toString().toLowerCase().contains(query.toLowerCase()) ||
          provider['type'].toString().toLowerCase().contains(query.toLowerCase()) ||
          (provider['servicesOffered'] as List)
              .any((service) => service.toString().toLowerCase().contains(query.toLowerCase())))
      .where((provider) => provider['avgRating'] >= minRating)
      .where((provider) => !verifiedOnly || provider['isVerified'])
      .toList();

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