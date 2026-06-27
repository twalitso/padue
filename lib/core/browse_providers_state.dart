import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/roadside/models/provider.dart' as provider_model;
import 'package:geolocator/geolocator.dart';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/roadside/models/provider.dart' as provider_model;
import 'package:padue/features/roadside/screens/browse_providers_screen.dart';

class BrowseProvidersState extends ChangeNotifier {
  // ── Raw Data ─────────────────────────────────────
  List<provider_model.Provider> _cachedProviders = [];
  List<provider_model.Provider> get cachedProviders => _cachedProviders;

  // ── Filters ──────────────────────────────────────
  String? _selectedCategory;
  String? get selectedCategory => _selectedCategory;

  double _maxDistance = 100.0;
  double get maxDistance => _maxDistance;

  bool _showVerifiedOnly = false;
  bool get showVerifiedOnly => _showVerifiedOnly;

  // ── User Context ─────────────────────────────────
  Position? _userLocation;
  Position? get userLocation => _userLocation;

  String _locationName = 'Loading...';
  String get locationName => _locationName;

  UserProfile? _profile;
  UserProfile? get profile => _profile;

  bool _isAdFree = false;
  bool get isAdFree => _isAdFree;

  // ── Services & Ads ───────────────────────────────
  List<String> _availableServices = ['All'];
  List<String> get availableServices => _availableServices;

  List<NativeAd?> _nativeAds = [];
  List<NativeAd?> get nativeAds => _nativeAds;

  bool _isNativeAdsLoading = true;
  bool get isNativeAdsLoading => _isNativeAdsLoading;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // ── Computed: Always up-to-date filtered list ─────
  List<provider_model.Provider> get filteredProviders {
    if (_cachedProviders.isEmpty) return [];

    var filtered = List<provider_model.Provider>.from(_cachedProviders);

    // Category filter
    if (_selectedCategory != null && _selectedCategory != 'All') {
      filtered = filtered.where((p) => p.type == _selectedCategory).toList();
    }

    // Distance + Verified filter
    if (_userLocation != null) {
      // Sort by distance
      filtered.sort((a, b) {
        final distA = a.location != null
            ? Geolocator.distanceBetween(
                _userLocation!.latitude,
                _userLocation!.longitude,
                a.location!.latitude,
                a.location!.longitude,
              )
            : double.infinity;
        final distB = b.location != null
            ? Geolocator.distanceBetween(
                _userLocation!.latitude,
                _userLocation!.longitude,
                b.location!.latitude,
                b.location!.longitude,
              )
            : double.infinity;
        return distA.compareTo(distB);
      });

      // Max distance
      if (_maxDistance < 100.0) {
        filtered = filtered.where((p) {
          if (p.location == null) return false;
          final distanceInKm = Geolocator.distanceBetween(
                _userLocation!.latitude,
                _userLocation!.longitude,
                p.location!.latitude,
                p.location!.longitude,
              ) /
              1000;
          return distanceInKm <= _maxDistance;
        }).toList();
      }

      // Verified only
      if (_showVerifiedOnly) {
        filtered = filtered.where((p) => p.isVerified == true).toList();
      }
    }

    return filtered;
  }

  // ── Update Methods ─────────────────────────────────
 

  void updateFilters({double? maxDistance, bool? showVerifiedOnly}) {
    bool changed = false;
    if (maxDistance != null && maxDistance != _maxDistance) {
      _maxDistance = maxDistance;
      changed = true;
    }
    if (showVerifiedOnly != null && showVerifiedOnly != _showVerifiedOnly) {
      _showVerifiedOnly = showVerifiedOnly;
      changed = true;
    }
    if (changed) _triggerRebuild();
  }

  void updateUserLocation(Position? location, {String? locationName}) {
    _userLocation = location;
    if (locationName != null) _locationName = locationName;
    _triggerRebuild();
  }

  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void updateCoreData({
    List<provider_model.Provider>? providers,
    List<String>? services,
    UserProfile? profile,
    bool? isAdFree,
  }) {
    bool changed = false;

    if (providers != null && !listEquals(providers, _cachedProviders)) {
      _cachedProviders = providers;
      changed = true;
    }
    if (services != null && !listEquals(services, _availableServices)) {
      _availableServices = ['All', ...services];
      changed = true;
    }
    if (profile != null && profile != _profile) {
      _profile = profile;
      changed = true;
    }
    if (isAdFree != null && isAdFree != _isAdFree) {
      _isAdFree = isAdFree;
      changed = true;
    }

    if (changed) _triggerRebuild();
  }

  void updateAds({
    List<NativeAd?>? nativeAds,
    bool? isNativeAdsLoading,
  }) {
    if (nativeAds != null) _nativeAds = nativeAds;
    if (isNativeAdsLoading != null) _isNativeAdsLoading = isNativeAdsLoading;
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────
  void _triggerRebuild() {
    // This ensures filteredProviders recomputes instantly
    notifyListeners();
  }

  void resetFilters() {
    _selectedCategory = null;
    _maxDistance = 100.0;
    _showVerifiedOnly = false;
    _triggerRebuild();
  }

 

 

 

 void updateState({
    String? selectedCategory,
    Position? userLocation,
    String? locationName,
    double? maxDistance,
    bool? showVerifiedOnly,
    bool? isLoading,
    bool? isAdFree,
    bool? isNativeAdsLoading,
    List<String>? availableServices,
    List<NativeAd?>? nativeAds,
    UserProfile? profile,
    List<provider_model.Provider>? cachedProviders,
  }) {
    print('Updating state: selectedCategory=$selectedCategory, isLoading=$isLoading, cachedProviders=${cachedProviders?.length}');

    _selectedCategory = selectedCategory ?? _selectedCategory;
    _userLocation = userLocation ?? _userLocation;
    _locationName = locationName ?? _locationName;
    _maxDistance = maxDistance ?? _maxDistance;
    _showVerifiedOnly = showVerifiedOnly ?? _showVerifiedOnly;
    _isLoading = isLoading ?? _isLoading;
    _isAdFree = isAdFree ?? _isAdFree;
    _isNativeAdsLoading = isNativeAdsLoading ?? _isNativeAdsLoading;
    _availableServices = availableServices ?? _availableServices;
    _nativeAds = nativeAds ?? _nativeAds;
    _profile = profile ?? _profile;
    _cachedProviders = cachedProviders ?? _cachedProviders;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('Notifying listeners after state update');
      notifyListeners();
    });
  }

void showFilterDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => FilterDialog(
      initialMaxDistance: maxDistance,
      initialShowVerifiedOnly: showVerifiedOnly,
      onApply: (newDistance, newVerifiedOnly) {
        updateFilters(
          maxDistance: newDistance,
          showVerifiedOnly: newVerifiedOnly,
        );
      },
    ),
  );
}

   void updateCategory(String? category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    _triggerRebuild();
      updateState(selectedCategory: category);
  }

  void resetNativeAds() {
    for (var ad in _nativeAds) {
      ad?.dispose();
    }
    _nativeAds = [];
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  @override
  void dispose() {
    resetNativeAds();
    super.dispose();
  }

}