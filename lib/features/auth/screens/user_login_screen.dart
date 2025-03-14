import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/auth_service.dart';
import '../../../core/firestore_service.dart';

class UserLoginScreen extends StatefulWidget {
  const UserLoginScreen({super.key});

  @override
  _UserLoginScreenState createState() => _UserLoginScreenState();
}

class _UserLoginScreenState extends State<UserLoginScreen> {
  final _authService = AuthService();
  final _firestore = FirestoreService();
  String phoneNumber = ''; // Single field for full phone number
  String verificationId = '';
  String smsCode = '';
  bool isCodeSent = false;
  bool _isLoading = false;

  Future<void> _sendCode() async {
    setState(() => _isLoading = true);
    await _authService.verifyPhoneNumber(
      phoneNumber, // Use single phoneNumber directly
      (vid) {
        setState(() {
          verificationId = vid;
          isCodeSent = true;
          _isLoading = false;
        });
      },
    );
  }

  Future<void> _verifyOtp() async {
    try {
      setState(() => _isLoading = true);
      print('Calling verifyOtp with verificationId: $verificationId, smsCode: $smsCode');
      User? user = await _authService.verifyOtp(verificationId, smsCode);
      print('verifyOtp returned: ${user?.uid}, type: ${user.runtimeType}');
      if (user != null) {
        //Navigator.pushReplacementNamed(context, '/profile');
        Navigator.pushReplacementNamed(context, '/request');
      }
    } catch (e) {
      print('OTP verification failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OTP verification failed: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Login'),
        elevation: 0,
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            Text(
              'Welcome Back!',
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Log in with your phone number',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: !isCodeSent
                  ? Column(
                      key: const ValueKey('phoneInput'),
                      children: [
                        TextField(
                          onChanged: (value) => phoneNumber = value,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number (e.g., +1234567890)',
                            prefixIcon: Icon(Icons.phone),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 24),
                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                onPressed: _sendCode,
                                child: const Text('Send Code'),
                              ),
                      ],
                    )
                  : Column(
                      key: const ValueKey('otpInput'),
                      children: [
                        TextField(
                          onChanged: (value) => smsCode = value,
                          decoration: const InputDecoration(
                            labelText: 'Enter OTP',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                        const SizedBox(height: 24),
                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                onPressed: _verifyOtp,
                                child: const Text('Verify OTP'),
                              ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/provider_login'),
              child: const Text('Switch to Provider Login'),
            ),
          ],
        ),
      ),
    );
  }
}