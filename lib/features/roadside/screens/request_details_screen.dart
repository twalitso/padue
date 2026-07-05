import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:padue/core/notification_service.dart';
import 'package:padue/core/utils.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/firestore_service.dart';
import '../../../core/admob_config.dart';
import '../../roadside/models/provider.dart';
import 'chat_screen.dart';

class RequestDetailsScreen extends StatefulWidget {
  final String requestId;
  const RequestDetailsScreen({required this.requestId, super.key});

  @override
  State<RequestDetailsScreen> createState() => _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends State<RequestDetailsScreen> {
  final _firestore = FirestoreService();
  final MapController _mapController = MapController();

  DocumentSnapshot? _requestSnap;
  Provider? _provider;
  LatLng? _userPos;
  LatLng? _providerPos;
  List<LatLng> _routePoints = [];
  double? _eta;
  Timer? _timer;

  // Ads
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  bool _isAdFree = false;

  // Chat
  int _unreadChatCount = 0;

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    await _checkAdFreeAndLoadBanner();
    await _loadRequestData();
    _listenForChatUnread();
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => _refreshDynamicData());
  }

  Future<void> _checkAdFreeAndLoadBanner() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    _isAdFree = doc['adFree'] == true;

    if (_isAdFree) return;

    _bannerAd = BannerAd(
      adUnitId: AdmobConfig().banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          setState(() => _isBannerAdLoaded = false);
        },
      ),
    );
    await _bannerAd!.load();
  }

  void _listenForChatUnread() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    FirebaseFirestore.instance
        .collection('chat_requests')
        .doc(widget.requestId)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      final data = doc.data()!;
      setState(() => _unreadChatCount = data['unreadCount'] ?? 0);
    });
  }

  Future<void> _loadRequestData() async {
    final reqSnap = await FirebaseFirestore.instance.collection('requests').doc(widget.requestId).get();
    if (!reqSnap.exists) return;

    final data = reqSnap.data()!;
    final providerId = data['providerId'] as String?;

    Provider? provider;
    LatLng? providerLat;

    if (providerId != null) {
      final results = await Future.wait([
        _firestore.getProviderProfile(providerId),
        FirebaseFirestore.instance.collection('providers').doc(providerId).get(),
      ]);

      provider = results[0] as Provider?;
      final geo = (results[1] as DocumentSnapshot)['location'] as GeoPoint?;
      if (geo != null) providerLat = LatLng(geo.latitude, geo.longitude);
    }

    final pos = await Geolocator.getCurrentPosition();
    final userLatLng = LatLng(pos.latitude, pos.longitude);

    setState(() {
      _requestSnap = reqSnap;
      _provider = provider;
      _userPos = userLatLng;
      _providerPos = providerLat;
    });

    if (_userPos != null && _providerPos != null) {
      await _fetchOSRMRoute();
      _fitMap();
    }
  }

  Future<void> _refreshDynamicData() async {
    if (!mounted) return;
    final pos = await Geolocator.getCurrentPosition();
    setState(() => _userPos = LatLng(pos.latitude, pos.longitude));

    if (_providerPos != null) {
      await _fetchOSRMRoute();
      _fitMap();
    }
  }

  Future<void> _fetchOSRMRoute() async {
    if (_userPos == null || _providerPos == null) return;

    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${_userPos!.longitude},${_userPos!.latitude};'
      '${_providerPos!.longitude},${_providerPos!.latitude}'
      '?overview=full&geometries=geojson'
    );

    try {
      final res = await http.get(url);
      if (res.statusCode != 200) return;

      final json = jsonDecode(res.body);
      final route = json['routes'][0];
      final coords = (route['geometry']['coordinates'] as List)
          .map<LatLng>((c) => LatLng(c[1], c[0]))
          .toList();
      final durationMin = (route['duration'] as num).toDouble() / 60;

      setState(() {
        _routePoints = coords;
        _eta = durationMin;
      });
    } catch (e) {
      debugPrint('OSRM route fetch error: $e');
    }
  }

  void _fitMap() {
    if (_userPos == null) return;

    final points = [_userPos!];
    if (_providerPos != null) points.add(_providerPos!);

    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)));
  }

  Future<void> _cancelRequest() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final reqDoc = await FirebaseFirestore.instance.collection('requests').doc(widget.requestId).get();
      if (!reqDoc.exists) return;

      final data = reqDoc.data()!;
      final providerId = data['providerId'] as String?;
      final issue = data['issue'] ?? data['service'] ?? 'service';

      if (providerId != null) {
        final providerDoc = await FirebaseFirestore.instance.collection('providers').doc(providerId).get();
        final playerId = providerDoc['oneSignalSubscriptionId'] ?? providerDoc['oneSignalSubscriptionId'];
        if (playerId != null && playerId.isNotEmpty) {
          await NotificationService.sendToSubscriptionIds(
            subscriptionIds: [playerId],
            title: 'Request Cancelled',
            body: 'The user cancelled their request for $issue.',
            data: {'type': 'request_cancel', 'requestId': widget.requestId},
          );
        }
      }

      await FirebaseFirestore.instance.collection('requests').doc(widget.requestId).update({
        'status': 'canceled',
        'canceledAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request cancelled')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Cancel request error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to cancel request')));
    }
  }

  Future<void> _openOrCreateChat(String providerId, String userId) async {
  try {
    final existingChat = await FirebaseFirestore.instance
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
      final doc = await FirebaseFirestore.instance
          .collection('chat_requests')
          .add({
        'providerId': providerId,
        'userId': userId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadCount': 0,
      });

      chatId = doc.id;
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(requestId: chatId)),
    );
  } catch (e) {
    debugPrint('Error opening chat: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open chat')),
      );
    }
  }
}



  Future<void> _call(String? phone) async {
    if (phone == null) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _shareLocation() async {
    if (_userPos == null) return;
    final desc = (_requestSnap?.data() as Map<String, dynamic>?)?['locationDescription'] ?? 'No description';
    final text =
        'Help request location: $desc\nLat: ${_userPos!.latitude}, Lng: ${_userPos!.longitude}\n'
        'Open in maps: https://www.google.com/maps/search/?api=1&query=${_userPos!.latitude},${_userPos!.longitude}';
    await Share.share(text, subject: 'My Roadside Assistance Request Location');
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_requestSnap == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final data = _requestSnap!.data()! as Map<String, dynamic>;
    final status = data['status'] as String;
    final created = (data['createdAt'] as Timestamp?)?.toDate();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Details'),
        actions: [
          if (status == 'open' || status == 'accepted')
            IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: _cancelRequest),
        ],
      ),
      body: Column(
        children: [
          // Map
          Expanded(
            flex: 3,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: _userPos!, initialZoom: 15),
              children: [
                TileLayer(
  urlTemplate: 'https://tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.twalitso.padue'
  , subdomains: const ['a', 'b', 'c']),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(polylines: [Polyline(points: _routePoints, color: Colors.blue, strokeWidth: 5)]),
                MarkerLayer(markers: [
                  if (_userPos != null)
                    Marker(
                      point: _userPos!,
                      width: 100,
                      height: 80,
                      child: Column(
                        children: [
                          const Icon(Icons.person_pin_circle, color: Colors.green, size: 40),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(20)),
                            child: const Text('Me', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ), 
                    ),
                  if (_providerPos != null)
                    Marker(
                      point: _providerPos!,
                      width: 120,
                      height: 90,
                      child:  Column(
                        children: [
                          SvgPicture.asset('assets/icons/toolbox.svg', width: 40, height: 40, colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                            child: Text(_provider?.name?.split(' ').first ?? 'Provider', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                ]),
              ],
            ),
          ),

          // Request details + actions
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('Service', data['service'] ?? '—'),
                  _infoRow('Notes', data['notes'] ?? '—'),
                  _infoRow('Location', data['locationDescription'] ?? '—'),
                  _infoRow('Status', status.replaceAll('_', ' ').toUpperCase()),
                  _infoRow('Created', created != null ? _format(created) : '—'),
                  if (_eta != null) _infoRow('ETA', '${_eta!.toStringAsFixed(0)} min', color: Colors.green),
                  const Divider(height: 32),
                  if (_provider != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                          _actionButton(
        Icons.chat,
        'Chat${_unreadChatCount > 0 ? ' ($_unreadChatCount)' : ''}',
        Colors.blue,
        () => _openOrCreateChat(_provider!.id!, FirebaseAuth.instance.currentUser!.uid),
      ),
                       // _actionButton(Icons.chat, 'Chat${_unreadChatCount > 0 ? ' ($_unreadChatCount)' : ''}', Colors.blue, _openChat),
                        _actionButton(Icons.phone, 'Call', Colors.green, () => _call(_provider!.phoneNumber)),
                        _actionButton(Icons.share, 'Share', Colors.purple, _shareLocation),
                      ],
                    ),
                  if (status == 'open' || status == 'accepted')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.cancel, size: 28),
                        label: const Text('Cancel This Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[700],
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _cancelRequest,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Banner Ad
          if (!_isAdFree && _isBannerAdLoaded && _bannerAd != null)
            SizedBox(width: double.infinity, height: _bannerAd!.size.height.toDouble(), child: AdWidget(ad: _bannerAd!)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(value, style: TextStyle(color: color ?? Colors.black87))),
          ],
        ),
      );

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return Column(
      children: [
        FloatingActionButton.small(heroTag: null, backgroundColor: color, onPressed: onTap, child: Icon(icon, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  String _format(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }
}
