/// Enhanced route predictor with stability concept.
/// Detects not just coverage transitions but stable 4G zones
/// (minimum N minutes/km of continuous 4G).
library;

import 'dart:math' as math;
import '../core/coverage_engine.dart';
import 'location_service.dart';
import 'data_ranker.dart';

/// Configuration for stability and prediction.
class PredictorConfig {
  /// Minimum duration of continuous 4G to consider it "stable" (seconds).
  int stabilityThresholdSeconds;

  /// Use km-based stability instead of time-based.
  bool useKmForStability;

  /// Minimum distance of continuous 4G to consider it "stable" (km).
  double stabilityThresholdKm;

  /// Look-ahead distance for prediction (km).
  double lookAheadKm;

  /// Sample interval along route (meters).
  double sampleIntervalM;

  /// Whether to use data ranking for confidence scoring.
  bool useDataRanking;

  PredictorConfig({
    this.stabilityThresholdSeconds = 180,
    this.useKmForStability = false,
    this.stabilityThresholdKm = 3.0,
    this.lookAheadKm = 60.0,
    this.sampleIntervalM = 200.0,
    this.useDataRanking = true,
  });

  PredictorConfig copyWith({
    int? stabilityThresholdSeconds,
    bool? useKmForStability,
    double? stabilityThresholdKm,
    double? lookAheadKm,
    double? sampleIntervalM,
    bool? useDataRanking,
  }) {
    return PredictorConfig(
      stabilityThresholdSeconds: stabilityThresholdSeconds ?? this.stabilityThresholdSeconds,
      useKmForStability: useKmForStability ?? this.useKmForStability,
      stabilityThresholdKm: stabilityThresholdKm ?? this.stabilityThresholdKm,
      lookAheadKm: lookAheadKm ?? this.lookAheadKm,
      sampleIntervalM: sampleIntervalM ?? this.sampleIntervalM,
      useDataRanking: useDataRanking ?? this.useDataRanking,
    );
  }
}

/// A coverage change event with confidence data.
class CoverageEvent {
  /// Distance from current position (km).
  final double distanceKm;

  /// Time until event at current speed (seconds).
  final double timeSeconds;

  /// True = entering no-4G zone, false = entering stable 4G zone.
  final bool isLosing4g;

  /// Length of the zone (km).
  final double zoneLengthKm;

  /// Time to cross the zone at current speed (seconds).
  final double zoneTimeSeconds;

  /// Whether the zone ends with stable 4G (only for blind zones).
  final bool endsWithStable4g;

  /// Stability duration after the blind zone (seconds).
  final double stableAfterSeconds;

  /// Coverage info at transition point.
  final CoverageInfo info;

  /// Confidence score from data ranking (0-1).
  final double confidence;

  const CoverageEvent({
    required this.distanceKm,
    required this.timeSeconds,
    required this.isLosing4g,
    required this.zoneLengthKm,
    required this.zoneTimeSeconds,
    required this.endsWithStable4g,
    required this.stableAfterSeconds,
    required this.info,
    required this.confidence,
  });

  String get distanceText {
    if (distanceKm >= 1) return '${distanceKm.toStringAsFixed(1)} km';
    return '${(distanceKm * 1000).toInt()} m';
  }

  String get timeText {
    if (timeSeconds >= 3600) return '${(timeSeconds / 3600).toInt()}h ${((timeSeconds % 3600) / 60).toInt()}m';
    if (timeSeconds >= 60) return '${(timeSeconds / 60).toInt()} min';
    return '${timeSeconds.toInt()} sec';
  }

  String get zoneTimeText {
    if (zoneTimeSeconds >= 60) return '${(zoneTimeSeconds / 60).toInt()} min';
    return '${zoneTimeSeconds.toInt()} sec';
  }

  String get stableAfterText {
    if (stableAfterSeconds >= 3600) return '${(stableAfterSeconds / 3600).toInt()}h';
    if (stableAfterSeconds >= 60) return '${(stableAfterSeconds / 60).toInt()} min';
    return '${stableAfterSeconds.toInt()} sec';
  }
}

class RoutePredictor {
  final CoverageEngine _engine;
  final DataRanker _ranker;
  PredictorConfig config;

  RoutePredictor(this._engine, {PredictorConfig? config, DataRanker? ranker})
      : config = config ?? PredictorConfig(),
        _ranker = ranker ?? DataRanker();

  /// Predict coverage changes ahead including stability analysis.
  List<CoverageEvent> predict(LocationData location) {
    if (!_engine.isLoaded) return [];

    final speedMs = location.speedMps > 0 ? location.speedMps : 1.0;
    final heading = location.heading;
    final speedKph = speedMs * 3.6;

    // Generate sample points along trajectory
    final points = _generateTrajectory(location, heading);
    if (points.length < 2) return [];

    // Sample coverage at each point
    final samples = <_SamplePoint>[];
    double dist = 0;
    for (int i = 0; i < points.length; i++) {
      if (i > 0) {
        dist += _haversine(
          points[i - 1].$1, points[i - 1].$2,
          points[i].$1, points[i].$2,
        );
      }
      final info = _engine.query(points[i].$1, points[i].$2);
      double confidence = 0.5;
      if (info != null && config.useDataRanking) {
        confidence = _ranker.rank(info).score;
      }
      samples.add(_SamplePoint(
        distKm: dist / 1000.0,
        has4g: info?.has4g ?? false,
        info: info,
        confidence: confidence,
      ));
    }

    // Analyze for blind zones and stable recovery
    return _analyzeCoverage(samples, speedMs, speedKph);
  }

