/// Core coverage data engine.
/// Loads the binary coverage file and provides fast spatial lookups.
library;

import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'geohash.dart';

/// Result of a coverage query at a specific location.
class CoverageInfo {
  final int geohash;
  final bool has4g;
  final bool hasLteTower;
  final bool hasSpeedData;
  final int avgDlMbps;
  final int avgUlMbps;
  final int avgLatMs;
  final int totalTests;
  final int operatorCount;
  final int operatorMask; // bitmask: 1=Vodafone, 2=Kyivstar, 4=lifecell, 8=other

  const CoverageInfo({
    required this.geohash,
    required this.has4g,
    required this.hasLteTower,
    required this.hasSpeedData,
    required this.avgDlMbps,
    required this.avgUlMbps,
    required this.avgLatMs,
    required this.totalTests,
    required this.operatorCount,
    this.operatorMask = 0,
  });

  bool get isOnline => has4g;

  bool get hasVodafone => (operatorMask & 0x01) != 0;
  bool get hasKyivstar => (operatorMask & 0x02) != 0;
  bool get hasLifecell => (operatorMask & 0x04) != 0;

  String get speedLabel {
    if (!has4g) return 'No 4G';
    if (avgDlMbps == 0) return '4G (no data)';
    if (avgDlMbps < 5) return '4G slow';
    if (avgDlMbps < 20) return '4G OK';
    return '4G fast';
  }

  @override
  String toString() =>
      'CoverageInfo(4g:$has4g dl:$avgDlMbps ul:$avgUlMbps lat:$avgLatMs)';
}

// Binary format constants
const _kMagic = '4GUA';
const _kHeaderSize = 16;
const _kRecordSize = 10;
const _kFlagHas4g = 1 << 0;
const _kFlagHasLteTower = 1 << 1;
const _kFlagHasSpeedData = 1 << 2;

class CoverageEngine {
  ByteData? _data;
  ByteData? _opsData;
  int _cellCount = 0;
  int _opsCount = 0;
  bool _loaded = false;

  /// Operator filter bitmask. 0 = all operators, otherwise only matching cells pass.
  int operatorFilter = 0;

  bool get isLoaded => _loaded;
  int get cellCount => _cellCount;

  Future<void> load() async {
    if (_loaded) return;
    final bytes = await rootBundle.load('assets/coverage_ua.bin');
    _data = bytes.buffer.asByteData();
    _loaded = true;

    // Verify header
    final magic = String.fromCharCodes([
      _data!.getUint8(0), _data!.getUint8(1),
      _data!.getUint8(2), _data!.getUint8(3),
    ]);
    if (magic != _kMagic) throw FormatException('Bad magic: $magic');
    if (_data!.getUint16(4, Endian.little) != 1) {
      throw FormatException('Bad version');
    }
    _cellCount = _data!.getUint32(8, Endian.little);

    // Load operator bitmask file
    try {
      final opsBytes = await rootBundle.load('assets/coverage_ops.bin');
      _opsData = opsBytes.buffer.asByteData();
      _opsCount = _opsData!.getUint32(6, Endian.little);
    } catch (_) {
      _opsData = null;
      _opsCount = 0;
    }
  }

  /// Query coverage at (lat, lon). Returns null if no data.
  CoverageInfo? query(double lat, double lon) {
    if (!_loaded) return null;
    final gh = Geohash.encode(lat, lon);

    // Binary search (file is sorted by geohash)
    int lo = 0, hi = _cellCount - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final midGh = _data!.getUint32(_recordOffset(mid), Endian.little);
      if (midGh == gh) return _decode(mid);
      if (midGh < gh) { lo = mid + 1; } else { hi = mid - 1; }
    }

    // Not found — try nearest neighbor within 300m
    for (final idx in [hi, lo]) {
      if (idx < 0 || idx >= _cellCount) continue;
      final gh2 = _data!.getUint32(_recordOffset(idx), Endian.little);
      final (clat, clon) = Geohash.decode(gh2);
      if (_haversine(lat, lon, clat, clon) < 300) return _decode(idx);
    }
    return null;
  }

  /// Query multiple points along a route.
  /// Returns list of (distanceMeters, CoverageInfo, lat, lon).
  List<({double dist, CoverageInfo info, double lat, double lon})> queryRoute(
    List<({double lat, double lon})> points,
  ) {
    final result = <({double dist, CoverageInfo info, double lat, double lon})>[];
    double dist = 0;
    CoverageInfo? prev;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (i > 0) {
        dist += _haversine(
          points[i - 1].lat, points[i - 1].lon, p.lat, p.lon,
        );
      }

      final info = query(p.lat, p.lon);
      if (info != null && (prev == null || info.has4g != prev.has4g)) {
        result.add((dist: dist, info: info, lat: p.lat, lon: p.lon));
        prev = info;
      }
    }
    return result;
  }

  int _recordOffset(int idx) => _kHeaderSize + idx * _kRecordSize;

  CoverageInfo _decode(int idx) {
    final off = _recordOffset(idx);
    final d = _data!;
    final gh = d.getUint32(off, Endian.little);
    final flags = d.getUint8(off + 4);

    // Look up operator mask from ops file
    int opMask = 0;
    if (_opsData != null && _opsCount > 0) {
      // Binary search in ops file (same geohash ordering)
      int lo = 0, hi = _opsCount - 1;
      const opsHeader = 12;
      const opsRecord = 5; // 4 bytes geohash + 1 byte mask
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        final midGh = _opsData!.getUint32(opsHeader + mid * opsRecord, Endian.little);
        if (midGh == gh) {
          opMask = _opsData!.getUint8(opsHeader + mid * opsRecord + 4);
          break;
        }
        if (midGh < gh) { lo = mid + 1; } else { hi = mid - 1; }
      }
    }

    // Apply operator filter
    final has4g = (flags & _kFlagHas4g) != 0;
    final effective4g = operatorFilter == 0
        ? has4g
        : has4g && ((opMask & operatorFilter) != 0);

    return CoverageInfo(
      geohash: gh,
      has4g: effective4g,
      hasLteTower: (flags & _kFlagHasLteTower) != 0,
      hasSpeedData: (flags & _kFlagHasSpeedData) != 0,
      avgDlMbps: d.getUint8(off + 5),
      avgUlMbps: d.getUint8(off + 6),
      avgLatMs: d.getUint8(off + 7),
      totalTests: d.getUint16(off + 8, Endian.little),
      operatorCount: (flags & 0xF8) >> 3,
      operatorMask: opMask,
    );
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _deg2rad(double deg) => deg * math.pi / 180.0;
}
