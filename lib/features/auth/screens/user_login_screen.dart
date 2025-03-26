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
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  String verificationId = '';
  bool isCodeSent = false;
  bool _isLoading = false;

  Future<void> _sendCode() async {
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter a phone number')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService.verifyPhoneNumber(
        _phoneController.text.trim(),
        (vid) {
          if (mounted) { // Ensure widget is still mounted
            setState(() {
              verificationId = vid;
              isCodeSent = true;
              _isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send code: $e')));
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter the OTP')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      User? user = await _authService.verifyOtp(verificationId, _otpController.text.trim());
      if (user != null && mounted) {
        Navigator.pushReplacementNamed(context, '/request');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OTP verification failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _isLoading = true);
    try {
      await _authService.verifyPhoneNumber(
        _phoneController.text.trim(),
        (vid) {
          if (mounted) {
            setState(() {
              verificationId = vid;
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Code resent successfully')));
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to resend code: $e')));
      }
    }
  }

  void _cancelOtp() {
    setState(() {
      isCodeSent = false;
      verificationId = '';
      _otpController.clear();
      _isLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OTP request canceled')));
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('User Login'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.purple[50]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header with Icon
                  Column(
                    children: [
                      Icon(Icons.lock_open, size: 60, color: Colors.purple),
                      SizedBox(height: 16),
                      Text(
                        isCodeSent ? 'Verify OTP' : 'Welcome Back!',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.purple),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        isCodeSent ? 'Enter the code sent to your phone' : 'Login with your phone number',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  SizedBox(height: 32),
                  // Form Fields
                  AnimatedSwitcher(
                    duration: Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                    child: !isCodeSent
                        ? Column(
                            key: ValueKey('phoneInput'),
                            children: [
                              TextField(
                                controller: _phoneController,
                                decoration: InputDecoration(
                                  labelText: 'Phone Number',
                                  hintText: 'e.g., +1234567890',
                                  prefixIcon: Icon(Icons.phone),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                ),
                                keyboardType: TextInputType.phone,
                              ),
                              SizedBox(height: 24),
                              _isLoading
                                  ? Center(child: CircularProgressIndicator())
                                  : ElevatedButton(
                                      onPressed: _sendCode,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.purple,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: EdgeInsets.symmetric(vertical: 20),
                                      ),
                                      child: Text('Send Code', style: TextStyle(fontSize: 16)),
                                    ),
                            ],
                          )
                        : Column(
                            key: ValueKey('otpInput'),
                            children: [
                              TextField(
                                controller: _otpController,
                                decoration: InputDecoration(
                                  labelText: 'OTP',
                                  hintText: 'Enter 6-digit code',
                                  prefixIcon: Icon(Icons.lock_outline),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                ),
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                              ),
                              SizedBox(height: 24),
                              _isLoading
                                  ? Center(child: CircularProgressIndicator())
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        ElevatedButton(
                                          onPressed: _verifyOtp,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.purple,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                                          ),
                                          child: Text('Verify OTP', style: TextStyle(fontSize: 16)),
                                        ),
                                        ElevatedButton(
                                          onPressed: _cancelOtp,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.grey,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                                          ),
                                          child: Text('Cancel', style: TextStyle(fontSize: 16)),
                                        ),
                                      ],
                                    ),
                              SizedBox(height: 16),
                              TextButton(
                                onPressed: _resendOtp,
                                child: Text('Resend OTP', style: TextStyle(color: Colors.blue)),
                              ),
                            ],
                          ),
                  ),
                  SizedBox(height: 50),
                  // Switch to Provider Login
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/provider_login'),
                      child: Text(
                        'Are you a provider? Login here',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}