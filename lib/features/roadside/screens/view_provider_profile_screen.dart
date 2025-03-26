import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/features/roadside/screens/chat_screen.dart';
import '../../roadside/models/provider.dart';

class ViewProviderProfileScreen extends StatefulWidget {
  final String providerId;

  ViewProviderProfileScreen({required this.providerId});

  @override
  _ProviderProfileScreenState createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ViewProviderProfileScreen>  with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  Provider? _provider;
  bool _canRate = false;
  int? _rating;
  final _reviewController = TextEditingController();

  @override
  void initState() {
    super.initState();
     WidgetsBinding.instance.addObserver(this);
    _loadProviderDetails();
    _checkCanRate();
  }

 @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data or resources
 _loadProviderDetails();
    }
  }
  Future<void> _loadProviderDetails() async {
    var provider = await _firestore.getProviderProfile(widget.providerId);
    if (mounted) setState(() => _provider = provider);
  }

  Future<void> _checkCanRate() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var completedOrCanceled = await FirebaseFirestore.instance
          .collection('requests')
          .where('providerId', isEqualTo: widget.providerId)
          .where('userId', isEqualTo: user.uid)
          .where('status', whereIn: ['closed', 'canceled'])
          .limit(1)
          .get();
      if (mounted) setState(() => _canRate = completedOrCanceled.docs.isNotEmpty);
    }
  }

  Future<void> _submitRating() async {
    if (_rating != null && _reviewController.text.trim().isNotEmpty) {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('provider_reviews').add({
          'providerId': widget.providerId,
          'userId': user.uid,
          'rating': _rating,
          'review': _reviewController.text.trim(),
          'timestamp': FieldValue.serverTimestamp(),
        });

        var reviews = await FirebaseFirestore.instance
            .collection('provider_reviews')
            .where('providerId', isEqualTo: widget.providerId)
            .get();
        double total = reviews.docs.fold(0, (sum, doc) => sum + (doc['rating'] as int));
        double newAverage = total / reviews.docs.length;

        await FirebaseFirestore.instance.collection('providers').doc(widget.providerId).update({
          'rating': newAverage,
          'reviewCount': reviews.docs.length,
        });

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review submitted successfully.')));
        Navigator.pop(context);
      }
    }
  }
  @override
  void dispose() {
  
     WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> _openOrCreateChat(String providerId, String userId) async {
    var existingChat = await FirebaseFirestore.instance
        .collection('chat_requests')
        .where('providerId', isEqualTo: providerId)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'accepted'])
        .limit(1)
        .get();

    String chatId;
    if (existingChat.docs.isNotEmpty) {
      chatId = existingChat.docs.first.id;
    } else {
      var newChat = await FirebaseFirestore.instance.collection('chat_requests').add({
        'providerId': providerId,
        'userId': userId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      chatId = newChat.id;
    }

    Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(requestId: chatId)));
  }

  @override
  Widget build(BuildContext context) {
    if (_provider == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Provider Profile'),
          flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue, Colors.blueAccent]))),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${_provider!.name}’s Profile'),
        flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue, Colors.blueAccent]))),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue[50]!, Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 50,
                      backgroundImage: _provider!.profilePicUrl != null
                          ? NetworkImage(_provider!.profilePicUrl!)
                          : AssetImage('assets/default_profile.png') as ImageProvider,
                      backgroundColor: Colors.grey[200],
                    ),
                  ),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      _provider!.name,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue[800]),
                    ),
                  ),
                  SizedBox(height: 8),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star, color: Colors.amber, size: 20),
                        SizedBox(width: 4),
                        Text(
                          _provider!.rating != null ? _provider!.rating!.toStringAsFixed(1) : 'No ratings yet',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  Divider(),
                  SizedBox(height: 8),
                  Text('Service Type: ${_provider!.type}', style: Theme.of(context).textTheme.bodyLarge),
                  SizedBox(height: 8),
                  Text('Verification: ${_provider!.isVerified ? "Verified" : "Unverified"}', style: Theme.of(context).textTheme.bodyLarge),
                  SizedBox(height: 8),
                  Text(
                    'Location: ${_provider!.location != null ? "${_provider!.location!.latitude}, ${_provider!.location!.longitude}" : "Not available"}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: Icon(Icons.chat),
                    label: Text('Chat'),
                    onPressed: () => _openOrCreateChat(widget.providerId, FirebaseAuth.instance.currentUser!.uid),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor:Colors.white ,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  SizedBox(height: 16),
                  if (_canRate) ...[
                    Divider(),
                    SizedBox(height: 8),
                    Text('Rate this Provider', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.blue[800])),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return IconButton(
                          icon: Icon(index < (_rating ?? 0) ? Icons.star : Icons.star_border, color: Colors.amber),
                          onPressed: () => setState(() => _rating = index + 1),
                        );
                      }),
                    ),
                    TextField(
                      controller: _reviewController,
                      decoration: InputDecoration(
                        labelText: 'Review',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                      maxLines: 3,
                    ),
                    SizedBox(height: 16),
                    Center(
                      child: ElevatedButton(
                        onPressed: _submitRating,
                        child: Text('Submit Review'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                        ),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'You are currently unable to rate ',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}