/// App coordinator — ties all services together and manages state.
library;

import 'dart:async';
import '../core/coverage_engine.dart';
import 'location_service.dart';
import 'network_monitor.dart';
import 'route_predictor.dart';
import 'notification_service.dart';

/// Main app state.
class AppState {
  // Services
  final CoverageEngine coverage;
  final LocationService location;
  final NetworkMonitor network;
  final RoutePredictor predictor;
  final NotificationService notifications;

  // Reactive state
  LocationData? _currentLocation;
  NetworkStatus _networkStatus = const NetworkStatus(state: NetworkState.checking);
  CoverageInfo? _currentCoverage;
  CoverageEvent? _nextEvent;
  double _timeToNextEvent = double.infinity;
  double _timeInZone = 0;
  bool _inDeadZone = false;

  // TTS announcement tracking — prevents spam
  final Set<double> _announcedDistances = {}; // distances already announced for current zone
  final Set<int> _announcedCountdowns = {}; // countdown minutes already announced
  bool _announcedEntered = false;
  bool _announcedStable = false;
  CoverageEvent? _lastEvent; // to detect new zone

  // State stream for UI
  final _stateController = StreamController<void>.broadcast();
  Stream<void> get stateStream => _stateController.stream;

  AppState({
    required this.coverage,
    required this.location,
    required this.network,
    required this.predictor,
    required this.notifications,
  });

  // Getters for UI
  LocationData? get currentLocation => _currentLocation;
  NetworkStatus get networkStatus => _networkStatus;
  CoverageInfo? get currentCoverage => _currentCoverage;
  CoverageEvent? get nextEvent => _nextEvent;
  double get timeToNextEvent => _timeToNextEvent;
  double get timeInZone => _timeInZone;
  bool get inDeadZone => _inDeadZone;
  bool get isReady => coverage.isLoaded && _currentLocation != null;

  /// Set which operators to include (bitmask: 1=Vodafone, 2=Kyivstar, 4=lifecell).
  /// 0 = all operators.
  void setOperatorFilter(int mask) {
    coverage.operatorFilter = mask;
  }
  int get operatorFilter => coverage.operatorFilter;

  // Counters for tracking zone transitions
  // CoverageEvent? _currentZoneStart;

  /// Start all services and monitoring.
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Subscribe to location updates
    location.stream.listen(_onLocationUpdate);

    // Subscribe to network status
    network.stream.listen(_onNetworkUpdate);

