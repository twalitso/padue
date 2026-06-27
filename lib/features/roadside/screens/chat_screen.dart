import 'dart:convert';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/core/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/firestore_service.dart';
import '../../../core/utils.dart';
import 'package:intl/intl.dart'; 

class ChatScreen extends StatefulWidget {
  final String? requestId;
  final String? providerId;

  const ChatScreen({super.key, this.requestId, this.providerId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final FirestoreService _firestore = FirestoreService();
  final TextEditingController _messageController = TextEditingController();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final ScrollController _scrollController = ScrollController();
  String? _recipientPhoneNumber;
  String? _recipientName;
  String? _senderName;
  String? _recipientProfilePicUrl;
  String? _chatId;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  DateTime? _recipientLastActive;
  final ValueNotifier<bool> _hasText = ValueNotifier(false);



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    
    updateLastActive();
    _setupNotifications();
   // saveFcmToken();
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null && mounted) {
        _showNotification(message);
      }
    });

    
  // NEW – mark everything read as soon as the screen is built
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_chatId != null) _markAllAsRead();
  });
  }


Future<void> _markAllAsRead() async {
  if (_currentUser == null || _chatId == null) return;

  final batch = FirebaseFirestore.instance.batch();
  final snaps = await FirebaseFirestore.instance
      .collection('chat_requests')
      .doc(_chatId!)
      .collection('messages')
      .where('senderId', isNotEqualTo: _currentUser!.uid)
      .where('read', isEqualTo: false)
      .get();

  for (final doc in snaps.docs) {
    batch.update(doc.reference, {'read': true});
  }
  await batch.commit();

  // Reset unreadCount in chat_requests
  await FirebaseFirestore.instance.collection('chat_requests').doc(_chatId!).update({
    'unreadCount': 0,
  });
}



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializeChat();
      updateLastActive();
     // saveFcmToken();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _hasText.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

  Future<void> _initializeChat() async {
    if (_currentUser == null) return;

    await _setSenderName();

    if (widget.requestId != null) {
      _chatId = widget.requestId;
      await _loadRecipientDetailsFromRequest();
    } else if (widget.providerId != null) {
      _chatId = await _createOrGetDirectChat(widget.providerId!);
      await _loadRecipientDetailsFromProvider();
    }
    if (_chatId != null) {
  await _markAllAsRead();
}
    setState(() {});
  }

  Future<void> _setSenderName() async {
    if (_currentUser == null) return;

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


String formatLastActive(DateTime? lastActive) {
  if (lastActive == null) return 'Offline';

  final now = DateTime.now();
  final diff = now.difference(lastActive);

  if (diff.inMinutes < 2) return 'Active now';
  if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Last seen yesterday';

  return 'Last seen ${DateFormat('MMM d').format(lastActive)}';
}


  Future<String> _createOrGetDirectChat(String providerId) async {
    var existingChats = await FirebaseFirestore.instance
        .collection('chat_requests')
        .where('userId', isEqualTo: _currentUser!.uid)
        .where('providerId', isEqualTo: providerId)
        .where('status', whereIn: ['pending', 'accepted'])
        .limit(1)
        .get();

    if (existingChats.docs.isNotEmpty) {
      return existingChats.docs.first.id;
    }

    var chatDoc = await FirebaseFirestore.instance.collection('chat_requests').add({
      'userId': _currentUser!.uid,
      'providerId': providerId,
      'status': 'pending',
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
      _recipientLastActive = provider?.lastActive; 
    } else if (_currentUser!.uid == providerId) {
      var userProfile = await _firestore.getUserProfile(userId);
      _recipientPhoneNumber = userProfile?.phoneNumber;
      _recipientName = userProfile?.name ?? 'Unknown User';
      _recipientProfilePicUrl = userProfile?.profilePicUrl;
      _recipientLastActive =  userProfile?.lastActive;
    }
    setState(() {});
  }

  Future<void> _loadRecipientDetailsFromProvider() async {
    var provider = await _firestore.getProviderProfile(widget.providerId!);
    _recipientPhoneNumber = provider?.phoneNumber;
    _recipientName = provider?.name ?? 'Unknown Provider';
    _recipientProfilePicUrl = provider?.profilePicUrl;
    _recipientLastActive = provider?.lastActive; 
    setState(() {});
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch phone call')),
      );
    }
  }

 Future<void> _sendMessage() async {
  if (_messageController.text.trim().isEmpty || _chatId == null || _currentUser == null) return;

  String _text  = _messageController.text.trim();
  _messageController.clear();

  final now = FieldValue.serverTimestamp();

  // 1️⃣ Send message
  await _firestore.sendMessage(_chatId!, _currentUser!.uid, _text);

  // 2️⃣ Update parent chat_requests document
  final chatRef = FirebaseFirestore.instance.collection('chat_requests').doc(_chatId!);
  final chatDoc = await chatRef.get();
  if (!chatDoc.exists) return;

  final receiverId = _currentUser!.uid == chatDoc['userId'] ? chatDoc['providerId'] : chatDoc['userId'];
  final prevUnread = chatDoc['unreadCount'] ?? 0;

  await chatRef.update({
    'lastMessage': _text,
    'lastMessageTime': now,
     'lastMessageAt': FieldValue.serverTimestamp(),
    'unreadCount': FieldValue.increment(1),
  });

 final userId = _currentUser!.uid;
  final String? providerId = chatDoc['providerId'] as String?;
  final String? recipientId = (userId == chatDoc['userId']) ? providerId : chatDoc['userId'];
 try {
    final recipientCollection = (userId == chatDoc['userId']) ? 'providers' : 'users';
    final recipientDoc = await FirebaseFirestore.instance.collection(recipientCollection).doc(recipientId).get();

    final playerId = recipientDoc['oneSignalSubscriptionId'] ?? recipientDoc['oneSignalPlayerId'];
    if (playerId != null && playerId.isNotEmpty) {
      await NotificationService.sendToSubscriptionIds(
        subscriptionIds: [playerId],
        title: 'New Message',
        body: '$_senderName: $_text',
        data: {
          'type': 'message',
          'chatId': _chatId,
          'senderId': userId,
        },
      );
    }
  } catch (e) {
    print('Error sending OneSignal push: $e');
  }
  // 3️⃣ Send FCM notification
  final receiverDoc = await FirebaseFirestore.instance
      .collection(_currentUser!.uid == chatDoc['userId'] ? 'providers' : 'users')
      .doc(receiverId)
      .get();
  final token = receiverDoc.data()?['fcmToken'] as String?;
  if (token != null) {
    await sendFcmNotificationV1(
      token: token,
      title: 'New Message',
      body: '$_senderName: $_text',
      type: 'message',
      id: _chatId,
      recipientUid: receiverId,
    );
  }
}


String messageDayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(date.year, date.month, date.day);

  if (msgDay == today) return 'Today';
  if (today.difference(msgDay).inDays == 1) return 'Yesterday';

  return DateFormat('MMM d, yyyy').format(date);
}

 


@override
Widget build(BuildContext context) {
  if (_chatId == null) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: const Center(child: CircularProgressIndicator(color: Color(0xFF26A69A))),
    );
  }

  return Scaffold(
    backgroundColor: const Color(0xFFF7F9FC),
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      shadowColor: Colors.black12,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
        onPressed: () => Navigator.pop(context, true),
      ),
      title: Row(
        children: [
          Hero(
            tag: 'recipient_avatar_${widget.requestId ?? widget.providerId}',
            child: CircleAvatar(
              radius: 18,
              backgroundImage: _recipientProfilePicUrl != null
                  ? NetworkImage(_recipientProfilePicUrl!)
                  : const AssetImage('assets/default_profile.png') as ImageProvider,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recipientName ?? 'Loading...',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              Text(
  formatLastActive(_recipientLastActive),
  style: GoogleFonts.poppins(
    fontSize: 12,
    color: formatLastActive(_recipientLastActive) == 'Active now'
        ? Colors.green
        : Colors.grey[600],
    fontWeight: FontWeight.w500,
  ),
),

              ],
            ),
          ),
        ],
      ),
      actions: [
        if (_recipientPhoneNumber != null)
          IconButton(
            icon: const Icon(Icons.call, color: Color(0xFF26A69A)),
            onPressed: () => _makePhoneCall(_recipientPhoneNumber!),
          ),
        const SizedBox(width: 8),
      ],
    ),

    body: Column(
      children: [
        // Messages List
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.getMessages(_chatId!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF26A69A)));
              }
              if (snapshot.hasData) {
  _markAllAsRead();
}

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No messages yet',
                        style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                      ),
                      Text(
                        'Say hi and start the conversation!',
                        style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }

             var messages = snapshot.data!.docs;
