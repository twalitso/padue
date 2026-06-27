import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/photo_picker.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/roadside/models/provider.dart';
import 'package:padue/features/roadside/screens/banner_ad_widget.dart';
import 'package:padue/features/roadside/screens/provider_bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/provider_profile_preview_screen.dart';
import 'package:timeago/timeago.dart' as timeago;

class ProviderProfileScreen extends StatefulWidget {
  const ProviderProfileScreen({super.key});

  @override
  _ProviderProfileScreenState createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  File? _profilePicture;
  String? _profilePicUrl;
  File? _document;
  String? _documentUrl;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _descriptionController;
  late TextEditingController _websiteController;
  String _type = 'Sole';
  List<String> _servicesOffered = [];
  Map<String, String> _operatingHours = {};
  List<String> _socialMediaLinks = [];
  bool _availability = true;
  bool _isVerified = false;
  double? _rating;
  GeoPoint? _location;
  List<Provider> _subProviders = [];
  bool _isLoading = false;
  bool _isAdFree = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _descriptionController = TextEditingController();
    _websiteController = TextEditingController();
    _loadProfile();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _isLoading = true);
      try {
        final doc = await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();
        if (doc.exists && mounted) {
          final provider = Provider.fromFirestore(doc);
          _nameController.text = provider.name;
          _phoneController.text = provider.phoneNumber ?? '';
          _addressController.text = provider.address ?? '';
          _descriptionController.text = provider.description ?? '';
          _websiteController.text = provider.website ?? '';
          _profilePicUrl = provider.profilePicUrl;
          _documentUrl = provider.documentUrl;
          _type = provider.type;
          _servicesOffered = provider.servicesOffered;
          _operatingHours = provider.operatingHours ?? {};
          _socialMediaLinks = provider.socialMediaLinks ?? [];
          _availability = provider.availability;
          _isVerified = provider.isVerified;
          _rating = provider.rating;
          _location = provider.location;
          _isAdFree = provider.adFree;
          final subProvidersSnapshot = await FirebaseFirestore.instance
              .collection('providers')
              .doc(user.uid)
              .collection('sub_providers')
              .get();
          _subProviders = subProvidersSnapshot.docs.map((doc) => Provider.fromFirestore(doc)).toList();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
        }
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickProfilePic() async {
    if (!mounted) return;
    final File? file = await PhotoPickerHelper.pickPhoto();
    if (file != null && mounted) {
      setState(() => _profilePicture = file);
    }
  }

  Future<void> _uploadProfilePic() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _profilePicture != null) {
      setState(() => _isLoading = true);
      try {
        _profilePicUrl = await _firestore.uploadProviderProfilePicture(user.uid, _profilePicture!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile Picture Updated')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading picture: $e')));
        }
      }
      if (mounted) {
        setState(() {
          _profilePicture = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickDocument() async {
    if (!mounted) return;
    final File? file = await PhotoPickerHelper.pickDocument();
    if (file != null && mounted) {
      setState(() => _document = file);
    }
  }

  Future<void> _uploadDocument() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _document != null) {
      setState(() => _isLoading = true);
      try {
        _documentUrl = await _firestore.uploadProviderDocument(user.uid, _document!);
        await FirebaseFirestore.instance.collection('providers').doc(user.uid).update({
          'documentUrl': _documentUrl,
          'isVerified': false,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document Uploaded')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading document: $e')));
        }
      }
      if (mounted) {
        setState(() {
          _document = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _isLoading = true);
      if (_location == null) {
        _location = await _getLocation();
        if (_location == null) {
          setState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to get location')));
          }
          return;
        }
      }

      try {
        final provider = Provider(
          id: user.uid,
          name: _nameController.text.trim(),
          type: _type,
          phoneNumber: _phoneController.text.trim(),
          location: _location!,
          servicesOffered: _servicesOffered,
          profilePicUrl: _profilePicUrl,
          availability: _availability,
          documentUrl: _documentUrl,
          isVerified: _isVerified,
          rating: _rating,
          address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
          adFree: _isAdFree,
          description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          operatingHours: _operatingHours.isEmpty ? null : _operatingHours,
          website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
          socialMediaLinks: _socialMediaLinks.isEmpty ? null : _socialMediaLinks,
        );
        await _firestore.updateProviderProfile(user.uid, provider.toMap());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile Updated')));
         // Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
        }
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<GeoPoint?> _getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services disabled')));
        }
        return null;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      return GeoPoint(position.latitude, position.longitude);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
      }
      return null;
    }
  }

  Future<void> _showServicePicker() async {
    var options = await FirebaseFirestore.instance.collection('services').get();
    var availableServices = options.docs.map((doc) => doc['name'] as String).toList();
    List<String> tempServices = List.from(_servicesOffered);
    bool saved = false;
    await showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text('Select Services', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
              Expanded(
                child: ListView(
                  children: availableServices.map((service) => CheckboxListTile(
                        title: Text(service, style: GoogleFonts.poppins()),
                        value: tempServices.contains(service),
                        onChanged: (value) => setModalState(() {
                          if (value!) tempServices.add(service);
                          else tempServices.remove(service);
                        }),
                      )).toList(),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  if (tempServices.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one service')));
                  } else {
                    saved = true;
                    Navigator.pop(context);
                  }
                },
                child: Text('Done', style: GoogleFonts.poppins(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF26A69A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved) setState(() => _servicesOffered = tempServices);
  }

  Future<void> _showOperatingHours() async {
    Map<String, String> tempHours = Map.from(_operatingHours);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set Operating Hours', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            children: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
                .map((day) => ListTile(
                      title: Text(day, style: GoogleFonts.poppins()),
                      subtitle: Text(tempHours[day] ?? 'Not set', style: GoogleFonts.poppins(color: Colors.grey)),
                      onTap: () async {
                        TimeOfDay? start = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(hour: 9, minute: 0),
                        );
                        if (start != null) {
                          TimeOfDay? end = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(hour: 17, minute: 0),
                          );
                          if (end != null) {
                            tempHours[day] = '${start.format(context)} - ${end.format(context)}';
                            Navigator.pop(context);
                            _showOperatingHours();
                          }
                        }
                      },
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _operatingHours = tempHours);
              Navigator.pop(context);
            },
            child: Text('Save', style: GoogleFonts.poppins(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF26A69A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  void _addSocialMediaLink() {
    final _linkController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add Social Media Link', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _linkController,
          decoration: InputDecoration(
            labelText: 'URL (e.g., https://facebook.com/yourpage)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey[100],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (_linkController.text.trim().isNotEmpty) {
                setState(() => _socialMediaLinks.add(_linkController.text.trim()));
                Navigator.pop(context);
              }
            },
            child: Text('Add', style: GoogleFonts.poppins(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF26A69A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  void _addSubProvider() {
    final _subNameController = TextEditingController();
    final _subPhoneController = TextEditingController();
    final _subAddressController = TextEditingController(text: _addressController.text);
    final _subDescriptionController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add Sub-Provider', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _subNameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subPhoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subAddressController,
                decoration: InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subDescriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final location = _location ?? await _getLocation();
              if (location != null) {
                try {
                  final subProvider = Provider(
                    id: '${FirebaseAuth.instance.currentUser!.uid}_${_subProviders.length + 1}',
                    name: _subNameController.text.trim(),
                    type: 'Sub',
                    phoneNumber: _subPhoneController.text.trim(),
                    location: location,
                    servicesOffered: _servicesOffered,
                    availability: true,
                    address: _subAddressController.text.trim().isEmpty ? null : _subAddressController.text.trim(),
                    adFree: _isAdFree,
                    description: _subDescriptionController.text.trim().isEmpty ? null : _subDescriptionController.text.trim(),
                  );
                  _subProviders.add(subProvider);
                  await FirebaseFirestore.instance
                      .collection('providers')
                      .doc(FirebaseAuth.instance.currentUser!.uid)
                      .collection('sub_providers')
                      .doc(subProvider.id)
                      .set(subProvider.toMap());
                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error adding sub-provider: $e')));
                  }
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to get location')));
                }
              }
            },
            child: Text('Add', style: GoogleFonts.poppins(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF26A69A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteSubProvider(String subProviderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not logged in')));
      }
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('providers')
          .doc(user.uid)
          .collection('sub_providers')
          .doc(subProviderId)
          .delete();
      if (mounted) {
        setState(() {
          _subProviders.removeWhere((sub) => sub.id == subProviderId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete sub-provider: $e')));
      }
    }
  }

  void _showProfilePreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProviderProfilePreviewScreen(
          provider: Provider(
            id: FirebaseAuth.instance.currentUser!.uid,
            name: _nameController.text.trim(),
            phoneNumber: _phoneController.text.trim(),
            address: _addressController.text.trim(),
            type: _type,
            servicesOffered: _servicesOffered,
            profilePicUrl: _profilePicUrl,
            documentUrl: _documentUrl,
            availability: _availability,
            isVerified: _isVerified,
            rating: _rating,
            location: _location ?? GeoPoint(0, 0),
            adFree: _isAdFree,
            description: _descriptionController.text.trim(),
            operatingHours: _operatingHours,
            website: _websiteController.text.trim(),
            socialMediaLinks: _socialMediaLinks,
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.star, color: Colors.white),
      label: Text('Go Ad-Free', style: GoogleFonts.poppins(fontSize: 16, color: Colors.white)),
      onPressed: () {
        Navigator.pushNamed(context, '/subscription');
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFFFF5252),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      //  padding: const EdgeInsets.symmetric(vertical: 12),
        shadowColor: Colors.black.withOpacity(0.3),
        elevation: 5,
      ),
    ).animate().fadeIn(duration: Duration(milliseconds: 400)).scale(duration: Duration(milliseconds: 800));
  }

  Widget _buildReviewsSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('provider_reviews')
          .where('providerId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .orderBy('timestamp', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator(color: Color(0xFF26A69A));
        var reviews = snapshot.data!.docs;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color(0xFF26A69A).withOpacity(0.2)),
          ),
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recent Reviews', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
              if (reviews.isEmpty)
                Text('No reviews yet', style: GoogleFonts.poppins(color: Colors.grey)),
              ...reviews.map((doc) {
                var data = doc.data() as Map<String, dynamic>;
                final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                final timeAgo = timestamp != null ? timeago.format(timestamp) : 'Just now';
                return ListTile(
                  leading: Icon(Icons.star, color: Colors.amber),
                  title: Text(data['review'] ?? 'No comment', style: GoogleFonts.poppins()),
                  subtitle: Text('Rating: ${data['rating']} • $timeAgo', style: GoogleFonts.poppins(color: Colors.grey)),
                ).animate().fadeIn(duration: Duration(milliseconds: 400));
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(
        title: 'My Profile',
        profilePicUrl: _profilePicUrl,
        showNotifications: true,
        isProvider: true,
      ),
      drawer: AppBarWidget.buildDrawer(context: context, isProvider: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Profile Picture
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 70,
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                          backgroundImage: _profilePicture != null
                              ? FileImage(_profilePicture!)
                              : _profilePicUrl != null
                                  ? NetworkImage(_profilePicUrl!)
                                  : const AssetImage('assets/default_profile.png') as ImageProvider,
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: InkWell(
                            onTap: _profilePicture != null ? _uploadProfilePic : _pickProfilePic,
                            child: CircleAvatar(
                              radius: 20,
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Icon(
                                _profilePicture != null ? Icons.check : Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Form Fields - fully using ThemeData
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Business Name',
                      prefixIcon: Icon(Icons.business),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Business Description',
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _websiteController,
                    decoration: const InputDecoration(
                      labelText: 'Website URL',
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Services Offered
                  _buildSection(
                    title: 'Services Offered',
                    items: _servicesOffered,
                    emptyText: 'No services selected',
                    onAdd: _showServicePicker,
                  ),

                  const SizedBox(height: 32),

                  // Operating Hours
                  _buildSection(
                    title: 'Operating Hours',
                    items: _operatingHours.isEmpty ? ['Not set'] : null,
                    onAdd: _showOperatingHours,
                    isMap: true,
                    mapData: _operatingHours, emptyText: '',
                  ),

                  const SizedBox(height: 32),

                  // Social Media
                  _buildSection(
                    title: 'Social Media Links',
                    items: _socialMediaLinks,
                    emptyText: 'No links added',
                    onAdd: _addSocialMediaLink,
                  ),

                  const SizedBox(height: 32),

                  // Availability
                  SwitchListTile(
                    title: const Text('Available Now'),
                    value: _availability,
                    onChanged: (v) => setState(() => _availability = v),
                  ),

                  const SizedBox(height: 32),

                  // Document Upload
                  ElevatedButton.icon(
                    icon: const Icon(Icons.cloud_upload),
                    label: Text(_document != null ? 'Upload Document' : 'Upload Verification Document'),
                    onPressed: _document != null ? _uploadDocument : _pickDocument,
                  ),

                  const SizedBox(height: 32),

                  // Go Ad-Free
                  if (!_isAdFree)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.star_border_purple500_sharp),
                      label: const Text('Go Ad-Free Forever'),
                      onPressed: () => Navigator.pushNamed(context, '/subscription'),
                    ),

                  const SizedBox(height: 32),

                  // Recenty Reviews
                  _buildReviewsCard(),

                  const SizedBox(height: 40),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Save Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      onPressed: _saveProfile,
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isAdFree) const BannerAdWidget(),
          const ProviderBottomNavBar(currentIndex: 1),
        ],
      ),
    );
  }



Widget _buildSection({
  required String title,
  List<String>? items,
  required String emptyText,
  required VoidCallback onAdd,
  bool isMap = false,
  Map<String, String>? mapData,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Title — full width
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
        ),
      ),

      // Content Area — ZERO horizontal padding
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: Colors.grey[50],
        child: items != null && items.isNotEmpty
            ? Wrap(
                spacing: 10,
                runSpacing: 10,
                children: items.map((item) => Chip(
                  label: Text(item, style: GoogleFonts.poppins(fontSize: 13.5)),
                  backgroundColor: const Color(0xFFFF6200).withOpacity(0.12),
                  deleteIconColor: Colors.red[700],
                  onDeleted: () => setState(() => items.remove(item)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                    side: BorderSide(color: const Color(0xFFFF6200).withOpacity(0.3)),
                  ),
                )).toList(),
              )
            : isMap && mapData != null && mapData.isNotEmpty
                ? Column(
                    children: mapData.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                          Text(e.value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.black87)),
                        ],
                      ),
                    )).toList(),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      emptyText,
                      style: GoogleFonts.poppins(
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
      ),

      // Edit Button — full width, no side margins
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF6200),
              side: const BorderSide(color: Color(0xFFFF6200), width: 2),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onAdd,
          ),
        ),
      ),

      // Optional subtle divider at bottom
      Divider(height: 1, thickness: 1, color: Colors.grey[300]),
    ],
  );
}

