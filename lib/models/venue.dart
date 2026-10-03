import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/venue_hours.dart';
import 'firestore_utils.dart';

class VenueTypeMeta {
  final String label;
  final String hours;
  final IconData icon;
  final bool cruising;
  final String group;
  const VenueTypeMeta(this.label, this.hours, this.icon, this.cruising, this.group);
}

// Mirrors VENUE_TYPES in frontend/src/hooks/useVenues.ts
const venueTypes = <String, VenueTypeMeta>{
  'club': VenueTypeMeta('Discotecas & Clubs', '01:00–06:00', Icons.nightlife, false, 'commercial'),
  'bar': VenueTypeMeta('Bares & Previas', '20:00–02:00', Icons.local_bar, false, 'commercial'),
  'sauna': VenueTypeMeta('Saunas & Spas', '12:00–03:00', Icons.hot_tub, true, 'commercial'),
  'chiringuito': VenueTypeMeta('Chiringuitos', '12:00–22:00', Icons.beach_access, false, 'commercial'),
  'cruising_outdoor': VenueTypeMeta('Cruising Exterior & Zonas Libres', '22:00–06:00', Icons.park, true, 'community'),
  'community_point': VenueTypeMeta('Puntos de Encuentro', '24h', Icons.place, false, 'community'),
  'event': VenueTypeMeta('Eventos Independientes', 'Especial', Icons.event, false, 'events'),
};

class Venue {
  final String id;
  final Map<String, dynamic> data;
  const Venue(this.id, this.data);

  factory Venue.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc, {String? forceType}) {
    final d = {...?doc.data()};
    if (forceType != null) d['type'] = forceType;
    return Venue(doc.id, d);
  }

  String get name => safeStr(data['name'] ?? data['title']);
  String get type => (data['type'] as String?) ?? '';
  String get address => safeStr(data['address'] ?? (data['location'] is Map ? data['location']['address'] : null));
  String get description => safeStr(data['description']);
  String get cityId => (data['cityId'] as String?) ?? '';
  String? get coverImage => (data['coverImage'] ?? data['banner_url'] ?? data['imageUrl']) as String?;
  String? get bannerUrl => data['banner_url'] as String?;
  int get currentCount => asInt(data['currentCount']);
  int? get capacity => data['capacity'] is num ? (data['capacity'] as num).toInt() : null;
  bool get isVerified => data['isVerified'] == true;
  bool get isClaimed => data['isClaimed'] == true;
  bool get isUnclaimedReference => isUnclaimedReferenceData(data);

  /// A reference venue: a real place seeded for map density, not a partner of Blow Nights until its owner claims it
  /// (web docs/REFERENCE_VENUES.md). Same rule as the backend (functions/modules/venue_claims.js) and the web.
  static bool isUnclaimedReferenceData(Map<dynamic, dynamic>? d) => d != null && d['source'] == 'reference' && d['isClaimed'] != true;
  bool get hasTicketing => data['hasTicketing'] == true;
  String? get externalTicketUrl => data['externalTicketUrl'] as String?;
  bool get isEvent => type == 'event';
  bool get boosted =>
      data['boostActive'] == true ||
      (data['subscription'] is Map && data['subscription']['status'] == 'active');

  ({double lat, double lng})? get location => parseLocation(data);

  VenueTypeMeta? get meta => venueTypes[type];
  String get group => meta?.group ?? 'commercial';

  List<String> get openingDays => asStringList(data['openingDays']);
  Map<String, Hours> get openingHours {
    final raw = data['openingHours'];
    if (raw is! Map) return const {};
    final out = <String, Hours>{};
    raw.forEach((k, v) {
      if (v is Map && v['open'] is String && v['close'] is String) {
        out[k as String] = (open: v['open'] as String, close: v['close'] as String);
      }
    });
    return out;
  }

  bool get hasSchedule => openingDays.isNotEmpty && openingHours.isNotEmpty;

  /// Open or closed by its schedule; unknown without one (most reference venues), never shown as open.
  VenueOpenStatus get openStatus => !hasSchedule
      ? VenueOpenStatus.unknown
      : isVenueOpenNow(openingDays, openingHours).isOpen
          ? VenueOpenStatus.open
          : VenueOpenStatus.closed;
}

/// In the order the city home lists them: open first, then without a schedule, closed last.
enum VenueOpenStatus { open, unknown, closed }
