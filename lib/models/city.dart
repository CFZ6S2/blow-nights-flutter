import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_utils.dart';

class City {
  final String id;
  final String name;
  final String slug;
  final double? lat;
  final double? lng;
  final String? country;
  final String? emoji;
  final String currency;

  const City({
    required this.id,
    required this.name,
    required this.slug,
    this.lat,
    this.lng,
    this.country,
    this.emoji,
    this.currency = 'eur',
  });

  factory City.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return City(
      id: doc.id,
      name: safeStr(d['name']).isEmpty ? doc.id : safeStr(d['name']),
      slug: (d['slug'] as String?) ?? doc.id,
      lat: asDouble(d['lat']),
      lng: asDouble(d['lng']),
      country: d['country'] as String?,
      emoji: d['emoji'] as String?,
      currency: (d['currency'] as String?) ?? 'eur',
    );
  }
}
