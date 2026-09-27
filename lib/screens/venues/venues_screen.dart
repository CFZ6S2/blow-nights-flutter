import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../models/venue.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/city_provider.dart';
import '../../providers/venues_provider.dart';
import '../../services/social.dart';
import '../../services/venue_hours.dart';
import '../../theme/app_theme.dart';
import '../../widgets/city_selector.dart';
import '../../widgets/common.dart';

String formatPrice(num amount, [String currency = 'eur']) {
  final sym = switch (currency.toLowerCase()) { 'eur' => '€', 'gbp' => '£', _ => currency.toUpperCase() };
  return '${amount.toStringAsFixed(2)} $sym';
}

/// Port of app/[city]/venues/page.tsx
class VenuesScreen extends StatefulWidget {
  const VenuesScreen({super.key});

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen> {
  final _db = FirebaseFirestore.instance;
  Map<String, dynamic>? _activeCheckin;
  bool _checkingIn = false;
  String _visibility = 'public';
  String _category = 'all';
  bool _openNow = false;
  final _search = TextEditingController();
  ({double lat, double lng})? _userLocation;
  bool _autoCheckoutDone = false;
  final List<StreamSubscription> _subs = [];
  String? _uid;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _locate();
  }

  Future<void> _locate() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 5)));
      if (mounted) setState(() => _userLocation = (lat: pos.latitude, lng: pos.longitude));
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthProvider>().user?.uid;
    if (uid == _uid) return;
    _uid = uid;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    if (uid == null) return;
    final now = Timestamp.now();
    List<Map<String, dynamic>> results = [];
    void merge() => setState(() => _activeCheckin = results.isNotEmpty ? results.first : null);
    _subs.add(_db
        .collection('checkins')
        .where('userId', isEqualTo: uid)
        .where('expiresAt', isGreaterThan: now)
        .snapshots()
        .listen((s) {
      results = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      merge();
    }, onError: (_) {}));
    _subs.add(_db
        .collection('checkins')
        .where('realUserId', isEqualTo: uid)
        .where('expiresAt', isGreaterThan: now)
        .snapshots()
        .listen((s) {
      final anon = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      if (anon.isNotEmpty && results.isEmpty) results = anon;
      merge();
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _search.dispose();
    super.dispose();
  }

  Future<void> _checkin(String venueId) async {
    if (_uid == null || _checkingIn) return;
    _autoCheckoutDone = false;
    setState(() => _checkingIn = true);
    try {
      final anonymous = _visibility == 'anonymous';
      await FirebaseFunctions.instance.httpsCallable('checkInUser').call({
        'venueId': venueId,
        'visibility': anonymous ? 'anonymous' : _visibility,
        'anonymous': anonymous,
      });
    } catch (_) {}
    if (mounted) setState(() => _checkingIn = false);
  }

  Future<void> _checkout() async {
    if (_activeCheckin == null) return;
    try {
      await FirebaseFunctions.instance.httpsCallable('checkOutUser').call();
    } catch (_) {}
  }

  double? _distance(Venue v) {
    final u = _userLocation;
    final l = v.location;
    if (u == null || l == null) return null;
    return calculateDistance(u.lat, u.lng, l.lat, l.lng);
  }

  List<Venue> _grouped(List<Venue> all, String type) {
    final list = all.where((v) => v.type == type).toList();
    final idx = {for (var i = 0; i < list.length; i++) list[i].id: i};
    list.sort((a, b) {
      if (a.boosted != b.boosted) return a.boosted ? -1 : 1;
      return idx[a.id]! - idx[b.id]!;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<VenuesProvider>();
    final currency = context.watch<CityProvider>().currency;
    if (auth.loading) return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (data.loading) return const _VenuesSkeleton();

    final all = data.all;
    final raw = _category == 'all'
        ? [for (final k in venueTypes.keys) ..._grouped(all, k)]
        : _grouped(all, _category);
    final q = _search.text.toLowerCase();
    final shown = raw.where((v) {
      if (_openNow) {
        if (!v.hasSchedule || !isVenueOpenNow(v.openingDays, v.openingHours).isOpen) return false;
      }
      if (q.isNotEmpty && !v.name.toLowerCase().contains(q) && !v.address.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    if (_userLocation != null) {
      final idx = {for (var i = 0; i < shown.length; i++) shown[i].id: i};
      shown.sort((a, b) {
        final da = _distance(a), db = _distance(b);
        if (da == null && db == null) return idx[a.id]! - idx[b.id]!;
        if (da == null) return 1;
        if (db == null) return -1;
        final c = da.compareTo(db);
        return c != 0 ? c : idx[a.id]! - idx[b.id]!;
      });
    }

    final active = _activeCheckin;
    if (active != null && !_autoCheckoutDone) {
      final v = raw.where((e) => e.id == active['venueId']).firstOrNull;
      if (v != null && v.hasSchedule && !isVenueOpenNow(v.openingDays, v.openingHours).isOpen) {
        _autoCheckoutDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkout();
          if (mounted) {
            showToast(context, context.read<I18n>().t('venuesPage.auto_checkout_closed',
                fallback: 'El local ha cerrado y se ha finalizado tu check-in automáticamente.'));
          }
        });
      }
    }

    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: Stack(children: [
        Positioned(top: -size.height * 0.1, left: -size.width * 0.2, child: Orb(color: Tw.fuchsia600.withValues(alpha: 0.1), size: size.width * 0.8)),
        Positioned(top: size.height * 0.2, right: -size.width * 0.2, child: Orb(color: Tw.indigo600.withValues(alpha: 0.1), size: size.width * 0.7)),
        SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 128),
            children: [
              Row(children: [
                Expanded(child: Text(context.t('venuesPage.whereTo'), style: tw(24, weight: black, tracking: -0.025))),
                const CitySelector(),
              ]),
              const SizedBox(height: 12),
              Text(context.t('venuesPage.selectVenue'), style: tw(12, color: Tw.slate500)),
              const SizedBox(height: 24),
              if (active != null) ...[_checkinBanner(context, active), const SizedBox(height: 24)],
              _visibilityRow(context),
              if (_visibility == 'anonymous') ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Tw.red500.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Tw.red500.withValues(alpha: 0.1)),
                  ),
                  child: Text.rich(TextSpan(children: [
                    WidgetSpan(child: Icon(Icons.info, size: 10, color: Tw.red400.withValues(alpha: 0.8))),
                    TextSpan(text: ' ${context.t('venuesPage.anonInfo')}'),
                  ]), style: tw(10, weight: bold, color: Tw.red400.withValues(alpha: 0.8))),
                ),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: _search,
                style: tw(14),
                decoration: InputDecoration(
                  hintText: context.t('venuesPage.searchPlaceholder', fallback: 'Buscar local...'),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Tw.slate500),
                  fillColor: Tw.slate900,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.slate700)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.fuchsia500)),
                ),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: _categorySelect(context)),
                const SizedBox(width: 8),
                Pressable(
                  onTap: () => setState(() => _openNow = !_openNow),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: _openNow ? Tw.green500.withValues(alpha: 0.2) : Tw.slate900,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _openNow ? Tw.green500.withValues(alpha: 0.3) : Tw.slate700),
                    ),
                    child: Row(children: [
                      Icon(Icons.schedule, size: 14, color: _openNow ? Tw.green400 : Tw.slate400),
                      const SizedBox(width: 4),
                      Label(context.t('venuesPage.open_now', fallback: 'Abierto'), size: 12,
                          color: _openNow ? Tw.green400 : Tw.slate400, tracking: 0.05),
                    ]),
                  ),
                ),
              ]),
              if (_category != 'all') ...[
                const SizedBox(height: 24),
                Label(venueTypes[_category]?.hours ?? '', color: Tw.slate600),
              ],
              if (shown.isNotEmpty && (q.isNotEmpty || _openNow || _category != 'all')) ...[
                const SizedBox(height: 24),
                Label('${shown.length} ${shown.length == 1 ? context.t('venuesPage.result', fallback: 'resultado') : context.t('venuesPage.results', fallback: 'resultados')}',
                    color: Tw.slate500, weight: bold),
              ],
              const SizedBox(height: 24),
              if (shown.isEmpty)
                _empty(context, q.isNotEmpty)
              else
                for (final v in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _VenueCard(
                      venue: v,
                      live: data.liveCounts[v.id] ?? 0,
                      distance: _distance(v),
                      isHere: active?['venueId'] == v.id,
                      checkingIn: _checkingIn,
                      currency: currency,
                      onCheckin: () => _checkin(v.id),
                    ),
                  ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _checkinBanner(BuildContext context, Map<String, dynamic> c) {
    final vis = c['visibility'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Tw.green500.withValues(alpha: 0.1), Tw.emerald500.withValues(alpha: 0.1)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Tw.green500.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Tw.green500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.location_on, color: Tw.green400),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(safeStr(c['venueName']), style: tw(14, weight: black)),
            Text(
              vis == 'anonymous'
                  ? context.t('venuesPage.anonMode')
                  : vis == 'ghost'
                      ? context.t('venuesPage.ghostMode')
                      : context.t('venuesPage.visibleAll'),
              style: tw(10, color: Tw.slate500),
            ),
          ]),
        ),
        Pressable(
          onTap: _checkout,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
            child: Text(context.t('venuesPage.exit'), style: tw(12, weight: bold)),
          ),
        ),
      ]),
    );
  }

  Widget _visibilityRow(BuildContext context) {
    Widget btn(String mode, IconData icon, String label, Color color) {
      final on = _visibility == mode;
      return Expanded(
        child: Pressable(
          onTap: () => setState(() => _visibility = mode),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: on ? color.withValues(alpha: 0.2) : Tw.w(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? color.withValues(alpha: 0.3) : Tw.w(0.1)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 14, color: on ? _light(color) : Tw.slate500),
              const SizedBox(width: 4),
              Flexible(child: Label(label, color: on ? _light(color) : Tw.slate500, maxLines: 1)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [
      btn('public', Icons.visibility, context.t('venuesPage.public'), Tw.fuchsia500),
      const SizedBox(width: 8),
      btn('ghost', Icons.visibility_off, context.t('venuesPage.ghost'), Tw.indigo500),
      const SizedBox(width: 8),
      btn('anonymous', Icons.shield, context.t('venuesPage.anonymous'), Tw.red500),
    ]);
  }

  Color _light(Color c) => c == Tw.fuchsia500 ? Tw.fuchsia400 : c == Tw.indigo500 ? Tw.indigo400 : Tw.red400;

  Widget _categorySelect(BuildContext context) {
    final i18n = context.watch<I18n>();
    final groups = <(String?, List<(String, String)>)>[
      (null, [('all', i18n.t('venuesPage.allCategories'))]),
      (i18n.t('venuesPage.commercialVenues'), [
        ('club', i18n.t('venuesPage.clubs')),
        ('bar', i18n.t('venuesPage.bars')),
        ('chiringuito', i18n.t('venuesPage.chiringuitos')),
      ]),
      (i18n.t('venuesPage.independentEvents'), [('event', i18n.t('venuesPage.events'))]),
      (i18n.t('venuesPage.moreCategories', fallback: 'Más categorías'), [
        ('sauna', i18n.t('venuesPage.saunas')),
        ('cruising_outdoor', i18n.t('venuesPage.cruising')),
        ('community_point', i18n.t('venuesPage.meetingPoints')),
      ]),
    ];
    final label = groups.expand((g) => g.$2).firstWhere((o) => o.$1 == _category).$2;
    return Pressable(
      onTap: () async {
        final picked = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            backgroundColor: Tw.slate900,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Tw.w(0.1))),
            children: [
              for (final g in groups) ...[
                if (g.$1 != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                    child: Text(g.$1!, style: tw(12, weight: bold, color: Tw.slate500)),
                  ),
                for (final o in g.$2)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(ctx).pop(o.$1),
                    child: Row(children: [
                      Expanded(child: Text(o.$2, style: tw(14, weight: medium, color: _category == o.$1 ? Tw.fuchsia400 : Tw.slate300))),
                      if (_category == o.$1) const Icon(Icons.check, size: 16, color: Tw.fuchsia400),
                    ]),
                  ),
              ],
            ],
          ),
        );
        if (picked != null) setState(() => _category = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.slate700)),
        child: Row(children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: tw(14, weight: medium, color: const Color(0xFFE2E8F0)))),
          const Text('▼', style: TextStyle(fontSize: 10, color: Tw.slate400)),
        ]),
      ),
    );
  }

  Widget _empty(BuildContext context, bool searching) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(children: [
          Icon(searching ? Icons.search_off : _openNow ? Icons.schedule : Icons.nightlife, size: 48, color: Tw.slate700),
          const SizedBox(height: 16),
          Text(
            searching
                ? context.t('venuesPage.noSearchResults', fallback: 'No se encontraron resultados')
                : _openNow
                    ? context.t('venuesPage.noOpenVenues', fallback: 'No hay locales abiertos ahora mismo')
                    : context.t('venuesPage.noVenues'),
            textAlign: TextAlign.center,
            style: tw(14, color: Tw.slate500),
          ),
          const SizedBox(height: 8),
          Text(
            searching
                ? context.t('venuesPage.tryDifferentSearch', fallback: 'Prueba con otro nombre o dirección')
                : _openNow
                    ? context.t('venuesPage.tryLater', fallback: 'Prueba más tarde o quita el filtro')
                    : context.t('venuesPage.venuesWillBeAdded'),
            textAlign: TextAlign.center,
            style: tw(10, color: Tw.slate600),
          ),
          if (_openNow || searching) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() {
                _openNow = false;
                _search.clear();
              }),
              child: Text(context.t('venuesPage.showAll', fallback: 'Ver todos'),
                  style: tw(12, weight: bold, color: Tw.fuchsia400, decoration: TextDecoration.underline)),
            ),
          ],
        ]),
      );
}

