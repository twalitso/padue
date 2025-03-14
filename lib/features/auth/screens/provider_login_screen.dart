import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/auth_service.dart';
import '../../../core/firestore_service.dart';
import '../../roadside/models/provider.dart';

class ProviderLoginScreen extends StatefulWidget {
  @override
  _ProviderLoginScreenState createState() => _ProviderLoginScreenState();
}

class _ProviderLoginScreenState extends State<ProviderLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(); // Add this
  final _authService = AuthService();
  final _firestore = FirestoreService();
  bool _isLogin = true;
  File? _document;

  Future<void> _pickDocument() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _document = File(pickedFile.path));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Provider Login')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              if (!_isLogin) ...[
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: 'Provider Name'),
                ),
                TextField(
                  controller: _phoneController,
                  decoration: InputDecoration(labelText: 'Phone Number (e.g., +1234567890)'),
                ),
                ElevatedButton(
                  onPressed: _pickDocument,
                  child: Text(_document == null ? 'Upload ID/License' : 'Document Selected'),
                ),
              ],
              ElevatedButton(
                onPressed: () async {
                  try {
                    User? user;
                    if (_isLogin) {
                      user = await _authService.providerSignIn(
                        _emailController.text,
                        _passwordController.text,
                      );
                    } else {
                      user = await _authService.providerSignUp(
                        _emailController.text,
                        _passwordController.text,
                      );
                      if (user != null) {
                        String? documentUrl = _document != null
                            ? await _firestore.uploadProviderDocument(user.uid, _document!)
                            : null;
                        final provider = Provider(
                          id: user.uid,
                          name: _nameController.text,
                          type: 'sole',
                          documentUrl: documentUrl,
                          phoneNumber: _phoneController.text, // Add this
                        );
                        await _firestore.updateProviderProfile(user.uid, provider.toMap());
                      }
                    }
                    if (user != null) {
                      await _authService.setUserRole('provider');
                      Navigator.pushReplacementNamed(context, '/provider_dashboard');
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                },
                child: Text(_isLogin ? 'Login' : 'Sign Up'),
              ),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin ? 'Create Account' : 'Already have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}