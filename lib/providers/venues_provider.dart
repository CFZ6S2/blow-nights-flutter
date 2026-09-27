import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/event.dart';
import '../models/venue.dart';

/// Port of useVenues(cityId) + the live_sense listener + the home page's upcoming-events query.
class VenuesProvider extends ChangeNotifier {
  final _db = FirebaseFirestore.instance;

  String? _cityId;
  List<Venue> venues = [];
  List<Venue> eventVenues = [];
  List<Event> upcomingEvents = [];
  Map<String, int> liveCounts = {};
  bool loading = true;
  bool eventsLoading = true;

  final List<StreamSubscription> _subs = [];
  StreamSubscription? _liveSub;

  VenuesProvider() {
    _liveSub = _db.collection('live_sense').snapshots().listen((snap) {
      final counts = <String, int>{};
      for (final d in snap.docs) {
        final c = d.data()['current_count'];
        if (c is num && c > 0) counts[d.id] = c.toInt();
      }
      liveCounts = counts;
      notifyListeners();
    }, onError: (_) {});
  }

  /// All venues + independent events, like `useVenues().venues` on the web.
  List<Venue> get all => [...venues, ...eventVenues];

  void setCity(String? cityId) {
    if (cityId == _cityId && _subs.isNotEmpty) return;
    _cityId = cityId;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    loading = true;
    eventsLoading = true;

    Query<Map<String, dynamic>> q = _db.collection('venues').where('isActive', isEqualTo: true);
    Query<Map<String, dynamic>> eq = _db.collection('events').where('isActive', isEqualTo: true);
    if (cityId != null) {
      q = q.where('cityId', isEqualTo: cityId);
      eq = eq.where('cityId', isEqualTo: cityId);
    }

    _subs.add(q.snapshots().listen((snap) {
      venues = snap.docs.map((d) => Venue.fromDoc(d)).toList();
      loading = false;
      notifyListeners();
    }, onError: (_) {
      loading = false;
      notifyListeners();
    }));

    _subs.add(eq.snapshots().listen((snap) {
      eventVenues = snap.docs.map((d) => Venue.fromDoc(d, forceType: 'event')).toList();
      notifyListeners();
    }, onError: (_) {}));

    if (cityId != null) {
      _subs.add(_db
          .collection('events')
          .where('cityId', isEqualTo: cityId)
          .where('isActive', isEqualTo: true)
          .orderBy('start_date')
          .limit(15)
          .snapshots()
          .listen((snap) {
        upcomingEvents = snap.docs.map(Event.fromDoc).where((e) => e.isVisible).toList();
        eventsLoading = false;
        notifyListeners();
      }, onError: (_) {
        eventsLoading = false;
        notifyListeners();
      }));
    }
  }

  int liveCountFor(Venue v) {
    final live = liveCounts[v.id] ?? 0;
    return v.currentCount > live ? v.currentCount : live;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _liveSub?.cancel();
    super.dispose();
  }
}