class _VenueCard extends StatelessWidget {
  final Venue venue;
  final int live;
  final double? distance;
  final bool isHere;
  final bool checkingIn;
  final String currency;
  final VoidCallback onCheckin;
  const _VenueCard({
    required this.venue,
    required this.live,
    required this.distance,
    required this.isHere,
    required this.checkingIn,
    required this.currency,
    required this.onCheckin,
  });

  static const _cruising = {'sauna', 'cruising_outdoor'};

  @override
  Widget build(BuildContext context) {
    final v = venue;
    final isOpen = v.hasSchedule ? isVenueOpenNow(v.openingDays, v.openingHours).isOpen : true;
    final isClosed = v.openingDays.isNotEmpty && !isVenueOpenNow(v.openingDays, v.openingHours).isOpen;
    final sched = formatScheduleToday(v.openingDays, v.openingHours);
    final promo = v.data['promoBanner'];
    final pricing = v.data['ticketPricing'] is Map ? Map<String, dynamic>.from(v.data['ticketPricing']) : const <String, dynamic>{};
    final tiers = v.data['ticket_tiers'] is List ? (v.data['ticket_tiers'] as List).whereType<Map>().toList() : const <Map>[];
    void open() => openRoute(context, AppRoute.venueDetail, args: {'venueId': v.id, 'type': v.type});

    String? distLabel;
    if (distance != null) distLabel = distance! < 1 ? '${(distance! * 1000).round()}m' : '${distance}km';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isHere ? Tw.green500.withValues(alpha: 0.05) : Tw.w(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isHere ? Tw.green500.withValues(alpha: 0.3) : Tw.w(0.1)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (v.bannerUrl != null && v.bannerUrl!.isNotEmpty) GestureDetector(onTap: open, child: NetImage(v.bannerUrl, height: 128)),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: open,
                  behavior: HitTestBehavior.opaque,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(16)),
                      child: Icon(v.meta?.icon ?? Icons.place, color: Tw.fuchsia400),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(v.name, style: tw(14, weight: black)),
                          if (_cruising.contains(v.type)) _tag('18+', Tw.red500.withValues(alpha: 0.2), Tw.red400),
                          v.data['ownerId'] == 'community'
                              ? _tag(context.t('venuesPage.addedByCommunity'), Tw.slate700.withValues(alpha: 0.5), Tw.slate300)
                              : _tag(context.t('venuesPage.verifiedVenue'), Tw.green500.withValues(alpha: 0.2), Tw.green400),
                          if (isOpen && live > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Tw.fuchsia500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                              child: Text('$live ${context.t('venuesPage.people', count: live)}', style: tw(10, weight: black, color: Tw.fuchsia400)),
                            ),
                          if (v.openingDays.isNotEmpty)
                            isOpen
                                ? _tag(context.t('venuesPage.open_now', fallback: 'Abierto'), Tw.green500.withValues(alpha: 0.2), Tw.green400)
                                : _tag(_nextOpening(context, v), Tw.slate700.withValues(alpha: 0.5), Tw.slate400),
                        ]),
                        if (v.address.isNotEmpty || distLabel != null)
                          Text(
                            [if (v.address.isNotEmpty) v.address, ?distLabel].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tw(10, color: Tw.slate500),
                          ),
                        if (sched != null) Text('${context.t('venuesPage.today_hours', fallback: 'Hoy')}: $sched', style: tw(10, color: Tw.slate500)),
                        if (promo is Map && promo['active'] == true)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [Tw.amber500.withValues(alpha: 0.2), Tw.purple500.withValues(alpha: 0.2)]),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Tw.amber500.withValues(alpha: 0.4)),
                            ),
                            child: Row(children: [
                              const Text('🔥'),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(safeStr(promo['text']),
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(12, weight: medium, color: const Color(0xFFFCD34D))),
                              ),
                            ]),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              if (isHere)
                Row(children: [
                  Label(context.t('venuesPage.here'), color: Tw.green400),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Tw.green400)),
                ])
              else if (isClosed)
                Pressable(
                  onTap: () => showToast(context, context.read<I18n>().t('venuesPage.venue_closed_msg', fallback: 'Este local se encuentra actualmente cerrado.')),
                  child: Opacity(
                    opacity: 0.6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
                      child: Label(context.t('venuesPage.closed_now', fallback: 'Cerrado'), color: Tw.slate500),
                    ),
                  ),
                )
              else
                Opacity(
                  opacity: checkingIn ? 0.5 : 1,
                  child: Pressable(
                    onTap: checkingIn ? () {} : onCheckin,
                    scale: 0.95,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.circular(16)),
                      child: Label(checkingIn ? '...' : context.t('venuesPage.go'), color: Tw.white),
                    ),
                  ),
                ),
            ]),
            if (pricing.isNotEmpty || tiers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(color: Tw.w(0.05), height: 1),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in pricing.entries)
                      _price('${(e.value is Map ? e.value['name'] : null) ?? e.key}: '
                          '${formatPrice((asDouble(e.value is Map ? e.value['amount'] : 0) ?? 0) / 100, currency)}'),
                    for (final t in tiers) _price('${t['name']}: ${formatPrice(asDouble(t['price']) ?? 0, currency)}'),
                  ]),
                ),
                GestureDetector(onTap: open, child: Label(context.t('venuesPage.tickets'), color: const Color(0xFFEAB308))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  String _nextOpening(BuildContext context, Venue v) {
    final next = getNextOpening(v.openingDays, v.openingHours);
    if (next == null) return context.t('venuesPage.closed_now', fallback: 'Cerrado');
    if (next.isToday) return context.t('venuesPage.opens_today_at', params: {'time': next.open}, fallback: 'Abre a las ${next.open}');
    final day = context.t('venue_config.day_${next.dayKey}');
    return context.t('venuesPage.opens_on', params: {'day': day, 'time': next.open}, fallback: 'Abre $day ${next.open}');
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Label(text, size: 8, color: fg, tracking: 0.05),
      );

  Widget _price(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: tw(9, color: Tw.slate400)),
      );
}

class _VenuesSkeleton extends StatelessWidget {
  const _VenuesSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w, double r = 12}) =>
        Container(height: h, width: w, decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(r)));
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), children: [
          box(28, w: 192),
          const SizedBox(height: 12),
          box(16, w: 128, r: 8),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: box(48, r: 16)),
            const SizedBox(width: 8),
            Expanded(child: box(48, r: 16)),
            const SizedBox(width: 8),
            Expanded(child: box(48, r: 16)),
          ]),
          const SizedBox(height: 24),
          box(40),
          const SizedBox(height: 24),
          for (var i = 0; i < 4; i++) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
              child: Row(children: [
                Container(width: 64, height: 64, decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(16))),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FractionallySizedBox(widthFactor: 0.66, child: Container(height: 16, color: Tw.slate800)),
                    const SizedBox(height: 8),
                    FractionallySizedBox(widthFactor: 0.5, child: Container(height: 12, color: Tw.slate800)),
                    const SizedBox(height: 8),
                    FractionallySizedBox(widthFactor: 0.33, child: Container(height: 12, color: Tw.slate800)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ],
        ]),
      ),
    );
  }
}
