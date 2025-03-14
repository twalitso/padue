import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/auth_service.dart';
import '../../../core/firestore_service.dart';
import '../../roadside/models/provider.dart';

class ProviderLoginScreen extends StatefulWidget {
  const ProviderLoginScreen({super.key});

  @override
  _ProviderLoginScreenState createState() => _ProviderLoginScreenState();
}

class _ProviderLoginScreenState extends State<ProviderLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _authService = AuthService();
  final _firestore = FirestoreService();
  bool _isLogin = true;
  File? _document;
  bool _isLoading = false; // Added for loading state

  Future<void> _pickDocument() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _document = File(pickedFile.path));
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
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
            phoneNumber: _phoneController.text,
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
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider Login'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.secondary, // Orange to differentiate
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            Text(
              _isLogin ? 'Provider Login' : 'Become a Provider',
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _isLogin ? 'Log in to assist users' : 'Sign up to offer services',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: _isLogin
                  ? const SizedBox.shrink(key: ValueKey('login')) // Empty when logging in
                  : Column(
                      key: const ValueKey('signup'),
                      children: [
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Provider Name',
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number (e.g., +1234567890)',
                            prefixIcon: Icon(Icons.phone),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _pickDocument,
                          icon: Icon(_document == null ? Icons.upload : Icons.check),
                          label: Text(_document == null ? 'Upload ID/License' : 'Document Selected'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[300],
                            foregroundColor: Colors.black87,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _submit,
                    child: Text(_isLogin ? 'Login' : 'Sign Up'),
                  ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
              child: Text(_isLogin ? 'Create Account' : 'Already have an account? Login'),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              child: const Text('Switch to User Login'),
            ),
          ],
        ),
      ),
    );
  }
}