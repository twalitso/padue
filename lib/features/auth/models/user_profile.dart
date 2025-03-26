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
}