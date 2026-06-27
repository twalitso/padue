import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/photo_picker.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/roadside/models/provider.dart';
import 'dart:ui' as ui;

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  _CreatePostScreenState createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final FirestoreService _firestore = FirestoreService();
  final TextEditingController _contentController = TextEditingController();
  List<File> _mediaFiles = [];
  bool _includeLocation = false;
  Position? _userLocation;
  bool _isSubmitting = false;
  UserProfile? _userProfile;
  Provider? _providerProfile;
  bool _isAdFree = false;
  bool _isLoading = true;
  bool _isProviderUser = false;
   dynamic profile;
  String? profilePicUrl;

  @override
  void initState() {
    super.initState();
   // _loadUserData();
    _loadProfile();
  }




 Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isLoading = true);
    final providerDoc =
        await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();
    if (providerDoc.exists && mounted) {
      final provider = Provider.fromFirestore(providerDoc);
      final providerProfile = await _firestore.getProviderProfile(user.uid);
      setState(() {
        _isProviderUser = true;
        _isAdFree = provider.adFree;
        _isLoading = false;
        profile = providerProfile;
        profilePicUrl = providerProfile?.profilePicUrl ?? provider.profilePicUrl;
      });
    } else {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userProfile = await _firestore.getUserProfile(user.uid);
      setState(() {
        _isProviderUser = false;
        _isAdFree = userDoc.exists ? (userDoc.data()?['adFree'] ?? false) : false;
        _isLoading = false;
        profile = userProfile;
        profilePicUrl = profile?.profilePicUrl;
      });
    }
  }

  Future<void> _loadUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userProfile = await _firestore.getUserProfile(user.uid);
      _providerProfile = await _firestore.getProviderProfile(user.uid);
      setState(() {});
    }
  }

  Future<void> _pickMedia() async {
    try {
      final pickedFiles = await PhotoPickerHelper.pickPhotos(allowMultiple: true);
      if (pickedFiles != null && pickedFiles.isNotEmpty) {
        setState(() => _mediaFiles.addAll(pickedFiles));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No media selected')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking media: $e')));
    }
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services disabled')));
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return;
      }
      _userLocation = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
    }
  }

  Future<void> _submitPost() async {
    if (_isSubmitting || _contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter post content')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      String posterType = _providerProfile != null ? 'provider' : 'user';
      String posterName = profile?.name ?? 'Anonymous';
      String? posterProfilePicUrl = _providerProfile?.profilePicUrl ?? _userProfile?.profilePicUrl;

      await _firestore.createPost(
        content: _contentController.text.trim(),
        mediaFiles: _mediaFiles,
        location: _includeLocation && _userLocation != null ? GeoPoint(_userLocation!.latitude, _userLocation!.longitude) : null,
        posterId: user.uid,
        posterType: posterType,
        posterName: posterName,
        posterProfilePicUrl: profilePicUrl,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post created successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creating post: $e')));
      }
    }
    setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Post', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF26A69A).withOpacity(0.2)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _contentController,
                      decoration: InputDecoration(
                        labelText: 'What’s on your mind? *',
                        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.8),
                      ),
                      maxLines: 5,
                      style: GoogleFonts.poppins(color: const Color(0xFF1F2A44)),
                    ).animate().fadeIn(delay: 100.ms),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: Text('Include Location', style: GoogleFonts.poppins(color: const Color(0xFF1F2A44))),
                      value: _includeLocation,
                      onChanged: (value) {
                        setState(() => _includeLocation = value);
                        if (_includeLocation) _getUserLocation();
                      },
                      activeColor: const Color(0xFF26A69A),
                    ).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _pickMedia,
                      icon: const Icon(Icons.image, color: Color(0xFF26A69A)),
                      label: Text('Add Media', style: GoogleFonts.poppins(color: const Color(0xFF1F2A44))),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: Color(0xFF26A69A)),
                      ),
                    ).animate().fadeIn(delay: 300.ms),
                    if (_mediaFiles.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _mediaFiles.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(_mediaFiles[index], width: 100, height: 100, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: IconButton(
                                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                                      onPressed: () => setState(() => _mediaFiles.removeAt(index)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitPost,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: const Color(0xFF26A69A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text('Submit Post', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16)),
                    ).animate().fadeIn(delay: 400.ms),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }
}