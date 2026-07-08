import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:padue/core/browse_providers_state.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/roadside/models/provider.dart' as provider_model;
import 'package:padue/features/roadside/screens/inbox_screen.dart';
import 'package:padue/features/roadside/screens/notifications_screen.dart';
import 'package:padue/features/roadside/screens/provider_dashboard.dart';
import 'package:padue/features/roadside/screens/provider_profile_screen.dart'; // New import
import 'package:padue/features/roadside/screens/request_screen.dart';
import 'package:padue/features/roadside/screens/request_status.dart';
import 'package:padue/features/roadside/screens/subscription_screen.dart';
import 'package:padue/features/roadside/screens/user_profile_screen.dart';
import 'package:padue/features/auth/screens/profile_screen.dart';
import 'package:padue/features/settings/screens/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? profilePicUrl;
  final bool showNotifications;
  final bool isProvider;
  final Function(VoidCallback)? onInterstitialAd; // Optional ad callback

  const AppBarWidget({
    super.key,
    required this.title,
    this.profilePicUrl,
    this.showNotifications = true,
    this.isProvider = false,
    this.onInterstitialAd,
  });

static Future<void> clearAllCache() async {
  try {
    // 1. SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Removes role, welcome, etc.

    // 2. CachedNetworkImage
   // await CachedNetworkImage.evictAll();

    // 3. FlutterMap / Default Cache Manager (tiles)
   // await DefaultCacheManager().emptyCache();

    // 4. Firestore offline persistence (optional but safe)
  //  await FirebaseFirestore.instance.clearPersistence();

    print('All cache cleared on logout');
  } catch (e) {
    print('Cache clear error: $e');
  }
}

  Stream<int> _getUnreadNotificationsCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .where('type', isNotEqualTo: 'message')
        .snapshots()
        .map((snapshot) => snapshot.docs.length)
        .handleError((e) {
      print('Error fetching notifications count: $e');
      return 0;
    });
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
      ),
      leading: Builder(
        builder: (context) => IconButton(
          icon: CircleAvatar(
            radius: 16,
            backgroundImage: profilePicUrl != null && profilePicUrl!.isNotEmpty
                ? NetworkImage(profilePicUrl!)
                : const AssetImage('assets/default_profile.png') as ImageProvider,
            backgroundColor: Colors.grey[300],
          ),
          onPressed: () {
            if (onInterstitialAd != null) {
              onInterstitialAd!(() {
                Scaffold.of(context).openDrawer();
              });
            } else {
              Scaffold.of(context).openDrawer();
            }
          },
        ),
      ),
      actions: [
        if (showNotifications)
  StreamBuilder<int>(
    stream: _getUnreadNotificationsCount(),
    initialData: 0,
    builder: (context, snapshot) {
      int unreadCount = snapshot.data ?? 0;

      void openNotifications() {
        if (onInterstitialAd != null) {
          onInterstitialAd!(() {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NotificationsScreen(isProvider: isProvider),
              ),
            );
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NotificationsScreen(isProvider: isProvider),
            ),
          );
        }
      }

      return GestureDetector(
        onTap: openNotifications,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications, color: Color(0xFFFF6200)),
              tooltip: 'Notifications',
              onPressed: openNotifications,
            ),
            if (unreadCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  ),
       if (ModalRoute.of(context)?.settings.name == '/browse_providers' ||
      ModalRoute.of(context)?.settings.name == '/browse_providers_map')
    Consumer<BrowseProvidersState>(
      builder: (context, state, _) => IconButton(
        icon: const Icon(Icons.tune_rounded, color: Color(0xFFFF6200)),
        tooltip: 'Filters',
        onPressed: () => state.showFilterDialog(context),
      ),
    ),
      ],
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
    );
  }

  static Widget buildDrawer({
    required BuildContext context,
    required bool isProvider,
    Function(VoidCallback)? onInterstitialAd,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    final firestore = FirestoreService();

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFFFF6200),
            ),
          child: FutureBuilder<dynamic>(
              future: user != null
                  ? (isProvider
                      ? FirebaseFirestore.instance.collection('providers').doc(user.uid).get()
                      : firestore.getUserProfile(user.uid))
                  : Future.value(null),
              builder: (context, snapshot) {
                String displayName = 'User';
                String email = '';
                String? photoUrl;

                if (snapshot.hasData && snapshot.data != null) {
                  if (isProvider) {
                    // Handle provider data
                    final doc = snapshot.data as DocumentSnapshot;
                    if (doc.exists) {
                      final provider = provider_model.Provider.fromFirestore(doc);
                      displayName = provider.name ?? 'Provider';
                      photoUrl = provider.profilePicUrl;
                    //  email = provider.email ?? ''; // Adjust based on Provider model
                    }
                  } else {
                    // Handle user data
                    final userProfile = snapshot.data as UserProfile?;
                    if (userProfile != null) {
                      displayName = userProfile.name ?? 'User';
                      photoUrl = userProfile.profilePicUrl;
                    //  email = userProfile.email ?? '';
                    }
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl)
                          : const AssetImage('assets/default_profile.png') as ImageProvider,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Color(0xFFFF6200)),
            title: const Text('Home'),
            onTap: () {
              if (onInterstitialAd != null) {
                onInterstitialAd!(() {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => isProvider
                          ? ProviderDashboard()
                          :  RequestScreen(),
                    ),
                  );
                });
              } else {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => isProvider
                        ? ProviderDashboard()
                        :  RequestScreen(),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Color(0xFFFF6200)),
            title: const Text('My Profile'),
            onTap: () {
              if (onInterstitialAd != null) {
                onInterstitialAd!(() {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => isProvider
                          ? ProviderProfileScreen()
                          :  ProfileScreen(),
                    ),
                  );
                });
              } else {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => isProvider
                        ? ProviderProfileScreen()
                        :  ProfileScreen(),
                  ),
                );
              }
            },
          ),
          if (!isProvider) // Hide "My Requests" for providers
            ListTile(
              leading: const Icon(Icons.list_alt, color: Color.fromARGB(255, 241, 151, 95)),
              title: const Text('My Requests'),
              onTap: () {
                if (onInterstitialAd != null) {
                  onInterstitialAd!(() {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RequestStatusScreen(),
                      ),
                    );
                  });
                } else {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RequestStatusScreen(),
                    ),
                  );
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.subscriptions, color: Color(0xFFFF6200)),
            title: const Text('Subscription'),
            onTap: () {
              if (onInterstitialAd != null) {
                onInterstitialAd!(() {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SubscriptionScreen(),
                    ),
                  );
                });
              } else {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SubscriptionScreen(),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.inbox, color: Color(0xFFFF6200)),
            title: const Text('Inbox'),
            onTap: () {
              if (onInterstitialAd != null) {
                onInterstitialAd!(() {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => InboxScreen(isProvider: isProvider),
                    ),
                  );
                });
              } else {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InboxScreen(isProvider: isProvider),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Color(0xFFFF6200)),
            title: const Text('Settings'),
            onTap: () {
              if (onInterstitialAd != null) {
                onInterstitialAd!(() {
                  Navigator.pop(context);
                   Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsScreen(isProvider: isProvider),
                  ),
                );
                });
              } else {
                Navigator.pop(context);
                 Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsScreen(isProvider: isProvider),
                  ),
                );
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              if (onInterstitialAd != null) {
                onInterstitialAd!(() async {
                    await clearAllCache(); // ← ADD THIS
                  await FirebaseAuth.instance.signOut();
                  Navigator.pop(context);
                  Navigator.pushReplacementNamed(context, '/welcome');
                });
              } else {
                  await clearAllCache(); // ← ADD THIS
                await FirebaseAuth.instance.signOut();
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/welcome');
              }
            },
          ),
        ],
      ),
    );
  }
}