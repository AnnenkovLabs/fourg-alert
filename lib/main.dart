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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Init services
  final coverage = CoverageEngine();
  final location = LocationService();
  final network = NetworkMonitor();
  final notifications = NotificationService();

  await notifications.init();
  await coverage.load();

  // Create app state coordinator
  setAppState(AppState(
    coverage: coverage,
    location: location,
    network: network,
    predictor: RoutePredictor(coverage),
    notifications: notifications,
  ));

  runApp(const FourGAlertApp());
}

class FourGAlertApp extends StatelessWidget {
  const FourGAlertApp({super.key});

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
      home: const HomeScreen(),
    );
  }
}
