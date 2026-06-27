import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:padue/features/roadside/screens/inbox_screen.dart';
import 'package:padue/features/roadside/screens/notifications_screen.dart';
import 'package:padue/features/roadside/screens/provider_dashboard.dart';
import 'package:padue/features/roadside/screens/provider_profile_screen.dart';
import 'package:padue/features/roadside/screens/subscription_screen.dart';
import 'package:padue/features/roadside/screens/forum_screen.dart';

class ProviderBottomNavBar extends StatelessWidget {
  final int currentIndex;

  const ProviderBottomNavBar({
    super.key,
    required this.currentIndex,
  });



  Stream<int> _getUnreadCount() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collection('chat_requests')
      .where('providerId', isEqualTo: user.uid)
      .where('status', whereIn: ['pending', 'accepted'])
      .snapshots()
      .map((snapshot) {
        // Sum unreadCount from each chat (already maintained in chat_requests)
        int unread = 0;
        for (var doc in snapshot.docs) {
          unread += ((doc['unreadCount'] ?? 0) as int);
          if (doc['status'] == 'pending') unread++; // optional: count pending chats as 1 unread
        }
        return unread;
      }).handleError((e) => 0);
}
 /**  Stream<int> _getUnreadCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('chat_requests')
        .where('providerId', isEqualTo: user.uid)
        .where('status', whereIn: ['pending', 'accepted'])
        .snapshots()
        .asyncMap((snapshot) async {
          int unreadCount = 0;
          for (var chat in snapshot.docs) {
            var messages = await FirebaseFirestore.instance
                .collection('chat_requests')
                .doc(chat.id)
                .collection('messages')
                .where('senderId', isNotEqualTo: user.uid)
                .where('read', isEqualTo: false)
                .get();
            unreadCount += messages.docs.length;
          //  unreadCount += snapshot.docs.where((doc) => doc['status'] == 'pending').length;
          }
          return unreadCount;
        }).handleError((e) => 0);
  }*/

  Stream<int> _getUnreadNotificationsCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('providers')
        .doc(user.uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .where('type', isNotEqualTo: 'message')
        .snapshots()
        .map((snapshot) => snapshot.docs.length)
        .handleError((e) => 0);
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.home, size: 26),
          label: 'Home',
        ),
          const BottomNavigationBarItem(
          icon: Icon(Icons.person, size: 26),
          label: 'Profile',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.forum, size: 26),
          label: 'Forum',
        ),
        BottomNavigationBarItem(
          icon: StreamBuilder<int>(
            stream: _getUnreadCount(),
            initialData: 0,
            builder: (context, snapshot) {
              int unreadCount = snapshot.data ?? 0;
              return Stack(
                children: [
                  const Icon(Icons.message, size: 26),
                  if (unreadCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
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
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          label: 'Inbox',
        ),
       
     
       
      ],
      currentIndex: currentIndex,
      selectedItemColor: Color(0xFFFF6200),
      unselectedItemColor: Colors.grey[600],
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      onTap: (index) {
        Widget targetScreen;
        switch (index) {
          case 0:
            targetScreen = const ProviderDashboard();
            break;
                  case 1:
            targetScreen = const ProviderProfileScreen();
            break;
          case 2:
            targetScreen =  ForumScreen(isProvider: true);
            break;
          case 3:
            targetScreen =  InboxScreen(isProvider: true);
            break;
        
    
        
          default:
            return;
        }
        if (currentIndex != index) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => targetScreen),
          );
        }
      },
    );
  }
}