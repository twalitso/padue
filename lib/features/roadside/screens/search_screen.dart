import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/firestore_service.dart';

class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _firestore = FirestoreService();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Position? _userLocation;
  double _minRating = 0.0;
  bool _verifiedOnly = false;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enable location services')));
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    _userLocation = await Geolocator.getCurrentPosition();
    setState(() {});
  }

  Future<void> _searchProviders() async {
    if (_userLocation != null && _searchController.text.trim().isNotEmpty) {
      var results = await _firestore.searchProviders(
        _searchController.text.trim(),
        _userLocation!,
        minRating: _minRating,
        verifiedOnly: _verifiedOnly,
      );
      setState(() => _results = results);
    }
  }

  void _showFilterDialog() {
    double tempMinRating = _minRating;
    bool tempVerifiedOnly = _verifiedOnly;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Filter Options', style: Theme.of(context).textTheme.headlineMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Minimum Rating', style: Theme.of(context).textTheme.bodyMedium),
            Slider(
              value: tempMinRating,
              min: 0.0,
              max: 5.0,
              divisions: 10,
              label: tempMinRating.toStringAsFixed(1),
              onChanged: (value) => setState(() => tempMinRating = value),
            ),
            Row(
              children: [
                Checkbox(
                  value: tempVerifiedOnly,
                  onChanged: (value) => setState(() => tempVerifiedOnly = value ?? false),
                ),
                Text('Verified Providers Only', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _minRating = tempMinRating;
                _verifiedOnly = tempVerifiedOnly;
              });
              _searchProviders();
              Navigator.pop(context);
            },
            child: Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Search Services'),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter Results',
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search (e.g., car wash, mechanic)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: _searchProviders,
                ),
              ),
              onSubmitted: (_) => _searchProviders(),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters: ${_minRating > 0 ? "Rating ≥ ${_minRating.toStringAsFixed(1)}" : "No min rating"}'
                  '${_verifiedOnly ? ", Verified only" : ""}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${_results.length} results',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            SizedBox(height: 16),
            Expanded(
              child: _userLocation == null
                  ? Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(child: Text('No providers found', style: Theme.of(context).textTheme.bodyMedium))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            var provider = _results[index];
                            return Card(
                              margin: EdgeInsets.symmetric(vertical: 8),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              color: provider['adFree'] ? Colors.blue[50] : null,
                              child: ListTile(
                                title: Text(
                                  provider['name'],
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: provider['adFree'] ? FontWeight.bold : FontWeight.normal,
                                      ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${provider['type']} - ${provider['distance'] == double.infinity ? "Unknown distance" : "${provider['distance'].toStringAsFixed(1)} km"}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    Text(
                                      'Rating: ${provider['avgRating'].toStringAsFixed(1)} / 5',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                trailing: provider['isVerified']
                                    ? Icon(Icons.verified, color: Colors.green)
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