String? lastDayLabel;

         // final messages = snapshot.data!.docs;

return ListView.builder(
  reverse: true,
  controller: _scrollController,
  padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
  itemCount: messages.length,
  itemBuilder: (context, index) {
    final message = messages[index].data() as Map<String, dynamic>;
    final bool isMe = message['senderId'] == _currentUser!.uid;

    final Timestamp ts =
        (message['createdAt'] as Timestamp?) ??
        (message['timestamp'] as Timestamp?) ??
        Timestamp.now();

    final DateTime date = ts.toDate();
    final String dayLabel = messageDayLabel(date);

    String? previousDayLabel;
    if (index < messages.length - 1) {
      final prevMessage =
          messages[index + 1].data() as Map<String, dynamic>;

      final Timestamp prevTs =
          (prevMessage['createdAt'] as Timestamp?) ??
          (prevMessage['timestamp'] as Timestamp?) ??
          Timestamp.now();

      previousDayLabel = messageDayLabel(prevTs.toDate());
    }

    final bool showDayHeader = dayLabel != previousDayLabel;

    return Column(
      children: [
        if (showDayHeader)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                dayLabel,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

        _buildMessageBubble(
          text: message['text'],
          isMe: isMe,
          time: _formatTimestamp(ts),
          isRead: isMe ? (message['read'] == true) : true,
        ),
      ],
    );
  },
);


            },
          ),
        ),

        // Input Bar
        _buildMessageInput(),
      ],
    ),
  );
}

// ──────────────────────────────────────────────────────────────
// Beautiful Message Bubble
// ──────────────────────────────────────────────────────────────
Widget _buildMessageBubble({
  required String text,
  required bool isMe,
  required String time,
  required bool isRead,
}) {
  return Align(
    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF26A69A) : Colors.grey[100],
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
                bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  text,
                  style: GoogleFonts.poppins(
                    color: isMe ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: isMe ? Colors.white70 : Colors.grey[600],
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isRead ? Icons.done_all : Icons.done,
                        size: 14,
                        color: isRead ? Colors.white : Colors.white70,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ──────────────────────────────────────────────────────────────
// Modern Input Bar
// ──────────────────────────────────────────────────────────────
Widget _buildMessageInput() {
  final bool hasText = _messageController.text.trim().isNotEmpty;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
      ],
    ),
    child: SafeArea(
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                  border: InputBorder.none,
                ),
                style: GoogleFonts.poppins(),
             onChanged: (value) {
  _hasText.value = value.trim().isNotEmpty;
},

                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),

        ValueListenableBuilder<bool>(
  valueListenable: _hasText,
  builder: (_, hasText, __) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: hasText
          ? GestureDetector(
              key: const ValueKey('send'),
              onTap: _sendMessage,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Color(0xFF26A69A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            )
          : const SizedBox(
              key: ValueKey('empty'),
              width: 52,
              height: 52,
            ),
    );
  },
),

        ],
      ),
    ),
  );
}

// Helper: Format timestamp
String _formatTimestamp(Timestamp timestamp) {
  final date = timestamp.toDate();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDate = DateTime(date.year, date.month, date.day);

  if (msgDate == today) {
    return DateFormat('h:mm a').format(date);
  } else if (now.difference(date).inDays == 1) {
    return 'Yesterday';
  } else {
    return DateFormat('MMM d').format(date);
  }
}


}