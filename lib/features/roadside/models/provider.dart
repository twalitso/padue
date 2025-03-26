import 'package:cloud_firestore/cloud_firestore.dart';

class Provider {
  final String id;
  final String name;
  final String type;
  final String? phoneNumber; // Made nullable
  final bool isVerified;
  final String? documentUrl;
  final GeoPoint location;
  final List<String> servicesOffered;
  final double? rating;
  final String? profilePicUrl;
  final bool availability;
  final DateTime? lastActive;

  Provider({
    required this.id,
    required this.name,
    required this.type,
    this.phoneNumber, // Now optional
    this.isVerified = false,
    this.documentUrl,
    required this.location,
    this.servicesOffered = const [],
    this.rating,
    this.profilePicUrl,
    this.availability = true,
    this.lastActive,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'phoneNumber': phoneNumber,
      'isVerified': isVerified,
      'documentUrl': documentUrl,
      'location': location,
      'servicesOffered': servicesOffered,
      'rating': rating,
      'profilePicUrl': profilePicUrl,
      'availability': availability,
      'lastActive': lastActive != null ? Timestamp.fromDate(lastActive!) : null,
    };
  }

  factory Provider.fromMap(Map<String, dynamic> map) {
    return Provider(
      id: map['id'] as String? ?? '', // Fallback for required field
      name: map['name'] as String? ?? 'Unknown', // Already safe
      type: map['type'] as String? ?? 'Unknown', // Already safe
      phoneNumber: map['phoneNumber'] as String?, // Now nullable, no fallback needed
      isVerified: map['isVerified'] as bool? ?? false,
      documentUrl: map['documentUrl'] as String?,
      location: map['location'] as GeoPoint? ?? const GeoPoint(0.0, 0.0),
      servicesOffered: List<String>.from(map['servicesOffered'] ?? []),
      rating: map['rating'] != null ? (map['rating'] as num).toDouble() : null,
      profilePicUrl: map['profilePicUrl'] as String?,
      availability: map['availability'] as bool? ?? true,
      lastActive: map['lastActive'] != null
          ? (map['lastActive'] as Timestamp).toDate()
          : null,
    );
  }

  factory Provider.fromFirestore(DocumentSnapshot doc) {
    return Provider.fromMap(doc.data() as Map<String, dynamic>);
  }
}