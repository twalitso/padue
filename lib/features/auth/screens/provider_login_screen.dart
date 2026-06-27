import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/auth_service.dart';

class ProviderLoginScreen extends StatefulWidget {
  const ProviderLoginScreen({super.key});

  @override
  _ProviderLoginScreenState createState() => _ProviderLoginScreenState();
}

class _ProviderLoginScreenState extends State<ProviderLoginScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isEmailValid = true;
  bool _isPasswordValid = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_validateInputs()) return;
    setState(() => _isLoading = true);
    try {
      var user = await _authService.providerSignIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (user != null && mounted) {
        await _authService.setUserRole('provider');
        Navigator.pushReplacementNamed(context, '/provider_dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Login failed: ${e.toString().contains('user-not-found') ? 'User not found' : 'Invalid credentials'}',
              style: GoogleFonts.poppins(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_isValidEmail(_emailController.text.trim())) {
      setState(() => _isEmailValid = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid email', style: GoogleFonts.poppins())),
      );
      return;
    }
    try {
      await _authService.sendPasswordResetEmail(_emailController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset email sent. Check your inbox.', style: GoogleFonts.poppins())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to send reset email: ${e.toString().contains('user-not-found') ? 'User not found' : 'Error occurred'}',
              style: GoogleFonts.poppins(),
            ),
          ),
        );
      }
    }
  }

  bool _validateInputs() {
    final emailValid = _isValidEmail(_emailController.text.trim());
    final passwordValid = _passwordController.text.trim().length >= 6;
    setState(() {
      _isEmailValid = emailValid;
      _isPasswordValid = passwordValid;
    });
    if (!emailValid || !passwordValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid email and password (min 6 characters)', style: GoogleFonts.poppins()),
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
        title: Text('Provider Login', style: GoogleFonts.poppins()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Column(
              children: [
                Image.asset(
                  'assets/icon.png',
                  width: 100,
                  height: 100,
                ).animate().scale(duration: const Duration(milliseconds: 800), curve: Curves.easeOut),
                const SizedBox(height: 16),
                Text(
                  'Provider Login',
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: const Duration(milliseconds: 400)),
                const SizedBox(height: 8),
                Text(
                  'Sign in to manage your services',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 100)),
              ],
            ),
            const SizedBox(height: 32),
            // Email Input
            Semantics(
              label: 'Email Input',
              child: TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'e.g., provider@example.com',
                  prefixIcon: const Icon(Icons.email),
                  errorText: _isEmailValid ? null : 'Enter a valid email',
                ),
                keyboardType: TextInputType.emailAddress,
                onChanged: (value) => setState(() => _isEmailValid = _isValidEmail(value.trim())),
              ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 200)),
            ),
            const SizedBox(height: 16),
            // Password Input
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
              ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 300)),
            ),
            const SizedBox(height: 16),
            // Forgot Password
            Semantics(
              label: 'Forgot Password',
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _resetPassword,
                  child: Text('Forgot Password?', style: GoogleFonts.poppins()),
                ),
              ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 400)),
            ),
            const SizedBox(height: 24),
            // Login Button
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Semantics(
                    label: 'Login Button',
                    child: ElevatedButton(
                      onPressed: _signIn,
                      child: const Text('Login'),
                    ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 500)),
                  ),
            const SizedBox(height: 16),
            // Navigation to Sign Up and User Login
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
                    label: 'Sign Up',
                    child: OutlinedButton(
                      onPressed: () => Navigator.pushNamed(context, '/provider_signup'),
                      child: const Text('Create a Provider Account'),
                    ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 600)),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    label: 'User Login',
                    child: OutlinedButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      child: const Text('Switch to User Login'),
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