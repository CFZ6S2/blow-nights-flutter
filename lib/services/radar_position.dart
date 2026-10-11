import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

// What other people may see of someone's position: snapped to a fixed grid of 0.002° (~220 m north–south, ~170 m
// east–west in Spain), the same point for everyone in that cell, so repeated updates can't be averaged back to the
// exact spot. Profiles are readable by any signed-in user: the GPS fix itself is never written there. Same grid and
// geohash as the web (frontend/src/lib/geo.ts, geofire-common), so both apps put a person in the same cell and zone.
const double publicGridDeg = 0.002;

// Math.round of JavaScript (halves go up, also for negatives), not Dart's round (halves away from zero), so a value
// exactly between two cells lands in the same cell as on the web.
int _jsRound(double x) => (x + 0.5).floor();

double snapCoordinate(double value) {
  final snapped = _jsRound(value / publicGridDeg) * publicGridDeg;
  // Three decimals clear the float noise of the multiplication; + 0.0 turns -0.0 into 0.0.
  return double.parse(snapped.toStringAsFixed(3)) + 0.0;
}

// The profile fields written when someone turns the radar on: the snapped point and its geohash.
Map<String, Object> radarOnFields(double lat, double lng) {
  final sLat = snapCoordinate(lat);
  final sLng = snapCoordinate(lng);
  return {'online': true, 'radarVisible': true, 'lat': sLat, 'lng': sLng, 'geohash': geohashForLocation(sLat, sLng)};
}

// Turning it off removes the position too, so the last place someone was isn't left in their profile.
Map<String, Object> radarOffFields() => {
      'online': false,
      'radarVisible': false,
      'lat': FieldValue.delete(),
      'lng': FieldValue.delete(),
      'geohash': FieldValue.delete(),
    };

// ── Geohash (port of geofire-common 6, the library the web and Cloud Functions use) ──

const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
const _geohashPrecision = 10;
const _bitsPerChar = 5;
const _maximumBitsPrecision = 22 * _bitsPerChar;
const _earthMeriCircumference = 40007860.0;
const _metersPerDegreeLatitude = 110574.0;
const _earthEqRadius = 6378137.0;
const _e2 = 0.00669447819799;
const _epsilon = 1e-12;

double _log2(double x) => math.log(x) / math.ln2;

String geohashForLocation(double lat, double lng, [int precision = _geohashPrecision]) {
  var latMin = -90.0, latMax = 90.0, lngMin = -180.0, lngMax = 180.0;
  final hash = StringBuffer();
  var hashVal = 0, bits = 0, length = 0;
  var even = true;
  while (length < precision) {
    final val = even ? lng : lat;
    if (even) {
      final mid = (lngMin + lngMax) / 2;
      if (val > mid) {
        hashVal = (hashVal << 1) + 1;
        lngMin = mid;
      } else {
        hashVal = hashVal << 1;
        lngMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (val > mid) {
        hashVal = (hashVal << 1) + 1;
        latMin = mid;
      } else {
        hashVal = hashVal << 1;
        latMax = mid;
      }
    }
    even = !even;
    if (bits < 4) {
      bits++;
    } else {
      bits = 0;
      hash.write(_base32[hashVal]);
      hashVal = 0;
      length++;
    }
  }
  return hash.toString();
}

double _metersToLongitudeDegrees(double distance, double latitude) {
  final radians = latitude * math.pi / 180;
  final num = math.cos(radians) * _earthEqRadius * math.pi / 180;
  final denom = 1 / math.sqrt(1 - _e2 * math.sin(radians) * math.sin(radians));
  final deltaDeg = num * denom;
  if (deltaDeg < _epsilon) return distance > 0 ? 360 : 0;
  return math.min(360, distance / deltaDeg);
}

double _longitudeBitsForResolution(double resolution, double latitude) {
  final degs = _metersToLongitudeDegrees(resolution, latitude);
  return degs.abs() > 0.000001 ? math.max(1, _log2(360 / degs)) : 1;
}

double _latitudeBitsForResolution(double resolution) =>
    math.min(_log2(_earthMeriCircumference / 2 / resolution), _maximumBitsPrecision.toDouble());

double _wrapLongitude(double longitude) {
  if (longitude <= 180 && longitude >= -180) return longitude;
  final adjusted = longitude + 180;
  return adjusted > 0 ? (adjusted % 360) - 180 : 180 - (-adjusted % 360);
}

int _boundingBoxBits(double lat, double size) {
  final latDelta = size / _metersPerDegreeLatitude;
  final north = math.min(90.0, lat + latDelta);
  final south = math.max(-90.0, lat - latDelta);
  final bitsLat = _latitudeBitsForResolution(size).floor() * 2;
  final bitsLongNorth = _longitudeBitsForResolution(size, north).floor() * 2 - 1;
  final bitsLongSouth = _longitudeBitsForResolution(size, south).floor() * 2 - 1;
  return [bitsLat, bitsLongNorth, bitsLongSouth, _maximumBitsPrecision].reduce(math.min);
}

List<List<double>> _boundingBoxCoordinates(double lat, double lng, double radius) {
  final latDegrees = radius / _metersPerDegreeLatitude;
  final north = math.min(90.0, lat + latDegrees);
  final south = math.max(-90.0, lat - latDegrees);
  final longDegs = math.max(_metersToLongitudeDegrees(radius, north), _metersToLongitudeDegrees(radius, south));
  return [
    [lat, lng],
    [lat, _wrapLongitude(lng - longDegs)],
    [lat, _wrapLongitude(lng + longDegs)],
    [north, lng],
    [north, _wrapLongitude(lng - longDegs)],
    [north, _wrapLongitude(lng + longDegs)],
    [south, lng],
    [south, _wrapLongitude(lng - longDegs)],
    [south, _wrapLongitude(lng + longDegs)],
  ];
}

List<String> _geohashQuery(String geohash, int bits) {
  final precision = (bits / _bitsPerChar).ceil();
  if (geohash.length < precision) return [geohash, '$geohash~'];
  final hash = geohash.substring(0, precision);
  final base = hash.substring(0, hash.length - 1);
  final lastValue = _base32.indexOf(hash[hash.length - 1]);
  final significantBits = bits - base.length * _bitsPerChar;
  final unusedBits = _bitsPerChar - significantBits;
  final startValue = (lastValue >> unusedBits) << unusedBits;
  final endValue = startValue + (1 << unusedBits);
  return endValue > 31 ? [base + _base32[startValue], '$base~'] : [base + _base32[startValue], base + _base32[endValue]];
}

// [start, end] geohash ranges that together cover a circle of radiusMeters around the centre (duplicates removed),
// as geofire-common's geohashQueryBounds.
List<List<String>> geohashQueryBounds(double lat, double lng, double radiusMeters) {
  final queryBits = math.max(1, _boundingBoxBits(lat, radiusMeters));
  final precision = (queryBits / _bitsPerChar).ceil();
  final queries = [
    for (final c in _boundingBoxCoordinates(lat, lng, radiusMeters))
      _geohashQuery(geohashForLocation(c[0], c[1], precision), queryBits),
  ];
  final out = <List<String>>[];
  for (final q in queries) {
    if (!out.any((o) => o[0] == q[0] && o[1] == q[1])) out.add(q);
  }
  return out;
}
