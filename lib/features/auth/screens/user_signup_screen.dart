import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart'; // ← Add this
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/auth/widgets/legal_consent_widget.dart'; // ← Add this

import '../../../core/auth_service.dart';
import '../../../core/firestore_service.dart';

class UserSignUpScreen extends StatefulWidget {
  const UserSignUpScreen({super.key});

  @override
  _UserSignUpScreenState createState() => _UserSignUpScreenState();
}

class _UserSignUpScreenState extends State<UserSignUpScreen> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Legal Consent Key
  final _legalConsentKey = GlobalKey<LegalConsentWidgetState>();

  bool _isLoading = false;
  bool _isNameValid = true;
  bool _isEmailValid = true;
  bool _isPasswordValid = true;
  bool _isConfirmPasswordValid = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_validateInputs()) return;

    // Check Legal Consent
    final legalState = _legalConsentKey.currentState;
    if (legalState == null || !legalState.isValid) {
      legalState?.showError('Please accept all required terms');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the Terms of Service and Privacy Policy'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      var user = await _authService.signUpWithCredentials(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (user != null && mounted) {
        // Save user profile + consents
        await _firestoreService.updateUserProfile(user.uid, {
          'name': _nameController.text.trim(),
          'role': 'user',
          'consents': legalState.getConsentData(),
          'createdAt': FieldValue.serverTimestamp(),
        } as UserProfile);

 
        

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification email sent. Please check your inbox.', 
                style: GoogleFonts.poppins()),
          ),
        );
        Navigator.pushReplacementNamed(context, '/request');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sign-up failed: ${e.toString().contains('email-already-in-use') ? 'Email already in use' : 'Error occurred'}',
              style: GoogleFonts.poppins(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _validateInputs() {
    final nameValid = _nameController.text.trim().isNotEmpty;
    final emailValid = _isValidEmail(_emailController.text.trim());
    final passwordValid = _passwordController.text.trim().length >= 6;
    final confirmPasswordValid = _passwordController.text.trim() == _confirmPasswordController.text.trim();

    setState(() {
      _isNameValid = nameValid;
      _isEmailValid = emailValid;
      _isPasswordValid = passwordValid;
      _isConfirmPasswordValid = confirmPasswordValid;
    });

    if (!nameValid || !emailValid || !passwordValid || !confirmPasswordValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please ensure all fields are valid: name, email, password (min 6 characters), and matching passwords',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  bool _isValidEmail(String email) {
    return email.isNotEmpty && email.contains('@') && email.contains('.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sign Up', style: GoogleFonts.poppins()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header (unchanged)
            Column(
              children: [
                Image.asset(
                  'assets/icon.png',
                  width: 100,
                  height: 100,
                ).animate().scale(duration: const Duration(milliseconds: 800), curve: Curves.easeOut),
                const SizedBox(height: 16),
                Text(
                  'Join Padue!',
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: const Duration(milliseconds: 400)),
                const SizedBox(height: 8),
                Text(
                  'Create an account to access roadside & home assistance',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 100)),
              ],
            ),
            const SizedBox(height: 32),

            // Name, Email, Password, Confirm Password fields (unchanged)
            Semantics(
              label: 'Name Input',
              child: TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  hintText: 'e.g., John Doe',
                  prefixIcon: const Icon(Icons.person),
                  errorText: _isNameValid ? null : 'Please enter your name',
                ),
                keyboardType: TextInputType.name,
                onChanged: (value) => setState(() => _isNameValid = value.trim().isNotEmpty),
              ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 200)),
            ),
            const SizedBox(height: 16),

            Semantics(
              label: 'Email Input',
              child: TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'e.g., user@example.com',
                  prefixIcon: const Icon(Icons.email),
                  errorText: _isEmailValid ? null : 'Enter a valid email',
                ),
                keyboardType: TextInputType.emailAddress,
                onChanged: (value) => setState(() => _isEmailValid = _isValidEmail(value.trim())),
              ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 300)),
            ),
            const SizedBox(height: 16),

            Semantics(
              label: 'Password Input',
              child: TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter your password',
                  prefixIcon: const Icon(Icons.lock),
                  errorText: _isPasswordValid ? null : 'Password must be at least 6 characters',
                ),
                obscureText: true,
                onChanged: (value) => setState(() => _isPasswordValid = value.trim().length >= 6),
              ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 400)),
            ),
            const SizedBox(height: 16),

            Semantics(
              label: 'Confirm Password Input',
              child: TextField(
                controller: _confirmPasswordController,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  hintText: 'Re-enter your password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: _isConfirmPasswordValid ? null : 'Passwords do not match',
                ),
                obscureText: true,
                onChanged: (value) => setState(
                  () => _isConfirmPasswordValid = value.trim() == _passwordController.text.trim(),
                ),
              ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 500)),
            ),

            const SizedBox(height: 24),

            // ==================== LEGAL CONSENT ====================
            LegalConsentWidget(
              key: _legalConsentKey,
              showLocationConsent: false,   // Not needed for regular users
              showMarketingOptIn: true,
            ),

            const SizedBox(height: 24),

            // Sign Up Button
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Semantics(
                    label: 'Sign Up Button',
                    child: ElevatedButton(
                      onPressed: _signUp,
                      child: const Text('Sign Up'),
                    ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 600)),
                  ),

            const SizedBox(height: 16),

            // Navigation buttons (unchanged)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Semantics(
                    label: 'Back to Login',
                    child: OutlinedButton(
                      onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                      child: const Text('Already have an account? Log In'),
                    ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 700)),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    label: 'Back to Welcome',
                    child: OutlinedButton(
                      onPressed: () => Navigator.pushReplacementNamed(context, '/welcome'),
                      child: const Text('Back to Welcome'),
                    ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 800)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}