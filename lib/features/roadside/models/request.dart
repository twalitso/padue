import 'package:cloud_firestore/cloud_firestore.dart';

class RoadsideRequest {
  final String userId;
  final String issue;
  final String? locationDescription;
  final GeoPoint location;
  final String? mediaUrl;
  final String status;
  final String? providerId;

  RoadsideRequest({
    required this.userId,
    required this.issue,
    this.locationDescription,
    required this.location,
    this.mediaUrl,
    this.status = 'open',
    this.providerId,
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'issue': issue,
        'locationDescription': locationDescription,
        'location': location,
        'mediaUrl': mediaUrl,
        'status': status,
        'providerId': providerId,
        'timestamp': FieldValue.serverTimestamp(),
      };
}