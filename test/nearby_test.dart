import 'package:blow_nights/services/nearby.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sol = (lat: 40.4168, lng: -3.7038);
  const valencia = (lat: 39.4699, lng: -0.3763);
  final madridVenue = {'id': 'm', 'cityId': 'madrid', 'location': {'latitude': 40.4175, 'longitude': -3.7029}};
  final valenciaVenue = {'id': 'v', 'cityId': 'valencia', 'location': {'latitude': 39.4702, 'longitude': -0.3768}};
  final chill = {'id': 'c', 'approx_lat': 39.47, 'approx_lng': -0.377};
  final untaggedOld = {'id': 'o'};
  final taggedOld = {'id': 't', 'cityId': 'madrid'};
  List<String> ids(List<Map<String, dynamic>> l) => [for (final d in l) d['id'] as String];
  Map<String, dynamic> self(Map<String, dynamic> d) => d;

  test('Madrid–Valencia is about 300 km', () {
    final d = haversineKm(sol.lat, sol.lng, valencia.lat, valencia.lng);
    expect(d, inInclusiveRange(295, 310));
  });

  test('pointOf reads venue locations and chill approx coordinates', () {
    expect(pointOf(madridVenue), (lat: 40.4175, lng: -3.7029));
    expect(pointOf(chill), (lat: 39.47, lng: -0.377));
    expect(pointOf(untaggedOld), isNull);
  });

  test('in Valencia the zone has Valencia things, not Madrid', () {
    expect(ids(inZone([madridVenue, valenciaVenue, chill, untaggedOld], valencia, null, self)), ['v', 'c']);
  });

  test('in Madrid the zone has Madrid venues and older docs tagged madrid', () {
    expect(ids(inZone([valenciaVenue, madridVenue, taggedOld, untaggedOld], sol, 'madrid', self)), ['m', 't']);
  });

  test('nearest first, and a wider radius reaches further', () {
    expect(ids(inZone([valenciaVenue, madridVenue], sol, null, self, km: 400)), ['m', 'v']);
  });

  test('without a centre: everything, or what is tagged with the city', () {
    expect(inZone([madridVenue, valenciaVenue, untaggedOld], null, null, self), hasLength(3));
    expect(ids(inZone([madridVenue, valenciaVenue], null, 'madrid', self)), ['m']);
  });
}
