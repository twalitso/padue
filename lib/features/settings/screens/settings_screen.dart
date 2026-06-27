// lib/features/settings/screens/settings_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  final bool isProvider;

  const SettingsScreen({
    super.key,
    this.isProvider = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  bool _pushNotifications = true;
  bool _messageNotifications = true;
  bool _marketingNotifications = false;
  bool _darkMode = false;
  bool _locationSharing = true;
  bool _isDeleting = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  User? get _user => _auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {

    final prefs =
        await SharedPreferences.getInstance();

    setState(() {

      _pushNotifications =
          prefs.getBool(
              'push_notifications') ?? true;

      _messageNotifications =
          prefs.getBool(
              'message_notifications') ?? true;

      _marketingNotifications =
          prefs.getBool(
              'marketing_notifications') ?? false;

      _darkMode =
          prefs.getBool('dark_mode') ?? false;

      _locationSharing =
          prefs.getBool(
              'location_sharing') ?? true;

    });
  }

  Future<void> _saveSetting(
      String key,
      bool value) async {

    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setBool(key, value);
  }

  Future<void> _logout() async {

    final prefs =
        await SharedPreferences.getInstance();

    await prefs.clear();

    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/welcome',
      (route) => false,
    );
  }

  Future<void> _showDeleteAccountDialog() async {

    final passwordController =
        TextEditingController();

    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {

        return AlertDialog(

          title: const Text(
              'Delete Account'),

          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                const Text(
                  'This action is permanent.\n\n'
                  'Your profile, requests, chats, '
                  'subscriptions, and provider data '
                  'may be removed or anonymized.',
                ),

                const SizedBox(height: 20),

                TextFormField(
                  controller:
                      passwordController,
                  obscureText: true,
                  decoration:
                      const InputDecoration(
                    labelText: 'Password',
                    border:
                        OutlineInputBorder(),
                  ),
                  validator: (value) {

                    if (value == null ||
                        value.isEmpty) {
                      return 'Enter password';
                    }

                    return null;
                  },
                ),
              ],
            ),
          ),

          actions: [

            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () {

                if (!formKey.currentState!
                    .validate()) {
                  return;
                }

                Navigator.pop(context, true);
              },
              child: const Text(
                'Delete',
                style: TextStyle(
                    color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _deleteAccount(
      passwordController.text.trim(),
    );
  }

  Future<void> _deleteAccount(
      String password) async {

    try {

      setState(() {
        _isDeleting = true;
      });

      final user = _user;

      if (user == null) {
        throw Exception('No user found');
      }

      final email = user.email;

      if (email == null) {
        throw Exception('No email found');
      }

      // Reauthenticate
      final credential =
          EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      await user.reauthenticateWithCredential(
          credential);

      // Soft delete Firestore profile
      final collection = widget.isProvider
          ? 'providers'
          : 'users';

      await _firestore
          .collection(collection)
          .doc(user.uid)
          .set({

        'deleted': true,
        'deletedAt':
            FieldValue.serverTimestamp(),

        'email': null,
        'phone': null,
        'profilePicUrl': null,

      }, SetOptions(merge: true));

      // Delete auth account
      await user.delete();

      final prefs =
          await SharedPreferences.getInstance();

      await prefs.clear();

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
              Text('Account deleted'),
        ),
      );

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/welcome',
        (route) => false,
      );

    } on FirebaseAuthException catch (e) {

      String message =
          'Failed to delete account';

      if (e.code == 'wrong-password') {
        message = 'Incorrect password';
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(content: Text(message)),
      );

    } catch (e) {

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(content: Text(e.toString())),
      );

    } finally {

      if (!mounted) return;

      setState(() {
        _isDeleting = false;
      });
    }
  }

  Widget _buildSectionTitle(String title) {

    return Padding(
      padding: const EdgeInsets.only(
        left: 16,
        top: 24,
        bottom: 8,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Color? color,
    Widget? trailing,
  }) {

    return ListTile(
      leading: Icon(
        icon,
        color: color ?? Colors.orange,
      ),
      title: Text(title),
      subtitle:
          subtitle != null
              ? Text(subtitle)
              : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text('Settings'),
      ),

      body: ListView(

        children: [

          // ACCOUNT
          _buildSectionTitle('ACCOUNT'),

          _buildTile(
            icon: Icons.person,
            title: 'Edit Profile',
            onTap: () {
              Navigator.pushNamed(
                  context,
                  '/profile');
            },
          ),

          _buildTile(
            icon: Icons.lock,
            title: 'Change Password',
            onTap: () async {

              final email =
                  _user?.email;

              if (email == null) return;

              await FirebaseAuth.instance
                  .sendPasswordResetEmail(
                      email: email);

              if (!mounted) return;

              ScaffoldMessenger.of(context)
                  .showSnackBar(
                SnackBar(
                  content: Text(
                    'Password reset sent to $email',
                  ),
                ),
              );
            },
          ),

          // PROVIDER SETTINGS
          if (widget.isProvider) ...[

            _buildSectionTitle(
                'PROVIDER'),

            _buildTile(
              icon: Icons.toggle_on,
              title: 'Availability',
              subtitle:
                  'Manage online/offline status',
              onTap: () {},
            ),

            _buildTile(
              icon: Icons.location_on,
              title: 'Service Radius',
              subtitle:
                  'Adjust coverage distance',
              onTap: () {},
            ),

            _buildTile(
              icon: Icons.build,
              title: 'Services Offered',
              subtitle:
                  'Update your services',
              onTap: () {},
            ),
          ],

          // NOTIFICATIONS
          _buildSectionTitle(
              'NOTIFICATIONS'),

          SwitchListTile(
            secondary: const Icon(
              Icons.notifications,
              color: Colors.orange,
            ),
            title:
                const Text('Push Notifications'),
            value: _pushNotifications,
            onChanged: (value) {

              setState(() {
                _pushNotifications = value;
              });

              _saveSetting(
                  'push_notifications',
                  value);
            },
          ),

          SwitchListTile(
            secondary: const Icon(
              Icons.message,
              color: Colors.orange,
            ),
            title: const Text(
                'Message Notifications'),
            value:
                _messageNotifications,
            onChanged: (value) {

              setState(() {
                _messageNotifications =
                    value;
              });

              _saveSetting(
                  'message_notifications',
                  value);
            },
          ),

          SwitchListTile(
            secondary: const Icon(
              Icons.campaign,
              color: Colors.orange,
            ),
            title: const Text(
                'Marketing Notifications'),
            value:
                _marketingNotifications,
            onChanged: (value) {

              setState(() {
                _marketingNotifications =
                    value;
              });

              _saveSetting(
                  'marketing_notifications',
                  value);
            },
          ),

          // PRIVACY
          _buildSectionTitle(
              'PRIVACY & SECURITY'),

          SwitchListTile(
            secondary: const Icon(
              Icons.location_history,
              color: Colors.orange,
            ),
            title:
                const Text('Location Sharing'),
            value: _locationSharing,
            onChanged: (value) {

              setState(() {
                _locationSharing = value;
              });

              _saveSetting(
                  'location_sharing',
                  value);
            },
          ),

          _buildTile(
            icon: Icons.privacy_tip,
            title: 'Privacy Policy',
            onTap: () {},
          ),

          _buildTile(
            icon: Icons.description,
            title: 'Terms of Service',
            onTap: () {},
          ),

          // APP
          _buildSectionTitle('APP'),

          SwitchListTile(
            secondary: const Icon(
              Icons.dark_mode,
              color: Colors.orange,
            ),
            title: const Text('Dark Mode'),
            value: _darkMode,
            onChanged: (value) {

              setState(() {
                _darkMode = value;
              });

              _saveSetting(
                  'dark_mode',
                  value);
            },
          ),

          _buildTile(
            icon: Icons.cleaning_services,
            title: 'Clear Cache',
            onTap: () async {

              final prefs =
                  await SharedPreferences
                      .getInstance();

              await prefs.clear();

              if (!mounted) return;

              ScaffoldMessenger.of(context)
                  .showSnackBar(
                const SnackBar(
                  content:
                      Text('Cache cleared'),
                ),
              );
            },
          ),

          _buildTile(
            icon: Icons.info,
            title: 'App Version',
            subtitle: '1.0.0',
          ),

          // SUPPORT
          _buildSectionTitle('SUPPORT'),

          _buildTile(
            icon: Icons.help,
            title: 'Help Center',
            onTap: () {},
          ),

          _buildTile(
            icon: Icons.support_agent,
            title: 'Contact Support',
            onTap: () {},
          ),

          _buildTile(
            icon: Icons.bug_report,
            title: 'Report Problem',
            onTap: () {},
          ),

          // DANGER ZONE
          _buildSectionTitle(
              'DANGER ZONE'),

          _buildTile(
            icon: Icons.logout,
            title: 'Logout',
            color: Colors.red,
            onTap: _logout,
          ),

          _buildTile(
            icon: Icons.delete_forever,
            title: 'Delete Account',
            subtitle:
                'Permanently delete account',
            color: Colors.red,
            trailing: _isDeleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : null,
            onTap:
                _isDeleting
                    ? null
                    : _showDeleteAccountDialog,
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}