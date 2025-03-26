import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/firestore_service.dart';
import 'chat_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  UserProfileScreen({required this.userId});

  @override
  _UserProfileScreenState createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>  with WidgetsBindingObserver{
  final _firestore = FirestoreService();
  Map<String, dynamic>? _userDetails;
  double? _averageRating;
  int? _rating;
  final _reviewController = TextEditingController();

  @override
  void initState() {
    super.initState();
     WidgetsBinding.instance.addObserver(this);
    _loadUserDetails();
    _loadAverageRating();
  }

 @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data or resources

   _loadUserDetails();
    _loadAverageRating();
    }
  }

  @override
  void dispose() {
   
     WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> _loadUserDetails() async {
    var doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
    if (doc.exists) {
      setState(() {
        _userDetails = doc.data();
      });
    }
  }

  Future<void> _loadAverageRating() async {
    var reviews = await FirebaseFirestore.instance
        .collection('user_reviews')
        .where('userId', isEqualTo: widget.userId)
        .get();
    if (reviews.docs.isNotEmpty) {
      double total = reviews.docs.fold(0, (sum, doc) => sum + (doc['rating'] as int));
      setState(() {
        _averageRating = total / reviews.docs.length;
      });
    }
  }

  Future<void> _submitRating() async {
    if (_rating != null && _reviewController.text.trim().isNotEmpty) {
      String providerId = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('user_reviews').add({
        'userId': widget.userId,
        'providerId': providerId,
        'rating': _rating,
        'review': _reviewController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update user's average rating in Firestore
      var reviews = await FirebaseFirestore.instance
          .collection('user_reviews')
          .where('userId', isEqualTo: widget.userId)
          .get();
      double total = reviews.docs.fold(0, (sum, doc) => sum + (doc['rating'] as int));
      double newAverage = total / reviews.docs.length;

      await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
        'averageRating': newAverage,
        'reviewCount': reviews.docs.length,
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review submitted')));
      setState(() {
        _averageRating = newAverage;
      });
      Navigator.pop(context);
    }
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

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(requestId: chatId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userDetails == null) {
      return Scaffold(
        appBar: AppBar(title: Text('User Profile')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${_userDetails!['name']}’s Profile'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.purple[50]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 50,
                      backgroundImage: _userDetails!['profilePicUrl'] != null
                          ? NetworkImage(_userDetails!['profilePicUrl'])
                          : AssetImage('assets/default_profile.png') as ImageProvider,
                      backgroundColor: Colors.grey[200],
                    ),
                  ),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      _userDetails!['name'],
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star, color: Colors.amber, size: 20),
                      SizedBox(width: 4),
                      Text(
                        _averageRating != null ? _averageRating!.toStringAsFixed(1) : 'No ratings yet',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Divider(),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.phone, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Phone: ${_userDetails!['phoneNumber']}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Location: ${_userDetails!['location'] != null ? "${_userDetails!['location']['latitude']}, ${_userDetails!['location']['longitude']}" : "Not available"}',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: Icon(Icons.chat),
                    label: Text('Chat'),
                    onPressed: () => _openOrCreateChat(FirebaseAuth.instance.currentUser!.uid, widget.userId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor:Colors.white ,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                  ),
                  SizedBox(height: 16),
                  Divider(),
                  SizedBox(height: 8),
                  Text('Rate this user:', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.blue[800])),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < (_rating ?? 0) ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                        ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}