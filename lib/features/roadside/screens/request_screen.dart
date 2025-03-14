import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/firestore_service.dart';

class RequestScreen extends StatefulWidget {
  @override
  _RequestScreenState createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  final _firestore = FirestoreService();
  String? _selectedIssue;
  String _locationDescription = '';
  InterstitialAd? _interstitialAd;
  bool _isAdFree = false;

  @override
  void initState() {
    super.initState();
    _loadUserStatus();
    _loadInterstitialAd();
  }

  Future<void> _loadUserStatus() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _isAdFree = await _firestore.isAdFree(user.uid);
      setState(() {});
    }
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712', // Test ID
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

  Future<void> _submitRequest() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedIssue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select an issue')),
      );
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enable location services')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Location permission denied')),
          );
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location permissions permanently denied. Please enable in settings.')),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print('Location: ${position.latitude}, ${position.longitude}');

      await _firestore.createRequest({
        'userId': user.uid,
        'issue': _selectedIssue,
        'location': GeoPoint(position.latitude, position.longitude),
        'locationDescription': _locationDescription,
        'status': 'open',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!_isAdFree && _interstitialAd != null) {
        await _interstitialAd!.show();
      }

      Navigator.pushReplacementNamed(context, '/request_status');
    } catch (e) {
      print('Error submitting request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit request: $e')),
      );
    }
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Request Roadside Assistance')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.getOptions(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return CircularProgressIndicator();
                var options = snapshot.data!.docs.map((doc) => doc['name'] as String).toList();
                return DropdownButtonFormField<String>(
                  value: _selectedIssue,
                  hint: Text('Select an issue'),
                  items: options.map((option) => DropdownMenuItem(value: option, child: Text(option))).toList(),
                  onChanged: (value) => setState(() => _selectedIssue = value),
                  decoration: InputDecoration(border: OutlineInputBorder()),
                );
              },
            ),
            SizedBox(height: 16),
            TextField(
              onChanged: (value) => _locationDescription = value,
              decoration: InputDecoration(
                labelText: 'Location Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submitRequest,
              child: Text('Submit Request'),
            ),
             SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/search'),
              child: Text('Search Services'),
            ),
             SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/profile'),
              child: Text('My Profile'),
            ),
          ],
        ),
      ),
    );
  }
}