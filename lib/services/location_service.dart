/// GPS location tracking service.
/// Provides continuous location updates for route prediction.
library;

import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationData {
  final double lat;
  final double lon;
  final double speed; // m/s
  final double heading; // degrees
  final double accuracy; // meters
  final DateTime timestamp;

  const LocationData({
    required this.lat,
    required this.lon,
    required this.speed,
    required this.heading,
    required this.accuracy,
    required this.timestamp,
  });

  double get speedKph => speed * 3.6;
  double get speedMps => speed;

  bool get isMoving => speed > 1.0; // > 3.6 km/h

  @override
  String toString() =>
      'Location(${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}, '
      '${speedKph.toStringAsFixed(0)}km/h, hdg:${heading.toStringAsFixed(0)}°)';
}

class LocationService {
  final _controller = StreamController<LocationData>.broadcast();
  StreamSubscription<Position>? _subscription;
  LocationData? _last;
  bool _running = false;

  Stream<LocationData> get stream => _controller.stream;
  LocationData? get last => _last;
  bool get isRunning => _running;

  Future<bool> requestPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final result = await Geolocator.requestPermission();
      return result == LocationPermission.whileInUse ||
          result == LocationPermission.always;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  /// Start GPS tracking with optimized settings for driving.
  Future<void> start() async {
    if (_running) return;

    final hasPermission = await requestPermission();
    if (!hasPermission) throw Exception('Location permission denied');

    _running = true;

    // Use high accuracy for driving, update every 10m or 5s
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // update every 10 meters
        timeLimit: Duration(seconds: 5),
      ),
    ).listen(_onPosition);
  }

  void _onPosition(Position pos) {
    _last = LocationData(
      lat: pos.latitude,
      lon: pos.longitude,
      speed: pos.speed > 0 ? pos.speed : 0,
      heading: pos.heading > 0 ? pos.heading : 0,
      accuracy: pos.accuracy,
      timestamp: pos.timestamp,
    );
    _controller.add(_last!);
  }

  Future<void> stop() async {
    _running = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
