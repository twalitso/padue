import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/auth_service.dart';
import '../../../core/firestore_service.dart';

class UserLoginScreen extends StatefulWidget {
  @override
  _UserLoginScreenState createState() => _UserLoginScreenState();
}

class _UserLoginScreenState extends State<UserLoginScreen> {
  final _authService = AuthService();
  final _firestore = FirestoreService();
  String phoneNumber = '';
  String verificationId = '';
  String smsCode = '';
  bool isCodeSent = false;

  Future<void> _sendCode() async {
    await _authService.verifyPhoneNumber(
      phoneNumber,
      (vid) {
        setState(() {
          verificationId = vid;
          isCodeSent = true;
        });
      },
    );
  }
Future<void> _verifyOtp() async {
  try {
    print('Calling verifyOtp with verificationId: $verificationId, smsCode: $smsCode');
    User? user = await _authService.verifyOtp(verificationId, smsCode);
    print('verifyOtp returned: ${user?.uid}, type: ${user.runtimeType}');
    if (user != null) {
      Navigator.pushReplacementNamed(context, '/profile');
    }
  } catch (e) {
    print('OTP verification failed: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('OTP verification failed: $e')),
    );
  }
}
 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('User Login')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            if (!isCodeSent) ...[
              TextField(
                onChanged: (value) => phoneNumber = value,
                decoration: InputDecoration(
                  labelText: 'Phone Number (e.g., +1234567890)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _sendCode,
                child: Text('Send Code'),
              ),
            ] else ...[
              TextField(
                onChanged: (value) => smsCode = value,
                decoration: InputDecoration(
                  labelText: 'Enter OTP',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _verifyOtp, // Line 43: This triggers verifyOtp
                child: Text('Verify OTP'),
              ),
            ],
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/search'),
              child: Text('Search Services'),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/provider_login'),
              child: Text('Switch to Provider Login'),
            ),
          ],
        ),
      ),
    );
  }
}