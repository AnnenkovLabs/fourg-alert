/// Rich dashboard widget — maximally informative compact status display.
/// Shows: current 4G status, upcoming blind zone details, stability info.
library;

import 'package:flutter/material.dart';
import 'package:fourg_alert/services/globals.dart';
import 'package:fourg_alert/services/route_predictor.dart';
import 'package:fourg_alert/services/network_monitor.dart';
import 'package:fourg_alert/core/coverage_engine.dart';

class DashboardWidget extends StatelessWidget {
  const DashboardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = appState.currentLocation;
    final cov = appState.currentCoverage;
    final net = appState.networkStatus;
    final event = appState.nextEvent;
    final inZone = appState.inDeadZone;

    final bool real4g = net.hasWorking4g;
    final bool covered4g = cov?.has4g ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === ROW 1: Current status ===
          _buildStatusRow(covered4g, real4g, net, cov, loc),
          const SizedBox(height: 12),

          // === ROW 2: Prediction (if not in blind zone) ===
          if (!inZone && event != null) ...[
            _buildPredictionRow(event),
            const SizedBox(height: 10),
          ],

          // === ROW 3: Blind zone countdown (if in blind zone) ===
          if (inZone) ...[
            _buildBlindZoneRow(event),
            const SizedBox(height: 10),
          ],

          // === ROW 4: Stability forecast ===
          if (event != null && event.endsWithStable4g)
            _buildStabilityRow(event),

          // === ROW 5: Hotspot/WiFi warning ===
          if (net.isWifiOrHotspot)
            _buildHotspotWarning(net),
        ],
      ),
    );
  }

  Widget _buildStatusRow(
    bool covered4g,
    bool real4g,
    NetworkStatus net,
    CoverageInfo? cov,
    location,
  ) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (net.isWifiOrHotspot) {
      statusColor = const Color(0xFF2196F3);
      statusText = net.state == NetworkState.hotspot ? 'Hotspot' : 'WiFi';
      statusIcon = Icons.wifi;
    } else if (real4g && covered4g) {
      statusColor = const Color(0xFF00C853);
      statusText = '4G Active';
      statusIcon = Icons.signal_cellular_alt;
    } else if (covered4g && !real4g) {
      statusColor = const Color(0xFFFF9800);
      statusText = 'Phantom 4G';
      statusIcon = Icons.signal_wifi_statusbar_connected_no_internet_4;
    } else {
      statusColor = const Color(0xFFFF5252);
      statusText = 'No 4G';
      statusIcon = Icons.signal_cellular_off;
    }

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(statusIcon, color: statusColor, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(statusText,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: statusColor)),
              if (cov != null && cov.has4g)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${cov.avgDlMbps} Mbps · ${cov.avgLatMs}ms',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    const SizedBox(height: 2),
                    _operatorBadges(cov),
                  ],
                ),
            ],
          ),
        ),
        if (location != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${location.speedKph.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Text('km/h', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
      ],
    );
  }

  Widget _buildPredictionRow(CoverageEvent event) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, color: Color(0xFFFF9800), size: 16),
              const SizedBox(width: 6),
              const Text('Blind zone ahead',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF9800),
                      fontSize: 13)),
              const Spacer(),
              _confBadge(event.confidence),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _metricBox('Distance', event.distanceText, const Color(0xFFFF9800)),
              const SizedBox(width: 8),
              _metricBox('In', event.timeText, const Color(0xFFFF9800)),
              const SizedBox(width: 8),
              _metricBox('Duration', event.zoneTimeText, const Color(0xFFFF5252)),
              const SizedBox(width: 8),
              _metricBox('Length', '${event.zoneLengthKm.toStringAsFixed(1)} km',
                  const Color(0xFFFF5252)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBlindZoneRow(CoverageEvent? event) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5252).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer, color: Color(0xFFFF5252), size: 16),
              const SizedBox(width: 6),
              const Text('In blind zone',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF5252),
                      fontSize: 13)),
              const Spacer(),
              Text('${appState.timeInZone.toInt()}s elapsed',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _metricBox('Recovery', _fmtTime(appState.timeToNextEvent),
                  const Color(0xFF00C853)),
              if (event != null) ...[
                const SizedBox(width: 8),
                _metricBox('Zone end', event.distanceText,
                    const Color(0xFFFF9800)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStabilityRow(CoverageEvent event) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF00C853).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified, color: Color(0xFF00C853), size: 14),
          const SizedBox(width: 6),
          Text('Stable 4G after: ${event.stableAfterText}',
              style: const TextStyle(color: Color(0xFF00C853), fontSize: 12)),
          const Spacer(),
          Text('+${event.zoneLengthKm.toStringAsFixed(1)}km blind',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildHotspotWarning(NetworkStatus net) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF2196F3), size: 14),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Connected via WiFi/hotspot — mobile 4G monitoring paused',
              style: TextStyle(color: Color(0xFF2196F3), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBox(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey[600], fontSize: 9)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _confBadge(double confidence) {
    Color c;
    String t;
    if (confidence >= 0.7) {
      c = const Color(0xFF00C853);
      t = 'high';
    } else if (confidence >= 0.4) {
      c = const Color(0xFFFFC107);
      t = 'med';
    } else {
      c = const Color(0xFFFF5252);
      t = 'low';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(t,
          style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }

  Widget _operatorBadges(CoverageInfo cov) {
    final ops = <Widget>[];
    if (cov.hasVodafone) ops.add(_opBadge('V', const Color(0xFFE53935)));
    if (cov.hasKyivstar) ops.add(_opBadge('K', const Color(0xFF1E88E5)));
    if (cov.hasLifecell) ops.add(_opBadge('L', const Color(0xFFFFC107)));
    if (ops.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: ops);
  }

  Widget _opBadge(String letter, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(letter,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }

  static String _fmtTime(double sec) {
    if (sec <= 0) return 'now';
    if (sec >= 3600) return '${(sec / 3600).toInt()}h ${((sec % 3600) / 60).toInt()}m';
    if (sec >= 60) return '${(sec / 60).toInt()}m ${(sec % 60).toInt()}s';
    return '${sec.toInt()}s';
  }
}
