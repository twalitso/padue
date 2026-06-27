import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/core/services_cache.dart';
import 'package:padue/features/auth/screens/provider_services_onboarding_screen.dart';
import 'package:padue/features/auth/widgets/legal_consent_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth_service.dart';
import '../../../core/firestore_service.dart';
import '../../roadside/models/provider.dart';

class ProviderSignUpScreen extends StatefulWidget {
  const ProviderSignUpScreen({super.key});

  @override
  State<ProviderSignUpScreen> createState() => _ProviderSignUpScreenState();
}

class _ProviderSignUpScreenState extends State<ProviderSignUpScreen> {
  final _authService = AuthService();
  final _firestore = FirestoreService();
  final _legalConsentKey = GlobalKey<LegalConsentWidgetState>();
  final _formKey = GlobalKey<FormState>();

  int _currentStep = 0;
  bool _isLoading = false;           // For step navigation
  bool _isSubmitting = false;        // Separate flag for final submission

  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();

  List<String> _selectedServices = [];
  String _selectedType = 'Sole';

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    ServicesCache.load();
    _loadSavedProgress();
  }

  Future<void> _loadSavedProgress() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentStep = prefs.getInt('provider_signup_step') ?? 0;
      _nameController.text = prefs.getString('provider_name') ?? '';
      _emailController.text = prefs.getString('provider_email') ?? '';
      _phoneController.text = prefs.getString('provider_phone') ?? '';
      _selectedType = prefs.getString('provider_type') ?? 'Sole';
      _selectedServices = prefs.getStringList('provider_services') ?? [];
    });
  }

  Future<void> _debouncedSave() async {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('provider_signup_step', _currentStep);
      await prefs.setString('provider_name', _nameController.text);
      await prefs.setString('provider_email', _emailController.text);
      await prefs.setString('provider_phone', _phoneController.text);
      await prefs.setString('provider_type', _selectedType);
      await prefs.setStringList('provider_services', _selectedServices);
    });
  }

  Future<void> _clearProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('provider_signup_step');
    await prefs.remove('provider_name');
    await prefs.remove('provider_email');
    await prefs.remove('provider_phone');
    await prefs.remove('provider_type');
    await prefs.remove('provider_services');
  }

   @override
  void dispose() {
    _debounceTimer?.cancel();
    _debouncedSave();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<GeoPoint?> _getLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high,timeLimit: const Duration(seconds: 10),);
      return GeoPoint(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  void _nextStep() {
    if (_currentStep == 0 && !_formKey.currentState!.validate()) return;
   /**  if (_currentStep == 1 && _selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one service')),
      );
      return;
    }*/
    setState(() => _currentStep++);
    _debouncedSave();
  }

  void _prevStep() {
    setState(() => _currentStep--);
    _debouncedSave();
  }

  // ==================== SUBMIT WITH BETTER LOADING ====================
  Future<void> _submit() async {
    final legalState = _legalConsentKey.currentState;
    if (legalState == null || !legalState.isValid) {
      legalState?.showError('Please accept all required terms');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = await _authService.providerSignUp(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (user == null) throw 'Failed to create account';

    // Get location but don't fail registration
    final location = await _getLocation();

    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We couldn\'t get your location. You can set it later in your profile.'),
          duration: Duration(seconds: 4),
        ),
      );
    }

      final provider = Provider(
        id: user.uid,
        name: _nameController.text.trim(),
        type: _selectedType,
        phoneNumber: _phoneController.text.trim(),
        location: location ?? const GeoPoint(0, 0), // fallback
       servicesOffered: [], // empty for now
        availability: true,
      );

      await _firestore.updateProviderProfile(user.uid, {
        ...provider.toMap(),
        'consents': legalState.getConsentData(),
        'createdAt': FieldValue.serverTimestamp(),
        'email': _emailController.text.trim(),
      });

      await _authService.setUserRole('provider');
      await _clearProgress();

    /**  if (!user.emailVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification email sent. Please verify.', style: GoogleFonts.poppins())),
        );
      }*/

        if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ProviderServicesOnboardingScreen(userId: user.uid),
        ),
      );
    }

      //Navigator.pushReplacementNamed(context, '/provider_dashboard');
    } catch (e) {
      final msg = e.toString().contains('email-already-in-use')
          ? 'Account already exists with this email.kindly login instead.or use a different email.'
          : 'Sign-up failed. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

 @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Become a Provider (${_currentStep + 1}/2)', style: GoogleFonts.poppins()),
        leading: _currentStep > 0 && !_isSubmitting
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _prevStep)
            : null,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: (_currentStep + 1) / 2,
                      backgroundColor: Colors.grey[200],
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 32),

                    if (_currentStep == 0) _buildStep1(),
                    if (_currentStep == 1) _buildStep2(),
                  //  if (_currentStep == 2) _buildStep3(),

                    const SizedBox(height: 40),

                    Row(
                      children: [
                        if (_currentStep > 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isSubmitting ? null : _prevStep,
                              child: const Text('Back'),
                            ),
                          ),
                        if (_currentStep > 0) const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSubmitting
                                ? null
                                : _currentStep == 1
                                    ? _submit
                                    : _nextStep,
                            child: _currentStep == 1
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_isSubmitting)
                                        const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        ),
                                      if (_isSubmitting) const SizedBox(width: 12),
                                      Text(_isSubmitting ? 'Creating Account...' : 'Create Account'),
                                    ],
                                  )
                                : const Text('Continue'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Full Screen Loading Overlay
            if (_isSubmitting)
              Container(
                color: Colors.black.withOpacity(0.6),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Creating your provider account...'),
                          Text('Please wait', style: TextStyle(fontSize: 14, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==================== STEPS ====================

  Widget _buildStep1() {
    return Column(
      children: [
        Text('Personal Information', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        _buildTextField(_nameController, 'Provider Name', 'e.g., John’s Towing', Icons.person, validator: (v) => v!.trim().isEmpty ? 'Required' : null),
        _buildTextField(_emailController, 'Email', 'provider@example.com', Icons.email, keyboard: TextInputType.emailAddress),
        _buildTextField(_passwordController, 'Password', 'Min 6 characters', Icons.lock, obscure: true),
        _buildTextField(_confirmPasswordController, 'Confirm Password', 'Re-enter password', Icons.lock_outline, obscure: true),
        _buildTextField(_phoneController, 'Phone Number', '+260123456789', Icons.phone, keyboard: TextInputType.phone),
        
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedType,
          decoration: InputDecoration(
            labelText: 'Provider Type',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: const ['Sole', 'Company']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) => setState(() => _selectedType = v!),
        ),
      ],
    );
  }

  Widget _buildStepold() {
    return Column(
      children: [
        Text('Services', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () async {
            final result = await showModalBottomSheet<List<String>?>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _ServicePickerSheet(
                services: ServicesCache.services,
                selected: _selectedServices,
              ),
            );
            if (result != null) {
              setState(() => _selectedServices = result);
              _debouncedSave();
            }
          },
          icon: const Icon(Icons.add),
          label: Text(_selectedServices.isEmpty ? 'Select Services' : '${_selectedServices.length} selected'),
        ),
        if (_selectedServices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Wrap(
              spacing: 8,
              children: _selectedServices.map((s) => Chip(label: Text(s))).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      children: [
        Text('Legal & Consent', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 32),
        LegalConsentWidget(
          key: _legalConsentKey,
          showLocationConsent: true,
          showMarketingOptIn: true,
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint,
    IconData icon, {
    TextInputType? keyboard,
    bool obscure = false,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        validator: validator,
        onChanged: (_) => _debouncedSave(),
      ),
    );
  }
}

// Service Picker (unchanged - already efficient)
class _ServicePickerSheet extends StatefulWidget {
  final List<String> services;
  final List<String> selected;

  const _ServicePickerSheet({super.key, required this.services, required this.selected});

  @override
  State<_ServicePickerSheet> createState() => _ServicePickerSheetState();
}

class _ServicePickerSheetState extends State<_ServicePickerSheet> {
  late List<String> _tempSelected;

  @override
  void initState() {
    super.initState();
    _tempSelected = List.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select Services', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                  TextButton(onPressed: () => Navigator.pop(context, _tempSelected), child: const Text('Done')),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: widget.services.length,
                itemBuilder: (context, i) {
                  final service = widget.services[i];
                  return CheckboxListTile(
                    title: Text(service),
                    value: _tempSelected.contains(service),
                    activeColor: Colors.orange,
                    onChanged: (v) {
                      setState(() {
                        v == true ? _tempSelected.add(service) : _tempSelected.remove(service);
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}