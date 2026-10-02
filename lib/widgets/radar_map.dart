import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../models/firestore_utils.dart';
import '../models/rrpp_party.dart';
import '../models/venue.dart';
import '../models/user_model.dart';
import '../navigation.dart';
import '../providers/auth_provider.dart';
import '../providers/city_provider.dart';
import '../services/nearby.dart';
import '../services/social.dart';
import '../services/venue_hours.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'basemap.dart';
import 'profile_overlay.dart';
import 'swipe_cards.dart';

enum RadarMode { places, users, swipe }

const _placeCategories = [
  ('all', 'map.cat_all', '✨'),
  ('chill', 'map.cat_chill', '🟣'),
  ('bar', 'map.cat_bar', '🍸'),
  ('club', 'map.cat_club', '🪩'),
];

const _cruisingTypes = {'cruising_outdoor', 'community_point', 'cruising', 'public_cruising'};

/// Port of components/Map.tsx (MainMap)
class RadarMap extends StatefulWidget {
  const RadarMap({super.key});

  @override
  State<RadarMap> createState() => _RadarMapState();
}

class _RadarMapState extends State<RadarMap> with TickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final _map = MapController();
  final List<StreamSubscription> _subs = [];
  String? _subsKey;

  List<UserProfile> _rawUsers = [];
  Set<String> _passed = {};
  Set<String> _liked = {};
  List<Map<String, dynamic>> _venues = [];
  // RRPP parties are stored inactive (functions createRRPPParty), so they come from their own query.
  List<Map<String, dynamic>> _parties = [];
  Map<String, int> _checkins = {};
  List<Map<String, dynamic>> _chills = [];
  bool _loading = true;
  LatLng? _userLocation;
  // Wherever the user's zone is (see didChangeDependencies); a wide view until the GPS or a picked city gives one.
  LatLng _center = const LatLng(46, 2);
  String? _zoneKey;
  bool? _optimisticAvailable;

  bool _openNow = false;
  bool _addingPin = false;
  final _pinName = TextEditingController();
  bool _savingPin = false;

  RadarMode _mode = RadarMode.places;
  String _type = 'all';
  String _query = '';
  final _queryCtrl = TextEditingController();

  bool _filtersOpen = false;
  RangeValues _age = const RangeValues(18, 99);
  String? _roleFilter;
  String? _intentFilter;
  bool _onlyPremium = false;
  bool _onlyPhoto = false;
  double _distance = 50;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthProvider>().user?.uid;
    final city = context.watch<CityProvider>();
    final key = '$uid';
    if (key != _subsKey) {
      _subsKey = key;
      _subscribe(uid);
    }
    // Re-centre when the zone itself changes (first GPS fix, another city picked), not on every position update.
    final zone = city.center;
    final zoneKey = zone == null ? null : city.cityId ?? 'gps';
    if (zone != null && zoneKey != _zoneKey) {
      final first = _zoneKey == null;
      _zoneKey = zoneKey;
      _center = LatLng(zone.lat, zone.lng);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          first ? _map.move(_center, 14) : _flyTo(_center, 14);
        } catch (_) {}
      });
    }
  }

  void _subscribe(String? uid) {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    if (uid == null) return;

    final auth = context.read<AuthProvider>();
    _subs.add(_db.collection('users').where('online', isEqualTo: true).limit(30).snapshots().listen((snap) {
      final blocked = auth.profile?.data['blockedUsers'];
      final blockedIds = blocked is List ? blocked.whereType<String>().toSet() : <String>{};
      setState(() {
        _rawUsers = snap.docs
            .where((d) =>
                !blockedIds.contains(d.id) && d.id != uid && d.data()['rol'] != 'party_only' && d.data()['appMode'] != 'party')
            .map(UserProfile.fromDoc)
            .toList();
        _loading = false;
      });
    }, onError: (_) => setState(() => _loading = false)));

    _subs.add(_db.collection('users').doc(uid).collection('passes').snapshots().listen((snap) {
      final now = DateTime.now();
      setState(() => _passed = snap.docs.where((d) {
            final exp = parseDate(d.data()['expiresAt']);
            return exp == null || exp.isAfter(now);
          }).map((d) => d.id).toSet());
    }, onError: (_) {}));

    _subs.add(_db.collection('likes').where('fromId', isEqualTo: uid).snapshots().listen((snap) {
      setState(() => _liked = snap.docs.map((d) => d.data()['toId']).whereType<String>().toSet());
    }, onError: (_) {}));

    // Every active venue and chill; the zone filter happens in _visibleVenues / _visibleChills.
    final vq = _db.collection('venues').where('isActive', isEqualTo: true).where('type', whereNotIn: _cruisingTypes.toList());
    _subs.add(vq.snapshots().listen((snap) {
      final now = DateTime.now();
      final list = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final data = d.data();
        final exp = parseDate(data['expiresAt']);
        if (data['type'] == 'chill' && exp != null && exp.isBefore(now)) continue;
        if (!rrppPartyVisible(data, now)) continue;
        final loc = data['location'];
        final hasLoc = loc is GeoPoint || (loc is Map && loc['latitude'] != null && loc['longitude'] != null);
        if (hasLoc) list.add({'id': d.id, ...data});
      }
      setState(() => _venues = list);
    }, onError: (_) {}));

    final pq = _db.collection('venues').where('rrppParty', isEqualTo: true).where('visibleUntil', isGreaterThan: Timestamp.now());
    _subs.add(pq.snapshots().listen((snap) {
      final list = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final loc = d.data()['location'];
        final hasLoc = loc is GeoPoint || (loc is Map && loc['latitude'] != null && loc['longitude'] != null);
        if (hasLoc) list.add({'id': d.id, ...d.data()});
      }
      setState(() => _parties = list);
    }, onError: (_) {}));

    _subs.add(_db.collection('live_sense').snapshots().listen((snap) {
      final counts = <String, int>{};
      for (final d in snap.docs) {
        final c = d.data()['current_count'];
        if (c is num && c > 0) counts[d.id] = c.toInt();
      }
      setState(() => _checkins = counts);
    }, onError: (_) {}));

    _subs.add(_db
        .collection('chills')
        .where('status', whereIn: ['active', 'full'])
        .snapshots()
        .listen((snap) => setState(() => _chills = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()),
            onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _pinName.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  // Visible unless turned off (radarVisible false); online also needs the app open (AuthProvider presence).
  bool get _isAvailable {
    final p = context.read<AuthProvider>().profile;
    return _optimisticAvailable ?? (p?.radarVisible ?? false);
  }
  bool get _isVipUser => ['plus', 'black'].contains(context.read<AuthProvider>().profile?.membershipTier);

  List<UserProfile> get _usersNearby => _rawUsers.where((u) => !_passed.contains(u.id) && !_liked.contains(u.id)).toList();

  List<UserProfile> get _filteredUsers {
    final pos = context.read<CityProvider>().position;
    final me = _userLocation ?? (pos == null ? null : LatLng(pos.lat, pos.lng));
    return _usersNearby.where((u) {
      if (u.lat == null || u.lng == null) return false;
      final e = u.edad;
      if (e != null && (e < _age.start || e > _age.end)) return false;
      if (_roleFilter != null && u.rol != _roleFilter) return false;
      if (_intentFilter != null && u.intencion != _intentFilter) return false;
      if (_onlyPremium && !['plus', 'black'].contains(u.membershipTier)) return false;
      if (_onlyPhoto && u.fotoUrl.isEmpty) return false;
      if (me != null) {
        final d = calculateDistance(me.latitude, me.longitude, u.lat!, u.lng!);
        if (d > _distance) return false;
      }
      if (_query.isNotEmpty && !u.nick.toLowerCase().contains(_query.toLowerCase().trim())) return false;
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _visibleVenues {
    if (_mode != RadarMode.places) return const [];
    final city = context.read<CityProvider>();
    return inZone([..._venues, ..._parties], city.center, city.cityId, (v) => v).where((v) {
      final type = v['type'] as String?;
      if (type == null || type.isEmpty) return false;
      if (!rrppPartyVisible(v)) return false; // archived, or past visibleUntil since it was loaded
      if (_type != 'all') {
        if (_type == 'sauna' && type != 'sauna') return false;
        if (_type == 'club' && type != 'club' && type != 'nightlife') return false;
        if (_type == 'bar' && !{'bar', 'chiringuito', 'cruising_bar'}.contains(type)) return false;
        if (_type == 'cruising' && !_cruisingTypes.contains(type)) return false;
        if (_type == 'chill') return false;
      }
      if (_query.isNotEmpty && !safeStr(v['name']).toLowerCase().contains(_query.toLowerCase().trim())) return false;
      if (_openNow) {
        final days = asStringList(v['openingDays']);
        final hours = _hours(v);
        if (days.isEmpty || hours.isEmpty) return false;
        if (!isVenueOpenNow(days, hours).isOpen) return false;
      }
      return true;
    }).map((v) {
      final cc = asInt(v['currentCount']);
      final live = _checkins[v['id']] ?? 0;
      return {...v, 'currentCount': cc > live ? cc : live};
    }).toList();
  }

  List<Map<String, dynamic>> get _visibleChills {
    if (_mode != RadarMode.places) return const [];
    if (_type != 'all' && _type != 'chill') return const [];
    final city = context.read<CityProvider>();
    return inZone(_chills, city.center, city.citySlug, (c) => c).where((c) => _query.isEmpty || safeStr(c['title']).toLowerCase().contains(_query.toLowerCase().trim())).toList();
  }

  static Map<String, Hours> _hours(Map<String, dynamic> v) {
    final raw = v['openingHours'];
    if (raw is! Map) return const {};
    final out = <String, Hours>{};
    raw.forEach((k, h) {
      if (h is Map && h['open'] is String && h['close'] is String) out['$k'] = (open: h['open'], close: h['close']);
    });
    return out;
  }

  Future<void> _centerOnUser() async {
    HapticFeedback.mediumImpact();
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      final target = LatLng(pos.latitude, pos.longitude);
      setState(() => _userLocation = target);
      if (mounted) context.read<CityProvider>().refreshPosition();
      _flyTo(target, 15);
    } catch (_) {}
  }

  void _flyTo(LatLng dest, double zoom) {
    final cam = _map.camera;
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    final anim = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic);
    final lat = Tween(begin: cam.center.latitude, end: dest.latitude);
    final lng = Tween(begin: cam.center.longitude, end: dest.longitude);
    final z = Tween(begin: cam.zoom, end: zoom);
    anim.addListener(() => _map.move(LatLng(lat.evaluate(anim), lng.evaluate(anim)), z.evaluate(anim)));
    c.forward().whenComplete(c.dispose);
  }

  Future<void> _toggleAvailability() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;
    HapticFeedback.heavyImpact();
    final next = !_isAvailable;
    setState(() => _optimisticAvailable = next);
    try {
      if (next) {
        final pos = await Geolocator.getCurrentPosition();
        await _db.collection('locations').doc(uid).set({'lat': pos.latitude, 'lng': pos.longitude, 'updatedAt': DateTime.now()});
        await _db.collection('users').doc(uid).set({'online': true, 'radarVisible': true, 'lat': pos.latitude, 'lng': pos.longitude}, SetOptions(merge: true));
      } else {
        await _db.collection('users').doc(uid).set({'online': false, 'radarVisible': false}, SetOptions(merge: true));
      }
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _optimisticAvailable = null);
      });
    } catch (_) {
      if (mounted) setState(() => _optimisticAvailable = null);
    }
  }

  Future<void> _savePin() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (_pinName.text.trim().isEmpty || uid == null) return;
    final i18n = context.read<I18n>();
    setState(() => _savingPin = true);
    HapticFeedback.heavyImpact();
    try {
      await _db.collection('chills').doc().set({
        'title': _pinName.text.trim(),
        'type': 'chill',
        'city_slug': context.read<CityProvider>().citySlug,
        'approx_lat': _center.latitude,
        'approx_lng': _center.longitude,
        'max_capacity': 50,
        'accepted_users': [],
        'status': 'active',
        'host_uid': uid,
        'createdAt': DateTime.now(),
        'expiresAt': DateTime.now().add(const Duration(hours: 24)),
      });
      setState(() {
        _addingPin = false;
        _pinName.clear();
      });
    } catch (_) {
      if (mounted) showToast(context, i18n.t('map_error_create_pin', fallback: 'Error al crear el punto'), error: true);
    }
    if (mounted) setState(() => _savingPin = false);
  }

  void _tap(VoidCallback f) {
    HapticFeedback.selectionClick();
    f();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.65;
    final hasActiveFilters =
        _roleFilter != null || _intentFilter != null || _onlyPremium || _onlyPhoto || _query.isNotEmpty || _openNow;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: h,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Basemap.background,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Tw.w(0.1)),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 25))],
        ),
        child: Stack(children: [
          _mapWidget(),
          if (_mode == RadarMode.swipe)
            Positioned.fill(
              child: Container(
                color: Tw.slate950,
                child: SwipeCards(
                  users: _usersNearby,
                  onSwipe: (id, dir) => setState(() {
                    if (dir == 'left') _passed = {..._passed, id};
                    if (dir == 'right') _liked = {..._liked, id};
                  }),
                ),
              ),
            ),
          if (_loading && context.watch<AuthProvider>().user != null)
            Positioned.fill(child: IgnorePointer(child: Container(color: Tw.slate900))),
          if (_addingPin) _pinOverlay(context),
          if (!_addingPin && _mode != RadarMode.swipe) _bottomControls(),
          if (_mode != RadarMode.swipe) _locationNeeded(context),
        ]),
      ),
      const SizedBox(height: 16),
      _modeChips(context),
      if (_mode == RadarMode.places) ...[
        const SizedBox(height: 12),
        _categoryChips(context),
      ],
      const SizedBox(height: 12),
      _refine(context, hasActiveFilters),
    ]);
  }

  /// No GPS and no city picked: there's no zone to show yet.
  Widget _locationNeeded(BuildContext context) {
    final city = context.watch<CityProvider>();
    if (city.center != null || city.positionStatus == PositionStatus.pending) return const SizedBox.shrink();
    return Positioned(
      top: 90,
      left: 24,
      right: 24,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tw.slate900.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Tw.w(0.1)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(context.t('city.location_needed'), textAlign: TextAlign.center, style: tw(12, weight: bold, color: Tw.slate300)),
          const SizedBox(height: 12),
          Pressable(
            onTap: () {
              HapticFeedback.selectionClick();
              city.refreshPosition();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.circular(12)),
              child: Label(context.t('city.enable_location'), size: 11, weight: black, color: Tw.white),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _mapWidget() {
    final venues = _visibleVenues;
    final chills = _visibleChills;
    final users = _mode == RadarMode.users ? _filteredUsers : const <UserProfile>[];
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: _zoneKey == null ? 3.5 : 14,
        backgroundColor: Basemap.background,
        onPositionChanged: (cam, _) => _center = cam.center,
      ),
      children: [
        const Basemap(),
        MarkerLayer(markers: [
          for (var i = 0; i < venues.length; i++) _venueMarker(venues[i], i),
          for (var i = 0; i < chills.length; i++) ?_chillMarker(chills[i], i),
          for (var i = 0; i < users.length; i++) _userMarker(users[i], i),
        ]),
        const _NavigationControl(),
      ],
    );
  }

  Marker _userMarker(UserProfile u, int index) {
    final boosted = parseDate(u.data['boostedUntil'])?.isAfter(DateTime.now()) ?? false;
    final vip = ['plus', 'black'].contains(u.membershipTier);
    final border = boosted ? Tw.white : vip ? const Color(0xFFEAB308) : Tw.fuchsia500;
    final glow = boosted ? Tw.w(0.6) : vip ? const Color(0x66EAB308) : Tw.fuchsia500.withValues(alpha: 0.4);
    return Marker(
      point: LatLng(u.lat!, u.lng!),
      width: 72,
      height: 88,
      alignment: Alignment.topCenter,
      child: _PopIn(
        delay: Duration(milliseconds: (index * 10).clamp(0, 300)),
        scale: boosted ? 1.3 : 1,
        child: _PressTooltip(
          onTap: () {
            HapticFeedback.mediumImpact();
            showProfileOverlay(context, u.id);
          },
          tooltip: _userTooltip(u, vip),
          child: SizedBox(
            width: 72,
            height: 88,
            child: Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
              if (u.online)
                Positioned(
                  bottom: 0,
                  child: _Pulse(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                        BoxShadow(color: boosted ? Tw.amber400 : Tw.fuchsia500.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4),
                      ]),
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: border, width: 2),
                    boxShadow: [BoxShadow(color: glow, blurRadius: 15)],
                  ),
                  child: ClipOval(child: NetImage(u.fotoUrl, placeholder: Container(color: Tw.slate800, child: const Icon(Icons.public, color: Tw.slate500)))),
                ),
              ),
              if (u.mood != null && u.mood!.isNotEmpty)
                Positioned(
                  top: 0,
                  child: _Float(
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Tw.w(0.1),
                        border: Border.all(color: Tw.w(0.2)),
                      ),
                      child: Text(u.mood!, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
              Positioned(
                bottom: 36,
                right: 8,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: u.online ? Tw.green500 : Tw.slate500,
                    border: Border.all(color: Tw.slate950, width: 2),
                  ),
                ),
              ),
              if (u.verified)
                Positioned(
                  bottom: -4,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.blue500, border: Border.all(color: Tw.slate950, width: 2)),
                    child: const Icon(Icons.verified, size: 10, color: Tw.white),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _userTooltip(UserProfile u, bool vip) => Container(
        constraints: const BoxConstraints(minWidth: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tw.slate900.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Tw.w(0.2)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${u.nick}${u.edad != null ? ', ${u.edad}' : ''}', style: tw(16, weight: black)),
            if (u.verified) ...[const SizedBox(width: 8), const Icon(Icons.verified, color: Tw.blue500, size: 14)],
            if (vip) ...[const SizedBox(width: 8), const VipBadge()],
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            _tag(u.rol, Tw.w(0.05), Tw.slate300),
            _tag(u.intencion, Tw.fuchsia500.withValues(alpha: 0.1), Tw.fuchsia400),
          ]),
          const SizedBox(height: 12),
          Divider(color: Tw.w(0.05), height: 1),
          const SizedBox(height: 12),
          Center(child: Label(context.read<I18n>().t('map_view_profile', fallback: 'Ver Perfil'), color: Tw.w(0.4), tracking: 0.2)),
        ]),
      );

  Widget _tag(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(t.isEmpty ? '' : '${t[0].toUpperCase()}${t.substring(1)}', style: tw(10, weight: bold, color: fg)),
      );

  Marker _venueMarker(Map<String, dynamic> v, int index) {
    final type = v['type'] as String? ?? '';
    final loc = parseLocation(v)!;
    final sub = v['subscription'];
    final subActive = sub is Map && sub['status'] == 'active';
    final tier = v['subscriptionTier'] as String?;
    final status = v['subscriptionStatus'] as String?;
    final isPaying = (tier != null && tier != 'free' && status != 'canceled' && status != 'past_due') ||
        status == 'active' ||
        subActive ||
        v['boostActive'] == true;
    final days = asStringList(v['openingDays']);
    final hours = _hours(v);
    final hasSchedule = days.isNotEmpty && hours.isNotEmpty;
    final isOpen = hasSchedule ? isVenueOpenNow(days, hours).isOpen : true;
    final count = isOpen ? asInt(v['currentCount']) : 0;
    final party = isRRPPParty(v);
    // A reference point: a real place, not a partner (web docs/REFERENCE_VENUES.md); quieter than the network's venues.
    final reference = !party && Venue.isUnclaimedReferenceData(v);
    final unclaimed = v['isClaimed'] == false && !party && !reference;
    final cruising = _cruisingTypes.contains(type);
    final isBar = {'bar', 'chiringuito', 'cruising_bar'}.contains(type);
    final isClub = type == 'club' || type == 'nightlife';

    Color color = Tw.indigo500;
    IconData icon = Icons.place;
    if (party) {
      color = Tw.teal400;
      icon = Icons.celebration;
    } else if (reference) {
      color = Tw.slate300;
    } else if (unclaimed) {
      color = isPaying ? const Color(0xFFEAB308) : Tw.amber400;
      icon = Icons.storefront;
    } else if (cruising) {
      color = isPaying ? Tw.emerald500 : Tw.emerald400;
      icon = Icons.park;
    } else if (type == 'sauna') {
      color = Tw.red500;
      icon = Icons.hot_tub;
    } else if (isBar) {
      color = isPaying ? Tw.orange500 : const Color(0xFFFB923C);
      icon = Icons.local_bar;
    } else if (isClub) {
      color = Tw.cyan400;
      icon = Icons.nightlife;
    } else if (!isPaying) {
      color = Tw.indigo400;
    }

    final tooltip = _venueTooltip(v, isOpen, count, unclaimed, reference, days, hours);
    void open() {
      HapticFeedback.selectionClick();
      // An RRPP party isn't a venue: only its details, never a ticket purchase.
      if (party) {
        _showPartyCard(v);
      } else {
        openRoute(context, AppRoute.venueDetail, args: {'venueId': v['id'] as String});
      }
    }

    if (!isPaying) {
      return Marker(
        point: LatLng(loc.lat, loc.lng),
        width: 48,
        height: 48,
        child: _PopIn(
          delay: Duration(milliseconds: (index * 20).clamp(0, 400)),
          child: _PressTooltip(
            onTap: open,
            tooltip: tooltip,
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: Tw.slate950, width: 2),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 10)],
                ),
                child: Center(child: Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.w(0.8)))),
              ),
              if (isOpen && count > 0) Positioned(top: 4, right: 0, child: _countBadge(count, 9)),
            ]),
          ),
        ),
      );
    }

    final boosted = v['boostActive'] == true || subActive || tier == 'promo' || tier == 'ticketing';
    final cover = v['coverImage'] as String?;
    return Marker(
      point: LatLng(loc.lat, loc.lng),
      width: 64,
      height: 64,
      alignment: Alignment.topCenter,
      child: _PopIn(
        delay: Duration(milliseconds: (index * 50).clamp(0, 500)),
        slide: true,
        child: _PressTooltip(
          onTap: open,
          tooltip: tooltip,
          child: Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
            if (boosted)
              Positioned(
                bottom: 0,
                child: _Pulse(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [
                      BoxShadow(color: const Color(0xFFEAB308).withValues(alpha: 0.3), blurRadius: 24, spreadRadius: 4),
                    ]),
                  ),
                ),
              ),
            Positioned(
              bottom: 0,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Tw.slate900,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: boosted ? const Color(0xFFFACC15) : color, width: 2),
                  boxShadow: [
                    BoxShadow(color: (boosted ? const Color(0xFFFACC15) : color).withValues(alpha: boosted ? 0.6 : 0.5), blurRadius: boosted ? 25 : 20),
                  ],
                ),
                child: cover != null && cover.isNotEmpty
                    ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Opacity(opacity: 0.8, child: NetImage(cover)))
                    : Icon(icon, color: Tw.white, size: 24),
              ),
            ),
            if (isOpen && count > 0) Positioned(top: 0, left: 0, child: _Bounce(child: _countBadge(count, 10))),
            if (v['boostActive'] == true || subActive)
              Positioned(
                top: 4,
                right: 0,
                child: _Pulse(
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFFFDE047), Color(0xFFD97706)]),
                      border: Border.all(color: const Color(0xFFFEF08A)),
                    ),
                    child: const Icon(Icons.star, size: 12, color: Tw.black),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  void _showPartyCard(Map<String, dynamic> v) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Tw.slate900.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.teal500.withValues(alpha: 0.3)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Label(ctx.t('map_rrpp_party', fallback: 'Fiesta RRPP · entrada con el RRPP'), size: 10, weight: black, color: const Color(0xFF5EEAD4)),
              const SizedBox(height: 4),
              Text(safeStr(v['eventTitle']).isNotEmpty ? safeStr(v['eventTitle']) : safeStr(v['name']), style: tw(18, weight: black)),
              const SizedBox(height: 4),
              Text([v['eventDate'], v['eventTime']].where((x) => x != null && '$x'.isNotEmpty).join(' · '), style: tw(12, color: Tw.slate300)),
              Text([safeStr(v['name']), safeStr(v['address'])].where((x) => x.isNotEmpty).join(' · '), style: tw(12, color: Tw.slate400)),
              if (safeStr(v['rrppName']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(ctx.t('map_rrpp_party_by', params: {'name': safeStr(v['rrppName'])}, fallback: 'Organiza: ${safeStr(v['rrppName'])}'),
                      style: tw(12, color: Tw.slate300)),
                ),
              const SizedBox(height: 12),
              Text(ctx.t('map_rrpp_party_ticket', fallback: 'Pide tu entrada al RRPP; esta fiesta no vende entradas en la app.'), style: tw(11, color: Tw.slate500)),
            ]),
          ),
        ),
      );

  Widget _countBadge(int count, double size) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Tw.fuchsia600,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Tw.slate950, width: 2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.person, size: size + 1, color: Tw.white),
          Text('$count', style: tw(size, weight: black)),
        ]),
      );

  Widget _venueTooltip(Map<String, dynamic> v, bool isOpen, int count, bool unclaimed, bool reference, List<String> days, Map<String, Hours> hours) {
    final i18n = context.read<I18n>();
    String scheduleText() {
      if (isOpen) return i18n.t('map_open', fallback: 'Abierto');
      final next = getNextOpening(days, hours);
      if (next?.isToday == true) {
        return i18n.t('venuesPage.opens_today_at', params: {'time': next!.open}, fallback: 'Abre a las ${next.open}');
      }
      if (next != null) {
        final day = i18n.t('venue_config.day_${next.dayKey}');
        return i18n.t('venuesPage.opens_on', params: {'day': day, 'time': next.open}, fallback: 'Abre $day ${next.open}');
      }
      return i18n.t('map_closed', fallback: 'Cerrado');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Tw.slate900.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tw.w(0.2)),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 10))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(safeStr(v['name']), style: tw(14, weight: black)),
        if (isOpen && count > 0)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Tw.fuchsia500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
            child: Text('$count ${count == 1 ? 'persona ahora' : 'personas ahora'}', style: tw(10, weight: black, color: Tw.fuchsia400)),
          ),
        const SizedBox(height: 2),
        isRRPPParty(v)
            ? Label(i18n.t('map_rrpp_party', fallback: 'Fiesta RRPP · entrada con el RRPP'), size: 9, weight: bold, color: const Color(0xFF5EEAD4))
            : reference
            ? Label(i18n.t('reference_venue.badge'), size: 9, weight: bold, color: Tw.slate300)
            : unclaimed
            ? Label(i18n.t('map_pending_verification', fallback: '🟡 Pendiente Verificación'), size: 9, weight: bold, color: Tw.amber400)
            : Label(safeStr(v['type']).isEmpty ? 'Local' : safeStr(v['type']), size: 9, weight: bold),
        if (days.isNotEmpty) Label(scheduleText(), size: 8, weight: bold, color: isOpen ? Tw.green400 : Tw.slate500),
      ]),
    );
  }

  Marker? _chillMarker(Map<String, dynamic> c, int index) {
    final loc = c['location'];
    final lat = asDouble(loc is Map ? loc['latitude'] : null) ?? asDouble(c['approx_lat']);
    final lng = asDouble(loc is Map ? loc['longitude'] : null) ?? asDouble(c['approx_lng']);
    if (lat == null || lng == null) return null;
    final spots = asInt(c['max_capacity']) - (c['accepted_users'] is List ? (c['accepted_users'] as List).length : 0);
    final commercial = c['type'] == 'commercial';
    final i18n = context.read<I18n>();
    final accent = commercial ? Tw.amber400 : Tw.fuchsia400;
    return Marker(
      point: LatLng(lat, lng),
      width: 56,
      height: 56,
      child: _PopIn(
        delay: Duration(milliseconds: (index * 50).clamp(0, 500)),
        child: _PressTooltip(
          onTap: () {
            HapticFeedback.selectionClick();
            openRoute(context, AppRoute.chillDetail, args: {'id': c['id'] as String});
          },
          tooltip: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Tw.slate900.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(safeStr(c['title']), style: tw(14, weight: black)),
              Text(
                '${commercial ? i18n.t('map_after_private', fallback: 'After Privado') : i18n.t('map_chill_social', fallback: 'Chill Social')} · '
                '${spots > 0 ? i18n.t('map_spots_available', params: {'count': spots}, fallback: '$spots plazas') : i18n.t('map_full', fallback: 'Lleno')}',
                style: tw(9, weight: bold, color: accent),
              ),
            ]),
          ),
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            _Pulse(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(color: (commercial ? Tw.amber500 : Tw.fuchsia500).withValues(alpha: 0.3), blurRadius: 24, spreadRadius: 4),
                ]),
              ),
            ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: commercial ? const [Tw.amber400, Tw.orange500] : const [Tw.fuchsia600, Color(0xFF7E22CE)],
                ),
                border: Border.all(color: commercial ? const Color(0xFFFCD34D) : Tw.fuchsia400, width: 2),
              ),
              child: Icon(commercial ? Icons.vpn_key : Icons.local_fire_department, color: Tw.white, size: 20),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Tw.black,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Text(spots > 0 ? '$spots' : '0', style: tw(8, weight: black, color: accent)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _bottomControls() {
    final available = _isAvailable;
    Widget glassBtn({required Widget child, required VoidCallback onTap, double size = 48, bool active = false}) => Pressable(
          onTap: onTap,
          scale: 0.9,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? Tw.fuchsia600.withValues(alpha: 0.8) : Tw.slate900.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: active ? Tw.fuchsia400 : Tw.w(0.1)),
              boxShadow: active ? [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.4), blurRadius: 20)] : null,
            ),
            child: child,
          ),
        );
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        glassBtn(
          size: 56,
          active: available,
          onTap: _toggleAvailability,
          child: Text(available ? '👻' : '🫥', style: const TextStyle(fontSize: 24)),
        ),
        const Spacer(),
        glassBtn(
          onTap: () => _tap(() => setState(() => _addingPin = !_addingPin)),
          child: Icon(_addingPin ? Icons.close : Icons.add_location, color: Tw.white, size: 20),
        ),
        const SizedBox(width: 8),
        glassBtn(onTap: _centerOnUser, child: const Icon(Icons.my_location, color: Tw.fuchsia400, size: 20)),
      ]),
    );
  }

  Widget _pinOverlay(BuildContext context) => Positioned.fill(
        child: Stack(alignment: Alignment.center, children: [
          IgnorePointer(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_fire_department, size: 36, color: Tw.fuchsia500,
                    shadows: [Shadow(color: Tw.fuchsia500.withValues(alpha: 0.8), blurRadius: 15)]),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Tw.fuchsia500,
                    boxShadow: [BoxShadow(color: Tw.fuchsia500, blurRadius: 10)],
                  ),
                ),
              ]),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Tw.slate900.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Tw.w(0.1)),
                boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 50, offset: Offset(0, 20))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(context.t('map.create_chill', fallback: 'Crear Punto de Encuentro'), style: tw(14, weight: black, tracking: -0.025))),
                  GestureDetector(onTap: () => setState(() => _addingPin = false), child: const Icon(Icons.close, size: 18, color: Tw.slate500)),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinName,
                  onChanged: (_) => setState(() {}),
                  style: tw(14),
                  decoration: InputDecoration(
                    hintText: context.t('map.pin_name', fallback: 'Nombre (ej. Previa en mi casa...)'),
                    fillColor: Colors.black.withValues(alpha: 0.4),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Tw.w(0.1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.fuchsia500)),
                  ),
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: _pinName.text.trim().isEmpty || _savingPin ? 0.5 : 1,
                  child: Pressable(
                    onTap: _pinName.text.trim().isEmpty || _savingPin ? () {} : _savePin,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(12)),
                      child: Label(_savingPin ? context.t('map.saving', fallback: 'Guardando...') : context.t('map.save', fallback: 'Fijar Aquí'),
                          color: Tw.black, align: TextAlign.center),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Label(context.t('map_event_expires_24h', fallback: 'Este evento desaparecerá en 24h'), size: 9, weight: FontWeight.w400,
                    color: Tw.slate500, align: TextAlign.center),
              ]),
            ),
          ),
        ]),
      );

  Widget _modeChips(BuildContext context) {
    Widget chip(RadarMode m, String emoji, String label) {
      final active = _mode == m;
      final swipe = m == RadarMode.swipe;
      return Expanded(
        child: Pressable(
          onTap: () => _tap(() => setState(() => _mode = m)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active && !swipe ? Tw.fuchsia600 : null,
              gradient: active && swipe ? const LinearGradient(colors: [Tw.orange500, Tw.amber500]) : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: active
                  ? [BoxShadow(color: (swipe ? Tw.amber500 : Tw.fuchsia500).withValues(alpha: swipe ? 0.5 : 0.3), blurRadius: 15)]
                  : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(emoji, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 6),
              Flexible(child: Label(label, color: active ? Tw.white : Tw.slate400, tracking: 0, maxLines: 1)),
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Tw.w(0.1)),
      ),
      child: Row(children: [
        chip(RadarMode.places, '📍', context.t('map.mode_places', fallback: 'Lugares')),
        chip(RadarMode.users, '👥', context.t('map.mode_map', fallback: 'Mapa')),
        chip(RadarMode.swipe, '🔥', context.t('map.mode_swipe', fallback: 'Swipe')),
      ]),
    );
  }

  Widget _categoryChips(BuildContext context) {
    Widget chip({required bool active, required Widget leading, required String label, required VoidCallback onTap, Color activeColor = Tw.fuchsia500}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Pressable(
            onTap: () => _tap(onTap),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: active ? activeColor : Tw.w(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: active ? activeColor : Tw.w(0.05)),
                boxShadow: active ? [BoxShadow(color: activeColor.withValues(alpha: 0.2), blurRadius: 15)] : null,
              ),
              child: Row(children: [
                leading,
                const SizedBox(width: 6),
                Label(label, color: active ? Tw.white : Tw.slate400, tracking: 0.05),
              ]),
            ),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final c in _placeCategories)
          chip(
            active: _type == c.$1,
            leading: Text(c.$3, style: const TextStyle(fontSize: 14)),
            label: context.t(c.$2),
            onTap: () => setState(() => _type = c.$1),
          ),
        chip(
          active: _openNow,
          activeColor: Tw.green500,
          leading: Icon(Icons.schedule, size: 14, color: _openNow ? Tw.white : Tw.slate400),
          label: context.t('venuesPage.open_now', fallback: 'Abierto'),
          onTap: () => setState(() => _openNow = !_openNow),
        ),
      ]),
    );
  }

  Widget _refine(BuildContext context, bool active) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
      child: Column(children: [
        InkWell(
          onTap: () => _tap(() => setState(() => _filtersOpen = !_filtersOpen)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              const Icon(Icons.tune, size: 14, color: Tw.fuchsia400),
              const SizedBox(width: 8),
              Label(context.t('map.refine', fallback: 'Refinar Búsqueda')),
              if (active) ...[
                const SizedBox(width: 8),
                _Pulse(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Tw.fuchsia500,
                      boxShadow: [BoxShadow(color: Tw.fuchsia500, blurRadius: 6)],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              AnimatedRotation(
                turns: _filtersOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more, color: Tw.slate400, size: 20),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: const Cubic(0.32, 0.72, 0, 1),
          child: !_filtersOpen
              ? const SizedBox(width: double.infinity)
              : Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.w(0.05)))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _searchBox(context),
                    if (_mode != RadarMode.places) ..._userFilters(context),
                  ]),
                ),
        ),
      ]),
    );
  }

  Widget _searchBox(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tw.w(0.1)),
        ),
        child: Row(children: [
          const Icon(Icons.search, size: 16, color: Tw.slate400),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _queryCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: tw(14),
              decoration: InputDecoration(
                hintText: _mode == RadarMode.places
                    ? context.t('map.search_place', fallback: 'Buscar local, fiesta o villa...')
                    : context.t('map.search_user', fallback: 'Buscar usuarios por nombre...'),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _query = '';
                _queryCtrl.clear();
              }),
              child: const Icon(Icons.close, size: 14, color: Tw.slate500),
            ),
        ]),
      );

  List<Widget> _userFilters(BuildContext context) {
    final vip = _isVipUser;
    Widget header(String label, String value) => Row(children: [
          Expanded(child: Label(label, color: Tw.slate500, tracking: 0.2)),
          Text(value, style: tw(14, weight: black, color: Tw.fuchsia400)),
        ]);
    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: 4,
      activeTrackColor: Tw.fuchsia500,
      inactiveTrackColor: Tw.w(0.05),
      thumbColor: Tw.fuchsia500,
      overlayShape: SliderComponentShape.noOverlay,
      rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 8),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
    );
    Widget toggle(String label, bool active, VoidCallback onTap) => Expanded(
          child: Pressable(
            onTap: () => _tap(onTap),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? Tw.fuchsia500 : Tw.w(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? Tw.fuchsia500 : Tw.w(0.05)),
              ),
              child: Label(label, color: active ? Tw.white : Tw.slate400, align: TextAlign.center),
            ),
          ),
        );
    Widget vipToggle(String label, bool on, Color onColor, VoidCallback toggle) => Expanded(
          child: Pressable(
            onTap: () {
              if (!vip) {
                openRoute(context, AppRoute.premium);
                return;
              }
              _tap(toggle);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: on ? onColor.withValues(alpha: 0.2) : Tw.w(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: on ? onColor.withValues(alpha: 0.5) : Tw.w(0.05)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(on ? Icons.check_box : Icons.check_box_outline_blank, size: 12, color: on ? onColor : Tw.slate400),
                const SizedBox(width: 8),
                Flexible(child: Label(label, color: on ? onColor : Tw.slate400, tracking: 0.05, maxLines: 1)),
                if (!vip) ...[const SizedBox(width: 6), const Icon(Icons.lock, size: 12, color: Color(0xFFEAB308))],
              ]),
            ),
          ),
        );

    return [
      const SizedBox(height: 20),
      header(context.t('map.age', fallback: 'Rango de Edad'), '${_age.start.round()} - ${_age.end.round()}'),
      const SizedBox(height: 12),
      SliderTheme(
        data: sliderTheme,
        child: RangeSlider(values: _age, min: 18, max: 99, onChanged: (v) => setState(() => _age = v)),
      ),
      const SizedBox(height: 20),
      header(context.t('map.distance', fallback: 'Distancia Máxima'), '${_distance.round()} km'),
      const SizedBox(height: 12),
      SliderTheme(
        data: sliderTheme,
        child: Slider(value: _distance, min: 1, max: 100, onChanged: (v) => setState(() => _distance = v)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
          Label('1 km', size: 8, color: Tw.slate600),
          Label('100 km', size: 8, color: Tw.slate600),
        ]),
      ),
      const SizedBox(height: 20),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label(context.t('map.role', fallback: 'Rol'), color: Tw.slate500, tracking: 0.2),
            const SizedBox(height: 8),
            for (final r in platformRoles) ...[
              Row(children: [
                toggle(context.t(r.labelKey, fallback: r.fallbackLabel), _roleFilter == r.value,
                    () => setState(() => _roleFilter = _roleFilter == r.value ? null : r.value)),
              ]),
              const SizedBox(height: 6),
            ],
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label(context.t('map.intent', fallback: 'Busco...'), color: Tw.slate500, tracking: 0.2),
            const SizedBox(height: 8),
            for (final i in ['conocer', 'quedar']) ...[
              Row(children: [
                toggle(i, _intentFilter == i, () => setState(() => _intentFilter = _intentFilter == i ? null : i)),
              ]),
              const SizedBox(height: 6),
            ],
          ]),
        ),
      ]),
      const SizedBox(height: 20),
      Label(context.t('map.vip_filters', fallback: 'Filtros VIP'), color: Tw.slate500, tracking: 0.2),
      const SizedBox(height: 8),
      Row(children: [
        vipToggle(context.t('map.photo_only', fallback: 'Con foto'), _onlyPhoto, Tw.fuchsia400, () => setState(() => _onlyPhoto = !_onlyPhoto)),
        const SizedBox(width: 8),
        vipToggle(context.t('map.vip_only', fallback: 'Solo VIP'), _onlyPremium, const Color(0xFFEAB308),
            () => setState(() => _onlyPremium = !_onlyPremium)),
      ]),
    ];
  }
}

