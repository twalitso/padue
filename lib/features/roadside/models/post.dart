import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String content; // Renamed from description
  final String category;
  final String type;
  final List<String> mediaUrls;
  final GeoPoint? location;
  final String? geohash;
  final Map<String, dynamic>? geo;
  final String posterId;
  final String posterType;
  final String posterName;
  final String? posterProfilePicUrl;
  final DateTime? createdAt;
  final String status;
  final int likeCount;

  Post({
    required this.id,
    required this.content,
    required this.category,
    required this.type,
    this.mediaUrls = const [],
    this.location,
    this.geohash,
    this.geo,
    required this.posterId,
    required this.posterType,
    required this.posterName,
    this.posterProfilePicUrl,
    this.createdAt,
    required this.status,
    this.likeCount = 0,
  });

  Map<String, dynamic> toMap() => {
        'content': content,
        'category': category,
        'type': type,
        'mediaUrls': mediaUrls,
        'location': location,
        'geohash': geohash,
        'geo': geo,
        'posterId': posterId,
        'posterType': posterType,
        'posterName': posterName,
        'posterProfilePicUrl': posterProfilePicUrl,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
        'status': status,
        'likeCount': likeCount,
      };

  factory Post.fromMap(Map<String, dynamic> data, String id) => Post(
        id: id,
        content: data['content'] as String,
        category: data['category'] as String,
        type: data['type'] as String,
        mediaUrls: List<String>.from(data['mediaUrls'] ?? []),
        location: data['location'] as GeoPoint?,
        geohash: data['geohash'] as String?,
        geo: data['geo'] as Map<String, dynamic>?,
        posterId: data['posterId'] as String,
        posterType: data['posterType'] as String,
        posterName: data['posterName'] as String,
        posterProfilePicUrl: data['posterProfilePicUrl'] as String?,
        createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : null,
        status: data['status'] as String,
        likeCount: data['likeCount'] as int? ?? 0,
      );
}