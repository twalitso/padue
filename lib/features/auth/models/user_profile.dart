import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String phoneNumber;
  String? name;
  String? emergencyContact;
  String? profilePicUrl;
  String? deviceToken;
  bool adFree;
  DateTime? priorityUntil;
  DateTime? lastActive;
  DateTime? subscriptionEnd;
    final Map<String, dynamic>? consents;
  final DateTime? createdAt;


  UserProfile({
    required this.uid,
    required this.phoneNumber,
    this.name,
    this.emergencyContact,
    this.profilePicUrl,
    this.deviceToken,
    this.adFree = false,
    this.priorityUntil,
    this.lastActive,
    this.subscriptionEnd,
    this.consents,
    this.createdAt,

  });

  /// Converts to Firestore-compatible map (Timestamp for date fields)
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'phoneNumber': phoneNumber,
      'name': name,
      'emergencyContact': emergencyContact,
      'profilePicUrl': profilePicUrl,
      'deviceToken': deviceToken,
      'adFree': adFree,
      'priorityUntil': priorityUntil != null ? Timestamp.fromDate(priorityUntil!) : null,
      'lastActive': lastActive != null ? Timestamp.fromDate(lastActive!) : null,
      'subscriptionEnd':
    subscriptionEnd != null ? Timestamp.fromDate(subscriptionEnd!) : null,
     'consents': consents,
      'createdAt': createdAt,

    };
  }

  /// Safe factory: Handles both Timestamp (from Firestore) and int (from cache)
  factory UserProfile.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return null;
    }

    return UserProfile(
      uid: map['uid'] as String? ?? '',
      phoneNumber: map['phoneNumber'] as String? ?? '',
      name: map['name'] as String?,
      emergencyContact: map['emergencyContact'] as String?,
      profilePicUrl: map['profilePicUrl'] as String?,
      deviceToken: map['deviceToken'] as String?,
      adFree: map['adFree'] as bool? ?? false,
      priorityUntil: parseDate(map['priorityUntil']),
      lastActive: parseDate(map['lastActive']),
      subscriptionEnd: parseDate(map['subscriptionEnd']),

    );
  }

  /// From Firestore document
  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    data['uid'] = doc.id; // Ensure uid is set
    return UserProfile.fromMap(data);
  }

  /// Safe copyWith
  UserProfile copyWith({
    String? name,
    String? emergencyContact,
    String? profilePicUrl,
    String? deviceToken,
    bool? adFree,
    DateTime? priorityUntil,
    DateTime? lastActive,
  }) {
    return UserProfile(
      uid: uid,
      phoneNumber: phoneNumber,
      name: name ?? this.name,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      profilePicUrl: profilePicUrl ?? this.profilePicUrl,
      deviceToken: deviceToken ?? this.deviceToken,
      adFree: adFree ?? this.adFree,
      priorityUntil: priorityUntil ?? this.priorityUntil,
      lastActive: lastActive ?? this.lastActive,
    );
  }
}

/** 
 * class UserProfile {
  final String uid;
  final String phoneNumber;
  String? name;
  String? emergencyContact;
  String? profilePicUrl;
  String? deviceToken;
  bool adFree;
  DateTime? priorityUntil;
  DateTime? lastActive; // New field for last active timestamp

  UserProfile({
    required this.uid,
    required this.phoneNumber,
    this.name,
    this.emergencyContact,
    this.profilePicUrl,
    this.deviceToken,
    this.adFree = false,
    this.priorityUntil,
    this.lastActive, // Initialize as nullable
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'phoneNumber': phoneNumber,
        'name': name,
        'emergencyContact': emergencyContact,
        'profilePicUrl': profilePicUrl,
        'deviceToken': deviceToken,
        'adFree': adFree,
        'priorityUntil': priorityUntil != null ? Timestamp.fromDate(priorityUntil!) : null,
        'lastActive': lastActive != null ? Timestamp.fromDate(lastActive!) : null, // Convert to Timestamp
      };

  factory UserProfile.fromMap(Map<String, dynamic> data) => UserProfile(
        uid: data['uid'] as String,
        phoneNumber: data['phoneNumber'] as String,
        name: data['name'] as String?,
        emergencyContact: data['emergencyContact'] as String?,
        profilePicUrl: data['profilePicUrl'] as String?,
        deviceToken: data['deviceToken'] as String?,
        adFree: data['adFree'] as bool? ?? false,
        priorityUntil: data['priorityUntil'] != null
            ? (data['priorityUntil'] as Timestamp).toDate()
            : null,
        lastActive: data['lastActive'] != null
            ? (data['lastActive'] as Timestamp).toDate()
            : null, // Parse from Timestamp
      );

        factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    return UserProfile.fromMap(doc.data() as Map<String, dynamic>);
  }

// In user_profile.dart
UserProfile copyWith({
  String? name,
  String? emergencyContact,
  String? profilePicUrl,
  // add others if needed
}) {
  return UserProfile(
    uid: uid,
    phoneNumber: phoneNumber,
    name: name ?? this.name,
    emergencyContact: emergencyContact ?? this.emergencyContact,
    profilePicUrl: profilePicUrl ?? this.profilePicUrl,
    deviceToken: deviceToken,
    adFree: adFree,
    priorityUntil: priorityUntil,
  );
}

}*/