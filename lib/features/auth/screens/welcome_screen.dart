import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  _WelcomeScreenState createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  Future<void> _markWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_welcome', true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo and Header
              Image.asset(
                'assets/icon.png',
                width: 120,
                height: 120,
              ).animate().scale(duration: const Duration(milliseconds: 800), curve: Curves.easeOut),
              const SizedBox(height: 24),
              Text(
                'Welcome to Padue',
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: const Duration(milliseconds: 400)),
              const SizedBox(height: 12),
              Text(
                'Your trusted platform for roadside and home assistance services.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 100)),
              const SizedBox(height: 48),
              // User CTA
              Semantics(
                label: 'Find Services Button',
                child: ElevatedButton(
                  onPressed: () async {
                    await _markWelcomeSeen();
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: const Text('Find Services'),
                ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 200)),
              ),
              const SizedBox(height: 16),
              // Provider CTA
              Semantics(
                label: 'Offer Services Button',
                child: OutlinedButton(
                  onPressed: () async {
                    await _markWelcomeSeen();
                    Navigator.pushReplacementNamed(context, '/provider_login');
                  },
                  child: const Text('Offer Services'),
                ).animate().fadeIn(duration: const Duration(milliseconds: 400), delay: const Duration(milliseconds: 300)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}