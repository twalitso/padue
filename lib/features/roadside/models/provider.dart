import 'package:cloud_firestore/cloud_firestore.dart';
/** 
class Provider {
  final String id;
  final String name;
  final String type;
  final String? phoneNumber;
  final bool isVerified;
  final String? documentUrl;
  final GeoPoint location;
  final List<String> servicesOffered;
  final double? rating;
  final String? profilePicUrl;
  final bool availability;
  final DateTime? lastActive;
  final String? address;
  final bool adFree;
  final DateTime? priorityUntil;
  final String? description; // New field
  final Map<String, String>? operatingHours; // New field
  final String? website; // New field
  final List<String>? socialMediaLinks; // New field

  Provider({
    required this.id,
    required this.name,
    required this.type,
    this.phoneNumber,
    this.isVerified = false,
    this.documentUrl,
    required this.location,
    this.servicesOffered = const [],
    this.rating,
    this.profilePicUrl,
    this.availability = true,
    this.lastActive,
    this.address,
    this.adFree = false,
    this.priorityUntil,
    this.description,
    this.operatingHours,
    this.website,
    this.socialMediaLinks,
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
      'address': address,
      'adFree': adFree,
      'priorityUntil': priorityUntil != null ? Timestamp.fromDate(priorityUntil!) : null,
      'description': description,
      'operatingHours': operatingHours,
      'website': website,
      'socialMediaLinks': socialMediaLinks,
    };
  }

  factory Provider.fromMap(Map<String, dynamic> map) {
    return Provider(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown',
      type: map['type'] as String? ?? 'Unknown',
      phoneNumber: map['phoneNumber'] as String?,
      isVerified: map['isVerified'] as bool? ?? false,
      documentUrl: map['documentUrl'] as String?,
      location: map['location'] as GeoPoint? ?? const GeoPoint(0.0, 0.0),
      servicesOffered: List<String>.from(map['servicesOffered'] ?? []),
      rating: map['rating'] != null ? (map['rating'] as num).toDouble() : null,
      profilePicUrl: map['profilePicUrl'] as String?,
      availability: map['availability'] as bool? ?? true,
      lastActive: map['lastActive'] != null ? (map['lastActive'] as Timestamp).toDate() : null,
      address: map['address'] as String?,
      adFree: map['adFree'] as bool? ?? false,
      priorityUntil: map['priorityUntil'] != null ? (map['priorityUntil'] as Timestamp).toDate() : null,
      description: map['description'] as String?,
      operatingHours: map['operatingHours'] != null ? Map<String, String>.from(map['operatingHours']) : null,
      website: map['website'] as String?,
      socialMediaLinks: map['socialMediaLinks'] != null ? List<String>.from(map['socialMediaLinks']) : null,
    );
  }

  factory Provider.fromFirestore(DocumentSnapshot doc) {
    return Provider.fromMap(doc.data() as Map<String, dynamic>);
  }
}*/

import 'package:cloud_firestore/cloud_firestore.dart';

class Provider {
  final String id;
  final String name;
  final String type;
  final String? phoneNumber;
  final bool isVerified;
  final String? documentUrl;
  final GeoPoint location;
  final List<String> servicesOffered;
  final double? rating;
  final String? profilePicUrl;
  final bool availability;
  final DateTime? lastActive;
  final String? address;
  final bool adFree;
  final DateTime? priorityUntil;
  final String? description;
  final Map<String, String>? operatingHours;
  final String? website;
  final List<String>? socialMediaLinks;
  final DateTime? subscriptionEnd;


  Provider({
    required this.id,
    required this.name,
    required this.type,
    this.phoneNumber,
    this.isVerified = false,
    this.documentUrl,
    required this.location,
    this.servicesOffered = const [],
    this.rating,
    this.profilePicUrl,
    this.availability = true,
    this.lastActive,
    this.address,
    this.adFree = false,
    this.priorityUntil,
    this.description,
    this.operatingHours,
    this.website,
    this.socialMediaLinks,
    this.subscriptionEnd,

  });

  /// Converts Provider to Firestore-compatible map
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
      'address': address,
      'adFree': adFree,
      'priorityUntil': priorityUntil != null ? Timestamp.fromDate(priorityUntil!) : null,
      'description': description,
      'operatingHours': operatingHours,
      'website': website,
      'socialMediaLinks': socialMediaLinks,
      'subscriptionEnd':
    subscriptionEnd != null ? Timestamp.fromDate(subscriptionEnd!) : null,

    };
  }

  /// Creates Provider from cached/SharedPreferences map (supports old format)
  factory Provider.fromMap(Map<String, dynamic> map) {
    // Handle location: could be GeoPoint or old map format {latitude: ..., longitude: ...}
    GeoPoint location;
    final locData = map['location'];
    if (locData is GeoPoint) {
      location = locData;
    } else if (locData is Map<String, dynamic>) {
      final lat = (locData['latitude'] ?? locData['lat'] ?? 0.0) as double;
      final lng = (locData['longitude'] ?? locData['lng'] ?? 0.0) as double;
      location = GeoPoint(lat, lng);
    } else {
      location = const GeoPoint(0.0, 0.0);
    }

    // Handle lastActive and priorityUntil: could be Timestamp or millisecondsSinceEpoch (int)
    DateTime? lastActive;
    final lastActiveData = map['lastActive'];
    if (lastActiveData is Timestamp) {
      lastActive = lastActiveData.toDate();
    } else if (lastActiveData is int) {
      lastActive = DateTime.fromMillisecondsSinceEpoch(lastActiveData);
    }

    DateTime? priorityUntil;
    final priorityData = map['priorityUntil'];
    if (priorityData is Timestamp) {
      priorityUntil = priorityData.toDate();
    } else if (priorityData is int) {
      priorityUntil = DateTime.fromMillisecondsSinceEpoch(priorityData);
    }
    DateTime? subscriptionEnd;
final subEndData = map['subscriptionEnd'];
if (subEndData is Timestamp) {
  subscriptionEnd = subEndData.toDate();
} else if (subEndData is int) {
  subscriptionEnd = DateTime.fromMillisecondsSinceEpoch(subEndData);
}


    return Provider(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown',
      type: map['type'] as String? ?? 'Unknown',
      phoneNumber: map['phoneNumber'] as String?,
      isVerified: map['isVerified'] as bool? ?? false,
      documentUrl: map['documentUrl'] as String?,
      location: location,
      servicesOffered: List<String>.from(map['servicesOffered'] ?? []),
      rating: map['rating'] != null ? (map['rating'] as num).toDouble() : null,
      profilePicUrl: map['profilePicUrl'] as String?,
      availability: map['availability'] as bool? ?? true,
      lastActive: lastActive,
      subscriptionEnd: subscriptionEnd,

      address: map['address'] as String?,
      adFree: map['adFree'] as bool? ?? false,
      priorityUntil: priorityUntil,
      description: map['description'] as String?,
      operatingHours: map['operatingHours'] != null
          ? Map<String, String>.from(map['operatingHours'])
          : null,
      website: map['website'] as String?,
      socialMediaLinks: map['socialMediaLinks'] != null
          ? List<String>.from(map['socialMediaLinks'])
          : null,
    );
  }

  /// Creates Provider directly from Firestore document
  factory Provider.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    data['id'] = doc.id; // Ensure ID is included
    return Provider.fromMap(data);
  }
}