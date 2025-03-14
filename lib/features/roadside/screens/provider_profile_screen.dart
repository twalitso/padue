import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import '../../../core/firestore_service.dart';

class ProviderProfileScreen extends StatefulWidget {
  @override
  _ProviderProfileScreenState createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  final _firestore = FirestoreService();
  File? _profilePicture;
  String? _profilePicUrl;

  @override
  void initState() {
    super.initState();
    _loadProfilePic();
  }

  // Load current profile picture from Firestore
  Future<void> _loadProfilePic() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _profilePicUrl = await _firestore.getProfilePicUrl(user.uid);
      setState(() {});
    }
  }

  // Pick a new profile picture from the gallery
  Future<void> _pickProfilePic() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _profilePicture = File(pickedFile.path);
      });
      await _uploadProfilePic();
    }
  }

  // Upload the selected profile picture to Firestore and Firebase Storage
  Future<void> _uploadProfilePic() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && _profilePicture != null) {
      await _firestore. uploadProviderProfilePicture(user.uid, _profilePicture!);
      _loadProfilePic();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile Picture Updated')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Profile Picture Section
            CircleAvatar(
              radius: 50,
              backgroundImage: _profilePicUrl != null
                  ? NetworkImage(_profilePicUrl!)
                  : AssetImage('assets/default_profile.png') as ImageProvider,
              child: _profilePicUrl == null ? Icon(Icons.person, size: 50) : null,
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(Icons.edit),
              label: Text('Change Profile Picture'),
              onPressed: _pickProfilePic,
            ),

            // Other editable fields (name, contact, etc.)
            SizedBox(height: 20),
            TextField(
              decoration: InputDecoration(labelText: 'Name'),
              controller: TextEditingController(text: FirebaseAuth.instance.currentUser?.displayName),
            ),
            SizedBox(height: 20),
            TextField(
              decoration: InputDecoration(labelText: 'Contact Information'),
              controller: TextEditingController(),
            ),
            SizedBox(height: 20),

            // Save Changes Button
            ElevatedButton(
              onPressed: () {
                // Save profile changes here
              },
              child: Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
