import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/roadside/screens/banner_ad_widget.dart';
import 'package:padue/features/roadside/screens/bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/provider_bottom_nav_bar.dart';
import 'chat_screen.dart';

class InboxScreen extends StatefulWidget {
  final bool isProvider;
  const InboxScreen({super.key, this.isProvider = false});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isLoading = true;
  bool _isAdFree = false;
  String? profilePicUrl;
  String _searchQuery = '';

  /// CACHES
  final Map<String, Map<String, dynamic>> _profileCache = {};
  final Set<String> _loadingProfiles = {};

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      _searchQuery = _searchController.text.toLowerCase();
      setState(() {});
    });

    _loadUserProfile();
    _setupNotifications();

    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null) {
        _showNotification(message);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /* ───────────────────── NOTIFICATIONS ───────────────────── */

  Future<void> _setupNotifications() async {
    const channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
    );

    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _showNotification(RemoteMessage message) {
    final n = message.notification!;
    _notifications.show(
      n.hashCode,
      n.title,
      n.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /* ───────────────────── PROFILE ───────────────────── */

Future<void> _loadUserProfile() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    if (mounted) setState(() => _isLoading = false);
    return;
  }

  try {
    final doc = await FirebaseFirestore.instance
        .collection(widget.isProvider ? 'providers' : 'users')
        .doc(user.uid)
        .get();

    if (mounted) {
      setState(() {
        _isAdFree = doc.data()?['adFree'] ?? false;
        profilePicUrl = doc.data()?['profilePicUrl'];
        _isLoading = false; // ← ADD THIS HERE (critical)
      });
    }
  } catch (e) {
    debugPrint('Profile load error: $e');
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

  Future<void> _loadProfileOnce(String uid, bool isProvider) async {
    if (_profileCache.containsKey(uid) || _loadingProfiles.contains(uid)) {
      return;
    }

    _loadingProfiles.add(uid);

    final doc = await FirebaseFirestore.instance
        .collection(isProvider ? 'providers' : 'users')
        .doc(uid)
        .get();

    _profileCache[uid] = doc.data() ??
        {
          'name': 'Unknown',
          'profilePicUrl': null,
        };

    _loadingProfiles.remove(uid);

    if (mounted) setState(() {});
  }

  /* ───────────────────── CHAT ACTIONS ───────────────────── */

  Future<void> _openChat(String chatId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final unreadSnap = await FirebaseFirestore.instance
        .collection('chat_requests')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final d in unreadSnap.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(requestId: chatId),
      ),
    );
  }

  Future<void> _archiveChat(String chatId) async {
    await FirebaseFirestore.instance
        .collection('chat_requests')
        .doc(chatId)
        .update({'status': 'archived'});
  }

  /* ───────────────────── UI ───────────────────── */

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please sign in')));
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBarWidget(
        title: 'Inbox',
        profilePicUrl: profilePicUrl,
        showNotifications: true,
        isProvider: widget.isProvider,
      ),
      drawer:
          AppBarWidget.buildDrawer(context: context, isProvider: widget.isProvider),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6200)),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search conversations...',
                      prefixIcon:
                          const Icon(Icons.search, color: Color(0xFFFF6200)),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chat_requests')
                        .where(widget.isProvider ? 'providerId' : 'userId',
                            isEqualTo: user.uid)
                        .where('status', whereIn: ['pending', 'accepted'])
                        .orderBy('lastMessageAt', descending: true)
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFFF6200)),
                        );
                      }

                      final chats = snap.data!.docs.where((doc) {
                        final otherId = widget.isProvider
                            ? doc['userId']
                            : doc['providerId'];
                        return otherId
                                .toString()
                                .toLowerCase()
                                .contains(_searchQuery) ||
                            doc.id.toLowerCase().contains(_searchQuery);
                      }).toList();

                      if (chats.isEmpty) return _emptyState();

                      /// preload profiles ONCE
                      for (final chat in chats) {
                        final otherId = widget.isProvider
                            ? chat['userId']
                            : chat['providerId'];
                        _loadProfileOnce(otherId, !widget.isProvider);
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(0),
                        itemCount: chats.length,
                        itemBuilder: (context, i) {
                          final chat = chats[i];
                          final chatId = chat.id;
                          final otherId = widget.isProvider
                              ? chat['userId']
                              : chat['providerId'];

                          final profile = _profileCache[otherId] ??
                              {'name': 'Loading...', 'profilePicUrl': null};

                          return KeyedSubtree(
                            key: ValueKey(chatId),
                            child: Dismissible(
                              key: ValueKey('$chatId-dismiss'),
                              background:
                                  _swipeBg(Colors.orange, Icons.archive, 'Archive'),
                              secondaryBackground:
                                  _swipeBg(Colors.red, Icons.delete, 'Delete'),
                              onDismissed: (d) {
                                if (d == DismissDirection.startToEnd) {
                                  _archiveChat(chatId);
                                } else {
                                  FirebaseFirestore.instance
                                      .collection('chat_requests')
                                      .doc(chatId)
                                      .delete();
                                }
                              },
                              child: _chatTile(
                                name: profile['name'],
                                pic: profile['profilePicUrl'],
                                lastMessage:
                                    chat['lastMessage'] ?? 'Sent a message',
                                time: (chat['lastMessageTime'] as Timestamp?)
                                        ?.toDate() ??
                                    DateTime.now(),
                                unread: chat['unreadCount'] ?? 0,
                                onTap: () => _openChat(chatId),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isAdFree) const BannerAdWidget(),
          widget.isProvider
              ? const ProviderBottomNavBar(currentIndex: 3)
              : const BottomNavBar(currentIndex: 3),
        ],
      ),
    );
  }

  /* ───────────────────── COMPONENTS ───────────────────── */

  Widget _chatTile({
    required String name,
    required String? pic,
    required String lastMessage,
    required DateTime time,
    required int unread,
    required VoidCallback onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 26,
          backgroundImage: pic != null
              ? NetworkImage(pic)
              : const AssetImage('assets/default_profile.png')
                  as ImageProvider,
        ),
        title: Text(name,
            style: GoogleFonts.poppins(
                fontWeight:
                    unread > 0 ? FontWeight.w600 : FontWeight.w500)),
        subtitle: Text(lastMessage,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: unread > 0
            ? CircleAvatar(
                radius: 12,
                backgroundColor: const Color(0xFFFF6200),
                child: Text('$unread',
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              )
            : null,
      ),
    );
  }

  Widget _swipeBg(Color c, IconData i, String t) {
    return Container(
      color: c,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(i, color: Colors.white),
          Text(t, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text('No conversations yet'),
        ],
      ),
    );
  }
}
