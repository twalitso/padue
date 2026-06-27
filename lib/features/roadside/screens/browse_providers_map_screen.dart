import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:latlong2/latlong.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/browse_providers_state.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/roadside/models/provider.dart' as provider_model;
import 'package:padue/features/roadside/screens/browse_providers_screen.dart';
import 'package:padue/features/roadside/screens/view_provider_profile_screen.dart';
import 'package:provider/provider.dart';

class BrowseProvidersMapScreen extends StatefulWidget {
  final String? selectedCategory;
  const BrowseProvidersMapScreen({super.key, this.selectedCategory});

  @override
  State<BrowseProvidersMapScreen> createState() => _BrowseProvidersMapScreenState();
}

class _BrowseProvidersMapScreenState extends State<BrowseProvidersMapScreen> {
  final MapController _mapController = MapController();
  final FirestoreService _firestore = FirestoreService();
  Position? _userLocation;
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  bool _isLoading = true;
  String? _profilePicUrl;
  bool _isAdfree = false;

  @override
  void initState() {
    super.initState();
    _loadUserLocationAndData();
    _loadBannerAd();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadUserLocationAndData() async {
    try {
      // Get location
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }

      _userLocation = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // Load profile pic
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final profile = await _firestore.getUserProfile(user.uid);
        _profilePicUrl = profile?.profilePicUrl;
        _isAdfree = profile?.adFree ?? false;
      }

      if (mounted) {
        setState(() => _isLoading = false);
        _mapController.move(LatLng(_userLocation!.latitude, _userLocation!.longitude), 13.5);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadBannerAd() async {
    final state = context.read<BrowseProvidersState>();
    if (state.isAdFree) return;

    _bannerAd = BannerAd(
      adUnitId: AdmobConfig().banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdLoaded = true),
        onAdFailedToLoad: (ad, err) => ad.dispose(),
      ),
    );
    await _bannerAd!.load();
  }

  @override
  Widget build(BuildContext context) {
    // THIS IS THE KEY: We now safely access the provider using context.read()
    final filterState = context.watch<BrowseProvidersState>();

    return Scaffold(
      appBar: AppBarWidget(
        title: 'Providers Nearby',
        profilePicUrl: _profilePicUrl,
        showNotifications: true,
        isProvider: false,
      ),
      drawer: AppBarWidget.buildDrawer(context: context, isProvider: false),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))
          : Stack(
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: widget.selectedCategory == null || widget.selectedCategory == 'All'
                      ? _firestore.getAllProvidersold()
                      : _firestore.getProvidersByServiceold(widget.selectedCategory!),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)));
                    }

                    var providers = snapshot.data!.docs
                        .map((doc) => provider_model.Provider.fromFirestore(doc))
                        .where((p) => p.location != null)
                        .toList();

                    // Apply same filters as list screen
                    if (filterState.selectedCategory != null) {
                      providers = providers.where((p) => p.type == filterState.selectedCategory).toList();
                    }
                    if (filterState.userLocation != null && filterState.maxDistance < 100) {
                      providers = providers.where((p) {
                        final dist = Geolocator.distanceBetween(
                              filterState.userLocation!.latitude,
                              filterState.userLocation!.longitude,
                              p.location!.latitude,
                              p.location!.longitude,
                            ) / 1000;
                        return dist <= filterState.maxDistance;
                      }).toList();
                    }
                    if (filterState.showVerifiedOnly) {
                      providers = providers.where((p) => p.isVerified).toList();
                    }

                    final markers = <Marker>[];

                    // Your Location
                    if (_userLocation != null) {
                      markers.add(
                        Marker(
                          point: LatLng(_userLocation!.latitude, _userLocation!.longitude),
                          width: 100,
                          height: 100,
                          child: Column(
                            children: [
                              Text('You', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
                              const SizedBox(height: 4),
                              CircleAvatar(
                                radius: 26,
                                backgroundImage: _profilePicUrl?.isNotEmpty == true
                                    ? NetworkImage(_profilePicUrl!)
                                    : const AssetImage('assets/default_profile.png') as ImageProvider,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFFFF6200), width: 4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // Provider Markers
                    for (var provider in providers) {
                      markers.add(
                        Marker(
                          point: LatLng(provider.location!.latitude, provider.location!.longitude),
                          width: 110,
                          height: 110,
                          child: GestureDetector(
                            onTap: () => _showProviderBottomSheet(provider),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6200),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    provider.name ?? 'Provider',
                                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                CircleAvatar(
                                  radius: 24,
                                  backgroundImage: provider.profilePicUrl?.isNotEmpty == true
                                      ? NetworkImage(provider.profilePicUrl!)
                                      : const AssetImage('assets/default_profile.png') as ImageProvider,
                                ),
                                if (provider.isVerified)
                                  const Icon(Icons.verified, color: Color(0xFFFF6200), size: 18)
                                      .animate()
                                      .scale(duration: 600.ms, curve: Curves.elasticOut),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    return FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _userLocation != null
                            ? LatLng(_userLocation!.latitude, _userLocation!.longitude)
                            : const LatLng(-1.2921, 36.8219), // Nairobi fallback
                        initialZoom: 13.0,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                      ),
                      children: [
                        TileLayer(urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', subdomains: const ['a', 'b', 'c']),
                        MarkerLayer(markers: markers),
                      ],
                    );
                  },
                ),

                // Banner Ad
                if (!_isAdfree && _isBannerAdLoaded && _bannerAd != null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: AdWidget(ad: _bannerAd!),
                    ),
                  ),
              ],
            ),
    );
  }

  void _showProviderBottomSheet(provider_model.Provider provider) {
    final distance = _userLocation != null && provider.location != null
        ? (Geolocator.distanceBetween(
                _userLocation!.latitude,
                _userLocation!.longitude,
                provider.location!.latitude,
                provider.location!.longitude,
              ) / 1000)
            .toStringAsFixed(1)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Hero(
                          tag: 'provider-${provider.id}',
                          child: CircleAvatar(
                            radius: 42,
                            backgroundImage: provider.profilePicUrl?.isNotEmpty == true
                                ? NetworkImage(provider.profilePicUrl!)
                                : const AssetImage('assets/default_profile.png') as ImageProvider,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      provider.name ?? 'Provider',
                                      style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (provider.isVerified) const Icon(Icons.verified, color: Color(0xFFFF6200), size: 28),
                                ],
                              ),
                              Text(provider.type ?? '', style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600])),
                              if (distance != null)
                                Text('$distance km away', style: GoogleFonts.poppins(fontSize: 15, color: const Color(0xFFFF6200), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            context.read<BrowseProvidersState>().updateCategory(provider.type);
                            Navigator.pop(context);
                            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const BrowseProvidersScreen()));
                          },
                          icon: const Icon(Icons.list_alt),
                          label: const Text('List View'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => ViewProviderProfileScreen(providerId: provider.id!)));
                          },
                          icon: const Icon(Icons.person_outline),
                          label: const Text('View Profile'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6200), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ).animate().slideY(begin: 1.0, end: 0, duration: 400.ms, curve: Curves.easeOutBack),
    );
  }
}