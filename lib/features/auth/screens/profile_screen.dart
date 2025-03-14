import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/firestore_service.dart';
import '../models/user_profile.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _emergencyController = TextEditingController();
  final _firestore = FirestoreService();
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _profile = await _firestore.getUserProfile(user.uid);
      if (_profile != null) {
        _nameController.text = _profile!.name ?? '';
        _emergencyController.text = _profile!.emergencyContact ?? '';
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Update Profile')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _emergencyController,
              decoration: InputDecoration(labelText: 'Emergency Contact (Phone)'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                User? user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  final profile = UserProfile(
                    uid: user.uid,
                    phoneNumber: user.phoneNumber!,
                    name: _nameController.text,
                    emergencyContact: _emergencyController.text,
                  );
                  await _firestore.updateUserProfile(user.uid, profile);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Profile updated')),
                  );
                  Navigator.pushReplacementNamed(context, '/request');
                }
              },
              child: Text('Save Profile'),
            ),
          ],
        ),
      ),
    );
  }
}