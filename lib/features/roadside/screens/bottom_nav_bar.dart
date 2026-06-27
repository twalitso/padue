import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:padue/features/roadside/screens/inbox_screen.dart';
import 'package:padue/features/roadside/screens/notifications_screen.dart';
import 'package:padue/features/roadside/screens/forum_screen.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final bool isProvider;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    this.isProvider = false,
  });



Stream<int> _globalUnreadCount() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collection('chat_requests')
      .where('userId', isEqualTo: user.uid)
      .where('status', whereIn: ['pending', 'accepted'])
      .snapshots()
      .asyncMap((chatSnap) async {
        int total = 0;
        for (final chat in chatSnap.docs) {
          final msgs = await chat.reference
              .collection('messages')
              .where('senderId', isNotEqualTo: user.uid)
              .where('read', isEqualTo: false)
              .get();
          total += msgs.docs.length;
        }
        // also count pending requests (optional)
    //    total += chatSnap.docs.where((c) => c['status'] == 'pending').length;
        return total;
      });
}

  Stream<int> _getUnreadCount() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collection('chat_requests')
      .where('userId', isEqualTo: user.uid)
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
        .handleError((e) => 0);
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      items: [
        BottomNavigationBarItem(
          icon: Icon(Icons.home, size: 26),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.search_rounded, size: 26),
          label: 'Browse',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.forum_rounded, size: 26),
          label: 'Forum',
        ),
        BottomNavigationBarItem(
          icon:StreamBuilder<int>(
  stream: _globalUnreadCount(),
  builder: (context, snap) {
    final count = snap.data ?? 0;
    return Stack(
      children: [
        const Icon(Icons.message, size: 26),
        if (count > 0)
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
                count > 99 ? '99+' : count.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  },
),
          label: 'inbox',
        ),
        
       
      ],
      currentIndex: currentIndex,
      selectedItemColor: Color(0xFFFF6200),
      unselectedItemColor: Colors.grey[600],
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      onTap: (index) {
        switch (index) {
          case 0:
            Navigator.pushNamed(context, '/request');
            break;
          case 1:
            Navigator.pushNamed(context, '/browse_providers');
            break;
          case 2:
           // Navigator.pushNamed(context, '/forum');
             Navigator.push(context, MaterialPageRoute(builder: (context) => ForumScreen(isProvider: false)));
            break;
          case 3:
            Navigator.push(context, MaterialPageRoute(builder: (context) => InboxScreen(isProvider: false)));
            break;
          case 4:
            Navigator.push(context, MaterialPageRoute(builder: (context) => NotificationsScreen(isProvider: false)));
            break;
          case 5:
            Navigator.pushNamed(context, '/request_status');
            break;
        }
      },
    );
  }
}