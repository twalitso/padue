import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/utils.dart';
import 'dart:io';
import '../../../core/firestore_service.dart';
import '../models/user_profile.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>  with WidgetsBindingObserver {
  final _nameController = TextEditingController();
  final _emergencyController = TextEditingController();
  final _firestore = FirestoreService();
  UserProfile? _profile;
  File? _image;
  bool _isLoading = true;
  double? _averageRating;
  BannerAd? _bannerAd;
   bool _isBannerAdLoaded = false;

  @override
  void initState() {

    super.initState();
 WidgetsBinding.instance.addObserver(this);
     _loadBannerAd();
    _loadProfile();
    _loadAverageRating();
    updateLastActive();
   
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data or resources
_loadBannerAd();
    _loadProfile();
    _loadAverageRating();
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdmobConfig().getAdUnitId('banner') ?? 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdLoaded = true),
        onAdFailedToLoad: (ad, error) {
          print('Banner ad failed to load: $error');
          ad.dispose();
        },
      ),
    );
    _bannerAd!.load();
  }


  Future<void> _loadProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _profile = await _firestore.getUserProfile(user.uid);
      if (_profile != null) {
        _nameController.text = _profile!.name ?? '';
        _emergencyController.text = _profile!.emergencyContact ?? '';
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAverageRating() async {
    var reviews = await FirebaseFirestore.instance
        .collection('user_reviews')
        .where('userId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .get();
    if (reviews.docs.isNotEmpty) {
      double total = reviews.docs.fold(0, (sum, doc) => sum + (doc['rating'] as int));
      setState(() {
        _averageRating = total / reviews.docs.length;
      });
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _image = File(pickedFile.path));
    }
  }

  Future<void> _saveProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && _profile != null) {
      setState(() => _isLoading = true);
      String? profilePicUrl = _profile!.profilePicUrl;
       if (_image == null || !_image!.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No valid image selected')));
        }
        return;
      }
      if (_image != null) {
        profilePicUrl = await _firestore.uploadMedia(
          _image!,
          'profiles/${user.uid}',
        );
      }

      final updatedProfile = UserProfile(
        uid: user.uid,
        phoneNumber: user.phoneNumber!,
        name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
        emergencyContact: _emergencyController.text.trim().isEmpty ? null : _emergencyController.text.trim(),
        profilePicUrl: profilePicUrl,
        deviceToken: _profile!.deviceToken,
        adFree: _profile!.adFree,
        priorityUntil: _profile!.priorityUntil,
      );

      await _firestore.updateUserProfile(user.uid, updatedProfile);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile updated')),
      );
      Navigator.pushReplacementNamed(context, '/request');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _profile == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Update Profile')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('My Profile'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.purple[50]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(10),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _pickImage,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundImage: _image != null
                                    ? FileImage(_image!)
                                    : _profile!.profilePicUrl != null
                                        ? NetworkImage(_profile!.profilePicUrl!)
                                        : AssetImage('assets/default_profile.png') as ImageProvider,
                                backgroundColor: Colors.grey[200],
                              ),
                              Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                        if (_averageRating != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 20),
                              SizedBox(width: 4),
                              Text(
                                _averageRating!.toStringAsFixed(1),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        SizedBox(height: 16),
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Name',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                        ),
                        SizedBox(height: 16),
                        TextField(
                          controller: _emergencyController,
                          decoration: InputDecoration(
                            labelText: 'Emergency Contact (Phone)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey[100],
                            errorText: _emergencyController.text.isNotEmpty &&
                                    !RegExp(r'^\+?[1-9]\d{1,14}$')
                                        .hasMatch(_emergencyController.text)
                                ? 'Enter a valid phone number'
                                : null,
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading
                              ? CircularProgressIndicator(color: Colors.white)
                              : Text('Save Profile', style: TextStyle(fontSize: 16)),
                        ),
                        SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _logout,
                          icon: Icon(Icons.logout),
                          label: Text('Logout'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_bannerAd != null)
              Container(
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emergencyController.dispose();
    _bannerAd?.dispose();
     WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}