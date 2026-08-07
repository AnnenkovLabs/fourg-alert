/// Routing service using OSRM public API for road-following routes.
/// Falls back to straight-line interpolation if API unavailable.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

class RoutePoint {
  final double lat;
  final double lon;
  const RoutePoint(this.lat, this.lon);
}

class RouteResult {
  final List<RoutePoint> points;
  final double distanceKm;
  final double durationMin;

  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });
}

class RoutingService {
  // Public OSRM demo server (rate-limited, for development)
  static const _osrmUrl = 'https://router.project-osrm.org/route/v1/driving/';

  /// Get road-following route between waypoints.
  /// Falls back to straight-line interpolation on failure.
  Future<RouteResult> getRoute(
    List<RoutePoint> waypoints, {
    bool useRoads = true,
  }) async {
    if (waypoints.length < 2) {
      return const RouteResult(points: [], distanceKm: 0, durationMin: 0);
    }

    if (useRoads) {
      try {
        return await _fetchOsrmRoute(waypoints);
      } catch (_) {
        // Fall through to straight-line
      }
    }

    return _straightLineRoute(waypoints);
  }

  Future<RouteResult> _fetchOsrmRoute(List<RoutePoint> waypoints) async {
    // Build coordinates string: lon,lat;lon,lat;...
    final coords = waypoints
        .map((p) => '${p.lon},${p.lat}')
        .join(';');

    final url = '$_osrmUrl$coords?overview=full&geometries=geojson&steps=false';
    final response = await http.get(Uri.parse(url)).timeout(
      const Duration(seconds: 10),
    );

    if (response.statusCode != 200) {
      throw Exception('OSRM returned ${response.statusCode}');
    }

    final data = json.decode(response.body);
    final routes = data['routes'] as List;
    if (routes.isEmpty) throw Exception('No routes found');

    final route = routes[0];
    final distanceKm = (route['distance'] as num) / 1000.0;
    final durationMin = (route['duration'] as num) / 60.0;
    final geometry = route['geometry'] as Map;
    final coordsList = geometry['coordinates'] as List;

    final points = coordsList.map((c) {
      return RoutePoint(
        (c[1] as num).toDouble(), // lat
        (c[0] as num).toDouble(), // lon
      );
    }).toList();

    return RouteResult(
      points: points,
      distanceKm: distanceKm,
      durationMin: durationMin,
    );
  }

  /// Generate straight-line route with intermediate points.
  RouteResult _straightLineRoute(List<RoutePoint> waypoints) {
    final points = <RoutePoint>[];
    double totalDist = 0;

    for (int i = 0; i < waypoints.length - 1; i++) {
      final a = waypoints[i];
      final b = waypoints[i + 1];
      final segDist = _haversine(a.lat, a.lon, b.lat, b.lon);
      totalDist += segDist;

      // Interpolate points every 200m
      final steps = (segDist / 200).ceil().clamp(1, 500);
      for (int s = 0; s <= steps; s++) {
        final frac = s / steps;
        points.add(RoutePoint(
          a.lat + (b.lat - a.lat) * frac,
          a.lon + (b.lon - a.lon) * frac,
        ));
      }
    }

    const avgSpeedKph = 60.0;
    return RouteResult(
      points: points,
      distanceKm: totalDist,
      durationMin: totalDist / avgSpeedKph * 60,
    );
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
