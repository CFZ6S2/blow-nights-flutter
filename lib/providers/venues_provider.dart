import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/event.dart';
import '../models/venue.dart';
import '../services/nearby.dart';

/// Port of useVenues(center, cityId) + the live_sense listener + the home page's upcoming-events query.
/// Location-first: everything active is loaded once and filtered to the user's zone (see CityProvider.center), so it
/// works anywhere, not only in a city.
class VenuesProvider extends ChangeNotifier {
  final _db = FirebaseFirestore.instance;

  GeoPos? _center;
  String? _cityId;
  List<Venue> _allVenues = [];
  List<Venue> _allEventVenues = [];
  List<Event> _allEvents = [];
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

  /// All venues + independent events in the zone, like `useVenues().venues` on the web.
  List<Venue> get all => [...venues, ...eventVenues];

  /// The user's zone changed (first GPS fix, another city picked). Subscribes on the first call.
  void setZone(GeoPos? center, String? cityId) {
    if (_subs.isNotEmpty && center == _center && cityId == _cityId) return;
    _center = center;
    _cityId = cityId;
    if (_subs.isEmpty) _subscribe();
    _applyZone();
  }

  void _subscribe() {
    _subs.add(_db.collection('venues').where('isActive', isEqualTo: true).snapshots().listen((snap) {
      _allVenues = snap.docs.map((d) => Venue.fromDoc(d)).toList();
      loading = false;
      _applyZone();
    }, onError: (_) {
      loading = false;
      notifyListeners();
    }));

    _subs.add(_db.collection('events').where('isActive', isEqualTo: true).limit(200).snapshots().listen((snap) {
      _allEventVenues = snap.docs.map((d) => Venue.fromDoc(d, forceType: 'event')).toList();
      _allEvents = snap.docs.map(Event.fromDoc).where((e) => e.isVisible).toList();
      eventsLoading = false;
      _applyZone();
    }, onError: (_) {
      eventsLoading = false;
      notifyListeners();
    }));
  }

  void _applyZone() {
    venues = inZone(_allVenues, _center, _cityId, (v) => v.data);
    eventVenues = inZone(_allEventVenues, _center, _cityId, (v) => v.data);
    // Sorted here instead of orderBy(start_date): no composite index needed without the city filter.
    upcomingEvents = inZone(_allEvents, _center, _cityId, (e) => e.data)
      ..sort((a, b) => (a.start ?? DateTime(9999)).compareTo(b.start ?? DateTime(9999)));
    if (upcomingEvents.length > 15) upcomingEvents = upcomingEvents.sublist(0, 15);
    notifyListeners();
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
