import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'chat_screen.dart';
import '../../../core/utils.dart';

class InboxScreen extends StatefulWidget {
  final bool isProvider;

  InboxScreen({this.isProvider = false});

  @override
  _InboxScreenState createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>  with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
     WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    updateLastActive();
   _setupNotifications();
    saveFcmToken(); // From utils.dart
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null && mounted) {
        _showNotification(message);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      updateLastActive();
      saveFcmToken(); // From utils.dart
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
          setState(() {}); // Refresh inbox
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
  Future<String> _getLastMessage(String chatId) async {
    var messages = await FirebaseFirestore.instance
        .collection('chat_requests')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    return messages.docs.isNotEmpty ? messages.docs.first['text'] : 'No messages yet';
  }

  Future<int> _getUnreadCount(String chatId, String userId) async {
    var messages = await FirebaseFirestore.instance
        .collection('chat_requests')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();
    return messages.docs.length;
  }

  Future<void> _openChat(String chatId, String userId) async {
    await _markMessagesAsRead(chatId, userId);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(requestId: chatId)),
    );
    if (result == true) setState(() {});
  }

  Future<bool> _isOnline(String otherPartyId) async {
    var doc = await FirebaseFirestore.instance
        .collection(widget.isProvider ? 'users' : 'providers')
        .doc(otherPartyId)
        .get();
    var lastActive = doc.data()?['lastActive'] as Timestamp?;
    if (lastActive == null) return false;
    return DateTime.now().difference(lastActive.toDate()).inMinutes < 5;
  }

  Future<void> _markMessagesAsRead(String chatId, String userId) async {
    var unreadMessages = await FirebaseFirestore.instance
        .collection('chat_requests')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();

    for (var doc in unreadMessages.docs) {
      await doc.reference.update({'read': true});
    }
  }

  Future<void> _archiveChat(String chatId) async {
    await FirebaseFirestore.instance.collection('chat_requests').doc(chatId).update({'status': 'archived'});
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Inbox')),
        body: Center(child: Text('Please sign in.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Inbox'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(60),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search chats...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
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
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('chat_requests')
              .where(widget.isProvider ? 'providerId' : 'userId', isEqualTo: user.uid)
              .where('status', isEqualTo: 'accepted')
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

            var chats = snapshot.data!.docs;
            if (chats.isEmpty) {
              return Center(
                child: Card(
                  elevation: 8,
                  margin: EdgeInsets.all(16),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No chats found', style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ),
              );
            }

            var filteredChats = chats.where((chat) {
              var otherPartyId = widget.isProvider ? chat['userId'] : chat['providerId'];
              return otherPartyId.toLowerCase().contains(_searchQuery) ||
                  chat.id.toLowerCase().contains(_searchQuery);
            }).toList();

            return ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: filteredChats.length,
              itemBuilder: (context, index) {
                var chat = filteredChats[index];
                var chatId = chat.id;
                var otherPartyId = widget.isProvider ? chat['userId'] : chat['providerId'];

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection(widget.isProvider ? 'users' : 'providers')
                      .doc(otherPartyId)
                      .get(),
                  builder: (context, otherPartySnapshot) {
                    if (!otherPartySnapshot.hasData) return SizedBox.shrink();

                    var otherParty = otherPartySnapshot.data!.data() as Map<String, dynamic>;
                    var name = otherParty['name'] ?? 'Unknown';

                    return FutureBuilder<String>(
                      future: _getLastMessage(chatId),
                      builder: (context, messageSnapshot) {
                        var lastMessage = messageSnapshot.data ?? 'Loading...';

                        return FutureBuilder<int>(
                          future: _getUnreadCount(chatId, user.uid),
                          builder: (context, unreadSnapshot) {
                            int unreadCount = unreadSnapshot.data ?? 0;

                            return FutureBuilder<bool>(
                              future: _isOnline(otherPartyId),
                              builder: (context, onlineSnapshot) {
                                bool isOnline = onlineSnapshot.data ?? false;

                                return Dismissible(
                                  key: Key(chatId),
                                  background: Container(
                                    color: Colors.orange,
                                    child: Icon(Icons.archive, color: Colors.white),
                                    alignment: Alignment.centerLeft,
                                    padding: EdgeInsets.only(left: 16),
                                  ),
                                  secondaryBackground: Container(
                                    color: Colors.red,
                                    child: Icon(Icons.delete, color: Colors.white),
                                    alignment: Alignment.centerRight,
                                    padding: EdgeInsets.only(right: 16),
                                  ),
                                  onDismissed: (direction) async {
                                    if (direction == DismissDirection.startToEnd) {
                                      await _archiveChat(chatId);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$name archived')),
                                      );
                                    } else {
                                      await FirebaseFirestore.instance.collection('chat_requests').doc(chatId).delete();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$name chat deleted')),
                                      );
                                    }
                                  },
                                  child: Card(
                                    elevation: 8,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    margin: EdgeInsets.symmetric(vertical: 8),
                                    child: ListTile(
                                      leading: Stack(
                                        children: [
                                          CircleAvatar(
                                            radius: 24,
                                            backgroundImage: otherParty['profilePicUrl'] != null
                                                ? NetworkImage(otherParty['profilePicUrl'])
                                                : AssetImage('assets/default_profile.png') as ImageProvider,
                                          ),
                                          if (isOnline)
                                            Positioned(
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: Colors.green,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.white, width: 2),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      title: Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: Text(
                                        lastMessage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(_formatTimestamp(chat['createdAt'])),
                                          if (unreadCount > 0)
                                            Container(
                                              margin: EdgeInsets.only(top: 4),
                                              padding: EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: Colors.blue,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Text(
                                                unreadCount.toString(),
                                                style: TextStyle(color: Colors.white, fontSize: 12),
                                              ),
                                            ),
                                        ],
                                      ),
                                      onTap: () => _openChat(chatId, user.uid),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    DateTime date = timestamp.toDate();
    DateTime now = DateTime.now();
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month}';
  }

  @override
  void dispose() {
    _searchController.dispose();
     WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}