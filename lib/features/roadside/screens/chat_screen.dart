import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:animations/animations.dart';
import '../../../core/firestore_service.dart';
import '../../../core/utils.dart';

class ChatScreen extends StatefulWidget {
  final String? requestId;
  final String? providerId;

  ChatScreen({this.requestId, this.providerId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  final _messageController = TextEditingController();
  final _currentUser = FirebaseAuth.instance.currentUser;
  String? _recipientPhoneNumber;
  String? _recipientName;
  String? _senderName;
  String? _recipientProfilePicUrl;
  String? _chatId;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    updateLastActive();
    _setupNotifications();
    saveFcmToken();
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null && mounted) {
        _showNotification(message);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializeChat();
      updateLastActive();
      saveFcmToken();
    }
  }

  Future<void> _setupNotifications() async {
    const channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
    );
    await _notificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (details) {
        final data = jsonDecode(details.payload ?? '{}');
        if (data['type'] == 'message') {
          setState(() {});
        }
      },
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _showNotification(RemoteMessage message) {
    final notification = message.notification!;
    _notificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializeChat() async {
    if (_currentUser == null) return;

    // Set sender name based on role
    await _setSenderName();

    if (widget.requestId != null) {
      _chatId = widget.requestId;
      await _loadRecipientDetailsFromRequest();
    } else if (widget.providerId != null) {
      _chatId = await _createOrGetDirectChat(widget.providerId!);
      await _loadRecipientDetailsFromProvider();
    }
    setState(() {});
  }

  Future<void> _setSenderName() async {
    if (_currentUser == null) return;

    // Check the user's role
    final role = await _firestore.getUserRole(_currentUser!.uid);
    if (role == 'user') {
      var userProfile = await _firestore.getUserProfile(_currentUser!.uid);
      _senderName = userProfile?.name ?? 'Unknown User';
    } else if (role == 'provider') {
      var providerProfile = await _firestore.getProviderProfile(_currentUser!.uid);
      _senderName = providerProfile?.name ?? 'Unknown Provider';
    }
    setState(() {});
  }

  Future<String> _createOrGetDirectChat(String providerId) async {
    var existingChats = await FirebaseFirestore.instance
        .collection('chat_requests')
        .where('userId', isEqualTo: _currentUser!.uid)
        .where('providerId', isEqualTo: providerId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();

    if (existingChats.docs.isNotEmpty) {
      return existingChats.docs.first.id;
    }

    var chatDoc = await FirebaseFirestore.instance.collection('chat_requests').add({
      'userId': _currentUser!.uid,
      'providerId': providerId,
      'status': 'accepted',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return chatDoc.id;
  }

  Future<void> _loadRecipientDetailsFromRequest() async {
    var requestDoc = await FirebaseFirestore.instance.collection('chat_requests').doc(widget.requestId).get();
    var request = requestDoc.data();
    if (request == null) return;

    String userId = request['userId'];
    String? providerId = request['providerId'];

    if (_currentUser!.uid == userId && providerId != null) {
      var provider = await _firestore.getProviderProfile(providerId);
      _recipientPhoneNumber = provider?.phoneNumber;
      _recipientName = provider?.name ?? 'Unknown Provider';
      _recipientProfilePicUrl = provider?.profilePicUrl;
    } else if (_currentUser!.uid == providerId) {
      var userProfile = await _firestore.getUserProfile(userId);
      _recipientPhoneNumber = userProfile?.phoneNumber;
      _recipientName = userProfile?.name ?? 'Unknown User';
      _recipientProfilePicUrl = userProfile?.profilePicUrl;
    }
    setState(() {});
  }

  Future<void> _loadRecipientDetailsFromProvider() async {
    var provider = await _firestore.getProviderProfile(widget.providerId!);
    _recipientPhoneNumber = provider?.phoneNumber;
    _recipientName = provider?.name ?? 'Unknown Provider';
    _recipientProfilePicUrl = provider?.profilePicUrl;
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

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isNotEmpty && _chatId != null && _currentUser != null) {
      await _firestore.sendMessage(
        _chatId!,
        _currentUser!.uid,
        _messageController.text.trim(),
      );
      var chatDoc = await FirebaseFirestore.instance.collection('chat_requests').doc(_chatId).get();
      var receiverId = _currentUser!.uid == chatDoc['userId'] ? chatDoc['providerId'] : chatDoc['userId'];
      var receiverDoc = await FirebaseFirestore.instance
          .collection(_currentUser!.uid == chatDoc['userId'] ? 'providers' : 'users')
          .doc(receiverId)
          .get();
      var token = receiverDoc.data()?['fcmToken'] as String?;
      if (token != null) {
        await sendFcmNotificationV1(
          token: token,
          title: 'New Message',
          body: '$_senderName sent you a message.', // Use senderName here
          type: 'message',
          id: _chatId,
          recipientUid: receiverId,
        );
      }
      _messageController.clear();
      updateLastActive();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chatId == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Chat'),
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
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: _recipientProfilePicUrl != null
                  ? NetworkImage(_recipientProfilePicUrl!)
                  : AssetImage('assets/default_profile.png') as ImageProvider,
            ),
            SizedBox(width: 8),
            Text(_recipientName ?? 'Loading...'),
          ],
        ),
        actions: [
          if (_recipientPhoneNumber != null)
            IconButton(
              icon: Icon(Icons.call),
              onPressed: () => _makePhoneCall(_recipientPhoneNumber!),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.purple[50]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Card(
                elevation: 8,
                margin: EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore.getMessages(_chatId!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(child: Text('No messages yet'));
                      }

                      var messages = snapshot.data!.docs;
                      return ListView.builder(
                        reverse: true,
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
                                        color: isMe ? Colors.blue[100] : isPriority ? Colors.orange[100] : Colors.grey[200],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(message['text']),
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
              ),
            ),
            Card(
              elevation: 8,
              margin: EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}