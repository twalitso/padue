import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/roadside/screens/banner_ad_widget.dart';
import 'package:padue/features/roadside/screens/bottom_nav_bar.dart';
import 'package:padue/features/roadside/screens/post_detail_screen.dart';
import 'package:padue/features/roadside/screens/provider_bottom_nav_bar.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/features/roadside/models/provider.dart';

class NotificationsScreen extends StatefulWidget {
  final bool isProvider;

  const NotificationsScreen({super.key, required this.isProvider});

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isAdFree = false;
  bool _isLoading = true;
   dynamic profile;
  String? profilePicUrl;
   bool _isProviderUser = false;
    final FirestoreService _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _isLoading = true);
      var providerDoc = await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();
      if (providerDoc.exists && mounted) {
        Provider provider = Provider.fromFirestore(providerDoc);
         final providerProfile = await _firestore.getProviderProfile(user.uid);
        setState(() {
          _isAdFree = provider.adFree;
          _isLoading = false;

            _isProviderUser = true;
      
        profile = providerProfile;
        profilePicUrl = providerProfile?.profilePicUrl ?? provider.profilePicUrl;
        });
      } else {
        var userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final userProfile = await _firestore.getUserProfile(user.uid);
        setState(() {
          _isAdFree = userDoc.exists ? (userDoc.data()?['adFree'] ?? false) : false;
          _isLoading = false;

           _isProviderUser = false;
      
        profile = userProfile;
        profilePicUrl = profile?.profilePicUrl;
        });
      }
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
           title:  'Notifications',
        profilePicUrl:profilePicUrl,
        showNotifications: true,
       isProvider: widget.isProvider,
        ),
        drawer: AppBarWidget.buildDrawer(
        context: context,
        isProvider: widget.isProvider,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(collection)
                  .doc(user.uid)
                  .collection('notifications')
                  .where('type', isNotEqualTo: 'message')
                  .orderBy('type')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error loading notifications: ${snapshot.error}'));
                }

                final notifications = snapshot.data?.docs ?? [];

                if (notifications.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications yet',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey),
                        ),
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
                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(data['title'] ?? 'No Title', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(data['body'] ?? 'No Body'),
                        trailing: data['read'] == true
                            ? null
                            : const Icon(Icons.circle, color: Colors.blue, size: 10),
                        onTap: () async {
                          await notification.reference.update({'read': true});
                          final type = data['type'] as String?;
                          final id = data['id'] as String?;

                          switch (type) {
                            case 'request':
                            case 'status_update':
                              if (id != null) {
                                Navigator.pushNamed(
                                  context,
                                  widget.isProvider ? '/provider_dashboard' : '/request_status',
                                );
                              }
                              break;
                            case 'profile_update':
                              Navigator.pushNamed(
                                context,
                                widget.isProvider ? '/provider_profile' : '/profile',
                              );
                              break;
                            case 'payment':
                              Navigator.pushNamed(context, '/subscription');
                              break;
                            case 'comment':
                            case 'like':
                              if (id != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PostDetailScreen(postId: id),
                                  ),
                                );
                              }
                              break;
                            default:
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Tapped: ${data['title']}')),
                              );
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isAdFree) const BannerAdWidget(),
        /**   widget.isProvider
              ? const ProviderBottomNavBar(currentIndex: 3)
              : const BottomNavBar(currentIndex: 3),*/
        ],
      ),
    );
  }
}