import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationsScreen extends StatelessWidget {
  final bool isProvider;

  const NotificationsScreen({required this.isProvider});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Scaffold(body: Center(child: Text('Not logged in')));

    final collection = isProvider ? 'providers' : 'users';

    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, isProvider ? Colors.purple : Colors.blueAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection(collection)
            .doc(user.uid)
            .collection('notifications')
            .where('type', isNotEqualTo: 'message') // Filter out message notifications
            .orderBy('type') // Required due to Firestore rules when using isNotEqualTo
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          final notifications = snapshot.data!.docs;

          if (notifications.isEmpty) {
            return Center(child: Text('No notifications yet'));
          }

          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final data = notification.data() as Map<String, dynamic>;
              return Card(
                elevation: 4,
                margin: EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  title: Text(data['title'] ?? 'No Title'),
                  subtitle: Text(data['body'] ?? 'No Body'),
                  trailing: data['read'] == true
                      ? null
                      : Icon(Icons.circle, color: Colors.blue, size: 10),
                  onTap: () async {
                    await notification.reference.update({'read': true});
                    final type = data['type'] as String?;
                    final id = data['id'] as String?;

                    switch (type) {
                      case 'request':
                        if (id != null) {
                          if (isProvider) {
                            Navigator.pushNamed(context, '/provider_dashboard');
                          } else {
                            Navigator.pushNamed(context, '/request_status');
                          }
                        }
                        break;

                      case 'status_update':
                        if (id != null) {
                          if (isProvider) {
                            Navigator.pushNamed(context, '/provider_dashboard');
                          } else {
                            Navigator.pushNamed(context, '/request_status');
                          }
                        }
                        break;

                      case 'profile_update':
                        Navigator.pushNamed(context, isProvider ? '/provider_profile' : '/profile');
                        break;

                      case 'payment':
                        Navigator.pushNamed(context, '/subscription');
                        break;

                      default:
                        // Handle unknown non-message types
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Tapped: ${data['title']}')),
                        );
                        break;
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}