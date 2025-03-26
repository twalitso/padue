import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:padue/core/utils.dart';
import 'dart:io';
import '../../../core/firestore_service.dart';
import '../../roadside/models/provider.dart';

class ProviderProfileScreen extends StatefulWidget {
  const ProviderProfileScreen({super.key});

  @override
  _ProviderProfileScreenState createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen>   with WidgetsBindingObserver{
  final _firestore = FirestoreService();
  File? _profilePicture;
  String? _profilePicUrl;
  File? _document;
  String? _documentUrl;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  String _type = 'Sole';
  List<String> _servicesOffered = [];
  bool _availability = true;
  bool _isVerified = false;
  double? _rating;
  GeoPoint? _location;
  List<Provider> _subProviders = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
     WidgetsBinding.instance.addObserver(this);
    _loadProfile();
    updateLastActive();
  }
 @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data or resources
_loadProfile();
    updateLastActive();
    }
  }

  Future<void> _loadProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      
      var doc = await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();
     if (doc.exists && mounted) {
      setState(() => _isLoading = true);
        Provider provider = Provider.fromFirestore(doc);
        _nameController = TextEditingController(text: provider.name);
        _phoneController = TextEditingController(text: provider.phoneNumber);
        _profilePicUrl = provider.profilePicUrl;
        _documentUrl = provider.documentUrl;
        _type = provider.type;
        _servicesOffered = provider.servicesOffered;
        _availability = provider.availability;
        _isVerified = provider.isVerified;
        _rating = provider.rating;
        _location = provider.location;
        var subProvidersSnapshot = await FirebaseFirestore.instance
            .collection('providers')
            .doc(user.uid)
            .collection('sub_providers')
            .get();
        _subProviders = subProvidersSnapshot.docs.map((doc) => Provider.fromFirestore(doc)).toList();
      } else {
        _nameController = TextEditingController(text: user.displayName);
        _phoneController = TextEditingController();
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickProfilePic() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _profilePicture = File(pickedFile.path));
  }

  Future<void> _uploadProfilePic() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && _profilePicture != null) {
      setState(() => _isLoading = true);
      _profilePicUrl = await _firestore.uploadProviderProfilePicture(user.uid, _profilePicture!);
      setState(() {
        _profilePicture = null;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile Picture Updated')));
    }
  }

  Future<void> _pickDocument() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _document = File(pickedFile.path));
  }

  Future<void> _uploadDocument() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && _document != null) {
      setState(() => _isLoading = true);
      _documentUrl = await _firestore.uploadProviderDocument(user.uid, _document!);
      await FirebaseFirestore.instance.collection('providers').doc(user.uid).update({
        'documentUrl': _documentUrl,
        'isVerified': false,
      });
      setState(() {
        _document = null;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Document Uploaded')));
    }
  }

  Future<void> _saveProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _isLoading = true);
      if (_location == null) {
        _location = await _getLocation();
        if (_location == null) {
          setState(() => _isLoading = false);
          return;
        }
      }

      final provider = Provider(
        id: user.uid,
        name: _nameController.text.trim(),
        type: _type,
        phoneNumber: _phoneController.text.trim(),
        location: _location!,
        servicesOffered: _servicesOffered,
        profilePicUrl: _profilePicUrl,
        availability: _availability,
        documentUrl: _documentUrl,
        isVerified: _isVerified,
        rating: _rating,
      );
      await _firestore.updateProviderProfile(user.uid, provider.toMap());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile Updated')));
      Navigator.pop(context);
      setState(() => _isLoading = false);
    }
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

  Future<void> _showServicePicker() async {
    var options = await FirebaseFirestore.instance.collection('services').get();
    var availableServices = options.docs.map((doc) => doc['name'] as String).toList();
    List<String> tempServices = List.from(_servicesOffered);
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
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Select at least one service')));
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
    if (saved) setState(() => _servicesOffered = tempServices);
  }

  void _addSubProvider() {
    final _subNameController = TextEditingController();
    final _subPhoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Sub-Provider'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _subNameController, decoration: InputDecoration(labelText: 'Name')),
            TextField(controller: _subPhoneController, decoration: InputDecoration(labelText: 'Phone Number')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              GeoPoint? location = _location ?? await _getLocation();
              if (location != null) {
                final subProvider = Provider(
                  id: '${FirebaseAuth.instance.currentUser!.uid}_${_subProviders.length + 1}',
                  name: _subNameController.text.trim(),
                  type: 'Sub',
                  phoneNumber: _subPhoneController.text.trim(),
                  location: location,
                  servicesOffered: _servicesOffered,
                  availability: true,
                );
                _subProviders.add(subProvider);
                await FirebaseFirestore.instance
                    .collection('providers')
                    .doc(FirebaseAuth.instance.currentUser!.uid)
                    .collection('sub_providers')
                    .doc(subProvider.id)
                    .set(subProvider.toMap());
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: Text('Add'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          ),
        ],
      ),
    );
  }

  void _deleteSubProvider(String subProviderId) async {
    await FirebaseFirestore.instance
        .collection('providers')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .collection('sub_providers')
        .doc(subProviderId)
        .delete();
    _subProviders.removeWhere((sub) => sub.id == subProviderId);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile'),
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
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: CircleAvatar(
                            radius: 50,
                            backgroundImage: _profilePicture != null
                                ? FileImage(_profilePicture!)
                                : _profilePicUrl != null
                                    ? NetworkImage(_profilePicUrl!)
                                    : AssetImage('assets/default_profile.png') as ImageProvider,
                          ),
                        ),
                        SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              icon: Icon(Icons.edit),
                              label: Text(_profilePicture != null ? 'Upload Picture' : 'Change Picture'),
                              onPressed: _profilePicture != null ? _uploadProfilePic : _pickProfilePic,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor:Colors.white ,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            if (_profilePicture != null)
                              Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: ElevatedButton.icon(
                                  icon: Icon(Icons.cancel),
                                  label: Text('Cancel'),
                                  onPressed: () => setState(() => _profilePicture = null),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 16),
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Name',
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
                        ),
                        SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _type,
                          decoration: InputDecoration(
                            labelText: 'Provider Type',
                            prefixIcon: Icon(Icons.business),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          items: ['Sole', 'Company'].map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                          onChanged: (value) => setState(() => _type = value!),
                        ),
                        SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _showServicePicker,
                          icon: Icon(_servicesOffered.isEmpty ? Icons.list : Icons.check),
                          label: Text(_servicesOffered.isEmpty ? 'Select Services' : 'Services: ${_servicesOffered.join(", ")}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor:Colors.white ,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        SizedBox(height: 16),
                        SwitchListTile(
                          title: Text('Available'),
                          value: _availability,
                          onChanged: (value) => setState(() => _availability = value),
                          activeColor: Colors.purple,
                        ),
                        SizedBox(height: 16),
                       Padding(
  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0), // Optional padding
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Status: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  _isVerified ? 'Verified' : 'Not Verified',
                  style: TextStyle(
                    fontSize: 16,
                    color: _isVerified ? Colors.blue : Colors.red,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8), // Space between text and button/check
            _isVerified
                ? Icon(
                    Icons.check_circle,
                    color: Colors.blue,
                    size: 24,
                  )
                : ElevatedButton.icon(
                    icon: Icon(Icons.upload),
                    label: Text(_document != null ? 'Upload Document' : 'Re-upload Document'),
                    onPressed: _document != null ? _uploadDocument : _pickDocument,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
          ],
        ),
      ),
    ],
  ),
),
                        if (_document != null)
                          Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('New Document Selected'),
                                SizedBox(width: 8),
                                ElevatedButton.icon(
                                  icon: Icon(Icons.cancel),
                                  label: Text('Cancel'),
                                  onPressed: () => setState(() => _document = null),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        SizedBox(height: 16),
                        ListTile(
                          title: Text('Rating'),
                          subtitle: Text(_rating != null ? _rating!.toStringAsFixed(1) : 'No rating yet'),
                          trailing: Icon(Icons.star, color: Colors.amber),
                        ),
                        if (_type == 'Company') ...[
                          SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _addSubProvider,
                            icon: Icon(Icons.add),
                            label: Text('Add Sub-Provider'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor:Colors.white ,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          SizedBox(height: 16),
                          Text('Sub-Providers:', style: Theme.of(context).textTheme.headlineSmall),
                          if (_subProviders.isEmpty)
                            Text('No sub-providers added')
                          else
                            ..._subProviders.map((sub) => ListTile(
                                  title: Text(sub.name),
                                  subtitle: Text(sub.phoneNumber ?? 'No phone'),
                                  trailing: IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteSubProvider(sub.id),
                                  ),
                                )),
                        ],
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _saveProfile,
                          child: Text('Save Changes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor:Colors.white ,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: EdgeInsets.symmetric(vertical: 12),
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