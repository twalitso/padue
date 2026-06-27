import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'dart:math' as math; // Import dart:math for trigonometric functions
import 'package:url_launcher/url_launcher.dart';


class EmergencyContactsScreen extends StatefulWidget {
  final double? latitude;
  final double? longitude;

  const EmergencyContactsScreen({super.key, this.latitude, this.longitude});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
 String? _city;
  String? _state;
  String? _country;
  bool _isLoading = true;
  List<Map<String, dynamic>> _emergencyContacts = [];
  final String _overpassUrl = 'https://overpass-api.de/api/interpreter';

  @override
  void initState() {
    super.initState();
    _fetchLocationAndContacts();
  }

  Future<void> _fetchLocationAndContacts() async {
    // Fallback contacts if Overpass API or location fails
    final fallbackContacts = [
      {'service': 'Emergency', 'number': '911', 'description': 'Universal emergency number (US)'},
      {'service': 'Emergency', 'number': '112', 'description': 'Universal emergency number (EU)'},
    ];

    if (widget.latitude == null || widget.longitude == null) {
      setState(() {
        _emergencyContacts = fallbackContacts;
        _isLoading = false;
      });
      return;
    }

    try {
      // Step 1: Get location details using Nominatim
      final nominatimResponse = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=${widget.latitude}&lon=${widget.longitude}&format=json',
        ),
        headers: {'User-Agent': 'PadueApp/1.0'},
      );

      if (nominatimResponse.statusCode == 200) {
        final nominatimData = jsonDecode(nominatimResponse.body);
        setState(() {
          _city = nominatimData['address']['city'] ??
              nominatimData['address']['town'] ??
              nominatimData['address']['village'];
          _state = nominatimData['address']['state'];
          _country = nominatimData['address']['country'];
        });
      }

      // Step 2: Query Overpass API for emergency services
      final overpassQuery = '''
        [out:json][timeout:25];
        (
          node["amenity"~"police|fire_station|hospital"](around:5000,${widget.latitude},${widget.longitude});
          way["amenity"~"police|fire_station|hospital"](around:5000,${widget.latitude},${widget.longitude});
          relation["amenity"~"police|fire_station|hospital"](around:5000,${widget.latitude},${widget.longitude});
        );
        out center tags;
      ''';

      final overpassResponse = await http.post(
        Uri.parse(_overpassUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'data': overpassQuery},
      );

      if (overpassResponse.statusCode == 200) {
        final overpassData = jsonDecode(overpassResponse.body);
        final elements = overpassData['elements'] as List<dynamic>;

        final contacts = <Map<String, dynamic>>[];
        for (var element in elements) {
          final tags = element['tags'] ?? {};
          final serviceType = tags['amenity']?.toString() ?? 'Unknown';
          final serviceName = tags['name']?.toString() ?? 'Unnamed $serviceType';
          final phone = tags['phone']?.toString() ?? tags['contact:phone']?.toString();
          final description = tags['emergency'] == 'yes'
              ? 'Emergency $serviceType'
              : 'Non-emergency $serviceType';

          // Calculate distance (approximate, using centroid or node coordinates)
          final lat = (element['center']?['lat'] ?? element['lat'] ?? widget.latitude) as double?;
          final lon = (element['center']?['lon'] ?? element['lon'] ?? widget.longitude) as double?;
          final distance = (lat != null && lon != null)
              ? _calculateDistance(
                  widget.latitude!,
                  widget.longitude!,
                  lat,
                  lon,
                )
              : 0.0; // Fallback distance if coordinates are missing

          contacts.add({
            'service': serviceType.replaceAll('_', ' ').capitalize(),
            'name': serviceName,
            'number': phone,
            'description': description,
            'distance': distance.toStringAsFixed(1),
          });
        }

        // Sort by distance
        contacts.sort((a, b) => double.parse(a['distance']).compareTo(double.parse(b['distance'])));

        setState(() {
          _emergencyContacts = contacts.isNotEmpty ? contacts : fallbackContacts;
          _isLoading = false;
        });
      } else {
        throw Exception('Overpass API request failed: ${overpassResponse.statusCode}');
      }
    } catch (e) {
      setState(() {
        _emergencyContacts = fallbackContacts;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching contacts: $e')),
      );
    }
  }

  // Helper method to calculate distance (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371; // km
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) => degrees * (math.pi / 180);

  

  Future<void> _launchPhoneCall(String phoneNumber) async {
    final url = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to make call')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFFA855F7)]),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_city != null || _state != null || _country != null)
                    Text(
                      'Location: ${_city ?? ''}${_city != null && _state != null ? ', ' : ''}${_state ?? ''}${(_city != null || _state != null) && _country != null ? ', ' : ''}${_country ?? ''}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Contact information may be incomplete. In emergencies, call 911 (US) or 112 (EU).',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _emergencyContacts.isEmpty
                        ? const Center(child: Text('No emergency contacts available'))
                        : ListView.builder(
                            itemCount: _emergencyContacts.length,
                            itemBuilder: (context, index) {
                              final contact = _emergencyContacts[index];
                              final hasPhone = contact['number'] != null && contact['number'].isNotEmpty;
                              return Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                child: ListTile(
                                  leading: Icon(
                                    contact['service'].toLowerCase().contains('police')
                                        ? Icons.local_police
                                        : contact['service'].toLowerCase().contains('fire')
                                            ? Icons.local_fire_department
                                            : contact['service'].toLowerCase().contains('hospital')
                                                ? Icons.medical_services
                                                : Icons.emergency,
                                    color: Colors.blue[700],
                                  ),
                                  title: Text(
                                    contact['name'],
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(contact['description']),
                                      Text('Distance: ${contact['distance']} km'),
                                      if (!hasPhone)
                                        const Text(
                                          'No phone number available. Call 911 or 112 for emergencies.',
                                          style: TextStyle(color: Colors.red, fontSize: 12),
                                        ),
                                    ],
                                  ),
                                  trailing: hasPhone
                                      ? TextButton(
                                          onPressed: () => _launchPhoneCall(contact['number']),
                                          child: Text(
                                            contact['number'],
                                            style: TextStyle(color: Colors.blue[700]),
                                          ),
                                        )
                                      : null,
                                ),
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

extension on String {
  capitalize() {}
}