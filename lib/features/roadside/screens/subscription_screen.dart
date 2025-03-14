import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/firestore_service.dart';

class SubscriptionScreen extends StatefulWidget {
  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _firestore = FirestoreService();
  final InAppPurchase _iap = InAppPurchase.instance;
  List<ProductDetails> _products = [];
  bool _isAdFree = false;
  bool _hasTemporaryPriority = false;
  RewardedAd? _rewardedAd;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionStatus();
    _loadProducts();
    _loadRewardedAd();
  }

  Future<void> _loadSubscriptionStatus() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _isAdFree = await _firestore.isAdFree(user.uid);
      _hasTemporaryPriority = await _firestore.hasTemporaryPriority(user.uid);
      setState(() {});
    }
  }

  Future<void> _loadProducts() async {
    final bool available = await _iap.isAvailable();
    if (!available) return;

    const Set<String> _kIds = {'padue_ad_free'};
    final ProductDetailsResponse response = await _iap.queryProductDetails(_kIds);
    setState(() {
      _products = response.productDetails;
    });

    _iap.purchaseStream.listen((purchases) {
      purchases.forEach((purchase) async {
        if (purchase.status == PurchaseStatus.purchased) {
          User? user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await _firestore.setAdFree(user.uid, true);
            setState(() => _isAdFree = true);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ad-free subscription activated!')));
          }
          await _iap.completePurchase(purchase);
        }
      });
    });
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/5224354917', // Test rewarded ad ID
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
      _loadRewardedAd(); // Reload for next use
    }
  }

  Future<void> _buyProduct(ProductDetails product) async {
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Subscription')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
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
                    'Upgrade to Premium for these benefits:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: 8),
                  Text('• Ad-free experience', style: Theme.of(context).textTheme.bodyMedium),
                  Text('• Priority support in chats', style: Theme.of(context).textTheme.bodyMedium),
                  Text('• Faster provider matching', style: Theme.of(context).textTheme.bodyMedium),
                  Text('• Top search ranking (for providers)', style: Theme.of(context).textTheme.bodyMedium),
                  SizedBox(height: 16),
                  if (_products.isNotEmpty)
                    ElevatedButton(
                      onPressed: () => _buyProduct(_products.first),
                      child: Text('Subscribe for ${_products.first.price}/month'),
                    ),
                ],
              ),
              SizedBox(height: 20),
              Text(
                _hasTemporaryPriority ? 'You have temporary priority!' : 'Earn Temporary Priority',
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