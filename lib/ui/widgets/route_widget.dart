/// Compact route info widget showing coverage profile.
/// Designed to be displayed alongside the map or in a bottom sheet.
library;

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:fourg_alert/core/coverage_engine.dart';
import 'package:fourg_alert/services/routing_service.dart';

/// Coverage profile for a route segment.
class RouteCoverageSegment {
  final double startKm;
  final double endKm;
  final bool has4g;
  final int avgSpeedMbps;
  final Color color;

  const RouteCoverageSegment({
    required this.startKm,
    required this.endKm,
    required this.has4g,
    required this.avgSpeedMbps,
    required this.color,
  });
}

/// Analysis of coverage along a route.
class RouteCoverageAnalysis {
  final List<RouteCoverageSegment> segments;
  final double totalKm;
  final double coveredKm;
  final double blindKm;
  final int blindZoneCount;
  final double maxBlindZoneKm;

  const RouteCoverageAnalysis({
    required this.segments,
    required this.totalKm,
    required this.coveredKm,
    required this.blindKm,
    required this.blindZoneCount,
    required this.maxBlindZoneKm,
  });

  double get coveragePercent =>
      totalKm > 0 ? (coveredKm / totalKm * 100) : 100;
}

/// Analyze coverage along a route.
RouteCoverageAnalysis analyzeRouteCoverage(
  CoverageEngine engine,
  List<RoutePoint> points,
) {
  if (points.isEmpty || !engine.isLoaded) {
    return const RouteCoverageAnalysis(
      segments: [],
      totalKm: 0,
      coveredKm: 0,
      blindKm: 0,
      blindZoneCount: 0,
      maxBlindZoneKm: 0,
    );
  }

  // Sample every 500m
  const sampleIntervalKm = 0.5;
  final segments = <RouteCoverageSegment>[];
  double totalDist = 0;
  double coveredDist = 0;
  double blindDist = 0;
  int blindZones = 0;
  double maxBlind = 0;

  bool? prev4g;
  double segmentStart = 0;
  int segmentSpeed = 0;

  for (int i = 0; i < points.length; i++) {
    if (i > 0) {
      totalDist += _haversine(
        points[i - 1].lat, points[i - 1].lon,
        points[i].lat, points[i].lon,
      );
    }

    if (i == 0 || totalDist - segmentStart >= sampleIntervalKm) {
      final info = engine.query(points[i].lat, points[i].lon);
      final has4g = info?.has4g ?? false;
      final speed = info?.avgDlMbps ?? 0;

      if (has4g != prev4g && prev4g != null) {
        // Coverage changed — prev4g is non-null here
        final segLen = totalDist - segmentStart;
        final color = prev4g
            ? (segmentSpeed >= 50
                ? const Color(0xFF00C853)
                : segmentSpeed >= 20
                    ? const Color(0xFF00E676)
                    : const Color(0xFFFFC107))
            : const Color(0xFFFF5252);

        segments.add(RouteCoverageSegment(
          startKm: segmentStart,
          endKm: totalDist,
          has4g: prev4g,
          avgSpeedMbps: segmentSpeed,
          color: color,
        ));

        if (prev4g) {
          coveredDist += segLen;
        } else {
          blindDist += segLen;
          blindZones++;
          if (segLen > maxBlind) maxBlind = segLen;
        }

        segmentStart = totalDist;
        segmentSpeed = speed;
      } else if (prev4g == null) {
        segmentSpeed = speed;
      }

      prev4g = has4g;
    }
  }

  // Final segment
  if (prev4g != null) {
    final segLen = totalDist - segmentStart;
    final color = prev4g
        ? (segmentSpeed >= 50
            ? const Color(0xFF00C853)
            : segmentSpeed >= 20
                ? const Color(0xFF00E676)
                : const Color(0xFFFFC107))
        : const Color(0xFFFF5252);

    segments.add(RouteCoverageSegment(
      startKm: segmentStart,
      endKm: totalDist,
      has4g: prev4g,
      avgSpeedMbps: segmentSpeed,
      color: color,
    ));

    if (prev4g) {
      coveredDist += segLen;
    } else {
      blindDist += segLen;
      blindZones++;
      if (segLen > maxBlind) maxBlind = segLen;
    }
  }

  return RouteCoverageAnalysis(
    segments: segments,
    totalKm: totalDist,
    coveredKm: coveredDist,
    blindKm: blindDist,
    blindZoneCount: blindZones,
    maxBlindZoneKm: maxBlind,
  );
}

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Compact route coverage widget.
class RouteCoverageWidget extends StatelessWidget {
  final RouteCoverageAnalysis analysis;

  const RouteCoverageWidget({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    if (analysis.totalKm <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.route, size: 18, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                'Route: ${analysis.totalKm.toStringAsFixed(0)} km',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
              const Spacer(),
              _badge(
                '${analysis.coveragePercent.toStringAsFixed(0)}% 4G',
                analysis.coveragePercent >= 80
                    ? const Color(0xFF00C853)
                    : const Color(0xFFFF9800),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Coverage bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 22,
              child: Row(
                children: analysis.segments.map((seg) {
                  final fraction = (seg.endKm - seg.startKm) / analysis.totalKm;
                  return fraction > 0.005
                      ? Expanded(
                          flex: (fraction * 1000).round().clamp(1, 1000),
                          child: Container(
                            color: seg.color,
                          ),
                        )
                      : const SizedBox.shrink();
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Stats row
          Row(
            children: [
              _statChip(Icons.check_circle, '4G: ${analysis.coveredKm.toStringAsFixed(0)} km',
                  const Color(0xFF00C853)),
              const SizedBox(width: 8),
              _statChip(Icons.warning, 'Blind: ${analysis.blindKm.toStringAsFixed(0)} km',
                  const Color(0xFFFF5252)),
              const SizedBox(width: 8),
              _statChip(Icons.layers, '${analysis.blindZoneCount} zones',
                  Colors.white54),
            ],
          ),
          if (analysis.maxBlindZoneKm > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Longest blind zone: ${analysis.maxBlindZoneKm.toStringAsFixed(1)} km',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
