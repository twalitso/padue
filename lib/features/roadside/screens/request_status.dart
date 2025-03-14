import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:animations/animations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/firestore_service.dart';
import '../../roadside/models/provider.dart';
import 'chat_screen.dart';

class RequestStatusScreen extends StatefulWidget {
  @override
  _RequestStatusScreenState createState() => _RequestStatusScreenState();
}

class _RequestStatusScreenState extends State<RequestStatusScreen> {
  final _firestore = FirestoreService();
  String? _requestId;
  int? _rating;
  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  bool _isAdFree = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
    _loadInterstitialAd();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchLatestRequest();
  }

  Future<void> _fetchLatestRequest() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var query = await FirebaseFirestore.instance
          .collection('requests')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        _requestId = query.docs.first.id;
        _isAdFree = await _firestore.isAdFree(user.uid);
        setState(() {});
      }
    }
  }

  Future<void> _completeRequest(String providerId) async {
    await FirebaseFirestore.instance.collection('requests').doc(_requestId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
    await FirebaseFirestore.instance
        .collection('analytics')
        .doc('requests')
        .collection('records')
        .doc(_requestId)
        .update({
      'completedAt': FieldValue.serverTimestamp(),
    });
    await _firestore.sendNotification(
      providerId,
      'Service Completed',
      'The request you accepted has been marked as completed.',
    );
    _showRatingDialog(providerId);
    if (!_isAdFree && _interstitialAd != null) {
      await _interstitialAd!.show();
    }
  }

  void _showRatingDialog(String providerId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rate the Provider', style: Theme.of(context).textTheme.headlineMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('How would you rate this service?', style: Theme.of(context).textTheme.bodyMedium),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < (_rating ?? 0) ? Icons.star : Icons.star_border,
                    color: Colors.yellow[700],
                    size: 32,
                  ),
                  onPressed: () => setState(() => _rating = index + 1),
                );
              }),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_rating != null) {
                User? user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await _firestore.submitRating(_requestId!, user.uid, providerId, _rating!);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Rating submitted!')),
                  );
                }
              }
            },
            child: Text('Submit'),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(String providerId) {
    final _reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report Provider', style: Theme.of(context).textTheme.headlineMedium),
        content: TextField(
          controller: _reasonController,
          decoration: InputDecoration(
            labelText: 'Reason for reporting',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              User? user = FirebaseAuth.instance.currentUser;
              if (user != null && _reasonController.text.trim().isNotEmpty) {
                await _firestore.submitReport(
                  user.uid,
                  providerId,
                  _reasonController.text.trim(),
                  'provider',
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Report submitted!')),
                );
              }
            },
            child: Text('Submit'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Test banner ID
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() {}),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          print('Banner ad failed to load: $error');
        },
      ),
    );
    _bannerAd!.load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712', // Test interstitial ID
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
          );
        },
        onAdFailedToLoad: (error) => print('Interstitial ad failed to load: $error'),
      ),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Request Status'),
        actions: [
          IconButton(
            icon: Icon(Icons.monetization_on),
            onPressed: () => Navigator.pushNamed(context, '/subscription'),
            tooltip: 'Manage Subscription',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _requestId == null
                ? Center(child: CircularProgressIndicator())
                : StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('requests').doc(_requestId).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                      var request = snapshot.data!.data() as Map<String, dynamic>?;
                      if (request == null) return Center(child: Text('Request not found'));
                      String? providerId = request['providerId'];
                      return Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('Request: ${request['issue']}', style: Theme.of(context).textTheme.headlineMedium),
                            SizedBox(height: 8),
                            Text('Status: ${request['status']}', style: Theme.of(context).textTheme.bodyMedium),
                            SizedBox(height: 16),
                            if (providerId != null) ...[
                              FutureBuilder<Provider?>(
                                future: _firestore.getProviderProfile(providerId),
                                builder: (context, providerSnapshot) {
                                  if (!providerSnapshot.hasData) return CircularProgressIndicator();
                                  var provider = providerSnapshot.data;
                                  if (provider == null) return Text('Provider not found');
                                  return Card(
                                    elevation: 4,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Column(
                                        children: [
                                          Text('Provider: ${provider.name}',
                                              style: Theme.of(context).textTheme.bodyMedium),
                                          Text('Verification: ${provider.isVerified ? "Verified" : "Unverified"}',
                                              style: Theme.of(context).textTheme.bodySmall),
                                          if (request['status'] == 'accepted') ...[
                                            SizedBox(height: 16),
                                            ScaleTransition(
                                              scale: CurvedAnimation(
                                                parent: ModalRoute.of(context)!.animation!,
                                                curve: Curves.easeInOut,
                                              ),
                                              child: ElevatedButton.icon(
                                                icon: Icon(Icons.chat),
                                                label: Text('Chat with Provider'),
                                                onPressed: () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => ChatScreen(requestId: _requestId!),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            ScaleTransition(
                                              scale: CurvedAnimation(
                                                parent: ModalRoute.of(context)!.animation!,
                                                curve: Curves.easeInOut,
                                              ),
                                              child: ElevatedButton.icon(
                                                icon: Icon(Icons.check),
                                                label: Text('Mark as Completed'),
                                                onPressed: () => _completeRequest(providerId),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            ScaleTransition(
                                              scale: CurvedAnimation(
                                                parent: ModalRoute.of(context)!.animation!,
                                                curve: Curves.easeInOut,
                                              ),
                                              child: ElevatedButton.icon(
                                                icon: Icon(Icons.report),
                                                label: Text('Report Provider'),
                                                onPressed: () => _showReportDialog(providerId),
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                              ),
                                            ),
                                          ],
                                          if (request['status'] == 'completed')
                                            Padding(
                                              padding: EdgeInsets.only(top: 16),
                                              child: Text(
                                                'Service completed. Rating: ${_rating ?? "Not yet"}',
                                                style: Theme.of(context).textTheme.bodyMedium,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ] else
                              Text('Waiting for provider to accept...', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (!_isAdFree && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }
}