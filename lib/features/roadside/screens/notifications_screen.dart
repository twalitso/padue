import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/roadside/screens/banner_ad_widget.dart';
import 'package:padue/features/roadside/screens/post_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final bool isProvider;
  const NotificationsScreen({super.key, required this.isProvider});

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isAdFree = false;
  String? profilePicUrl;
  bool _isProviderUser = false;

  @override
  void initState() {
    super.initState();
    _loadProfile(); // Fire-and-forget, don't block UI
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    try {
      // Single read: try providers first
      final providerDoc = await FirebaseFirestore.instance
          .collection('providers')
          .doc(user.uid)
          .get();

      if (providerDoc.exists && mounted) {
        final data = providerDoc.data()!;
        setState(() {
          _isAdFree = data['adFree'] ?? false;
          _isProviderUser = true;
          profilePicUrl = data['profilePicUrl'];
        });
        return;
      }

      // Fall back to users
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (mounted) {
        setState(() {
          _isAdFree = userDoc.exists ? (userDoc.data()?['adFree'] ?? false) : false;
          _isProviderUser = false;
          profilePicUrl = userDoc.data()?['profilePicUrl'];
        });
      }
    } catch (e) {
      debugPrint('Profile load error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    final collection = widget.isProvider ? 'providers' : 'users';

    return Scaffold(
      appBar: AppBarWidget(
        title: 'Notifications',
        profilePicUrl: profilePicUrl,
        showNotifications: true,
        isProvider: widget.isProvider,
      ),
      drawer: AppBarWidget.buildDrawer(
        context: context,
        isProvider: widget.isProvider,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Simpler query: no isNotEqualTo, filter in code
        stream: FirebaseFirestore.instance
            .collection(collection)
            .doc(user.uid)
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          // Filter out messages in code (faster than isNotEqualTo query)
          final allDocs = snapshot.data?.docs ?? [];
          final notifications = allDocs
              .where((n) => (n.data() as Map<String, dynamic>)['type'] != 'message')
              .toList();

          if (notifications.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No notifications yet'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final data = notification.data() as Map<String, dynamic>;
              return _NotificationTile(
                data: data,
                onTap: () => _handleNotificationTap(context, data, notification),
              );
            },
          );
        },
      ),
      bottomNavigationBar: !_isAdFree ? const BannerAdWidget() : null,
    );
  }

  Future<void> _handleNotificationTap(
    BuildContext context,
    Map<String, dynamic> data,
    DocumentSnapshot doc,
  ) async {
    await doc.reference.update({'read': true});
    final type = data['type'] as String?;
    final id = data['id'] as String?;

    switch (type) {
      case 'request':
      case 'status_update':
        Navigator.pushNamed(
          context,
          widget.isProvider ? '/provider_dashboard' : '/request_status',
        );
      case 'profile_update':
        Navigator.pushNamed(
          context,
          widget.isProvider ? '/provider_profile' : '/profile',
        );
      case 'payment':
        Navigator.pushNamed(context, '/subscription');
      case 'comment':
      case 'like':
        if (id != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PostDetailScreen(postId: id)),
          );
        }
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tapped: ${data['title']}')),
        );
    }
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _NotificationTile({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: data['read'] == true ? Colors.grey[300] : Colors.blue[100],
          child: Icon(
            _iconForType(data['type']),
            color: data['read'] == true ? Colors.grey : Colors.blue,
            size: 20,
          ),
        ),
        title: Text(
          data['title'] ?? 'No Title',
          style: TextStyle(
            fontWeight: data['read'] == true ? FontWeight.normal : FontWeight.bold,
          ),
        ),
        subtitle: Text(data['body'] ?? 'No Body'),
        trailing: data['read'] == true
            ? null
            : Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
        onTap: onTap,
      ),
    );
  }

  IconData _iconForType(String? type) {
    return switch (type) {
      'request' => Icons.local_taxi,
      'status_update' => Icons.update,
      'payment' => Icons.payment,
      'comment' => Icons.comment,
      'like' => Icons.favorite,
      _ => Icons.notifications,
    };
  }
}