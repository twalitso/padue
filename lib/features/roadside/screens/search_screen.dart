import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/utils.dart';
import 'package:padue/features/roadside/screens/view_provider_profile_screen.dart';
import 'package:padue/features/roadside/screens/chat_screen.dart';

class SearchScreen extends StatefulWidget {
  final dynamic arguments;
  const SearchScreen({super.key, this.arguments});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with WidgetsBindingObserver {
  final FirestoreService _firestore = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _results = [];
  List<String> _suggestions = [];
  List<String> _recentSearches = [];
  Position? _userLocation;
  double _minRating = 0.0;
  bool _verifiedOnly = false;
  String _sortBy = 'distance'; // Options: 'distance', 'rating', 'availability'
  String? _selectedCategory;
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  Timer? _debounce;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _getUserLocation();
    updateLastActive();
    _loadRecentSearches();
    _searchController.addListener(() {
      _onSearchChanged();
      _updateSuggestions(_searchController.text.trim());
    });
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && _searchController.text.isEmpty) {
        _updateSuggestions('');
      } else if (!_searchFocusNode.hasFocus) {
        _removeOverlay();
      }
    });
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading &&
          _hasMore) {
        _loadMoreProviders();
      }
    });
    if (widget.arguments != null) {
      if (widget.arguments is String && widget.arguments.isNotEmpty) {
        _searchController.text = widget.arguments as String;
        _searchProviders();
      } else if (widget.arguments is Map) {
        _searchController.text = widget.arguments['query'] ?? '';
        _minRating = (widget.arguments['minRating'] as num?)?.toDouble() ?? 0.0;
        _verifiedOnly = widget.arguments['verifiedOnly'] ?? false;
        _selectedCategory = widget.arguments['category'];
        if (_searchController.text.isNotEmpty) {
          _searchProviders();
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _getUserLocation();
      updateLastActive();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(() {});
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _removeOverlay();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services')),
        );
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      _userLocation = await Geolocator.getCurrentPosition();
      setState(() {});
    } catch (e) {
      // Handle silently
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.trim().isNotEmpty) {
        _searchProviders();
      } else {
        setState(() => _results = []);
      }
    });
  }

  Future<void> _loadRecentSearches() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches = prefs.getStringList('recent_searches') ?? [];
    });
  }

  Future<void> _saveRecentSearch(String query) async {
    if (query.trim().isEmpty) return;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> searches = prefs.getStringList('recent_searches') ?? [];
    searches.remove(query);
    searches.insert(0, query);
    if (searches.length > 5) searches.removeLast();
    await prefs.setStringList('recent_searches', searches);
    setState(() => _recentSearches = searches);
  }

  Future<void> _updateSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() => _suggestions = _recentSearches);
      _showSuggestionsOverlay();
      return;
    }
    try {
      var snapshot = await FirebaseFirestore.instance
          .collection('services')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(5)
          .get();
      setState(() {
        _suggestions = snapshot.docs.map((doc) => doc['name'] as String).toList();
      });
      _showSuggestionsOverlay();
      await _saveRecentSearch(query);
    } catch (e) {
      // Handle silently
    }
  }

  void _showSuggestionsOverlay() {
    _removeOverlay();
    if (_suggestions.isEmpty) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 120,
        left: 16,
        right: 16,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: Icon(
                    _searchController.text.isEmpty ? Icons.history : Icons.search,
                    color: Colors.grey[600],
                  ),
                  title: Text(_suggestions[index], style: const TextStyle(fontSize: 14)),
                  onTap: () {
                    _searchController.text = _suggestions[index];
                    _removeOverlay();
                    _searchProviders();
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _searchProviders() async {
    if (_searchController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a search term')),
      );
      return;
    }
    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for location... Please ensure location services are enabled')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _results = [];
      _lastDocument = null;
      _hasMore = true;
    });

    try {
      var results = await _firestore.searchProviders(
        _searchController.text.trim(),
        _userLocation!,
        minRating: _minRating,
        verifiedOnly: _verifiedOnly,
        category: _selectedCategory,
        sortBy: _sortBy,
        limit: 20,
      );

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_search_${_searchController.text.trim()}',
        jsonEncode({
          'results': results,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      setState(() {
        _results = results;
        _lastDocument = results.isNotEmpty ? results.last['doc'] : null;
        _hasMore = results.length == 20;
      });
    } catch (e) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? cached = prefs.getString('cached_search_${_searchController.text.trim()}');
      if (cached != null) {
        var cachedData = jsonDecode(cached);
        DateTime cacheTime = DateTime.parse(cachedData['timestamp']);
        if (DateTime.now().difference(cacheTime).inHours < 24) {
          setState(() {
            _results = List<Map<String, dynamic>>.from(cachedData['results']);
            _lastDocument = _results.isNotEmpty ? _results.last['doc'] : null;
            _hasMore = _results.length == 20;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Showing cached results due to network issue')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error searching providers: $e')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching providers: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreProviders() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      var results = await _firestore.searchProviders(
        _searchController.text.trim(),
        _userLocation!,
        minRating: _minRating,
        verifiedOnly: _verifiedOnly,
        category: _selectedCategory,
        sortBy: _sortBy,
        limit: 10,
        startAfter: _lastDocument,
      );

      setState(() {
        _results.addAll(results);
        _lastDocument = results.isNotEmpty ? results.last['doc'] : _lastDocument;
        _hasMore = results.length == 10;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading more providers: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _callProvider(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone number available')));
      return;
    }
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot make call')));
    }
  }

  Future<void> _openOrCreateChat(String providerId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userId = user.uid;
    var existingChat = await FirebaseFirestore.instance
        .collection('chat_requests')
        .where('providerId', isEqualTo: providerId)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'accepted'])
        .limit(1)
        .get();

    String chatId;
    if (existingChat.docs.isNotEmpty) {
      chatId = existingChat.docs.first.id;
    } else {
      // Create new chat request
    final doc = await FirebaseFirestore.instance.collection('chat_requests').add({
      'providerId': providerId,
      'userId': userId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadCount': 1, // new chat counts as 1 unread
    });
    chatId = doc.id;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(requestId: chatId)),
    );
  }

  void _showFilterDialog() {
    double tempMinRating = _minRating;
    bool tempVerifiedOnly = _verifiedOnly;
    String tempSortBy = _sortBy;
    String? tempSelectedCategory = _selectedCategory;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter & Sort', style: TextStyle(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Category', style: TextStyle(fontSize: 14)),
              DropdownButton<String?>(
                value: tempSelectedCategory,
                isExpanded: true,
                hint: const Text('Select Category'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Categories')),
                  ...['Landscaping', 'Roadside Assistance', 'Plumbing', 'Electrical']
                      .map((category) => DropdownMenuItem(value: category, child: Text(category))),
                ],
                onChanged: (value) {
                  setState(() => tempSelectedCategory = value);
                },
              ),
              const SizedBox(height: 8),
              const Text('Minimum Rating', style: TextStyle(fontSize: 14)),
              Slider(
                value: tempMinRating,
                min: 0.0,
                max: 5.0,
                divisions: 10,
                label: tempMinRating.toStringAsFixed(1),
                activeColor: Colors.blue[700],
                onChanged: (value) {
                  setState(() => tempMinRating = value);
                },
              ),
              Row(
                children: [
                  Checkbox(
                    value: tempVerifiedOnly,
                    activeColor: Colors.blue[700],
                    onChanged: (value) {
                      setState(() => tempVerifiedOnly = value ?? false);
                    },
                  ),
                  const Text('Verified Providers Only', style: TextStyle(fontSize: 14)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Sort By', style: TextStyle(fontSize: 14)),
              DropdownButton<String>(
                value: tempSortBy,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'distance', child: Text('Distance')),
                  DropdownMenuItem(value: 'rating', child: Text('Rating')),
                  DropdownMenuItem(value: 'availability', child: Text('Availability')),
                ],
                onChanged: (value) {
                  setState(() => tempSortBy = value ?? 'distance');
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _minRating = tempMinRating;
                _verifiedOnly = tempVerifiedOnly;
                _sortBy = tempSortBy;
                _selectedCategory = tempSelectedCategory;
              });
              if (_searchController.text.isNotEmpty) {
                _searchProviders();
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Services', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFFA855F7)]),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, size: 24, color: Colors.white),
            onPressed: _showFilterDialog,
            tooltip: 'Filter Results',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.purple[50]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'Search (e.g., mechanic, tire repair)',
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                  prefixIcon: Icon(Icons.search, color: Colors.blue[700], size: 24),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.grey[600], size: 24),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _results = []);
                            _removeOverlay();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Filters: ${_selectedCategory ?? "All Categories"} ${_minRating > 0 ? "| Rating ≥ ${_minRating.toStringAsFixed(1)}" : ""} ${_verifiedOnly ? "| Verified Only" : ""} | Sort: ${_sortBy.capitalize()}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${_results.length} Providers',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedOpacity(
                opacity: _isLoading && _results.isEmpty ? 0.5 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: _isLoading && _results.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('Searching...', style: TextStyle(fontSize: 16, color: Colors.grey)),
                          ],
                        ),
                      )
                    : _userLocation == null
                        ? const Center(child: Text('Waiting for location...', style: TextStyle(fontSize: 16, color: Colors.grey)))
                        : _results.isEmpty
                            ? const Center(child: Text('No providers found', style: TextStyle(fontSize: 16, color: Colors.grey)))
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                itemCount: _results.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _results.length && _hasMore) {
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                  var provider = _results[index];
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ViewProviderProfileScreen(providerId: provider['id']),
                                        ),
                                      ),
                                      child: Card(
                                        elevation: 3,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: Image.network(
                                                  provider['profilePicUrl'] ?? 'https://placehold.co/48x48?text=Provider',
                                                  width: 48,
                                                  height: 48,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, _) => Image.asset(
                                                    'assets/default_profile.png',
                                                    width: 48,
                                                    height: 48,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            provider['name'] ?? 'Unknown',
                                                            style: const TextStyle(
                                                              fontWeight: FontWeight.w700,
                                                              fontSize: 14,
                                                              color: Color(0xFF111827),
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        if (provider['isVerified'] == true)
                                                          Icon(Icons.verified, color: Colors.green[600], size: 18),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      provider['type'] ?? 'Unknown',
                                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      provider['address'] ?? 'No address provided',
                                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      provider['availability'] == true ? 'Available' : 'Offline',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: provider['availability'] == true ? Colors.green[600] : Colors.red[600],
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        Text(
                                                          provider['distance'] != null && provider['distance'] != double.infinity
                                                              ? 'Distance: ${(provider['distance'] as double).toStringAsFixed(1)} km'
                                                              : 'Distance: Unknown',
                                                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Row(
                                                          children: List.generate(5, (starIndex) {
                                                            return Icon(
                                                              starIndex < ((provider['rating'] as double?)?.round() ?? 0)
                                                                  ? Icons.star
                                                                  : Icons.star_border,
                                                              color: Colors.amber,
                                                              size: 16,
                                                            );
                                                          }),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          provider['rating'] != null
                                                              ? '${(provider['rating'] as double).toStringAsFixed(1)}/5'
                                                              : 'N/A',
                                                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Column(
                                                children: [
                                                  IconButton(
                                                    icon: Icon(Icons.phone, color: Colors.green[600], size: 24),
                                                    onPressed: () => _callProvider(provider['phoneNumber']),
                                                    tooltip: 'Call',
                                                  ),
                                                  IconButton(
                                                    icon: Icon(Icons.chat, color: Colors.blue[600], size: 24),
                                                    onPressed: () => _openOrCreateChat(provider['id']),
                                                    tooltip: 'Chat',
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Utility extension for string capitalization
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}