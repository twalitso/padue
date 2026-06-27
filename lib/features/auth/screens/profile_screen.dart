import 'dart:io';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/photo_picker.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/roadside/screens/bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/subscription_screen.dart';
import '../models/user_profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _emergencyController = TextEditingController();
  final _firestore = FirestoreService();

  UserProfile? _profile;
  File? _pickedImage;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAdFree = false;
  double? _averageRating;
  BannerAd? _bannerAd;

  StreamSubscription<DocumentSnapshot>? _userDocSubscription;

  @override
  void initState() {
    super.initState();
    _loadEverything();
    _listenToUserChanges();
  }

  // Real-time listener for ad-free status & profile changes
  void _listenToUserChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;

      final bool nowAdFree = await _firestore.isAdFree(user.uid);

      if (mounted && _isAdFree != nowAdFree) {
        setState(() => _isAdFree = nowAdFree);
        _loadBannerAdIfNeeded();
      }
    });
  }

  Future<void> _loadEverything() async {
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    await Future.wait([
      _loadProfile(),
      _loadAverageRating(),
      _loadBannerAdIfNeeded(),
    ]);

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final profile = await _firestore.getUserProfile(user.uid);
    final adFree = await _firestore.isAdFree(user.uid);

    if (mounted) {
      setState(() {
        _profile = profile;
        _isAdFree = adFree;
        _nameController.text = profile?.name ?? '';
        _emergencyController.text = profile?.emergencyContact ?? '';
      });
    }
  }

  Future<void> _loadAverageRating() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final reviews = await FirebaseFirestore.instance
        .collection('user_reviews')
        .where('userId', isEqualTo: user.uid)
        .get();

    if (reviews.docs.isNotEmpty && mounted) {
      final total = reviews.docs.fold(0, (sum, doc) => sum + (doc['rating'] as int));
      setState(() => _averageRating = total / reviews.docs.length);
    }
  }

  Future<void> _loadBannerAdIfNeeded() async {
    if (_isAdFree) {
      _bannerAd?.dispose();
      _bannerAd = null;
      return;
    }

    _bannerAd = BannerAd(
      adUnitId: AdmobConfig().banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() {}),
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
    );
    await _bannerAd!.load();
  }

  Future<void> _pickImage() async {
    final file = await PhotoPickerHelper.pickPhoto();
    if (file != null && mounted) {
      setState(() => _pickedImage = file);
    }
  }

  // SMART SAVE: Only update fields that actually changed
  Future<void> _saveProfile() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _profile == null) return;

      final Map<String, dynamic> updates = {};

      // Name
      final String trimmedName = _nameController.text.trim();
      if (trimmedName.isNotEmpty && trimmedName != (_profile!.name ?? '')) {
        updates['name'] = trimmedName;
      } else if (trimmedName.isEmpty && _profile!.name != null) {
        updates['name'] = FieldValue.delete(); // Clear if user deleted it
      }

      // Emergency Contact
      final String trimmedEmergency = _emergencyController.text.trim();
      if (trimmedEmergency.isNotEmpty && trimmedEmergency != (_profile!.emergencyContact ?? '')) {
        updates['emergencyContact'] = trimmedEmergency;
      } else if (trimmedEmergency.isEmpty && _profile!.emergencyContact != null) {
        updates['emergencyContact'] = FieldValue.delete();
      }

      // Profile Picture
      if (_pickedImage != null) {
        final String newUrl = await _firestore.uploadMedia(
          _pickedImage!,
          'profiles/${user.uid}',
        );
        updates['profilePicUrl'] = newUrl;
      }

      // Nothing changed?
      if (updates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No changes to save')),
        );
        setState(() => _pickedImage = null);
        return;
      }

      // Apply only changed fields
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(updates);

      // Update local model
      setState(() {
        _profile = _profile!.copyWith(
          name: updates.containsKey('name')
              ? (updates['name'] == FieldValue.delete() ? null : updates['name'] as String)
              : _profile!.name,
          emergencyContact: updates.containsKey('emergencyContact')
              ? (updates['emergencyContact'] == FieldValue.delete() ? null : updates['emergencyContact'] as String)
              : _profile!.emergencyContact,
          profilePicUrl: updates['profilePicUrl'] as String? ?? _profile!.profilePicUrl,
        );
        _pickedImage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text('Profile updated!', style: GoogleFonts.poppins()),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _profile == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFFF6200),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBarWidget(
        title: 'My Profile',
        profilePicUrl: _profile!.profilePicUrl,
        showNotifications: true,
        isProvider: false,
      ),
      drawer: AppBarWidget.buildDrawer(context: context, isProvider: false),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF6200), Color(0xFFFF8A50)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Profile Avatar
                      GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [Colors.white, Colors.white24]),
                              ),
                              child: CircleAvatar(
                                radius: 70,
                                backgroundImage: _pickedImage != null
                                    ? FileImage(_pickedImage!)
                                    : _profile!.profilePicUrl != null
                                        ? CachedNetworkImageProvider(_profile!.profilePicUrl!)
                                        : const AssetImage('assets/default_profile.png') as ImageProvider,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                                ),
                                child: const Icon(Icons.camera_alt, color: Color(0xFFFF6200), size: 24),
                              ),
                            ),
                          ],
                        ).animate().scale(duration: 800.ms, curve: Curves.elasticOut),
                      ),

                      const SizedBox(height: 24),
                      Text(
                        _profile!.name ?? 'Your Name',
                        style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                      ),

                      if (_averageRating != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                            const SizedBox(width: 8),
                            Text(
                              _averageRating!.toStringAsFixed(1),
                              style: GoogleFonts.poppins(fontSize: 20, color: Colors.white),
                            ),
                            Text(' Rating', style: GoogleFonts.poppins(color: Colors.white70)),
                          ],
                        ),
                      ],

                      const SizedBox(height: 32),

                      // Form Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Full Name',
                                prefixIcon: const Icon(Icons.person),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _emergencyController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Emergency Contact',
                                prefixIcon: const Icon(Icons.phone),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                filled: true,
                                fillColor: Colors.grey[50],
                                helperText: 'e.g. +254712345678',
                              ),
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveProfile,
                              icon: _isSaving
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save),
                              label: Text(
                                _isSaving ? 'Saving...' : 'Save Changes',
                                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6200),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 40),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 10,
                              ),
                            ),
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                              ),
                              icon: const Icon(Icons.diamond, color: Color(0xFFFF6200)),
                              label: Text(
                                _isAdFree ? 'Premium Active' : 'Go Premium – Remove Ads',
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFFF6200), width: 2),
                                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // Banner Ad
              if (!_isAdFree && _bannerAd != null)
                Container(
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 0, isProvider: false),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emergencyController.dispose();
    _bannerAd?.dispose();
    _userDocSubscription?.cancel();
    super.dispose();
  }
}