/// MapLibre-style NavigationControl (zoom in/out) at top-left.
class _NavigationControl extends StatelessWidget {
  const _NavigationControl();

  @override
  Widget build(BuildContext context) {
    final cam = MapCamera.of(context);
    final ctrl = MapController.of(context);
    Widget btn(IconData icon, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: SizedBox(width: 29, height: 29, child: Icon(icon, size: 18, color: const Color(0xFF333333))),
        );
    return Positioned(
      top: 10,
      left: 10,
      child: Container(
        decoration: BoxDecoration(
          color: Tw.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Color(0x1A000000), spreadRadius: 2)],
        ),
        child: Column(children: [
          btn(Icons.add, () => ctrl.move(cam.center, cam.zoom + 1)),
          Container(height: 1, width: 29, color: const Color(0xFFDDDDDD)),
          btn(Icons.remove, () => ctrl.move(cam.center, cam.zoom - 1)),
          Container(height: 1, width: 29, color: const Color(0xFFDDDDDD)),
          btn(Icons.navigation, () => ctrl.rotate(0)),
        ]),
      ),
    );
  }
}

/// Shows [tooltip] above the marker while pressed (CSS `group-active:block`), taps call [onTap].
class _PressTooltip extends StatefulWidget {
  final Widget child;
  final Widget tooltip;
  final VoidCallback onTap;
  const _PressTooltip({required this.child, required this.tooltip, required this.onTap});

