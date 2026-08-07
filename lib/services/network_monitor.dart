/// Network monitor that checks real 4G status and detects "phantom 4G".
/// Also distinguishes mobile data from WiFi/hotspot connections.
library;

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

enum NetworkState { online4g, no4g, phantom4g, checking, wifi, hotspot }

class NetworkStatus {
  final NetworkState state;
  final int? latencyMs;
  final String? detail;
  final bool isHotspot; // true if connected via WiFi hotspot (not native mobile)
  final String? connectionType; // "mobile", "wifi", "hotspot", "none"

  const NetworkStatus({
    required this.state,
    this.latencyMs,
    this.detail,
    this.isHotspot = false,
    this.connectionType,
  });

  bool get hasWorking4g => state == NetworkState.online4g;
  bool get isOffline => state == NetworkState.no4g || state == NetworkState.phantom4g;
  bool get isWifiOrHotspot => state == NetworkState.wifi || state == NetworkState.hotspot;

  @override
  String toString() =>
      'NetworkStatus($state, lat:${latencyMs}ms, hotspot:$isHotspot)';
}

class NetworkMonitor {
  final _controller = StreamController<NetworkStatus>.broadcast();
  NetworkStatus _lastStatus = const NetworkStatus(state: NetworkState.checking);
  Timer? _antiFlapTimer;
  Timer? _phantomCheckTimer;
  bool _wasOffline = false;
  bool _isHotspot = false;

  Stream<NetworkStatus> get stream => _controller.stream;
  NetworkStatus get lastStatus => _lastStatus;

  static const _pingUrl = 'https://clients3.google.com/generate_204';
  static const _fallbackUrl = 'https://www.google.com/favicon.ico';

  /// Start monitoring.
  void start() {
    Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    _checkNow();
    _phantomCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _detectPhantom4G();
    });
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      _isHotspot = _detectHotspot();
      final state = _isHotspot ? NetworkState.hotspot : NetworkState.wifi;
      _emit(NetworkStatus(
        state: state,
        connectionType: _isHotspot ? 'hotspot' : 'wifi',
        isHotspot: _isHotspot,
        detail: _isHotspot ? 'Connected via WiFi hotspot' : 'Connected to WiFi',
      ));
      return;
    }

    if (!results.contains(ConnectivityResult.mobile)) {
      _emit(const NetworkStatus(
        state: NetworkState.no4g,
        detail: 'No connection',
        connectionType: 'none',
      ));
      return;
    }

    _detectPhantom4G();
  }

  /// Heuristic hotspot detection.
  /// WiFi with internet but with cellular-like characteristics = likely hotspot.
  bool _detectHotspot() {
    // A WiFi connection that routes through cellular is a hotspot.
    // We can't reliably detect this on Android without platform-specific APIs,
    // but we flag it so the user knows they're not on native mobile.
    return false; // Platform-specific — placeholder
  }

  Future<void> _checkNow() async {
    final connectivity = await Connectivity().checkConnectivity();

    if (connectivity.contains(ConnectivityResult.wifi)) {
      _emit(NetworkStatus(
        state: NetworkState.wifi,
        connectionType: 'wifi',
        detail: 'WiFi connected',
      ));
      return;
    }

    if (!connectivity.contains(ConnectivityResult.mobile)) {
      _emit(const NetworkStatus(
        state: NetworkState.no4g,
        detail: 'No connection',
        connectionType: 'none',
      ));
      return;
    }

    await _detectPhantom4G();
  }

  Future<void> _detectPhantom4G() async {
    final sw = Stopwatch()..start();

    try {
      final response = await http
          .head(Uri.parse(_pingUrl))
          .timeout(const Duration(seconds: 3));
      sw.stop();
      final latency = sw.elapsedMilliseconds;

      if (response.statusCode == 204 || response.statusCode == 200) {
        if (_wasOffline) {
          _antiFlapTimer?.cancel();
          _antiFlapTimer = Timer(const Duration(seconds: 1), () {
            _wasOffline = false;
            _emit(NetworkStatus(
              state: NetworkState.online4g,
              latencyMs: latency,
              detail: '4G verified',
              connectionType: 'mobile',
            ));
          });
          _emit(NetworkStatus(
            state: NetworkState.checking,
            latencyMs: latency,
            detail: 'Verifying 4G...',
            connectionType: 'mobile',
          ));
        } else {
          _emit(NetworkStatus(
            state: NetworkState.online4g,
            latencyMs: latency,
            detail: '4G OK',
            connectionType: 'mobile',
          ));
        }
      } else {
        _wasOffline = true;
        _emit(NetworkStatus(
          state: NetworkState.phantom4g,
          detail: '4G icon on, no data (HTTP ${response.statusCode})',
          connectionType: 'mobile',
        ));
      }
    } catch (e) {
      sw.stop();
      try {
        final response = await http
            .head(Uri.parse(_fallbackUrl))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          _wasOffline = false;
          _emit(NetworkStatus(
            state: NetworkState.online4g,
            latencyMs: sw.elapsedMilliseconds,
            detail: '4G OK (fallback)',
            connectionType: 'mobile',
          ));
          return;
        }
      } catch (_) {}

      _wasOffline = true;
      _emit(NetworkStatus(
        state: NetworkState.no4g,
        detail: 'No internet: $e',
        connectionType: 'mobile',
      ));
    }
  }

  void _emit(NetworkStatus status) {
    _lastStatus = status;
    _controller.add(status);
  }

  void stop() {
    _antiFlapTimer?.cancel();
    _phantomCheckTimer?.cancel();
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
