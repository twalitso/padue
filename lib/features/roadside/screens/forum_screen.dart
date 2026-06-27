import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/roadside/models/provider.dart';
import 'package:padue/features/roadside/screens/bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/create_post_screen.dart';
import 'package:padue/features/roadside/screens/post_detail_screen.dart';
import 'package:padue/features/roadside/screens/provider_bottom_nav_bar.dart';
import 'package:padue/core/post_list.dart'; // Import the new widget

class ForumScreen extends StatefulWidget {
  final bool isProvider;
   ForumScreen({super.key, this.isProvider = false});
   

  @override
  _ForumScreenState createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FirestoreService _firestore = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isAdFree = false;
  bool _isLoading = true;
  bool _isProviderUser = false;
  String _searchQuery = '';
  String? _locationName;
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoaded = false;
  final ValueNotifier<List<NativeAd?>> _nativeAds = ValueNotifier<List<NativeAd?>>([]);
  final ValueNotifier<bool> _isNativeAdsLoading = ValueNotifier<bool>(false);
  DateTime? _lastInterstitialAdTime;
  DateTime? _lastLocationUpdate;
  dynamic profile;
  String? profilePicUrl;
  

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
    _getUserLocation();
   // _loadInterstitialAd();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAds();
    });
    _searchController.addListener(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      (context as Element).markNeedsBuild(); // Trigger rebuild for search
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_lastLocationUpdate == null ||
          DateTime.now().difference(_lastLocationUpdate!).inMinutes >= 5) {
        _getUserLocation();
        _loadProfile();
      }
      _loadInterstitialAd();
    }
  }

  Future<void> _initializeAds() async {
    try {
      _isAdFree = await _firestore.isAdFree(_auth.currentUser!.uid);
      if (!_isAdFree) {
        await _loadNativeAds();
      } else {
        _isNativeAdsLoading.value = false;
      }
    } catch (e) {
      print('Error initializing ads: $e');
      _isNativeAdsLoading.value = false;
    }
  }



 Future<void> _loadProfile() async {
   final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
  if(widget.isProvider){
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
    }

  }else{

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

  Future<void> _loadProfileold() async {
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        var providerDoc = await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();
        
        if (providerDoc.exists && mounted) {
           var providerProfile = await _firestore.getProviderProfile(user.uid);
          setState(()  {
            _isProviderUser = true;
            _isAdFree = providerDoc.data()?['adFree'] ?? false;
            _isLoading = false;
            // profile = providerProfile;
          profilePicUrl = providerProfile?.profilePicUrl ;
            

          });
        } else {
          var userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
           profile = await _firestore.getUserProfile(user.uid);
          setState(()  {
            _isProviderUser = false;
            _isAdFree = userDoc.exists ? (userDoc.data()?['adFree'] ?? false) : false;
            _isLoading = false;
             profilePicUrl = profile?.profilePicUrl;
          });
        }
      } catch (e) {
        print('Error loading profile: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (_locationName != 'Unknown') setState(() => _locationName = 'Unknown');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
          if (_locationName != 'Unknown') setState(() => _locationName = 'Unknown');
          return;
        }
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String? newLocationName;
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      newLocationName = placemarks.isNotEmpty ? placemarks.first.locality ?? 'Unknown' : 'Unknown';
      if (mounted && _locationName != newLocationName) {
        setState(() {
          _locationName = newLocationName;
          _lastLocationUpdate = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted && _locationName != 'Unknown') {
        setState(() => _locationName = 'Unknown');
      }
    }
  }

  Future<void> _loadNativeAds() async {
    if (_isAdFree) {
      _isNativeAdsLoading.value = false;
      return;
    }
    _isNativeAdsLoading.value = true;
    const int maxAds = 5;
    List<NativeAd?> tempAds = [];
    for (int i = 0; i < maxAds; i++) {
      try {
        final nativeAd = NativeAd(
          adUnitId: AdmobConfig().native,
          factoryId: 'listTile',
          request: const AdRequest(),
          listener: NativeAdListener(
            onAdLoaded: (ad) {
              print('Native ad loaded: ${ad.responseInfo?.responseId}');
              tempAds.add(ad as NativeAd);
              if (tempAds.length >= maxAds) {
                _nativeAds.value = tempAds;
                _isNativeAdsLoading.value = false;
              }
            },
            onAdFailedToLoad: (ad, error) {
              print('Native ad failed to load: $error');
              ad.dispose();
              tempAds.add(null);
              if (tempAds.length >= maxAds) {
                _nativeAds.value = tempAds;
                _isNativeAdsLoading.value = false;
              }
            },
          ),
          nativeTemplateStyle: NativeTemplateStyle(
            templateType: TemplateType.small,
            mainBackgroundColor: Colors.white,
            primaryTextStyle: NativeTemplateTextStyle(textColor: Colors.black),
            secondaryTextStyle: NativeTemplateTextStyle(textColor: Colors.black87),
            cornerRadius: 12.0,
          ),
        );
        await nativeAd.load();
      } catch (e) {
        print('Error creating native ad: $e');
        tempAds.add(null);
        if (tempAds.length >= maxAds) {
          _nativeAds.value = tempAds;
          _isNativeAdsLoading.value = false;
        }
      }
    }
  }

  Future<void> _loadInterstitialAd() async {
    if (_isAdFree) return;
    InterstitialAd.load(
      adUnitId: AdmobConfig().interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd?.dispose();
          _interstitialAd = ad;
          _isInterstitialAdLoaded = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              _lastInterstitialAdTime = DateTime.now();
              _loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              _lastInterstitialAdTime = DateTime.now();
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) => _isInterstitialAdLoaded = false,
      ),
    );
  }

  bool _canShowInterstitialAd() {
    if (_isAdFree || !_isInterstitialAdLoaded || _interstitialAd == null) return false;
    if (_lastInterstitialAdTime == null) return true;
    return DateTime.now().difference(_lastInterstitialAdTime!).inSeconds >= 60;
  }

  Future<void> _showInterstitialAd(VoidCallback onAdComplete) async {
    if (_canShowInterstitialAd()) {
      _interstitialAd?.show().then((_) => onAdComplete()).catchError((_) => onAdComplete());
    } else {
      onAdComplete();
    }
  }



