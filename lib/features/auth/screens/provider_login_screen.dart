import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
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
  bool _isLoading = false;
  List<String> _selectedServices = [];
  String _selectedType = 'Sole';

  Future<void> _pickDocument() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _document = File(pickedFile.path));
  }

  Future<GeoPoint?> _getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      return GeoPoint(position.latitude, position.longitude);
    } catch (e) {
      return null;
    }
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      User? user;
      if (_isLogin) {
        user = await _authService.providerSignIn(_emailController.text.trim(), _passwordController.text.trim());
      } else {
        user = await _authService.providerSignUp(_emailController.text.trim(), _passwordController.text.trim());
        if (user != null) {
          GeoPoint? location = await _getLocation();
          if (location == null) throw 'Location is required';
          String? documentUrl = _document != null ? await _firestore.uploadProviderDocument(user.uid, _document!) : null;
          final provider = Provider(
            id: user.uid,
            name: _nameController.text.trim(),
            type: _selectedType,
            documentUrl: documentUrl,
            phoneNumber: _phoneController.text.trim(),
            location: location,
            servicesOffered: _selectedServices.isNotEmpty ? _selectedServices : ['General'],
            availability: true,
          );
          await _firestore.updateProviderProfile(user.uid, provider.toMap());
        }
      }
      if (user != null) {
        await _authService.setUserRole('provider');
        Navigator.pushReplacementNamed(context, '/provider_dashboard');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

Future<void> _showServicePicker() async {
  var options = await FirebaseFirestore.instance.collection('services').get();
  var availableServices = options.docs.map((doc) => doc['name'] as String).toList();
  List<String> tempServices = List.from(_selectedServices); // Assuming _selectedServices is a class-level List<String>
  bool saved = false;

  await showModalBottomSheet(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Select Services', style: Theme.of(context).textTheme.headlineMedium),
            Expanded(
              child: ListView(
                children: availableServices.map((service) => CheckboxListTile(
                  title: Text(service),
                  value: tempServices.contains(service),
                  onChanged: (value) => setModalState(() {
                    if (value!) tempServices.add(service);
                    else tempServices.remove(service);
                  }),
                )).toList(),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (tempServices.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Select at least one service')),
                  );
                } else {
                  saved = true;
                  Navigator.pop(context);
                }
              },
              child: Text('Done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (saved) setState(() => _selectedServices = tempServices);
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
        title: Text('Provider Login'),
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
                  Text(
                    _isLogin ? 'Provider Login' : 'Become a Provider',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    obscureText: true,
                  ),
                  AnimatedSwitcher(
                    duration: Duration(milliseconds: 300),
                    child: _isLogin
                        ? SizedBox.shrink(key: ValueKey('login'))
                        : Column(
                            key: ValueKey('signup'),
                            children: [
                              SizedBox(height: 16),
                              TextField(
                                controller: _nameController,
                                decoration: InputDecoration(
                                  labelText: 'Provider Name',
                                  prefixIcon: Icon(Icons.person),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                ),
                              ),
                              SizedBox(height: 16),
                              TextField(
                                controller: _phoneController,
                                decoration: InputDecoration(
                                  labelText: 'Phone Number',
                                  prefixIcon: Icon(Icons.phone),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                ),
                                keyboardType: TextInputType.phone,
                              ),
                              SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: _selectedType,
                                decoration: InputDecoration(
                                  labelText: 'Provider Type',
                                  prefixIcon: Icon(Icons.business),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                ),
                                items: ['Sole', 'Company'].map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                                onChanged: (value) => setState(() => _selectedType = value!),
                              ),
                              SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _pickDocument,
                                icon: Icon(_document == null ? Icons.upload : Icons.check),
                                label: Text(_document == null ? 'Upload ID/License' : 'Document Selected'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor:Colors.white ,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _showServicePicker,
                                icon: Icon(_selectedServices.isEmpty ? Icons.list : Icons.check),
                                label: Text(_selectedServices.isEmpty ? 'Select Services' : 'Services: ${_selectedServices.join(", ")}'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor:Colors.white ,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),
                  ),
                  SizedBox(height: 24),
                  _isLoading
                      ? Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _submit,
                          child: Text(_isLogin ? 'Login' : 'Sign Up'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                  SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _isLogin = !_isLogin),
                    child: Text(_isLogin ? 'Create Account' : 'Already have an account? Login'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                    child: Text('Switch to User Login'),
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