Widget _buildReviewsCard() {
  final providerId = FirebaseAuth.instance.currentUser?.uid;
  if (providerId == null) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text('Please log in to view reviews'),
      ),
    );
  }

  return Card(
    elevation: 6,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.reviews_outlined, color: Color(0xFFFF6200), size: 28),
              const SizedBox(width: 10),
              Text(
                'Customer Reviews',
                style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('provider_reviews')
                .where('providerId', isEqualTo: providerId)
                .orderBy('timestamp', descending: true)
                .limit(10)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: LinearProgressIndicator(color: Color(0xFFFF6200)));
              }

              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red));
              }

              final reviews = snapshot.data?.docs ?? [];

              if (reviews.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Column(
                      children: [
                        Icon(Icons.rate_review_outlined, size: 60, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No reviews yet', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        Text('Your first happy customer is on the way!', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: reviews.length,
                separatorBuilder: (_, __) => const Divider(height: 32),
                itemBuilder: (context, index) {
                  final reviewDoc = reviews[index];
                  final data = reviewDoc.data() as Map<String, dynamic>;

                  final userId = data['userId'] as String;
                  final rating = (data['rating'] as num?)?.toInt() ?? 0;
                  final reviewText = data['review'] as String? ?? 'No comment';
                  final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                  final timeAgo = timestamp != null ? timeago.format(timestamp) : 'Just now';

                  // Fetch user name & photo from 'users' collection
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
                    builder: (context, userSnapshot) {
                      String userName = 'Anonymous';
                      String? photoUrl;

                      if (userSnapshot.hasData && userSnapshot.data!.exists) {
                        final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                        userName = userData?['name'] ?? userData?['displayName'] ?? 'Anonymous';
                        photoUrl = userData?['profilePicUrl'];
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                ? NetworkImage(photoUrl)
                                : const AssetImage('assets/default_profile.png') as ImageProvider,
                            backgroundColor: Colors.grey[200],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      userName,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                    ),
                                    const Spacer(),
                                    Text(
                                      timeAgo,
                                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: List.generate(5, (i) => Icon(
                                    i < rating ? Icons.star : Icons.star_border,
                                    color: Colors.amber,
                                    size: 17,
                                  )),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  reviewText,
                                  style: const TextStyle(height: 1.4, fontSize: 14.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ).animate()
                       .fadeIn(delay: (100 * index).ms)
                       .slideX(begin: 0.2, curve: Curves.easeOutQuad);
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    ),
  );
}

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    _websiteController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}