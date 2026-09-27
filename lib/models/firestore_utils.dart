import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? parseDate(Object? v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  if (v is Map && v['seconds'] is num) {
    return DateTime.fromMillisecondsSinceEpoch(((v['seconds'] as num) * 1000).toInt());
  }
  return null;
}

String safeStr(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  final d = parseDate(v);
  if (d != null) return '${d.day}/${d.month}/${d.year}';
  return '';
}

double? asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int asInt(Object? v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

List<String> asStringList(Object? v) =>
    v is List ? v.whereType<String>().toList() : const [];

/// Reads `location` as GeoPoint or {latitude, longitude}; falls back to lat/lng fields.
({double lat, double lng})? parseLocation(Map<String, dynamic> d,
    {String latKey = 'lat', String lngKey = 'lng'}) {
  final loc = d['location'];
  if (loc is GeoPoint) return (lat: loc.latitude, lng: loc.longitude);
  if (loc is Map) {
    final lat = asDouble(loc['latitude']);
    final lng = asDouble(loc['longitude']);
    if (lat != null && lng != null && lat != 0) return (lat: lat, lng: lng);
  }
  final lat = asDouble(d[latKey]);
  final lng = asDouble(d[lngKey]);
  if (lat != null && lng != null) return (lat: lat, lng: lng);
  return null;
}