    // Start monitoring
    network.start();
    await location.start();
  }

  void _onLocationUpdate(LocationData loc) {
    _currentLocation = loc;

    if (!coverage.isLoaded) return;

    // Query current coverage
    _currentCoverage = coverage.query(loc.lat, loc.lon);

    // Predict upcoming changes
    final events = predictor.predict(loc);
    if (events.isNotEmpty) {
      _nextEvent = events.first;
      _timeToNextEvent = _nextEvent!.timeSeconds;
    } else {
      _nextEvent = null;
      _timeToNextEvent = double.infinity;
    }

    _stateController.add(null);
  }

  void _onNetworkUpdate(NetworkStatus status) {
    final wasOnline = _networkStatus.hasWorking4g;
    _networkStatus = status;

    if (!wasOnline && status.hasWorking4g) {
      _inDeadZone = false;
      _timeInZone = 0;
      _announcedCountdowns.clear();
      _announcedEntered = false;
      notifications.announce(
        AlertType.restored,
        '4G відновлено',
        push: true,
      );
    } else if (wasOnline && status.isOffline) {
      _inDeadZone = true;
      _announcedDistances.clear();
      _announcedEntered = false;
    }

    _stateController.add(null);
  }

  /// Update time counters and check for TTS announcements.
  void tick(double dt) {
    if (_inDeadZone) {
      _timeInZone += dt;
    }
    if (_timeToNextEvent < double.infinity) {
      _timeToNextEvent -= dt;
    }
    _checkTtsAnnouncements();
  }

  /// Check if we should announce something via TTS.
  void _checkTtsAnnouncements() {
    if (!isReady) return;

    // Detect new event (zone changed) — reset tracking
    if (_nextEvent != _lastEvent) {
      _lastEvent = _nextEvent;
      _announcedDistances.clear();
      _announcedCountdowns.clear();
      _announcedEntered = false;
      _announcedStable = false;
    }

    final event = _nextEvent;
    if (event == null) return;

    final distanceKm = (_timeToNextEvent > 0
        ? (event.distanceKm * _timeToNextEvent / event.timeSeconds)
        : 0)
        .toDouble();

    // --- Approaching blind zone: announce at thresholds ---
    if (!_inDeadZone && event.isLosing4g) {
      _announceAtThreshold(distanceKm, event);
    }

    // --- In blind zone: countdown announcements ---
    if (_inDeadZone) {
      _announceCountdown();
    }

    // --- Stable 4G confirmed after blind zone ---
    if (!_inDeadZone && event.endsWithStable4g && !_announcedStable) {
      _announcedStable = true;
      notifications.announce(
        AlertType.restored,
        'Стабільний 4G підтверджено на ${_secToUa(event.stableAfterSeconds)}',
        push: false,
      );
    }
  }

  void _announceAtThreshold(double distanceKm, CoverageEvent event) {
    // Thresholds (km): 5, 3, 2, 1, 0.5, 0.2
    const thresholds = [5.0, 3.0, 2.0, 1.0, 0.5, 0.2];
    for (final t in thresholds) {
      if (distanceKm <= t && distanceKm > t - 0.3 && !_announcedDistances.contains(t)) {
        _announcedDistances.add(t);

        final distText = t >= 1
            ? '${t.toStringAsFixed(0)} кілометрів'
            : '${(t * 1000).toInt()} метрів';
        final zoneText = _secToUa(event.zoneTimeSeconds);

        final msg = 'Через $distText зникне 4G. '
            'Сліпа зона триватиме приблизно $zoneText. '
            '${event.endsWithStable4g ? "Стабільний 4G повернеться через ${_secToUa(event.stableAfterSeconds)}." : ""}';

        notifications.announce(AlertType.warning, msg, push: false);
        return;
      }
    }

    // Just about to enter
    if (distanceKm <= 0.15 && !_announcedEntered) {
      _announcedEntered = true;
      notifications.announce(
        AlertType.warning,
        'Вхід у сліпу зону. 4G відсутній ${_secToUa(event.zoneTimeSeconds)}.',
        push: true,
      );
    }
  }

  void _announceCountdown() {
    final remainingSec = _timeToNextEvent;
    if (remainingSec <= 0) return;

    // Announce at: 5min, 2min, 1min, 30sec, 10sec
    final checkpoints = [300, 120, 60, 30, 10];
    for (final cp in checkpoints) {
      if (remainingSec <= cp && remainingSec > cp - 6 && !_announcedCountdowns.contains(cp)) {
        _announcedCountdowns.add(cp);
        final text = cp >= 60
            ? '4G відновиться приблизно через ${cp ~/ 60} хвилин'
            : '4G відновиться приблизно через $cp секунд';
        notifications.announce(AlertType.countdown, text, push: false);
        return;
      }
    }
  }

  /// Convert seconds to Ukrainian text (e.g. "8 хвилин", "12 хвилин", "30 секунд").
  String _secToUa(double sec) {
    if (sec >= 3600) {
      final h = (sec / 3600).toInt();
      final m = ((sec % 3600) / 60).toInt();
      return '$h г $m хв';
    }
    if (sec >= 60) return '${(sec / 60).toInt()} хвилин';
    return '${sec.toInt()} секунд';
  }

  /// Format the status text for the overlay widget.
  String get statusText {
    if (!isReady) return 'Loading...';

    if (_inDeadZone) {
      final secs = _timeToNextEvent > 0 ? _timeToNextEvent : 0;
      if (secs >= 60) {
        return '4G in ${(secs / 60).toInt()} min';
      }
      return '4G in ${secs.toInt()} sec';
    }

    if (_nextEvent != null) {
      final e = _nextEvent!;
      return '4G lost in ${e.distanceText} (${e.timeText})';
    }

    if (_currentCoverage != null && _currentCoverage!.has4g) {
      return '4G OK';
    }

    return 'No coverage data';
  }

  void stop() {
    _started = false;
    location.stop();
    network.stop();
    notifications.cancelOngoingStatus();
  }

  void dispose() {
    stop();
    location.dispose();
    network.dispose();
    _stateController.close();
    notifications.dispose();
  }
}