@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.grey[50],
    appBar: AppBarWidget(
      title: _locationName != null && _locationName != 'Unknown'
          ? 'Forum • $_locationName'
          : 'Community Forum',
      profilePicUrl: profilePicUrl,
      showNotifications: true,
      isProvider: widget.isProvider,
    ),
    drawer: AppBarWidget.buildDrawer(context: context, isProvider: widget.isProvider),

    body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))
        : ValueListenableBuilder<List<NativeAd?>>(
            valueListenable: _nativeAds,
            builder: (context, nativeAds, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: _isNativeAdsLoading,
                builder: (context, isNativeAdsLoading, _) {
                  return PostList(
                    firestore: _firestore,
                    searchQuery: _searchQuery,
                    isAdFree: _isAdFree,
                    nativeAds: nativeAds,
                    isNativeAdsLoading: isNativeAdsLoading,
                    onPostTap: (postId) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PostDetailScreen(postId: postId),
                        ),
                      );
                    },
                    onProfileTap: (posterId) async {
                      final role = await _firestore.getUserRole(posterId);
                      if (role == 'provider') {
                        Navigator.pushNamed(context, '/view_provider_profile', arguments: posterId);
                      } else {
                        Navigator.pushNamed(context, '/user_profile', arguments: posterId);
                      }
                    },
                  );
                },
              );
            },
          ),

    floatingActionButton: FloatingActionButton.extended(
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostScreen()));
      },
      backgroundColor: const Color(0xFFFF6200),
      foregroundColor: Colors.white,
      elevation: 8,
      icon: const Icon(Icons.add, size: 28),
      label: Text('New Post', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
    ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),

    bottomNavigationBar: widget.isProvider
        ? const ProviderBottomNavBar(currentIndex: 2)
        : const BottomNavBar(currentIndex: 2),
  );
}


/** 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
       appBar: AppBarWidget(
           title:  _locationName != null && _locationName != 'Unknown' ? '${_locationName}' : 'Forum',
        profilePicUrl: profile?.profilePicUrl,
        showNotifications: true,
       isProvider: widget.isProvider,
        ),
        drawer: AppBarWidget.buildDrawer(
        context: context,
        isProvider: widget.isProvider,
      ),
   
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<List<NativeAd?>>(
              valueListenable: _nativeAds,
              builder: (context, nativeAds, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _isNativeAdsLoading,
                  builder: (context, isNativeAdsLoading, _) {
                    return PostList(
                      firestore: _firestore,
                      searchQuery: _searchQuery,
                      isAdFree: _isAdFree,
                      nativeAds: nativeAds,
                      isNativeAdsLoading: isNativeAdsLoading,
                      onPostTap: (postId) {
                      //  _showInterstitialAd(() {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PostDetailScreen(postId: postId),
                            ),
                          );
                       // });
                      },
                      onProfileTap: (posterId) async {
                        try {
                       //   _showInterstitialAd(() async {
                            final role = await _firestore.getUserRole(posterId);
                            if (role == 'provider') {
                              Navigator.pushNamed(context, '/view_provider_profile', arguments: posterId);
                            } else if (role == 'user') {
                              Navigator.pushNamed(context, '/user_profile', arguments: posterId);
                            }
                         // });
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                        }
                      },
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
        //  _showInterstitialAd(() {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const CreatePostScreen()));
        //  });
        },
        child: const Icon(Icons.add),
        tooltip: 'Create Post',
        backgroundColor: const Color(0xFFFF6200),
      ).animate(),
      bottomNavigationBar: widget.isProvider == null
    ? SizedBox.shrink()
    : widget.isProvider!
        ? ProviderBottomNavBar(currentIndex: 2)
        : BottomNavBar(currentIndex: 2),

     // bottomNavigationBar: widget.isProvider ? const ProviderBottomNavBar(currentIndex: 2) : const BottomNavBar(currentIndex: 2),
    );
  }*/

  @override
  void dispose() {
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
  //  _interstitialAd?.dispose();
    for (var ad in _nativeAds.value) {
      ad?.dispose();
    }
    _nativeAds.dispose();
    _isNativeAdsLoading.dispose();
    super.dispose();
  }
}