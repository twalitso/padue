import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:animations/animations.dart';
import '../../../core/firestore_service.dart';

class ChatScreen extends StatefulWidget {
  final String requestId;

  ChatScreen({required this.requestId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _firestore = FirestoreService();
  final _messageController = TextEditingController();
  final _currentUser = FirebaseAuth.instance.currentUser;
  String? _recipientPhoneNumber;

  @override
  void initState() {
    super.initState();
    _loadRecipientPhoneNumber();
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${message.data['title']}: ${message.data['body']}')),
      );
    });
  }

  Future<void> _loadRecipientPhoneNumber() async {
    var requestDoc = await FirebaseFirestore.instance.collection('requests').doc(widget.requestId).get();
    var request = requestDoc.data() as Map<String, dynamic>;
    String userId = request['userId'];
    String? providerId = request['providerId'];

    if (_currentUser!.uid == userId && providerId != null) {
      var provider = await _firestore.getProviderProfile(providerId);
      _recipientPhoneNumber = provider?.phoneNumber;
    } else if (_currentUser!.uid == providerId) {
      var userProfile = await _firestore.getUserProfile(userId);
      _recipientPhoneNumber = userProfile?.phoneNumber;
    }
    setState(() {});
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch phone call')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat'),
        actions: [
          if (_recipientPhoneNumber != null)
            IconButton(
              icon: Icon(Icons.call, color: Colors.white),
              onPressed: () => _makePhoneCall(_recipientPhoneNumber!),
              tooltip: 'Call',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.getMessages(widget.requestId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                var messages = snapshot.data!.docs;
                return ListView.builder(
                  reverse: true,
                  padding: EdgeInsets.all(8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var message = messages[index].data() as Map<String, dynamic>;
                    bool isMe = message['senderId'] == _currentUser!.uid;
                    bool isPriority = message['isPriority'] ?? false;
                    return FadeTransition(
                      opacity: CurvedAnimation(
                        parent: ModalRoute.of(context)!.animation!,
                        curve: Curves.easeIn,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.blue[100]
                                      : isPriority
                                          ? Colors.orange[100]
                                          : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  message['text'],
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: isPriority ? FontWeight.bold : FontWeight.normal,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ScaleTransition(
                  scale: CurvedAnimation( // Fixed typo: Cur CrownAnimation -> CurvedAnimation
                    parent: ModalRoute.of(context)!.animation!,
                    curve: Curves.easeInOut,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.send, color: Theme.of(context).colorScheme.primary),
                    onPressed: () async {
                      if (_messageController.text.trim().isNotEmpty) {
                        await _firestore.sendMessage(
                          widget.requestId,
                          _currentUser!.uid,
                          _messageController.text.trim(),
                        );
                        _messageController.clear();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}