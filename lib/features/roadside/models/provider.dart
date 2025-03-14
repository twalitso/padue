// lib/features/roadside/models/provider.dart
class Provider {
  final String id;
  final String name;
  final String type;
  final bool isVerified;
  final String? documentUrl;
  final String? phoneNumber; // Add this

  Provider({
    required this.id,
    required this.name,
    required this.type,
    this.isVerified = false,
    this.documentUrl,
    this.phoneNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'isVerified': isVerified,
      'documentUrl': documentUrl,
      'phoneNumber': phoneNumber, // Add this
    };
  }

  factory Provider.fromMap(Map<String, dynamic> map) {
    return Provider(
      id: map['id'],
      name: map['name'],
      type: map['type'],
      isVerified: map['isVerified'] ?? false,
      documentUrl: map['documentUrl'],
      phoneNumber: map['phoneNumber'], // Add this
    );
  }
}