import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:padue/core/admob_config.dart';
import 'package:padue/core/utils.dart';
import 'package:padue/features/auth/screens/user_login_screen.dart';
import 'package:padue/features/roadside/screens/inbox_screen.dart';
import '../../../core/firestore_service.dart';
import '../../roadside/models/provider.dart';
import 'chat_screen.dart';

class RequestStatusScreen extends StatefulWidget {
  @override
  _RequestStatusScreenState createState() => _RequestStatusScreenState();
}

class _RequestStatusScreenState extends State<RequestStatusScreen>  with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  bool _isAdFree = false;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAd();
    _loadInterstitialAd();
    _checkAdFreeStatus();
    updateLastActive();
  }

 @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data or resources

   _loadAd();
    _loadInterstitialAd();
    _checkAdFreeStatus();
    updateLastActive();
    }
  }
  Future<void> _checkAdFreeStatus() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _isAdFree = await _firestore.isAdFree(user.uid);
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmRequest(String providerId, String requestId) async {
    await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
    });
    await FirebaseFirestore.instance
        .collection('analytics')
        .doc('requests')
        .collection('records')
        .doc(requestId)
        .update({'closedAt': FieldValue.serverTimestamp()});
    await _firestore.sendNotification(providerId, 'Request Closed', 'The user has confirmed your service as completed.');
    _showRatingDialog(providerId, requestId);
    if (!_isAdFree && _interstitialAd != null) await _interstitialAd!.show();
  }

  Future<void> _disputeRequest(String providerId, String requestId) async {
    final _reasonController = TextEditingController();
    bool? shouldDispute = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dispute Completion', style: Theme.of(context).textTheme.headlineMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Please specify why this request is not complete.', style: Theme.of(context).textTheme.bodyMedium),
            SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'Reason for Dispute',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Submit'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
    if (shouldDispute == true && _reasonController.text.trim().isNotEmpty) {
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
        'status': 'accepted',
        'disputeReason': _reasonController.text.trim(),
        'disputedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance
          .collection('analytics')
          .doc('requests')
          .collection('records')
          .doc(requestId)
          .update({'disputeReason': _reasonController.text.trim(), 'disputedAt': FieldValue.serverTimestamp()});
      await _firestore.sendNotification(providerId, 'Request Disputed', 'The user has disputed your completion: ${_reasonController.text.trim()}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dispute submitted successfully.')));
    }
  }

  Future<void> _completeRequest(String providerId, String requestId) async {
    await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
      'status': 'closed',
      'completedAt': FieldValue.serverTimestamp(),
    });
    await FirebaseFirestore.instance
        .collection('analytics')
        .doc('requests')
        .collection('records')
        .doc(requestId)
        .update({'completedAt': FieldValue.serverTimestamp()});
    await _firestore.sendNotification(providerId, 'Service Completed', 'The user has marked the request as completed.');
    _showRatingDialog(providerId, requestId);
    if (!_isAdFree && _interstitialAd != null) await _interstitialAd!.show();
  }

  void _showRatingDialog(String providerId, String requestId) {
    int? _rating;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rate the Provider', style: Theme.of(context).textTheme.headlineMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('How would you rate this service?', style: Theme.of(context).textTheme.bodyMedium),
            SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setState) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(index < (_rating ?? 0) ? Icons.star : Icons.star_border, color: Colors.amber, size: 32),
                    onPressed: () => setState(() => _rating = index + 1),
                  );
                }),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (_rating != null) {
                User? user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await _firestore.submitRating(requestId, user.uid, providerId, _rating!);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rating submitted successfully.')));
                }
              }
            },
            child: Text('Submit'),
            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
            labelText: 'Reason for Reporting',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey[100],
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              User? user = FirebaseAuth.instance.currentUser;
              if (user != null && _reasonController.text.trim().isNotEmpty) {
                await _firestore.submitReport(user.uid, providerId, _reasonController.text.trim(), 'provider');
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report submitted successfully.')));
              }
            },
            child: Text('Submit'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: AdmobConfig().getAdUnitId('banner')  ?? 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdLoaded = true),
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
      adUnitId: AdmobConfig().getAdUnitId('interstitial') ?? 'ca-app-pub-3940256099942544/1033173712',
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Request Status'),
          flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue, Colors.blueAccent]))),
        ),
        body: Center(child: Text('Please sign in to view your request status.')),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue[50]!, Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: Text('Request Status'),
                flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue, Colors.blueAccent]))),
                actions: [
                  IconButton(
                    icon: Icon(Icons.message),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => InboxScreen(isProvider: false))),
                    tooltip: 'Inbox',
                  ),
                  IconButton(
                    icon: Icon(Icons.monetization_on),
                    onPressed: () => Navigator.pushNamed(context, '/subscription'),
                    tooltip: 'Manage Subscription',
                  ),
                  IconButton(
                    icon: Icon(Icons.logout),
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => UserLoginScreen()));
                    },
                    tooltip: 'Logout',
                  ),
                  IconButton(
  icon: const Icon(Icons.logout),
  onPressed: () async {
    // Show confirmation dialog
    bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), // Cancel
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true), // Confirm
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    // Proceed with logout if confirmed
    if (confirmLogout == true) {
      await FirebaseAuth.instance.signOut();
       Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => UserLoginScreen()));
    //  Navigator.pushReplacementNamed(context, '/login');
    }
  },
),
                ],
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('requests')
                      .where('userId', isEqualTo: user.uid)
                      .orderBy('createdAt', descending: true)
                      .limit(1)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
                    if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(child: Text('No active requests found.', style: Theme.of(context).textTheme.bodyMedium));
                    }

                    var requestDoc = snapshot.data!.docs.first;
                    var request = requestDoc.data() as Map<String, dynamic>;
                    final String requestId = requestDoc.id;
                    final String? providerId = request['providerId'];

                    return SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Request Details',
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue[800]),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 8),
                                Text('Service: ${request['issue'] ?? request['service']}', style: Theme.of(context).textTheme.bodyLarge),
                                SizedBox(height: 8),
                                Text('Status: ${request['status']}', style: Theme.of(context).textTheme.bodyLarge),
                                SizedBox(height: 16),
                                if (providerId != null) ...[
                                  FutureBuilder<Provider?>(
                                    future: _firestore.getProviderProfile(providerId),
                                    builder: (context, providerSnapshot) {
                                      if (!providerSnapshot.hasData) return Center(child: CircularProgressIndicator());
                                      var provider = providerSnapshot.data;
                                      if (provider == null) return Text('Provider not found');
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 24,
                                                backgroundImage: provider.profilePicUrl != null
                                                    ? NetworkImage(provider.profilePicUrl!)
                                                    : AssetImage('assets/default_profile.png') as ImageProvider,
                                              ),
                                              SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text('Provider: ${provider.name}', style: Theme.of(context).textTheme.bodyLarge),
                                                    Text('Verification: ${provider.isVerified ? "Verified" : "Unverified"}',
                                                        style: Theme.of(context).textTheme.bodyMedium),
                                                    if (provider.rating != null)
                                                      Row(
                                                        children: [
                                                          Text('Rating: ${provider.rating!.toStringAsFixed(1)}',
                                                              style: Theme.of(context).textTheme.bodyMedium),
                                                          SizedBox(width: 4),
                                                          Icon(Icons.star, color: Colors.amber, size: 16),
                                                        ],
                                                      )
                                                    else
                                                      Text('Rating: N/A', style: Theme.of(context).textTheme.bodyMedium),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 16),
                                          if (request['status'] == 'accepted') ...[
                                            ElevatedButton.icon(
                                              icon: Icon(Icons.chat),
                                              label: Text('Chat with Provider'),
                                              onPressed: () => Navigator.push(
                                                context,
                                                MaterialPageRoute(builder: (context) => ChatScreen(requestId: requestId)),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.blue,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                padding: EdgeInsets.symmetric(vertical: 12),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            ElevatedButton.icon(
                                              icon: Icon(Icons.check),
                                              label: Text('Mark as Completed'),
                                              onPressed: () => _completeRequest(providerId, requestId),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                padding: EdgeInsets.symmetric(vertical: 12),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            ElevatedButton.icon(
                                              icon: Icon(Icons.report),
                                              label: Text('Report Provider'),
                                              onPressed: () => _showReportDialog(providerId),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                padding: EdgeInsets.symmetric(vertical: 12),
                                              ),
                                            ),
                                          ],
                                          if (request['status'] == 'provider_completed') ...[
                                            SizedBox(height: 16),
                                            Text(
                                              'The provider has marked this as completed. Please confirm or dispute.',
                                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                                              textAlign: TextAlign.center,
                                            ),
                                            SizedBox(height: 8),
                                            ElevatedButton.icon(
                                              icon: Icon(Icons.check_circle),
                                              label: Text('Confirm Completion'),
                                              onPressed: () => _confirmRequest(providerId, requestId),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                padding: EdgeInsets.symmetric(vertical: 12),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            ElevatedButton.icon(
                                              icon: Icon(Icons.warning),
                                              label: Text('Dispute Completion'),
                                              onPressed: () => _disputeRequest(providerId, requestId),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.orange,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                padding: EdgeInsets.symmetric(vertical: 12),
                                              ),
                                            ),
                                          ],
                                          if (request['status'] == 'closed')
                                            Padding(
                                              padding: EdgeInsets.only(top: 16),
                                              child: Text(
                                                'Service completed and confirmed.',
                                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.green),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          if (request['status'] == 'canceled')
                                            Padding(
                                              padding: EdgeInsets.only(top: 16),
                                              child: Text(
                                                'Request canceled by provider.',
                                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.red),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ] else
                                  Text('Awaiting provider acceptance...', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (!_isAdFree && _isBannerAdLoaded && _bannerAd != null)
                Container(
                  width: double.infinity,
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}