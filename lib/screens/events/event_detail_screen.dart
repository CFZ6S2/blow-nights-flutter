import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/city_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/poster.dart';
import '../venues/venues_screen.dart' show formatPrice;

/// Port of app/events/[eventId]/EventDetailClient.tsx
class EventDetailScreen extends StatefulWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  Map<String, dynamic>? _event;
  Map<String, dynamic>? _venue;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = FirebaseFirestore.instance;
    try {
      final e = await db.collection('events').doc(widget.eventId).get();
      if (e.exists) {
        _event = {'id': e.id, ...?e.data()};
        final vid = _event!['venueId'] as String?;
        if (vid != null && vid.isNotEmpty) {
          final v = await db.collection('venues').doc(vid).get();
          if (v.exists) _venue = v.data();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2))));
    final e = _event;
    if (e == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.event_busy, size: 48, color: Tw.line),
              const SizedBox(height: 16),
              Text(context.t('events.not_found', fallback: 'Evento no encontrado'), style: tw(20, weight: black)),
              const SizedBox(height: 16),
              Pressable(
                onTap: () => openRoute(context, AppRoute.events, replace: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(color: Tw.party, borderRadius: BorderRadius.circular(16)),
                  child: Label(context.t('events.back_to_events', fallback: 'Ver eventos'), size: 12, color: Tw.white),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    final currency = context.watch<CityProvider>().currency;
    final hero = (e['banner_url'] ?? e['coverImage'] ?? _venue?['coverImage']) as String?;
    final tiers = e['ticket_tiers'] is List ? (e['ticket_tiers'] as List).whereType<Map>().toList() : <Map>[];
    final prices = tiers.map((t) => asDouble(t['price']) ?? 0).toList();
    final minPrice = prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b);
    final start = parseDate(e['start_date']);
    final place = safeStr(_venue?['name'] ?? e['venueName'] ?? e['location']);
    final ext = e['externalTicketUrl'] as String?;
    final tags = asStringList(e['tags']);
    final top = MediaQuery.of(context).padding.top;

    Widget backBtn(Color bg) => Positioned(
          top: top + 24,
          left: 24,
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
              child: const Icon(Icons.arrow_back, color: Tw.white),
            ),
          ),
        );

    return Scaffold(
      body: Stack(children: [
        ListView(padding: const EdgeInsets.only(bottom: 160), children: [
          Poster(
            type: 'event',
            imageUrl: hero,
            height: 288 + top,
            child: Stack(children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.6, 1],
                      colors: [Colors.transparent, Tw.night],
                    ),
                  ),
                ),
              ),
              backBtn(Tw.nightDeep.withValues(alpha: 0.5)),
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(safeStr(e['title']), style: tw(32, weight: FontWeight.w800, tracking: -0.025, height: 1.05)),
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.calendar_today, size: 16, color: Tw.sun),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      start == null ? '' : '${DateFormat("EEEE, d 'de' MMMM 'de' y", 'es').format(start)} ${DateFormat('HH:mm').format(start)}',
                      style: tw(14, weight: semibold, color: Tw.sun),
                    ),
                  ),
                ]),
                if (place.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on, size: 16, color: Tw.sun),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: place),
                        if (safeStr(e['address']).isNotEmpty) TextSpan(text: ' ${safeStr(e['address'])}', style: tw(14, color: Tw.inkDim)),
                      ]), style: tw(14, color: Tw.inkSoft)),
                    ),
                  ]),
                ],
                if (safeStr(e['description']).isNotEmpty) ...[
                  const SizedBox(height: 24),
                  GlassCard(
                    color: Tw.panel.withValues(alpha: 0.8),
                    padding: const EdgeInsets.all(20),
                    child: Text(safeStr(e['description']), style: tw(15, color: Tw.inkSoft, height: 1.6)),
                  ),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final t in tags)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Tw.panel, borderRadius: BorderRadius.circular(99), border: Border.all(color: Tw.line)),
                        child: Text(t, style: tw(12, weight: semibold, color: Tw.inkSoft)),
                      ),
                  ]),
                ],
                if (tiers.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(context.t('events.tickets', fallback: 'Entradas'), style: tw(24, weight: FontWeight.w800, tracking: -0.025)),
                  const SizedBox(height: 12),
                  for (final tier in tiers) _tierRow(context, tier, currency),
                ],
                if (ext != null && ext.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Pressable(
                    onTap: () => openInApp(ext),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(gradient: AppTheme.ctaGradient, borderRadius: BorderRadius.circular(16)),
                      child: Text(context.t('events.buy_tickets', fallback: 'Comprar entradas'),
                          textAlign: TextAlign.center, style: tw(16, weight: bold)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ]),
        if ((ext == null || ext.isEmpty) && minPrice != null && safeStr(e['venueId']).isNotEmpty)
          Positioned(
            left: 24,
            right: 24,
            bottom: 24 + MediaQuery.of(context).padding.bottom,
            child: Pressable(
              onTap: () => openRoute(context, AppRoute.buy, args: {'venue': safeStr(e['venueId']), 'event': e['id'] as String}),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: const BoxDecoration(
                  gradient: AppTheme.ctaGradient,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  boxShadow: [BoxShadow(color: Color(0xB3E8318A), blurRadius: 30, spreadRadius: -12, offset: Offset(0, 12))],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.confirmation_number, color: Tw.white),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      minPrice == 0
                          ? context.t('events.reserve', fallback: 'Reservar plaza')
                          : '${context.t('events.buy_from', fallback: 'Comprar desde')} ${formatPrice(minPrice, currency)}',
                      style: tw(16, weight: bold),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _tierRow(BuildContext context, Map tier, String currency) {
    final available = tier['available'] is num ? (tier['available'] as num).toInt() : null;
    final sold = tier['sold'] is num ? (tier['sold'] as num).toInt() : null;
    final soldOut = available != null && sold != null && sold >= available;
    final price = asDouble(tier['price']) ?? 0;
    return Opacity(
      opacity: soldOut ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tw.panel.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: soldOut ? Tw.lineSoft : Tw.line),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(safeStr(tier['name']), style: tw(16, weight: bold, party: true)),
              if (available != null) Text('${sold ?? 0}/$available ${context.t('events.sold', fallback: 'vendidas')}', style: tw(12, color: Tw.inkDim)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            price == 0
                ? Text(context.t('events.free_label', fallback: 'Gratis'), style: tw(16, weight: black, color: Tw.live))
                : Text(formatPrice(price, (tier['currency'] as String?) ?? currency), style: tw(16, weight: black, color: Tw.sun)),
            if (soldOut) Text(context.t('events.sold_out', fallback: 'Agotadas'), style: tw(10, weight: bold, color: Tw.red400)),
          ]),
        ]),
      ),
    );
  }
}
