/// Coverage data ranking system.
/// Scores each coverage cell by multiple criteria to provide maximum accuracy.
library;

import 'package:fourg_alert/core/coverage_engine.dart';

/// Configuration for data ranking weights.
class RankerConfig {
  /// Weight of recency (how recent the data is). 0.0-1.0
  double recencyWeight;

  /// Weight of sample count (number of measurements). 0.0-1.0
  double sampleCountWeight;

  /// Weight of source type (speedtest > tower-only). 0.0-1.0
  double sourceTypeWeight;

  /// Weight of operator presence (more operators = more reliable). 0.0-1.0
  double operatorWeight;

  /// Weight of speed consistency (low variance = more reliable). 0.0-1.0
  double consistencyWeight;

  /// Reference timestamp (now) for recency calculation.
  final int referenceTimestamp;

  RankerConfig({
    this.recencyWeight = 0.25,
    this.sampleCountWeight = 0.30,
    this.sourceTypeWeight = 0.20,
    this.operatorWeight = 0.15,
    this.consistencyWeight = 0.10,
    this.referenceTimestamp = 0,
  });

  RankerConfig copyWith({
    double? recencyWeight,
    double? sampleCountWeight,
    double? sourceTypeWeight,
    double? operatorWeight,
    double? consistencyWeight,
  }) {
    return RankerConfig(
      recencyWeight: recencyWeight ?? this.recencyWeight,
      sampleCountWeight: sampleCountWeight ?? this.sampleCountWeight,
      sourceTypeWeight: sourceTypeWeight ?? this.sourceTypeWeight,
      operatorWeight: operatorWeight ?? this.operatorWeight,
      consistencyWeight: consistencyWeight ?? this.consistencyWeight,
      referenceTimestamp: referenceTimestamp,
    );
  }
}

/// Scored coverage result.
class RankedCoverage {
  final CoverageInfo info;
  final double score; // 0.0 - 1.0
  final String confidence; // "high", "medium", "low"

  const RankedCoverage({
    required this.info,
    required this.score,
    required this.confidence,
  });
}

/// Ranks coverage data by multiple criteria.
class DataRanker {
  final RankerConfig config;

  DataRanker({RankerConfig? config}) : config = config ?? RankerConfig();

  /// Rank a single coverage cell.
  RankedCoverage rank(CoverageInfo info) {
    final scores = <String, double>{};

    // 1. Recency score (based on updated timestamp)
    // The binary format doesn't store the timestamp, but we use the data vintage:
    // Data from 2024-Q2 to 2026-Q1. All data is within ~2 years.
    // We weight by the presence of recent speed tests (hasSpeedData flag).
    // Tower-only data is older on average.
    if (info.hasSpeedData) {
      scores['recency'] = 0.9; // Speedtest data is recent (<2 years)
    } else if (info.hasLteTower) {
      scores['recency'] = 0.5; // Tower data may be older
    } else {
      scores['recency'] = 0.1;
    }

    // 2. Sample count score
    if (info.totalTests >= 50) {
      scores['samples'] = 1.0;
    } else if (info.totalTests >= 20) {
      scores['samples'] = 0.8;
    } else if (info.totalTests >= 5) {
      scores['samples'] = 0.5;
    } else if (info.totalTests > 0) {
      scores['samples'] = 0.3;
    } else if (info.hasLteTower) {
      scores['samples'] = 0.2; // Tower presence but no measurements
    } else {
      scores['samples'] = 0.0;
    }

    // 3. Source type score
    if (info.hasSpeedData) {
      scores['source'] = 1.0; // Actual speed measurements
    } else if (info.hasLteTower) {
      scores['source'] = 0.4; // Tower location only
    } else {
      scores['source'] = 0.0;
    }

    // 4. Operator presence score
    if (info.operatorCount >= 3) {
      scores['operators'] = 1.0;
    } else if (info.operatorCount >= 2) {
      scores['operators'] = 0.7;
    } else if (info.operatorCount >= 1) {
      scores['operators'] = 0.4;
    } else {
      scores['operators'] = 0.0;
    }

    // 5. Consistency score (based on speed)
    // Higher speed = more likely consistent coverage
    if (info.avgDlMbps >= 50) {
      scores['consistency'] = 1.0;
    } else if (info.avgDlMbps >= 20) {
      scores['consistency'] = 0.8;
    } else if (info.avgDlMbps >= 5) {
      scores['consistency'] = 0.5;
    } else if (info.avgDlMbps > 0) {
      scores['consistency'] = 0.3;
    } else {
      scores['consistency'] = 0.1;
    }

    // Weighted sum
    double total = 0;
    total += scores['recency']! * config.recencyWeight;
    total += scores['samples']! * config.sampleCountWeight;
    total += scores['source']! * config.sourceTypeWeight;
    total += scores['operators']! * config.operatorWeight;
    total += scores['consistency']! * config.consistencyWeight;

    String confidence;
    if (total >= 0.7) {
      confidence = 'high';
    } else if (total >= 0.4) {
      confidence = 'medium';
    } else {
      confidence = 'low';
    }

    return RankedCoverage(info: info, score: total, confidence: confidence);
  }

  /// Rank multiple cells and return sorted by score (best first).
  List<RankedCoverage> rankAll(List<CoverageInfo> cells) {
    final ranked = cells.map(rank).toList();
    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }
}