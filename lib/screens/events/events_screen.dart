import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/event.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/city_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../venues/venues_screen.dart' show formatPrice;

class _PublicEvent {
  final String id;
  final String source; // venue_event | independent | chill
  final Map<String, dynamic> data;
  final String? venueId;
  final String? venueName;
  final double? priceFrom;
  const _PublicEvent(this.id, this.source, this.data, {this.venueId, this.venueName, this.priceFrom});

  String get title => safeStr(data['title']);
  String? get banner => (data['banner_url'] ?? data['coverImage']) as String?;
  String? get hostNick => data['host_nick'] as String?;
  int? get maxCapacity => data['max_capacity'] is num ? (data['max_capacity'] as num).toInt() : null;
  int get taken => data['accepted_users'] is List ? (data['accepted_users'] as List).length : 0;
  Event get asEvent => Event(id, data);
  DateTime? get date => parseDate(data['start_date'] ?? data['date']);
}

/// Port of app/[city]/events/page.tsx
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _db = FirebaseFirestore.instance;
  List<_PublicEvent> _independent = [], _chills = [], _venueEvents = [];
  bool _loading = true;
  String? _filter;
  final _search = TextEditingController();
  final List<StreamSubscription> _subs = [];
  String? _key;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final city = context.watch<CityProvider>();
    if (auth.loading) return;
    final key = '${city.cityId}|${city.citySlug}|${auth.user?.uid}';
    if (key == _key) return;
    _key = key;
    _load(city.cityId, city.citySlug, auth.user != null);
  }

  void _load(String? cityId, String? citySlug, bool loggedIn) {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    setState(() => _loading = true);

    if (cityId != null) {
      _subs.add(_db
          .collection('events')
          .where('cityId', isEqualTo: cityId)
          .where('isActive', isEqualTo: true)
          .orderBy('created_at', descending: true)
          .limit(50)
          .snapshots()
          .listen((snap) {
        setState(() => _independent = snap.docs.map((d) {
              final data = d.data();
              final tiers = data['ticket_tiers'];
              return _PublicEvent(d.id, 'independent', data,
                  venueId: data['venueId'] as String?,
                  priceFrom: tiers is List && tiers.isNotEmpty && tiers.first is Map ? asDouble(tiers.first['price']) : null);
            }).toList());
      }, onError: (_) {}));

      if (loggedIn && citySlug != null) {
        _subs.add(_db
            .collection('chills')
            .where('city_slug', isEqualTo: citySlug)
            .where('status', isEqualTo: 'active')
            .orderBy('created_at', descending: true)
            .limit(30)
            .snapshots()
            .listen((snap) {
          setState(() => _chills = snap.docs.map((d) {
                final data = {...d.data()};
                data['start_date'] = data['starts_at'] ?? data['created_at'];
                final cents = asDouble(data['priceCents']);
                return _PublicEvent(d.id, 'chill', data, priceFrom: cents != null && cents > 0 ? cents / 100 : 0);
              }).toList());
        }, onError: (_) {}));
      }
    }
    _fetchVenueEvents(cityId);
  }

  Future<void> _fetchVenueEvents(String? cityId) async {
    try {
      Query<Map<String, dynamic>> vq = _db.collection('venues');
      if (cityId != null) vq = vq.where('cityId', isEqualTo: cityId);
      final venues = await vq.where('isActive', isEqualTo: true).get();
      final all = <_PublicEvent>[];
      for (final v in venues.docs) {
        final evs = await v.reference.collection('events').orderBy('start_date', descending: true).limit(10).get();
        for (final e in evs.docs) {
          final data = e.data();
          final tiers = data['ticket_tiers'];
          all.add(_PublicEvent(e.id, 'venue_event', data,
              venueId: v.id,
              venueName: safeStr(v.data()['name']),
              priceFrom: tiers is List && tiers.isNotEmpty && tiers.first is Map ? asDouble(tiers.first['price']) : null));
        }
      }
      if (mounted) setState(() => _venueEvents = all);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _search.dispose();
    super.dispose();
  }

  String _formatDate(BuildContext context, DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inHours / 24;
    final time = DateFormat('HH:mm').format(d);
    if (diff.round() == 0) return '${context.t('events.today', fallback: 'Hoy')} · $time';
    if (diff.round() == 1) return '${context.t('events.tomorrow', fallback: 'Mañana')} · $time';
    if (diff.round() >= 2 && diff.round() <= 6) {
      return '${context.t('events.this', fallback: 'Este')} ${DateFormat('EEEE', 'es').format(d)} · $time';
    }
    return '${DateFormat('EEE, d MMM', 'es').format(d)} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currency = context.watch<CityProvider>().currency;
    if (auth.loading) return const Scaffold(body: SizedBox.shrink());

    final q = _search.text.toLowerCase();
    final now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final all = [..._independent, ..._chills, ..._venueEvents];
    final filtered = all.where((e) {
      if (!e.asEvent.isVisible) return false;
      if (q.isNotEmpty &&
          !e.title.toLowerCase().contains(q) &&
          !(e.venueName ?? '').toLowerCase().contains(q) &&
          !(e.hostNick ?? '').toLowerCase().contains(q)) {
        return false;
      }
      final d = e.date;
      if (_filter == 'today' && (d == null || !sameDay(d, now))) return false;
      if (_filter == 'upcoming' && (d == null || d.isBefore(now))) return false;
      if (_filter == 'free' && (e.priceFrom ?? 0) > 0) return false;
      if (_filter == 'paid' && (e.priceFrom == null || e.priceFrom == 0)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final da = a.date, db = b.date;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.6), border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
            child: Text(context.t('events.title', fallback: 'Eventos y Planes'), textAlign: TextAlign.center, style: tw(20, weight: black)),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 128), children: [
              TextField(
                controller: _search,
                style: tw(14),
                decoration: InputDecoration(
                  hintText: context.t('events.searchPlaceholder', fallback: 'Buscar evento...'),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Tw.slate500),
                  fillColor: Tw.slate900,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.slate700)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.fuchsia500)),
                ),
              ),
              const SizedBox(height: 24),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final f in [
                    ('today', context.t('events.filter_today', fallback: 'Hoy')),
                    ('upcoming', context.t('events.filter_upcoming', fallback: 'Próximos')),
                    ('paid', context.t('events.price_paid', fallback: 'De pago')),
                    ('free', context.t('events.price_free', fallback: 'Gratis')),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Pressable(
                        onTap: () => setState(() => _filter = _filter == f.$1 ? null : f.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _filter == f.$1 ? Tw.fuchsia600 : Tw.w(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _filter == f.$1 ? Tw.fuchsia500 : Tw.w(0.1)),
                          ),
                          child: Label(f.$2, size: 12, weight: bold, color: _filter == f.$1 ? Tw.white : Tw.slate400, tracking: 0.05),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 24),
              if (_loading)
                for (var i = 0; i < 4; i++) _skeletonRow()
              else if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 64),
                  child: Column(children: [
                    Icon(q.isNotEmpty ? Icons.search_off : Icons.event_busy, size: 48, color: Tw.slate700),
                    const SizedBox(height: 12),
                    Text(
                      q.isNotEmpty
                          ? context.t('events.noSearchResults', fallback: 'No se encontraron eventos')
                          : context.t('events.no_events', fallback: 'No hay eventos para estos filtros'),
                      textAlign: TextAlign.center,
                      style: tw(16, color: Tw.slate500),
                    ),
                    if (q.isNotEmpty || _filter != null) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => setState(() {
                          _search.clear();
                          _filter = null;
                        }),
                        child: Text(context.t('events.clearFilters', fallback: 'Ver todos'),
                            style: tw(12, weight: bold, color: Tw.fuchsia400, decoration: TextDecoration.underline)),
                      ),
                    ],
                  ]),
                )
              else
                for (var i = 0; i < filtered.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _card(context, filtered[i], currency),
                  ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, _PublicEvent e, String currency) {
    final (label, color) = switch (e.source) {
      'chill' => ('Plan', Tw.amber400),
      'independent' => (context.t('events.source_event', fallback: 'Evento'), Tw.fuchsia400),
      _ => ('Local', Tw.emerald400),
    };
    void open() {
      if (e.source == 'chill') {
        openRoute(context, AppRoute.chillDetail, args: {'id': e.id});
      } else if (e.source == 'venue_event' && e.venueId != null) {
        openRoute(context, AppRoute.buy, args: {'venue': e.venueId!, 'event': e.id});
      } else {
        openRoute(context, AppRoute.eventDetail, args: {'eventId': e.id});
      }
    }

    Widget? capacity;
    final max = e.maxCapacity;
    if (max != null && max > 0) {
      final remaining = max - e.taken;
      if (remaining <= 0) {
        capacity = _pill(context.t('events.sold_out', fallback: 'Agotado'), Tw.red400);
      } else if (e.taken / max >= 0.8) {
        capacity = _pill(context.t('events.spots_left', count: remaining, fallback: 'Quedan $remaining plazas'), Tw.amber400);
      } else {
        capacity = Text('${e.taken}/$max', style: tw(10, color: Tw.slate500));
      }
    }

    return GlassCard(
      onTap: open,
      radius: 16,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: NetImage(
            e.banner,
            width: 96,
            height: 96,
            placeholder: Container(
              width: 96,
              height: 96,
              color: Tw.slate800,
              child: Icon(e.source == 'chill' ? Icons.local_fire_department : Icons.event, size: 30, color: Tw.slate600),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(14, weight: black))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Label(label, size: 9, weight: bold, color: color, tracking: 0),
              ),
            ]),
            const SizedBox(height: 6),
            Text(_formatDate(context, e.date), style: tw(12, color: Tw.slate400)),
            if (e.venueName != null && e.venueName!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(e.venueName!, style: tw(12, color: Tw.slate500)),
            ],
            if (e.hostNick != null && e.hostNick!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('por ${e.hostNick}', style: tw(12, color: Tw.slate500)),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              (e.priceFrom ?? 0) > 0
                  ? Text('${context.t('events.from', fallback: 'Desde')} ${formatPrice(e.priceFrom!, currency)}',
                      style: tw(12, weight: bold, color: Tw.fuchsia400))
                  : Text(context.t('events.free_label', fallback: 'Gratis'), style: tw(12, weight: bold, color: Tw.emerald400)),
              ?capacity,
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _pill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: tw(10, weight: bold, color: c)),
      );

  Widget _skeletonRow() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
        child: Row(children: [
          Container(width: 96, height: 96, decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(12))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FractionallySizedBox(widthFactor: 0.75, child: Container(height: 16, color: Tw.slate800)),
              const SizedBox(height: 8),
              FractionallySizedBox(widthFactor: 0.5, child: Container(height: 12, color: Tw.slate800)),
              const SizedBox(height: 8),
              FractionallySizedBox(widthFactor: 0.33, child: Container(height: 12, color: Tw.slate800)),
            ]),
          ),
        ]),
      );
}
