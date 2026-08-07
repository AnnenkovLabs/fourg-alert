/// Coverage heatmap overlay for flutter_map.
/// Renders colored rectangles based on binary coverage data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fourg_alert/core/coverage_engine.dart';

/// Pre-sampled coverage grid for map rendering.
class CoverageTileData {
  final LatLng center;
  final bool has4g;
  final int avgSpeedMbps;
  final Color color;

  const CoverageTileData({
    required this.center,
    required this.has4g,
    required this.avgSpeedMbps,
    required this.color,
  });
}

/// Generates a list of colored polygons from coverage data for the visible area.
List<CoverageTileData> generateCoverageOverlay(
  CoverageEngine engine,
  LatLngBounds bounds,
  int zoomLevel,
) {
  final results = <CoverageTileData>[];

  // Adjust sampling density based on zoom
  double step;
  if (zoomLevel >= 12) {
    step = 0.02; // ~2km
  } else if (zoomLevel >= 10) {
    step = 0.05; // ~5km
  } else if (zoomLevel >= 8) {
    step = 0.1; // ~10km
  } else {
    step = 0.2; // ~20km
  }

  for (double lat = bounds.south; lat <= bounds.north; lat += step) {
    for (double lon = bounds.west; lon <= bounds.east; lon += step) {
      final info = engine.query(lat, lon);
      if (info == null) continue;

      Color color;
      if (!info.has4g) {
        color = const Color(0x44FF5252); // red tint for no 4G
      } else if (info.avgDlMbps >= 50) {
        color = const Color(0x4400C853); // green: fast
      } else if (info.avgDlMbps >= 20) {
        color = const Color(0x4400E676); // light green: good
      } else if (info.avgDlMbps > 0) {
        color = const Color(0x44FFC107); // amber: slow
      } else {
        color = const Color(0x2200C853); // very faint: tower only
      }

      results.add(CoverageTileData(
        center: LatLng(lat, lon),
        has4g: info.has4g,
        avgSpeedMbps: info.avgDlMbps,
        color: color,
      ));
    }
  }

  return results;
}

/// Coverage layer widget for flutter_map.
class CoverageOverlayLayer extends StatelessWidget {
  final CoverageEngine engine;
  final LatLngBounds bounds;
  final double zoom;

  const CoverageOverlayLayer({
    super.key,
    required this.engine,
    required this.bounds,
    required this.zoom,
  });

  @override
  Widget build(BuildContext context) {
    if (!engine.isLoaded) return const SizedBox.shrink();

    final tiles = generateCoverageOverlay(engine, bounds, zoom.toInt());

    return Stack(
      children: tiles.map((tile) {
        // Don't render tiles at very low zoom to avoid lag
        if (zoom < 7 && tiles.length > 500) {
          // Sample only 1 in 4
          if (tile.center.latitude.round() % 2 != 0 ||
              tile.center.longitude.round() % 2 != 0) {
            return const SizedBox.shrink();
          }
        }

        return Positioned(
          left: 0,
          top: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: tile.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }).toList(),
    );
  }
}
