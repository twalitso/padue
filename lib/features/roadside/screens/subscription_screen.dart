import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/firestore_service.dart';

class SubscriptionScreen extends StatefulWidget {
  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>  with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  final InAppPurchase _iap = InAppPurchase.instance;
  List<Map<String, dynamic>> _subscriptionPackages = [];
  List<ProductDetails> _products = [];
  bool _isAdFree = false;
  bool _hasTemporaryPriority = false;
  RewardedAd? _rewardedAd;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
     WidgetsBinding.instance.addObserver(this);
    _loadSubscriptionStatus();
    _loadProductsAndPackages();
    _loadRewardedAd();
  }
 
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data or resources

     _loadSubscriptionStatus();
    _loadProductsAndPackages();
    _loadRewardedAd();
  }}
  Future<void> _loadSubscriptionStatus() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _isAdFree = await _firestore.isAdFree(user.uid);
      _hasTemporaryPriority = await _firestore.hasTemporaryPriority(user.uid);
      setState(() {});
    }
  }

  Future<void> _loadProductsAndPackages() async {
    final bool available = await _iap.isAvailable();
    if (!available) {
      setState(() => _isLoading = false);
      return;
    }

    // Fetch packages from Firestore
    List<Map<String, dynamic>> packages = await _firestore.getSubscriptionPackages();
    Set<String> productIds = packages.map((p) => p['productId'] as String).toSet();

    // Fetch product details from IAP
    final ProductDetailsResponse response = await _iap.queryProductDetails(productIds);
    setState(() {
      _subscriptionPackages = packages;
      _products = response.productDetails;
      _isLoading = false;
    });

    // Listen for purchase updates
    _iap.purchaseStream.listen((purchases) {
      purchases.forEach((purchase) async {
        if (purchase.status == PurchaseStatus.purchased) {
          User? user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await _firestore.setAdFree(user.uid, true);
            setState(() => _isAdFree = true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Subscription activated!')),
            );
          }
          await _iap.completePurchase(purchase);
        }
      });
    });
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: AdmobConfig().getAdUnitId('rewarded') ?? 'ca-app-pub-3940256099942544/5224354917',
      request: AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
          );
        },
        onAdFailedToLoad: (error) => print('Rewarded ad failed to load: $error'),
      ),
    );
  }

  Future<void> _showRewardedAd() async {
    if (_rewardedAd != null) {
      _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) async {
          User? user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await _firestore.grantTemporaryPriority(user.uid);
            setState(() => _hasTemporaryPriority = true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('You earned 24 hours of priority!')),
            );
          }
        },
      );
      _rewardedAd = null;
      _loadRewardedAd();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ad not ready yet, please wait.')),
      );
    }
  }

  Future<void> _buyProduct(ProductDetails product) async {
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  void dispose() {
     WidgetsBinding.instance.removeObserver(this);
    _rewardedAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Subscription'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isAdFree ? 'You are ad-free!' : 'Go Ad-Free with Premium',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  SizedBox(height: 16),
                  if (_isAdFree)
                    Text(
                      'Enjoy an ad-free experience with priority support, faster provider matching, and top search ranking (for providers)!',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose a Premium Plan:',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        SizedBox(height: 8),
                        ..._subscriptionPackages.map((package) {
                          final product = _products.firstWhere(
                            (p) => p.id == package['productId'],
                            orElse: () => ProductDetails(
                              id: package['productId'],
                              title: 'Not Available',
                              description: '',
                              price: 'N/A',
                              rawPrice: 0.0,
                              currencyCode: '',
                            ),
                          );
                          return Card(
                            margin: EdgeInsets.symmetric(vertical: 8),
                            child: ListTile(
                              title: Text(package['name']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(package['description']),
                                  Text('Duration: ${package['duration']}'),
                                  Text('Price: ${product.price}'),
                                ],
                              ),
                              trailing: ElevatedButton(
                                onPressed: product.price == 'N/A'
                                    ? null
                                    : () => _buyProduct(product),
                                child: Text('Subscribe'),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                    SizedBox(height: 20),
                    Text(
                      _hasTemporaryPriority
                          ? 'You have temporary priority!'
                          : 'Earn Temporary Priority',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    SizedBox(height: 8),
                    Text(
                      _hasTemporaryPriority
                          ? 'Enjoy priority for the next 24 hours!'
                          : 'Watch a video to get 24 hours of priority matching and support.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: 16),
                    if (!_hasTemporaryPriority)
                      ElevatedButton(
                        onPressed: _showRewardedAd,
                        child: Text('Watch Ad for Priority'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}