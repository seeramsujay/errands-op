/// Standard Geohash encoder/decoder for spatial matrix caching.
class Geohash {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encode (latitude, longitude) into a geohash string with given precision (default 6).
  static String encode(double latitude, double longitude, {int precision = 6}) {
    var latMin = -90.0;
    var latMax = 90.0;
    var lonMin = -180.0;
    var lonMax = 180.0;

    final buffer = StringBuffer();
    var isEven = true;
    var bit = 0;
    var ch = 0;

    while (buffer.length < precision) {
      if (isEven) {
        final mid = (lonMin + lonMax) / 2.0;
        if (longitude >= mid) {
          ch |= 1 << (4 - bit);
          lonMin = mid;
        } else {
          lonMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2.0;
        if (latitude >= mid) {
          ch |= 1 << (4 - bit);
          latMin = mid;
        } else {
          latMax = mid;
        }
      }

      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        buffer.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return buffer.toString();
  }

  /// Decode geohash string into [lat, lon] center coordinates.
  static List<double> decode(String geohash) {
    var latMin = -90.0;
    var latMax = 90.0;
    var lonMin = -180.0;
    var lonMax = 180.0;

    var isEven = true;

    for (var i = 0; i < geohash.length; i++) {
      final c = geohash[i].toLowerCase();
      final cd = _base32.indexOf(c);
      if (cd == -1) continue;

      for (var j = 0; j < 5; j++) {
        final mask = 1 << (4 - j);
        if (isEven) {
          final mid = (lonMin + lonMax) / 2.0;
          if ((cd & mask) != 0) {
            lonMin = mid;
          } else {
            lonMax = mid;
          }
        } else {
          final mid = (latMin + latMax) / 2.0;
          if ((cd & mask) != 0) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        isEven = !isEven;
      }
    }

    final lat = (latMin + latMax) / 2.0;
    final lon = (lonMin + lonMax) / 2.0;
    return [lat, lon];
  }
}