  List<(double, double)> _generateTrajectory(LocationData loc, double heading) {
    final points = <(double, double)>[];
    double dist = 0;
    double lat = loc.lat;
    double lon = loc.lon;

    while (dist < config.lookAheadKm * 1000) {
      points.add((lat, lon));
      dist += config.sampleIntervalM;
      final next = _project(lat, lon, heading, config.sampleIntervalM);
      lat = next.$1;
      lon = next.$2;
    }
    return points;
  }

  List<CoverageEvent> _analyzeCoverage(
    List<_SamplePoint> samples,
    double speedMs,
    double speedKph,
  ) {
    final events = <CoverageEvent>[];
    if (samples.isEmpty) return events;

    // Find blind zones: stretches where has4g is false
    int i = 0;
    while (i < samples.length) {
      if (samples[i].has4g) {
        i++;
        continue;
      }

      // Found start of blind zone
      final blindStart = samples[i].distKm;
      double totalConf = samples[i].confidence;
      int blindSamples = 1;

      // Find end of blind zone
      int j = i + 1;
      while (j < samples.length && !samples[j].has4g) {
        totalConf += samples[j].confidence;
        blindSamples++;
        j++;
      }

      final blindEnd = j < samples.length ? samples[j].distKm : samples.last.distKm;
      final blindLen = blindEnd - blindStart;
      final avgConf = totalConf / blindSamples;

      // Now find stable 4G after the blind zone
      double stableStart = blindEnd;
      int stableSamples = 0;

      if (j < samples.length) {
        // Check for stable 4G starting at j
        final stabilityThreshold = config.useKmForStability
            ? config.stabilityThresholdKm
            : config.stabilityThresholdSeconds * speedKph / 3600.0; // convert seconds to km

        int k = j;
        while (k < samples.length && samples[k].has4g) {
          k++;
        }

        if (k - j >= 2) {
          final contiguousLen = k < samples.length
              ? samples[k - 1].distKm - samples[j].distKm
              : samples.last.distKm - samples[j].distKm;

          if (contiguousLen >= stabilityThreshold) {
            stableStart = samples[j].distKm;
            stableSamples = k - j;
          } else {
            // Not stable — find further ahead
            int m = k;
            while (m < samples.length) {
              if (samples[m].has4g) {
                int n = m;
                while (n < samples.length && samples[n].has4g) {
                  n++;
                }
                if (n - m >= 2) {
                  final runLen = n < samples.length
                      ? samples[n - 1].distKm - samples[m].distKm
                      : samples.last.distKm - samples[m].distKm;
                  if (runLen >= stabilityThreshold) {
                    stableStart = samples[m].distKm;
                    stableSamples = n - m;
                    break;
                  }
                }
                m = n;
              } else {
                m++;
              }
            }
          }
        }
      }

      final stableAfterKm = stableStart - blindStart;
      final stableAfterSeconds = stableAfterKm / speedKph * 3600;

      events.add(CoverageEvent(
        distanceKm: blindStart,
        timeSeconds: blindStart / speedKph * 3600,
        isLosing4g: true,
        zoneLengthKm: blindLen,
        zoneTimeSeconds: blindLen / speedKph * 3600,
        endsWithStable4g: stableSamples > 0,
        stableAfterSeconds: stableAfterSeconds,
        info: samples[i].info ?? CoverageInfo(geohash: 0, has4g: false, hasLteTower: false, hasSpeedData: false, avgDlMbps: 0, avgUlMbps: 0, avgLatMs: 0, totalTests: 0, operatorCount: 0),
        confidence: avgConf,
      ));

      i = j;
    }

    return events;
  }

  /// Predict next event (simplified).
  CoverageEvent? predictNext(LocationData location) {
    final all = predict(location);
    return all.isNotEmpty ? all.first : null;
  }

  // Static helpers
  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static (double, double) _project(double lat, double lon, double bearingDeg, double distM) {
    const r = 6371000.0;
    final bearing = bearingDeg * math.pi / 180;
    final latR = lat * math.pi / 180;
    final lonR = lon * math.pi / 180;
    final ad = distM / r;
    final lat2 = math.asin(
      math.sin(latR) * math.cos(ad) +
          math.cos(latR) * math.sin(ad) * math.cos(bearing),
    );
    final lon2 = lonR +
        math.atan2(
          math.sin(bearing) * math.sin(ad) * math.cos(latR),
          math.cos(ad) - math.sin(latR) * math.sin(lat2),
        );
    return (lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }
}

class _SamplePoint {
  final double distKm;
  final bool has4g;
  final CoverageInfo? info;
  final double confidence;
  const _SamplePoint({
    required this.distKm,
    required this.has4g,
    this.info,
    required this.confidence,
  });
}
