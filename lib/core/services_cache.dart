import 'package:cloud_firestore/cloud_firestore.dart';

class ServicesCache {
  static List<String> services = [];
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded && services.isNotEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance.collection('services').get();
      services = snapshot.docs
          .map((d) => d['name'] as String)
          .where((name) => name.isNotEmpty)
          .toList();
      _loaded = true;
    } catch (_) {}
  }
}