  @override
  State<_PressTooltip> createState() => _PressTooltipState();
}

class _PressTooltipState extends State<_PressTooltip> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  bool _down = false;

  void _show() {
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        width: 260,
        child: CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -12),
          child: IgnorePointer(child: Center(child: Material(color: Colors.transparent, child: widget.tooltip))),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
        link: _link,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          onLongPressStart: (_) {
            setState(() => _down = true);
            _show();
          },
          onLongPressEnd: (_) {
            setState(() => _down = false);
            _hide();
          },
          child: AnimatedScale(scale: _down ? 0.95 : 1, duration: const Duration(milliseconds: 150), child: widget.child),
        ),
      );
}

class _PopIn extends StatelessWidget {
  final Widget child;
  final Duration delay;
  final double scale;
  final bool slide;
  const _PopIn({required this.child, required this.delay, this.scale = 1, this.slide = false});

  @override
  Widget build(BuildContext context) {
    final total = const Duration(milliseconds: 500) + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.elasticOut),
      builder: (_, v, c) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, slide ? 20 * (1 - v) : 0),
          child: Transform.scale(scale: (slide ? 0.6 + 0.4 * v : v) * scale, child: c),
        ),
      ),
      child: child,
    );
  }
}

class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: Tween(begin: 1.0, end: 0.4).animate(_c), child: ScaleTransition(scale: Tween(begin: 1.0, end: 1.15).animate(_c), child: widget.child));
}

class _Float extends StatefulWidget {
  final Widget child;
  const _Float({required this.child});

  @override
  State<_Float> createState() => _FloatState();
}

class _FloatState extends State<_Float> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, c) => Transform.translate(offset: Offset(0, -4 * Curves.easeInOut.transform(_c.value)), child: c),
        child: widget.child,
      );
}

class _Bounce extends StatefulWidget {
  final Widget child;
  const _Bounce({required this.child});

  @override
  State<_Bounce> createState() => _BounceState();
}

class _BounceState extends State<_Bounce> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, c) => Transform.translate(
          offset: Offset(0, -5 * (0.5 + 0.5 * math.cos(2 * math.pi * _c.value))),
          child: c,
        ),
        child: widget.child,
      );
}
