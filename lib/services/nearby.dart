import 'dart:math' as math;

import '../models/firestore_utils.dart';

/// Location-first discovery, as frontend/src/lib/nearby.ts: the radar and the lists show what is near the user, by
/// distance, not what is tagged with a city. Cities stay a business concept (City Managers, franchises, attribution).

typedef GeoPos = ({double lat, double lng});

/// How far the radar and the lists reach around the user (or around the chosen city's centre).
const nearbyRadiusKm = 50.0;

/// A city is "yours" when its centre is this close.
const cityMatchKm = 100.0;

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Coordinates of a Firestore doc in any shape the app stores: `location` (venues), `lat`/`lng`, or
/// `approx_lat`/`approx_lng` (chills).
GeoPos? pointOf(Map<String, dynamic> d) =>
    parseLocation(d) ?? parseLocation(d, latKey: 'approx_lat', lngKey: 'approx_lng');

/// What belongs to the user's zone: items with coordinates within [km] of [center], nearest first; items without
/// coordinates (older docs) only when tagged with [cityId]. With no [center] (no GPS, no city), everything tagged
/// with [cityId], or everything when there's no city either.
List<T> inZone<T>(
  List<T> items,
  GeoPos? center,
  String? cityId,
  Map<String, dynamic> Function(T) dataOf, {
  double km = nearbyRadiusKm,
}) {
  bool tagged(Map<String, dynamic> d) => cityId != null && (d['cityId'] == cityId || d['city_slug'] == cityId);
  if (center == null) {
    return cityId == null ? items : items.where((i) => dataOf(i)['cityId'] == null || tagged(dataOf(i))).toList();
  }
  final located = <(T, double)>[];
  final unlocated = <T>[];
  for (final item in items) {
    final d = dataOf(item);
    final p = pointOf(d);
    if (p == null) {
      if (tagged(d)) unlocated.add(item);
      continue;
    }
    final dist = haversineKm(center.lat, center.lng, p.lat, p.lng);
    if (dist <= km) located.add((item, dist));
  }
  located.sort((a, b) => a.$2.compareTo(b.$2));
  return [...located.map((e) => e.$1), ...unlocated];
}
