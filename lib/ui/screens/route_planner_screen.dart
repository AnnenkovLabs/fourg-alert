/// Route planner screen — allows setting start, destination, and waypoints.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:fourg_alert/services/routing_service.dart';
import 'package:fourg_alert/core/coverage_engine.dart';
import 'package:fourg_alert/ui/widgets/route_widget.dart';
import 'package:fourg_alert/services/offline_tiles.dart';

class RoutePlannerScreen extends StatefulWidget {
  final CoverageEngine engine;
  final LatLng? initialPosition;

  const RoutePlannerScreen({
    super.key,
    required this.engine,
    this.initialPosition,
  });

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  final List<_Waypoint> _waypoints = [];
  final _routingService = RoutingService();
  RouteResult? _routeResult;
  RouteCoverageAnalysis? _coverageAnalysis;
  bool _loading = false;
  String? _error;
  bool _downloadingTiles = false;
  DownloadProgress? _tileProgress;

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _waypoints.add(_Waypoint(
        label: 'Start',
        lat: widget.initialPosition!.latitude,
        lon: widget.initialPosition!.longitude,
      ));
    }
    // Add default destination
    _waypoints.add(_Waypoint(label: 'Destination', lat: 0, lon: 0, isEmpty: true));
  }

  Future<void> _calculateRoute() async {
    final filled = _waypoints.where((w) => !w.isEmpty).toList();
    if (filled.length < 2) {
      setState(() => _error = 'Need at least start and destination');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final routePoints = filled
          .map((w) => RoutePoint(w.lat, w.lon))
          .toList();
      final route = await _routingService.getRoute(routePoints);
      final analysis = analyzeRouteCoverage(widget.engine, route.points);

      setState(() {
        _routeResult = route;
        _coverageAnalysis = analysis;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Routing failed: $e';
        _loading = false;
      });
    }
  }

  void _addWaypoint() {
    setState(() {
      _waypoints.insert(
        _waypoints.length - 1,
        _Waypoint(label: 'Waypoint ${_waypoints.length}', lat: 0, lon: 0, isEmpty: true),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Planner'),
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          // Waypoint list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._waypoints.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final wp = entry.value;
                  final isFirst = idx == 0;
                  final isLast = idx == _waypoints.length - 1;

                  return _WaypointTile(
                    waypoint: wp,
                    isFirst: isFirst,
                    isLast: isLast,
                    canRemove: _waypoints.length > 2 && !isFirst && !isLast,
                    onChanged: (lat, lon) {
                      setState(() {
                        _waypoints[idx] = _Waypoint(
                          label: wp.label,
                          lat: lat,
                          lon: lon,
                        );
                      });
                    },
                    onRemove: () {
                      setState(() => _waypoints.removeAt(idx));
                    },
                  );
                }),

                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _addWaypoint,
                  icon: const Icon(Icons.add),
                  label: const Text('Add waypoint'),
                ),
                const SizedBox(height: 16),

                // Calculate button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _calculateRoute,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.route),
                    label: Text(_loading ? 'Calculating...' : 'Calculate Route'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),

                // Results
                if (_routeResult != null) ...[
                  _buildRouteInfo(),
                  const SizedBox(height: 12),
                  // Download offline maps for this route
                  _buildDownloadButton(),
                  const SizedBox(height: 12),
                  if (_coverageAnalysis != null)
                    RouteCoverageWidget(analysis: _coverageAnalysis!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfo() {
    final r = _routeResult!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _infoItem(Icons.straighten, '${r.distanceKm.toStringAsFixed(0)} km'),
          const SizedBox(width: 16),
          _infoItem(Icons.timer, '${r.durationMin.toStringAsFixed(0)} min'),
          const SizedBox(width: 16),
          _infoItem(Icons.polyline, '${r.points.length} pts'),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }

  Widget _buildDownloadButton() {
    if (_tileProgress != null) {
      final p = _tileProgress!;
      return Card(
        color: Colors.white.withValues(alpha: 0.05),
        child: ListTile(
          leading: p.isComplete
              ? const Icon(Icons.check_circle, color: Color(0xFF00C853))
              : p.isError
                  ? const Icon(Icons.error, color: Colors.red)
                  : const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C853)),
                    ),
          title: Text(p.isComplete ? 'Download complete' : 'Downloading tiles...',
              style: const TextStyle(fontSize: 13)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: p.progress,
                color: const Color(0xFF00C853),
                backgroundColor: Colors.white10,
              ),
              const SizedBox(height: 2),
              Text('${p.downloadedTiles}/${p.totalTiles} tiles',
                  style: const TextStyle(fontSize: 10)),
            ],
          ),
          trailing: p.isComplete || p.isError
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _tileProgress = null),
                )
              : null,
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: _downloadingTiles ? null : _downloadRouteTiles,
        icon: _downloadingTiles
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download, size: 18),
        label: Text(_downloadingTiles ? 'Downloading...' : 'Download Offline Maps for Route'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF00C853),
          side: const BorderSide(color: Color(0xFF00C853)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Future<void> _downloadRouteTiles() async {
    final r = _routeResult;
    if (r == null || r.points.isEmpty) return;

    setState(() => _downloadingTiles = true);

    final manager = OfflineTileManager();
    final label = 'Route ${r.distanceKm.toStringAsFixed(0)}km';
    final progress = await manager.downloadRoute(r.points, label);

    setState(() {
      _downloadingTiles = false;
      _tileProgress = progress;
    });
  }
}

class _Waypoint {
  final String label;
  final double lat;
  final double lon;
  final bool isEmpty;

  const _Waypoint({
    required this.label,
    required this.lat,
    required this.lon,
    this.isEmpty = false,
  });
}

class _WaypointTile extends StatefulWidget {
  final _Waypoint waypoint;
  final bool isFirst;
  final bool isLast;
  final bool canRemove;
  final Function(double lat, double lon) onChanged;
  final VoidCallback onRemove;

  const _WaypointTile({
    required this.waypoint,
    required this.isFirst,
    required this.isLast,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_WaypointTile> createState() => _WaypointTileState();
}

class _WaypointTileState extends State<_WaypointTile> {
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!widget.waypoint.isEmpty) {
      _latCtrl.text = widget.waypoint.lat.toStringAsFixed(4);
      _lonCtrl.text = widget.waypoint.lon.toStringAsFixed(4);
    }
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: widget.isFirst
                      ? const Color(0xFF00C853)
                      : widget.isLast
                          ? const Color(0xFFFF5252)
                          : const Color(0xFFFF9800),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(
                    widget.isFirst ? 'A' : widget.isLast ? 'B' : '·',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(widget.waypoint.label,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Spacer(),
              if (widget.canRemove)
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: (_) => _notify(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lonCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: (_) => _notify(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _notify() {
    final lat = double.tryParse(_latCtrl.text) ?? 0;
    final lon = double.tryParse(_lonCtrl.text) ?? 0;
    widget.onChanged(lat, lon);
  }
}
