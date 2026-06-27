import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/roadside/models/provider.dart';
import 'package:padue/features/roadside/screens/banner_ad_widget.dart';
import 'package:padue/features/roadside/screens/bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/provider_bottom_nav_bar.dart';
import '../../../core/admob_config.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with TickerProviderStateMixin {
  final FirestoreService _firestore = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isProvider = false;
  bool _isAdFree = false;
  bool _isLoading = true;
  bool _isAdLoading = false;
  RewardedAd? _rewardedAd;

  Timestamp? _subscriptionEnd;
  Timestamp? _priorityUntil;

  late AnimationController _pulseController;


  
  bool _isProviderUser = false;
  
   dynamic profile;
  String? profilePicUrl;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: 2.seconds)
      ..repeat();
    _loadUserData();
     _loadProfile();
    _loadRewardedAd();
  }


Future<void> _loadProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _isLoading = true);
      var providerDoc = await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();
      if (providerDoc.exists && mounted) {
        Provider provider = Provider.fromFirestore(providerDoc);
        final providerProfile = await _firestore.getProviderProfile(user.uid);
        setState(() {
          _isProviderUser = true;
          _isAdFree = provider.adFree;
        
          _isLoading = false;
           profilePicUrl = providerProfile?.profilePicUrl ?? provider.profilePicUrl;
        });
      } else {
        var userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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
  }

  // ────────────────────── CORE LOGIC ──────────────────────
  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final isProviderDoc = await FirebaseFirestore.instance
        .collection('providers')
        .doc(user.uid)
        .get();

    final collection = isProviderDoc.exists ? 'providers' : 'users';
    final doc = await FirebaseFirestore.instance
        .collection(collection)
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      setState(() => _isLoading = false);
      return;
    }

    final data = doc.data()!;
    final endDate = data['subscriptionEnd'] as Timestamp?;
    final priorityDate = data['priorityUntil'] as Timestamp?;

    // Auto-expire logic (runs silently)
    await _checkAndUpdateSubscriptionStatus(collection, user.uid, endDate, priorityDate);

    // Refresh data after auto-update
    final freshDoc = await FirebaseFirestore.instance
        .collection(collection)
        .doc(user.uid)
        .get();

    final freshData = freshDoc.data()!;
    setState(() {
     // _isProvider = isProviderDoc.exists;
      _isAdFree = freshData['adFree'] ?? false;
      _subscriptionEnd = freshData['subscriptionEnd'] as Timestamp?;
      _priorityUntil = freshData['priorityUntil'] as Timestamp?;
      _isLoading = false;
    });
  }

  Future<void> _checkAndUpdateSubscriptionStatus(
    String collection,
    String uid,
    Timestamp? subEnd,
    Timestamp? priorityEnd,
  ) async {
    final now = Timestamp.now();
    bool needsUpdate = false;
    Map<String, dynamic> updateData = {};

    if (subEnd != null && subEnd.toDate().isBefore(now.toDate())) {
      updateData['adFree'] = false;
      updateData['subscriptionEnd'] = null;
      needsUpdate = true;
    }

    if (priorityEnd != null && priorityEnd.toDate().isBefore(now.toDate())) {
      updateData['priorityUntil'] = null;
      if (subEnd == null || subEnd.toDate().isBefore(now.toDate())) {
        updateData['adFree'] = false;
      }
      needsUpdate = true;
    }

    if (needsUpdate) {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .update(updateData);
    }
  }

  void _loadRewardedAd() {
    setState(() => _isAdLoading = true);
    RewardedAd.load(
      adUnitId: AdmobConfig().rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => setState(() => {_rewardedAd = ad, _isAdLoading = false}),
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad failed: $error');
          setState(() => {_rewardedAd = null, _isAdLoading = false});
        },
      ),
    );
  }

  Future<void> _showRewardedAd() async {
    if (_rewardedAd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not ready. Try again.')),
      );
      return;
    }

   _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
  onAdDismissedFullScreenContent: (ad) {
    ad.dispose();
    _rewardedAd = null;
    _loadRewardedAd();
  },
  onAdFailedToShowFullScreenContent: (ad, error) {
    ad.dispose();
    _rewardedAd = null;
    _loadRewardedAd();
  },
);


    await _rewardedAd!.show(
      onUserEarnedReward: (_, __) => _grant24HourPriority(),
    );
  }

  Future<void> _grant24HourPriority() async {
    final user = _auth.currentUser!;
    final collection = _isProviderUser ? 'providers' : 'users';
    final end = Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24)));

  
    await FirebaseFirestore.instance
  .collection(collection)
  .doc(user.uid)
  .set({
    'adFree': true,
    'priorityUntil': end,
  }, SetOptions(merge: true));


    setState(() => _priorityUntil = end);
    

 if (mounted) {
        setState(() {
          _isAdFree = true;
         
        });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              '24-Hour Priority Activated!',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
        
    );
 }
  }

  Future<void> _subscribeMonthly() async {
    // Placeholder — Replace with RevenueCat / Stripe later
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFFF6200),
        content: Text(
          'Monthly Subscription - Coming Soon!',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  // ────────────────────── UI ──────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBarWidget(
        title: 'Subscription',
        profilePicUrl: profilePicUrl, // Will be loaded dynamically if needed
        showNotifications: true,
        isProvider: _isProviderUser,
       
      ),
      drawer: AppBarWidget.buildDrawer(context: context, isProvider: _isProviderUser),
      body: Stack(
        children: [
          // Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFF6200), Color(0xFFFF8A50)],
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const SizedBox(height: 40),

                        // Crown Icon
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))
                            ],
                          ),
                          child: const Icon(Icons.auto_awesome, size: 80, color: Color(0xFFFF6200)),
                          ).animate(controller: _pulseController).scale(
                          begin: const Offset(1.0, 1.0),
                          end: const Offset(1.15, 1.15),
                          duration: 2.seconds,
                          curve: Curves.easeInOut,
                        ),

                        const SizedBox(height: 32),

                        Text(
                          _isAdFree ? 'You\'re Premium!' : 'Go Premium',
                          style: GoogleFonts.poppins(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 16),

                        Text(
                          _isAdFree
                              ? 'Enjoy ad-free experience and priority visibility'
                              : 'Remove ads and get priority in searches',
                          style: GoogleFonts.poppins(fontSize: 18, color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 40),

                        // Status Chips
                        if (_isAdFree) ...[
                          _statusChip(
                            'Ad-Free Experience',
                            Icons.block,
                            Colors.green,
                          ),
                          if (_priorityUntil != null)
                            _statusChip(
                              'Priority Until ${_formatDate(_priorityUntil!)}',
                              Icons.trending_up,
                              Colors.orange,
                            ),
                          if (_subscriptionEnd != null)
                            _statusChip(
                              'Subscribed Until ${_formatDate(_subscriptionEnd!)}',
                              Icons.star_rounded,
                              Colors.purple,
                            ),
                        ],

                        const SizedBox(height: 40),

                        // Subscription Cards
                        if (!_isAdFree) ...[
                          _subscriptionCard(
                            title: '24-Hour Priority',
                            subtitle: 'Watch ad • Instant activation',
                            price: 'FREE',
                            color: Colors.green,
                            icon: Icons.play_circle_fill,
                            onTap:  _isAdLoading
      ? null
      : () async {
          // This is safe – no type error
          if (!mounted) return;
          await _showRewardedAd();
        },
                            isLoading: _isAdLoading,
                          ),
                          const SizedBox(height: 20),
                          _subscriptionCard(
                            title: 'Monthly Premium',
                            subtitle: 'Ad-free • Top priority • Coming soon',
                            price: 'SOON',
                            color: const Color(0xFFFF6200),
                            icon: Icons.diamond,
                            onTap: _subscribeMonthly,
                            gradient: true,
                          ),
                        ] else
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.check_circle, size: 80, color: Colors.white),
                                const SizedBox(height: 16),
                                Text(
                                  'You\'re all set!',
                                  style: GoogleFonts.poppins(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Enjoy your premium benefits',
                                  style: GoogleFonts.poppins(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),

      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isAdFree) const BannerAdWidget(),
          /**_isProvider
              ? const ProviderBottomNavBar(currentIndex: 5)
              : const BottomNavBar(currentIndex: 5),*/
        ],
      ),
    );
  }

  Widget _statusChip(String text, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Text(text, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3);
  }

  Widget _subscriptionCard({
    required String title,
    required String subtitle,
    required String price,
    required Color color,
    required IconData icon,
    GestureTapCallback? onTap,  // This allows async functions!
    bool isLoading = false,
    bool gradient = false,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: gradient
              ? const LinearGradient(colors: [Color(0xFFFF6200), Color(0xFFFF4500)])
              : null,
          color: gradient ? null : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, 10))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: gradient ? Colors.white24 : color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: gradient ? Colors.white : color),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: gradient ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: gradient ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  )
                else
                  Text(
                    price,
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: gradient ? Colors.white : color,
                    ),
                  ),
                if (!isLoading && price != 'SOON')
                  const Icon(Icons.arrow_forward_ios, color: Colors.white70),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.3);
  }

  String _formatDate(Timestamp timestamp) {
    return DateFormat('MMM d, h:mm a').format(timestamp.toDate());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }
}