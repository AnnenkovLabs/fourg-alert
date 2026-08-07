/// Geohash encoding matching the Python implementation exactly.
/// Uses 14-bit precision (~19m at equator).
library;

class Geohash {
  static const int bits = 14;
  static const int totalBits = bits * 2; // 28 bits fits in uint32

  /// Encode (lat, lon) into a uint32 geohash.
  /// Must match Python encode_geohash_uint32 exactly.
  static int encode(double lat, double lon) {
    double latMin = -90.0, latMax = 90.0;
    double lonMin = -180.0, lonMax = 180.0;
    int result = 0;

    for (int i = 0; i < totalBits; i++) {
      if (i % 2 == 0) {
        // Even bit: longitude
        final double mid = (lonMin + lonMax) / 2.0;
        if (lon > mid) {
          result |= (1 << (totalBits - 1 - i));
          lonMin = mid;
        } else {
          lonMax = mid;
        }
      } else {
        // Odd bit: latitude
        final double mid = (latMin + latMax) / 2.0;
        if (lat > mid) {
          result |= (1 << (totalBits - 1 - i));
          latMin = mid;
        } else {
          latMax = mid;
        }
      }
    }
    return result;
  }

  /// Decode a uint32 geohash back to (lat, lon) center.
  static (double, double) decode(int gh) {
    double latMin = -90.0, latMax = 90.0;
    double lonMin = -180.0, lonMax = 180.0;

    for (int i = 0; i < totalBits; i++) {
      final int bit = (gh >> (totalBits - 1 - i)) & 1;
      if (i % 2 == 0) {
        final double mid = (lonMin + lonMax) / 2.0;
        if (bit == 1) {
          lonMin = mid;
        } else {
          lonMax = mid;
        }
      } else {
        final double mid = (latMin + latMax) / 2.0;
        if (bit == 1) {
          latMin = mid;
        } else {
          latMax = mid;
        }
      }
    }
    return ((latMin + latMax) / 2.0, (lonMin + lonMax) / 2.0);
  }
}
