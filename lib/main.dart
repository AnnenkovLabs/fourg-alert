import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/coverage_engine.dart';
import 'services/location_service.dart';
import 'services/network_monitor.dart';
import 'services/route_predictor.dart';
import 'services/notification_service.dart';
import 'services/app_state.dart';
import 'services/globals.dart';
import 'ui/screens/home_screen.dart';

String? _initError;

void main() async {
  // Catch ALL errors so Flutter can still render something useful
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    final coverage = CoverageEngine();
    final location = LocationService();
    final network = NetworkMonitor();
    final notifications = NotificationService();

    // Init notifications (this may work even if coverage fails)
    try {
      await notifications.init();
    } catch (e) {
      debugPrint('Notification init failed: $e');
      // Non-fatal — app can work without TTS/push
    }

    // Load coverage data
    try {
      await coverage.load();
    } catch (e) {
      debugPrint('Coverage load failed: $e');
      _initError = 'Failed to load coverage data: $e';
      // Mark as loaded with a synthetic error state so the UI shows something
      // The coverage engine's _loaded flag won't be true; we handle this in the UI
    }

    // Create app state coordinator (even with partial init)
    setAppState(AppState(
      coverage: coverage,
      location: location,
      network: network,
      predictor: RoutePredictor(coverage),
      notifications: notifications,
    ));

    // Set up global error handler for Flutter framework errors
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exception}');
      debugPrint('Stack: ${details.stack}');
    };

    runApp(FourGAlertApp(initError: _initError));
  }, (error, stack) {
    // Catch errors from isolates / async gaps
    debugPrint('Unhandled error: $error');
    debugPrint('Stack: $stack');
    _initError = 'Unexpected error: $error';
    runApp(FourGAlertApp(initError: _initError));
  });
}

class FourGAlertApp extends StatelessWidget {
  final String? initError;
  const FourGAlertApp({super.key, this.initError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '4G Alert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C853),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(initError: initError),
    );
  }
}
