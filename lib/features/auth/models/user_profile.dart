class UserProfile {
  final String uid;
  final String phoneNumber; // Already here from OTP login
  String? name;
  String? emergencyContact;

  UserProfile({
    required this.uid,
    required this.phoneNumber,
    this.name,
    this.emergencyContact,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'phoneNumber': phoneNumber,
        'name': name,
        'emergencyContact': emergencyContact,
      };

  factory UserProfile.fromMap(Map<String, dynamic> data) => UserProfile(
        uid: data['uid'],
        phoneNumber: data['phoneNumber'],
        name: data['name'],
        emergencyContact: data['emergencyContact'],
      );
}