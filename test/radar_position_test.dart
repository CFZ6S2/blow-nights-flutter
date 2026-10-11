import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blow_nights/services/radar_position.dart';

// Expected values produced by the web's own code (frontend/src/lib/geo.ts snapToGrid and geofire-common 6), so the
// app puts a person in exactly the same cell and zone as the web does.
const _snaps = [
    [40.416775, 40.416],
    [-3.70379, -3.704],
    [-3.703, -3.702],
    [40.417, 40.418],
    [41.3870001, 41.388],
    [2.1700001, 2.17],
    [-0.0004, 0.0],
    [0.0004, 0.0],
    [-33.868, -33.868],
    [151.2093, 151.21],
    [89.9991, 90.0],
    [-179.9999, -180.0],
];
const _hashes = [
    [40.416, -3.704, 'ezjmgtwb68'],
    [41.388, 2.17, 'sp3e3qknsd'],
    [-33.868, 151.21, 'r3gx2feb87'],
    [0.0, 0.0, '7zzzzzzzzz'],
    [64.1466, -21.9426, 'ge2kuttch2'],
    [-54.8019, -68.303, '4qr2jxx7b9'],
];
const _bounds = [
    [40.4168, -3.7038, 100000.0, [['ezh', 'ezk'], ['ezn', 'ezq'], ['ezk', 'ezn'], ['ezq', 'ezs']]],
    [40.4168, -3.7038, 50000.0, [['ezjh', 'ezj~'], ['ezhh', 'ezh~'], ['ezm0', 'ezmh'], ['ezk0', 'ezkh'], ['ezj0', 'ezjh'], ['ezh0', 'ezhh']]],
    [41.387, 2.17, 100000.0, [['sp2', 'sp4'], ['sp6', 'sp8'], ['sp8', 'spb'], ['spd', 'spf'], ['sp0', 'sp2'], ['sp4', 'sp6']]],
    [-33.868, 151.2093, 2000.0, [['r3gx20', 'r3gx2h'], ['r3gx30', 'r3gx3h'], ['r3gx2h', 'r3gx2~'], ['r3gx3h', 'r3gx3~'], ['r3gx0h', 'r3gx0~'], ['r3gx1h', 'r3gx1~']]],
    [0.0, 179.9, 100000.0, [['rzy', 'rz~'], ['2pb', '2pd'], ['xbn', 'xbq'], ['800', '802']]],
];

void main() {
  test('snapCoordinate matches the web, halves included (-3.703 → -3.702 as in JavaScript)', () {
    for (final s in _snaps) {
      expect(snapCoordinate(s[0]), s[1], reason: '${s[0]}');
    }
  });

  test('geohashForLocation matches geofire-common', () {
    for (final h in _hashes) {
      expect(geohashForLocation(h[0] as double, h[1] as double), h[2], reason: '${h[0]},${h[1]}');
    }
  });

  test('geohashQueryBounds matches geofire-common', () {
    for (final b in _bounds) {
      final got = geohashQueryBounds(b[0] as double, b[1] as double, b[2] as double);
      expect(got, b[3], reason: '${b[0]},${b[1]} r=${b[2]}');
    }
  });

  test('turning the radar on stores the snapped point and its geohash, never the GPS fix', () {
    final f = radarOnFields(40.416775, -3.70379);
    expect(f, {'online': true, 'radarVisible': true, 'lat': 40.416, 'lng': -3.704, 'geohash': geohashForLocation(40.416, -3.704)});
    expect(f.toString(), isNot(contains('40.416775')));
  });

  test('turning it off removes lat, lng and geohash', () {
    final f = radarOffFields();
    expect(f['online'], false);
    expect(f['radarVisible'], false);
    for (final k in ['lat', 'lng', 'geohash']) {
      expect(f[k], isA<FieldValue>(), reason: k);
    }
  });
}
