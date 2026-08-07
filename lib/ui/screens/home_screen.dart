/// Main app screen with map + dashboard tabs.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fourg_alert/services/globals.dart';
import 'package:fourg_alert/ui/screens/route_planner_screen.dart';
import 'package:fourg_alert/ui/screens/settings_screen.dart';
import 'package:fourg_alert/ui/screens/offline_maps_screen.dart';
import 'package:fourg_alert/ui/widgets/dashboard_widget.dart';
import 'package:fourg_alert/services/offline_tiles.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _tickTimer;
  StreamSubscription? _stateSub;
  bool _started = false;
  bool _loading = true;
  int _tabIndex = 0;

  // Map controller
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      while (!appState.isReady) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  void _startMonitoring() async {
    setState(() => _started = true);
    await appState.start();
    await appState.notifications.showOngoingStatus('Monitoring...');

    _tickTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      appState.tick(5);
      if (mounted) setState(() {});
    });
    _stateSub = appState.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  void _stopMonitoring() {
    setState(() => _started = false);
    appState.stop();
    _tickTimer?.cancel();
    _stateSub?.cancel();
    if (mounted) setState(() {});
  }

  void _openRoutePlanner() async {
    final loc = appState.currentLocation;
    final initialPos = loc != null ? LatLng(loc.lat, loc.lon) : null;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePlannerScreen(
          engine: appState.coverage,
          initialPosition: initialPos,
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  @override
  void dispose() {
    _tickTimer?.cancel();
    _stateSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF00C853)),
              const SizedBox(height: 16),
              Text('Loading coverage data...',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text('${appState.coverage.cellCount} cells indexed',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),
            // Tab bar
            _buildTabBar(),
            // Content
            Expanded(child: _tabIndex == 0 ? _buildMapTab() : _buildDashboardTab()),
            // Bottom widget if monitoring
            if (_started) _buildBottomWidget(),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Route planner FAB
          FloatingActionButton.small(
            heroTag: 'route',
            onPressed: _openRoutePlanner,
            backgroundColor: const Color(0xFF2196F3),
            child: const Icon(Icons.route),
          ),
          const SizedBox(height: 10),
          // Start/Stop FAB
          FloatingActionButton(
            heroTag: 'start',
            onPressed: _started ? _stopMonitoring : _startMonitoring,
            backgroundColor: _started ? const Color(0xFFFF5252) : const Color(0xFF00C853),
            child: Icon(_started ? Icons.stop : Icons.play_arrow, size: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final cov = appState.currentCoverage;
    final has4g = cov?.has4g ?? false;
    final realNet = appState.networkStatus.hasWorking4g;
    final Color statusColor =
        (has4g && realNet) ? const Color(0xFF00C853) : const Color(0xFFFF5252);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              has4g ? Icons.signal_cellular_alt : Icons.signal_cellular_off,
              color: statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('4G Alert',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              Text(
                _started ? appState.statusText : 'Tap play to start',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          if (_started)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 7, color: Color(0xFF00C853)),
                  SizedBox(width: 4),
                  Text('Live',
                      style: TextStyle(color: Color(0xFF00C853), fontSize: 12)),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.download, size: 20, color: Colors.white54),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => OfflineMapsScreen(manager: OfflineTileManager()))),
            tooltip: 'Offline maps',
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 20, color: Colors.white54),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.black,
      child: Row(
        children: [
          _tab('Map', Icons.map, 0),
          _tab('Dashboard', Icons.dashboard, 1),
        ],
      ),
    );
  }

  Widget _tab(String label, IconData icon, int index) {
    final active = _tabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? const Color(0xFF00C853) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? const Color(0xFF00C853) : Colors.grey),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? const Color(0xFF00C853) : Colors.grey,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MAP TAB
  // ============================================================

  Widget _buildMapTab() {
    final loc = appState.currentLocation;
    final center = loc != null
        ? LatLng(loc.lat, loc.lon)
        : const LatLng(49.0, 31.0); // Ukraine center

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: loc != null ? 13 : 7,
            minZoom: 5,
            maxZoom: 18,
          ),
          children: [
            // OpenStreetMap tiles (free, no API key)
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.fourgalert.app',
              maxZoom: 19,
            ),

            // Coverage overlay as colored markers
            _buildCoverageLayer(),
          ],
        ),

        // Center crosshair
        const Center(
          child: Icon(Icons.my_location, color: Color(0xFF00C853), size: 28),
        ),

        // Position info overlay
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: _buildMapInfoBar(),
        ),
      ],
    );
  }

  Widget _buildCoverageLayer() {
    // Use MarkerLayer with simplified coverage dots
    if (!appState.coverage.isLoaded) return const SizedBox.shrink();

    final bounds = _mapController.camera.visibleBounds;
    final zoom = _mapController.camera.zoom;

    // Adaptive sampling based on zoom
    double step;
    if (zoom >= 13) {
      step = 0.015;
    } else if (zoom >= 11) {
      step = 0.03;
    } else if (zoom >= 9) {
      step = 0.06;
    } else if (zoom >= 7) {
      step = 0.12;
    } else {
      step = 0.25;
    }

    // Limit total markers to avoid lag
    final maxMarkers = zoom >= 12 ? 600 : 300;
    final markers = <Marker>[];
    int count = 0;

    for (double lat = bounds.south; lat <= bounds.north; lat += step) {
      for (double lon = bounds.west; lon <= bounds.east; lon += step) {
        if (count >= maxMarkers) break;
        final info = appState.coverage.query(lat, lon);
        if (info == null) continue;

        Color color;
        double radius;
        if (!info.has4g) {
          color = const Color(0xCCFF5252); // red: no 4G
          radius = 6;
        } else if (info.avgDlMbps >= 50) {
          color = const Color(0xCC00C853); // green: fast
          radius = 5;
        } else if (info.avgDlMbps >= 20) {
          color = const Color(0xCC00E676); // light green
          radius = 4;
        } else if (info.avgDlMbps > 0) {
          color = const Color(0xCCFFC107); // amber
          radius = 4;
        } else {
          color = const Color(0x8800C853); // faint: tower only
          radius = 3;
        }

        markers.add(Marker(
          point: LatLng(lat, lon),
          width: radius * 2,
          height: radius * 2,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ));
        count++;
      }
      if (count >= maxMarkers) break;
    }

    return MarkerLayer(markers: markers);
  }

  Widget _buildMapInfoBar() {
    final cov = appState.currentCoverage;
    final loc = appState.currentLocation;
    final event = appState.nextEvent;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _miniBadge(
                cov?.has4g ?? false ? '4G' : 'No 4G',
                cov?.has4g ?? false ? const Color(0xFF00C853) : const Color(0xFFFF5252),
              ),
              const SizedBox(width: 6),
              if (loc != null)
                Text('${loc.speedKph.toStringAsFixed(0)} km/h',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const Spacer(),
              if (cov != null)
                Text('~${cov.avgDlMbps} Mbps',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          if (event != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.warning_amber, color: Color(0xFFFF9800), size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '4G loss in ${event.distanceText} (~${event.timeText})',
                    style: const TextStyle(color: Color(0xFFFF9800), fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  // ============================================================
  // DASHBOARD TAB
  // ============================================================

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Main dashboard widget — maximally informative
          const DashboardWidget(),
          const SizedBox(height: 16),
          // LTE Only button
          OutlinedButton.icon(
            onPressed: () => _showLteOnlyDialog(),
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('LTE Only / Network Settings'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
          ),
          const SizedBox(height: 8),
          // Info cards
          if (_started) _buildInfoCards(),
        ],
      ),
    );
  }

  Widget _buildInfoCards() {
    final cov = appState.currentCoverage;
    return Row(
      children: [
        Expanded(child: _card(Icons.cell_tower, 'Towers', cov?.hasLteTower == true ? 'LTE' : '—')),
        const SizedBox(width: 8),
        Expanded(child: _card(Icons.speed, 'Ping', cov != null ? '${cov.avgLatMs}ms' : '—')),
        const SizedBox(width: 8),
        Expanded(child: _card(Icons.devices, 'Network', appState.networkStatus.hasWorking4g ? 'Online' : 'Off')),
      ],
    );
  }

  Widget _card(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: Colors.white38),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  // ============================================================
  // BOTTOM WIDGET (compact, always visible when monitoring)
  // ============================================================

  Widget _buildBottomWidget() {
    final loc = appState.currentLocation;
    final cov = appState.currentCoverage;
    final event = appState.nextEvent;
    final inZone = appState.inDeadZone;

    Color bg;
    String status;
    IconData icon;

    if (inZone) {
      bg = const Color(0xFFFF5252).withValues(alpha: 0.15);
      status = 'No 4G — ${_fmt(appState.timeToNextEvent)}';
      icon = Icons.timer;
    } else if (event != null) {
      bg = const Color(0xFFFF9800).withValues(alpha: 0.15);
      status = '4G loss in ${event.distanceText}';
      icon = Icons.warning_amber;
    } else {
      bg = const Color(0xFF00C853).withValues(alpha: 0.1);
      status = '4G OK';
      icon = Icons.check_circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(status, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (loc != null)
                  Text('${loc.speedKph.toStringAsFixed(0)} km/h · ${cov?.avgDlMbps ?? "?"} Mbps',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
          // Quick LTE Only shortcut
          InkWell(
            onTap: () => _showLteOnlyDialog(),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.tune, size: 20, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  void _showLteOnlyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('LTE Only Mode'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Force phone to stay on 4G/LTE:'),
            SizedBox(height: 12),
            Text('\u2022 Samsung: Settings \u2192 Connections \u2192 Mobile Networks \u2192 Network Mode \u2192 "LTE/4G Only"',
                style: TextStyle(fontSize: 12)),
            SizedBox(height: 6),
            Text('\u2022 Xiaomi: Dial *#*#4636#*#* \u2192 Phone Information \u2192 "LTE only"',
                style: TextStyle(fontSize: 12)),
            SizedBox(height: 6),
            Text('\u2022 Other: Settings \u2192 SIM \u2192 Preferred network \u2192 "4G/LTE"',
                style: TextStyle(fontSize: 12)),
            SizedBox(height: 12),
            Text('One UI 6+ may hide this option.',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  String _fmt(double sec) {
    if (sec <= 0) return 'now';
    if (sec >= 3600) return '${(sec / 3600).toInt()}h ${((sec % 3600) / 60).toInt()}m';
    if (sec >= 60) return '${(sec / 60).toInt()}m';
    return '${sec.toInt()}s';
  }
}
