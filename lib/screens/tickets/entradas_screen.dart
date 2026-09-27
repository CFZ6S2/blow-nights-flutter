import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../models/event.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../venues/venues_screen.dart' show formatPrice;

const _cityLabels = <String, (String, String, String)>{
  'madrid': ('Madrid', '🇪🇸', 'eur'),
  'barcelona': ('Barcelona', '🇪🇸', 'eur'),
  'london': ('London', '🇬🇧', 'gbp'),
  'lisboa': ('Lisboa', '🇵🇹', 'eur'),
  'paris': ('Paris', '🇫🇷', 'eur'),
  'berlin': ('Berlin', '🇩🇪', 'eur'),
};

class _EventWithVenue {
  final String id, venueId, venueName, cityId;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> tiers;
  const _EventWithVenue(this.id, this.venueId, this.venueName, this.cityId, this.data, this.tiers);
  String get title => safeStr(data['title']);
  String? get image => (data['flyerUrl'] ?? data['coverImage'] ?? data['banner_url']) as String?;
}

/// Port of app/entradas/page.tsx
class EntradasScreen extends StatefulWidget {
  final String refCode;
  const EntradasScreen({super.key, this.refCode = ''});

  @override
  State<EntradasScreen> createState() => _EntradasScreenState();
}

class _EntradasScreenState extends State<EntradasScreen> {
  final _db = FirebaseFirestore.instance;
  List<_EventWithVenue> _events = [];
  bool _loading = true;
  String? _activeCity;
  final _search = TextEditingController();
  String _mode = 'official';
  List<Map<String, dynamic>> _resale = [];
  bool _loadingResale = false;
  String? _copiedNick;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _fetchEvents();
    _fetchResale();
  }

  @override
  void dispose() {
    _search.dispose();
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchEvents() async {
    try {
      final venues = await _db.collection('venues').where('isActive', isEqualTo: true).get();
      final all = <_EventWithVenue>[];
      await Future.wait(venues.docs.map((vDoc) async {
        final v = vDoc.data();
        final ext = v['externalTicketUrl'];
        final hasTicketing = v['subscriptionTier'] == 'ticketing' || (ext is String && ext.isNotEmpty);
        if (!hasTicketing && v['ticketPricing'] == null) return;
        final evs = await vDoc.reference.collection('events').limit(20).get();
        for (final eDoc in evs.docs) {
          final e = eDoc.data();
          if (!Event(eDoc.id, e).isVisible) continue;
          final tiers = e['ticket_tiers'] is List
              ? (e['ticket_tiers'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
              : <Map<String, dynamic>>[];
          final available = tiers.any((t) => t['quota'] == null || asInt(t['sold']) < asInt(t['quota']));
          if (tiers.isNotEmpty && available) {
            all.add(_EventWithVenue(eDoc.id, vDoc.id, safeStr(v['name']), safeStr(v['cityId']).isEmpty ? 'other' : safeStr(v['cityId']).toLowerCase(), e, tiers));
          }
        }
      }));
      all.sort((a, b) => Event(a.id, a.data).millis.compareTo(Event(b.id, b.data).millis));
      _events = all;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchResale() async {
    setState(() => _loadingResale = true);
    try {
      final snap = await _db.collection('ticket_listings').where('status', isEqualTo: 'active').get();
      final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()
        ..sort((a, b) => (parseDate(b['createdAt'])?.millisecondsSinceEpoch ?? 0).compareTo(parseDate(a['createdAt'])?.millisecondsSinceEpoch ?? 0));
      _resale = list;
    } catch (_) {}
    if (mounted) setState(() => _loadingResale = false);
  }

  double? _lowest(List<Map<String, dynamic>> tiers) {
    final avail = tiers.where((t) => t['quota'] == null || asInt(t['sold']) < asInt(t['quota'])).map((t) => asDouble(t['price']) ?? 0).toList();
    if (avail.isEmpty) return null;
    return avail.reduce((a, b) => a < b ? a : b);
  }

  String? _dateStr(Map<String, dynamic> e) {
    final raw = parseDate(e['start_date']) ?? (e['date'] is String ? DateTime.tryParse(e['date'] as String) : null);
    return raw == null ? null : DateFormat('EEE, d MMM', 'es').format(raw);
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.toLowerCase();
    final order = _cityLabels.keys.toList();
    final cities = {for (final e in _events) e.cityId}.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    final filtered = _events.where((e) {
      if (_activeCity != null && e.cityId != _activeCity) return false;
      if (q.isNotEmpty) return e.title.toLowerCase().contains(q) || e.venueName.toLowerCase().contains(q);
      return true;
    }).toList();
    final filteredResale = _resale.where((r) {
      if (_activeCity != null && r['cityId'] != _activeCity) return false;
      if (q.isNotEmpty) {
        return [r['eventTitle'], r['venueName'], r['sellerNick'], r['notes']].any((f) => safeStr(f).toLowerCase().contains(q));
      }
      return true;
    }).toList();
    final grouped = <String, List<_EventWithVenue>>{};
    for (final e in filtered) {
      grouped.putIfAbsent(e.cityId, () => []).add(e);
    }
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        // Header
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
          child: Stack(children: [
            Positioned(top: -size.width * 0.2, left: -size.width * 0.1, child: Orb(color: Tw.fuchsia600.withValues(alpha: 0.15), size: size.width * 0.8)),
            Positioned(bottom: -size.width * 0.2, right: -size.width * 0.1, child: Orb(color: Tw.indigo600.withValues(alpha: 0.15), size: size.width * 0.7)),
            Padding(
              padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 40, 24, 40),
              child: Column(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_back, size: 14, color: Tw.slate500),
                    const SizedBox(width: 8),
                    Label('Blow Nights', size: 12, weight: bold, color: Tw.slate500),
                  ]),
                ),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.confirmation_number, size: 30, color: Tw.fuchsia400),
                  const SizedBox(width: 12),
                  Text(context.t('entradas.title', fallback: 'Entradas'), style: tw(30, weight: black, tracking: -0.03)),
                ]),
                const SizedBox(height: 20),
                Text(
                  context.t('entradas.subtitle_global',
                      fallback: 'Compra tu entrada oficial sin registro o accede a entradas de la comunidad sin comisiones intermediarias.'),
                  textAlign: TextAlign.center,
                  style: tw(14, color: Tw.slate400),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Tw.emerald500.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Tw.emerald500.withValues(alpha: 0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.lock_open, size: 14, color: Tw.emerald400),
                    const SizedBox(width: 8),
                    Label(context.t('entradas.no_account_needed', fallback: 'Sin registro necesario'), size: 12, weight: bold, color: Tw.emerald400, tracking: 0.05),
                  ]),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _search,
                  style: tw(14),
                  decoration: InputDecoration(
                    hintText: context.t('entradas.search_placeholder', fallback: 'Buscar evento, fiesta o vendedor...'),
                    prefixIcon: const Icon(Icons.search, color: Tw.slate500),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _modeBtn('official', Icons.confirmation_number, 'Oficiales', null),
                    const SizedBox(width: 6),
                    _modeBtn('p2p', Icons.storefront, 'Comunidad P2P', '0% comisión'),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
        if (cities.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _cityPill(context.t('entradas.all_cities', fallback: 'Todas'), _activeCity == null, () => setState(() => _activeCity = null)),
                for (final c in cities)
                  _cityPill('${_cityLabels[c]?.$2 ?? ''} ${_cityLabels[c]?.$1 ?? c}', _activeCity == c,
                      () => setState(() => _activeCity = _activeCity == c ? null : c)),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_mode == 'p2p')
              ..._p2p(context, filteredResale)
            else if (_loading)
              for (var i = 0; i < 3; i++)
                Container(
                  height: 208,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(24)),
                )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 80),
                child: Column(children: [
                  const Icon(Icons.confirmation_number, size: 60, color: Tw.slate700),
                  const SizedBox(height: 16),
                  Text(context.t('entradas.no_results', fallback: 'No hay eventos con entradas disponibles'),
                      textAlign: TextAlign.center, style: tw(14, weight: bold, color: Tw.slate500)),
                  const SizedBox(height: 8),
                  Text(context.t('entradas.try_another_search', fallback: 'Prueba con otra ciudad o busca otro evento'),
                      textAlign: TextAlign.center, style: tw(12, color: Tw.slate600)),
                ]),
              )
            else
              for (final entry in grouped.entries) ..._citySection(context, entry.key, entry.value),
            const SizedBox(height: 32),
            Divider(color: Tw.w(0.05)),
            const SizedBox(height: 32),
            Text(context.t('entradas.want_to_sell', fallback: '¿Tienes un local y quieres vender entradas?'),
                textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
            const SizedBox(height: 16),
            Center(
              child: Pressable(
                onTap: () => openRoute(context, AppRoute.businessLanding),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.circular(12)),
                  child: Label(context.t('entradas.register_venue', fallback: 'Registra tu venue'), size: 12, weight: FontWeight.w800, color: Tw.white, tracking: 0.12),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _modeBtn(String id, IconData icon, String label, String? badge) {
    final on = _mode == id;
    return Pressable(
      onTap: () => setState(() => _mode = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: on && id == 'official' ? Tw.fuchsia600 : null,
          gradient: on && id == 'p2p' ? const LinearGradient(colors: [Color(0xFF059669), Color(0xFF0D9488)]) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: on ? Tw.white : Tw.slate400),
          const SizedBox(width: 8),
          Label(label, size: 12, color: on ? Tw.white : Tw.slate400, tracking: 0.05),
          if (badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Tw.w(0.2), borderRadius: BorderRadius.circular(99)),
              child: Text(badge, style: tw(9, weight: black)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _cityPill(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: on ? Tw.fuchsia600 : Tw.w(0.05),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: on ? Tw.fuchsia600 : Tw.w(0.1)),
            ),
            child: Label(label, size: 12, weight: bold, color: on ? Tw.white : Tw.slate400, tracking: 0.05),
          ),
        ),
      );

  List<Widget> _citySection(BuildContext context, String cityId, List<_EventWithVenue> events) {
    final info = _cityLabels[cityId];
    final currency = info?.$3 ?? 'eur';
    return [
      Row(children: [
        Text(info?.$2 ?? '', style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Text(info?.$1 ?? cityId, style: tw(18, weight: black, tracking: -0.025)),
        const SizedBox(width: 12),
        Text('${events.length} ${events.length == 1 ? 'evento' : 'eventos'}', style: tw(12, weight: bold, color: Tw.slate500)),
      ]),
      const SizedBox(height: 16),
      for (final ev in events) _eventCard(context, ev, currency),
      const SizedBox(height: 24),
    ];
  }

  Widget _eventCard(BuildContext context, _EventWithVenue ev, String currency) {
    final lowest = _lowest(ev.tiers);
    final img = ev.image;
    final date = _dateStr(ev.data);
    final available = ev.tiers.fold<int>(0, (s, t) => s + (asInt(t['quota']) - asInt(t['sold'])).clamp(0, 1 << 30));
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (img != null && img.isNotEmpty)
          SizedBox(
            height: 144,
            child: Stack(fit: StackFit.expand, children: [
              NetImage(img),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xCC020617), Colors.transparent]),
                ),
              ),
              if (date != null)
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
                    child: Label(date, weight: bold, color: Tw.white, tracking: 0),
                  ),
                ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ev.title, style: tw(16, weight: black, tracking: -0.025, height: 1.2)),
            const SizedBox(height: 2),
            Text(ev.venueName, style: tw(11, weight: bold, color: Tw.fuchsia400)),
            if ((img == null || img.isEmpty) && date != null) Text(date, style: tw(11, color: Tw.slate500)),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.local_activity, size: 12, color: Tw.indigo400),
              const SizedBox(width: 4),
              Label('${ev.tiers.length} ${ev.tiers.length == 1 ? 'tipo' : 'tipos'}', weight: bold, color: Tw.slate500, tracking: 0.05),
              if (available > 0 && available < 20) ...[
                const SizedBox(width: 12),
                Label('$available restantes', weight: bold, color: Tw.amber400, tracking: 0.05),
              ],
              const Spacer(),
              if (lowest != null) Text(lowest == 0 ? 'GRATIS' : formatPrice(lowest, currency), style: tw(14, weight: black)),
            ]),
            const SizedBox(height: 12),
            Pressable(
              onTap: () => openRoute(context, AppRoute.buy, args: {
                'venue': ev.venueId,
                'event': ev.id,
                if (widget.refCode.isNotEmpty) 'ref': widget.refCode,
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(gradient: AppTheme.ctaGradient, borderRadius: BorderRadius.circular(12)),
                child: Label(
                  lowest == 0 ? context.t('entradas.claim_free', fallback: 'Reservar gratis') : context.t('entradas.buy_ticket', fallback: 'Comprar entrada'),
                  size: 12,
                  weight: FontWeight.w800,
                  color: Tw.white,
                  tracking: 0.15,
                  align: TextAlign.center,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _p2p(BuildContext context, List<Map<String, dynamic>> items) => [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [const Color(0x66022C22), Tw.slate900.withValues(alpha: 0.6), const Color(0x66022C22)]),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Tw.emerald500.withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Tw.emerald500.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.shield, color: Tw.emerald400),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Label('Mercado Comunitario P2P', size: 14, color: Tw.white, tracking: -0.025),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Tw.emerald500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                      child: Text('0€ Gastos de gestión', style: tw(10, weight: bold, color: const Color(0xFF6EE7B7))),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text('Acuerda el pago directo y el vendedor te transfiere la entrada al instante en la app con un nuevo código QR único.',
                      style: tw(12, color: Tw.slate400)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Pressable(
              onTap: () => openRoute(context, AppRoute.tickets),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFF059669), borderRadius: BorderRadius.circular(12)),
                child: Label('Vender mi entrada', size: 12, color: Tw.white, tracking: 0.05),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 32),
        if (_loadingResale)
          const Padding(padding: EdgeInsets.symmetric(vertical: 80), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.emerald500)))
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 80),
            child: Column(children: [
              const Icon(Icons.storefront, size: 60, color: Tw.slate700),
              const SizedBox(height: 16),
              Text('No hay entradas de la comunidad disponibles en este momento', textAlign: TextAlign.center, style: tw(16, weight: black, color: Tw.slate400)),
              const SizedBox(height: 16),
              Text('¿Tienes una entrada para una fiesta o local y no puedes ir? Ponla en venta gratis desde tu monedero con 1 click.',
                  textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
              const SizedBox(height: 16),
              Pressable(
                onTap: () => openRoute(context, AppRoute.tickets),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(color: const Color(0xFF059669), borderRadius: BorderRadius.circular(16)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.confirmation_number, size: 14, color: Tw.white),
                    const SizedBox(width: 8),
                    Label('Ir a Mis Entradas', size: 12, color: Tw.white, tracking: 0.05),
                  ]),
                ),
              ),
            ]),
          )
        else
          for (final item in items) _resaleCard(context, item),
      ];

  Widget _resaleCard(BuildContext context, Map<String, dynamic> item) {
    final original = asInt(item['originalPrice']), resale = asInt(item['resalePrice']);
    final discount = original > resale;
    final date = parseDate(item['eventDate']);
    final nick = safeStr(item['sellerNick']);
    final whatsapp = safeStr(item['whatsappNumber']);
    final title = safeStr(item['eventTitle']).isNotEmpty ? safeStr(item['eventTitle']) : safeStr(item['venueName']);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Tw.emerald500.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
                ),
                child: Label(safeStr(item['ticketType']).isNotEmpty ? safeStr(item['ticketType']) : 'Entrada', color: Tw.emerald400, tracking: 0.05),
              ),
              const SizedBox(height: 8),
              Text(title, style: tw(18, weight: black, tracking: -0.025)),
              Text('${safeStr(item['venueName'])} ${safeStr(item['cityId']).isNotEmpty ? '• ${safeStr(item['cityId']).toUpperCase()}' : ''}',
                  style: tw(12, weight: bold, color: Tw.slate400)),
              if (date != null) Text(DateFormat('EEE, d MMM', 'es').format(date), style: tw(11, weight: bold, color: Tw.fuchsia400)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${(resale / 100).toStringAsFixed(2)}€', style: tw(24, weight: black, color: Tw.emerald400)),
            if (discount) ...[
              Text('${(original / 100).toStringAsFixed(2)}€', style: tw(10, color: Tw.slate500, decoration: TextDecoration.lineThrough)),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Tw.emerald500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                child: Text('Ahorras ${((original - resale) / 100).toStringAsFixed(2)}€', style: tw(9, weight: black, color: const Color(0xFF6EE7B7))),
              ),
            ],
          ]),
        ]),
        if (safeStr(item['notes']).isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
            child: Text('"${safeStr(item['notes'])}"', style: tw(12, color: Tw.slate300, style: FontStyle.italic)),
          ),
        ],
        const SizedBox(height: 16),
        Divider(color: Tw.w(0.05), height: 1),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 32,
            height: 32,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Tw.fuchsia600, Tw.indigo600]),
            ),
            child: NetImage(
              item['sellerPhoto'] as String?,
              placeholder: Center(child: Text(nick.isNotEmpty ? nick[0].toUpperCase() : 'U', style: tw(12, weight: black))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('@$nick', maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(11, weight: bold, color: Tw.slate300)),
              Text('Vendedor verificado', style: tw(9, color: Tw.slate500)),
            ]),
          ),
          if (whatsapp.isNotEmpty) ...[
            Pressable(
              onTap: () => launchUrl(
                Uri.parse('https://wa.me/${whatsapp.replaceAll(RegExp('[^0-9]'), '')}?text=${Uri.encodeComponent('Hola @$nick, he visto tu entrada para $title en Blow Nights por ${(resale / 100).toStringAsFixed(2)}€ y me interesa.')}'),
                mode: LaunchMode.externalApplication,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF059669), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.phone, size: 14, color: Tw.white),
                  const SizedBox(width: 6),
                  Text('WhatsApp', style: tw(12, weight: bold)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Pressable(
            onTap: () {
              Clipboard.setData(ClipboardData(text: '@$nick'));
              _copiedTimer?.cancel();
              setState(() => _copiedNick = nick);
              _copiedTimer = Timer(const Duration(seconds: 3), () {
                if (mounted) setState(() => _copiedNick = null);
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.chat, size: 14, color: Color(0xFFE2E8F0)),
                const SizedBox(width: 6),
                Text(_copiedNick == nick ? '¡Nick copiado!' : '@$nick', style: tw(12, weight: bold, color: const Color(0xFFE2E8F0))),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}
