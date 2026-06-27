// lib/core/osm_navigation_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class OSMNavigationService {
  static Future<Map<String, dynamic>?> getRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson&steps=true'
    );
    try {
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      final route = json['routes'][0];

      // Extract polyline
      final coords = (route['geometry']['coordinates'] as List)
          .map<LatLng>((c) => LatLng(c[1], c[0]))
          .toList();

      // Extract real steps
      final legs = route['legs'] as List;
      final steps = <Map<String, dynamic>>[];
      for (var leg in legs) {
        for (var step in leg['steps']) {
          final instruction = step['maneuver']['type'] == 'turn'
              ? _formatManeuver(step['maneuver']['modifier'] ?? '', step['name'] ?? '')
              : 'Continue on ${step['name']}';
          steps.add({
            'instruction': instruction,
            'distance': (step['distance'] as num).toDouble(),
            'duration': (step['duration'] as num).toDouble(),
          });
        }
      }

      final duration = (route['duration'] as num).toDouble() / 60;
      final distance = (route['distance'] as num).toDouble() / 1000;

      return {
        'points': coords,
        'duration_min': duration,
        'distance_km': distance,
        'steps': steps,
      };
    } catch (e) {
      return null;
    }
  }

  static String _formatManeuver(String? modifier, String road) {
    if (modifier == null) return 'Continue on $road';
    final dir = modifier.toLowerCase();
    if (dir.contains('left')) return 'Turn left onto $road';
    if (dir.contains('right')) return 'Turn right onto $road';
    if (dir.contains('sharp left')) return 'Sharp left onto $road';
    if (dir.contains('sharp right')) return 'Sharp right onto $road';
    if (dir.contains('slight left')) return 'Slight left onto $road';
    if (dir.contains('slight right')) return 'Slight right onto $road';
    return 'Continue on $road';
  }
}