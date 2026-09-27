import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_utils.dart';

class Event {
  final String id;
  final Map<String, dynamic> data;
  const Event(this.id, this.data);

  factory Event.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) => Event(doc.id, {...?doc.data()});

  String get title => safeStr(data['title'] ?? data['name']);
  String get description => safeStr(data['description']);
  String? get bannerUrl => (data['banner_url'] ?? data['coverImage'] ?? data['flyerUrl']) as String?;
  String get venueId => (data['venueId'] as String?) ?? '';
  String get venueName => safeStr(data['venueName'] ?? data['organizerName']);
  String get cityId => (data['cityId'] as String?) ?? '';
  String get address => safeStr(data['address'] ?? (data['location'] is Map ? data['location']['address'] : null));
  List<Map<String, dynamic>> get tiers => (data['ticket_tiers'] is List)
      ? (data['ticket_tiers'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : const [];

  ({double lat, double lng})? get location => parseLocation(data);

  /// Port of getEventStartTime in utils/eventHelpers.ts
  DateTime? get start {
    final direct = parseDate(data['start_date'] ?? data['starts_at']);
    if (direct != null) return direct;
    final date = data['date'];
    if (date != null) {
      final time = data['time'];
      if (date is String && time is String) {
        final combined = DateTime.tryParse('${date}T$time:00');
        if (combined != null) return combined;
      }
      final d = parseDate(date);
      if (d != null) return d;
    }
    return parseDate(data['created_at']);
  }

  DateTime? get end {
    final direct = parseDate(data['end_date'] ?? data['ends_at']);
    if (direct != null) return direct;
    final s = start;
    if (s == null) return null;
    final dh = data['durationHours'];
    final hours = dh is num && dh > 0 ? dh : 6;
    return s.add(Duration(minutes: (hours * 60).round()));
  }

  /// Port of isEventVisible: hidden 1h before the party ends.
  bool get isVisible {
    if (data['isActive'] == false || data['is_active'] == false) return false;
    if (data['status'] == 'cancelled' || data['status'] == 'deleted') return false;
    if (data['is_deleted'] == true) return false;
    final e = end;
    if (e == null) return true;
    return DateTime.now().isBefore(e.subtract(const Duration(hours: 1)));
  }

  int get millis => start?.millisecondsSinceEpoch ?? (1 << 62);
}
