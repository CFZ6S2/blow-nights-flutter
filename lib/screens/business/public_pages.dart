import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/city_provider.dart';
import '../../providers/platform_settings.dart' show uuidV4;
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import '../../widgets/marketing.dart';
import '../tickets/wallet_screen.dart' show currencySymbol;

/// Port of app/discover/DiscoverClient.tsx
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _venues = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = FirebaseFirestore.instance;
    try {
      final u = await db.collection('users').where('online', isEqualTo: true).limit(10).get();
      final v = await db.collection('venues').where('active', isEqualTo: true).limit(5).get();
      setState(() {
        _users = [for (final d in u.docs) {'id': d.id, ...d.data()}];
        _venues = [for (final d in v.docs) {'id': d.id, ...d.data()}];
      });
    } catch (e) {
      debugPrint('Error fetching discover data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: Tw.slate950, body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)));
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 96), children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GradientText('DISCOVER', align: TextAlign.start, style: tw(30, weight: black, style: FontStyle.italic, tracking: -0.05), colors: const [Tw.fuchsia400, Tw.amber400]),
              const SizedBox(height: 4),
              Text(context.t('discover.subtitle', fallback: 'El pulso de la noche en directo'), style: tw(14, weight: medium, color: Tw.slate400)),
            ]),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              const PulseDot(color: Tw.green500),
              const SizedBox(width: 8),
              Text(context.t('discover.online_now', fallback: 'Saliendo ahora'), style: tw(18, weight: black)),
            ]),
          ),
          const SizedBox(height: 16),
          if (_users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(children: [
                const Icon(Icons.person_off, size: 30, color: Tw.slate700),
                const SizedBox(height: 8),
                Text(context.t('discover.no_users', fallback: 'Nadie conectado ahora'), style: tw(12, weight: bold, color: Tw.slate500)),
                Text(context.t('discover.check_later', fallback: 'Vuelve más tarde'), style: tw(10, color: Tw.slate600)),
              ]),
            )
          else
            SizedBox(
              height: 72,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                for (final u in _users)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: GestureDetector(
                      onTap: () => openRoute(context, AppRoute.profileView, args: {'id': u['id'] as String}),
                      child: Container(
                        width: 64,
                        height: 64,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1), width: 2)),
                        child: Stack(fit: StackFit.expand, children: [
                          NetImage(u['fotoUrl'] as String?),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent]),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4, left: 2, right: 2),
                              child: Text(((u['nick'] as String?) ?? '').toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(9, weight: black)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              const Icon(Icons.local_fire_department, color: Tw.amber400),
              const SizedBox(width: 8),
              Text(context.t('discover.hot_venues', fallback: 'Locales On Fire'), style: tw(18, weight: black, color: Tw.amber400)),
            ]),
          ),
          const SizedBox(height: 16),
          if (_venues.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(children: [
                const Icon(Icons.explore_off, size: 40, color: Tw.slate700),
                const SizedBox(height: 8),
                Text(context.t('discover.no_venues', fallback: 'Sin locales activos'), style: tw(12, weight: bold, color: Tw.slate500)),
              ]),
            )
          else
            for (final v in _venues)
              Pressable(
                onTap: () => openRoute(context, AppRoute.events),
                child: Container(
                  height: 128,
                  margin: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
                  child: Stack(fit: StackFit.expand, children: [
                    NetImage((v['coverUrl'] ?? v['logoUrl']) as String?),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black.withValues(alpha: 0.9), Colors.black.withValues(alpha: 0.4), Colors.transparent],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text((v['name'] as String?) ?? '', style: tw(20, weight: black)),
                        Row(children: [
                          const Icon(Icons.location_on, size: 12, color: Tw.amber400),
                          const SizedBox(width: 4),
                          Text((v['city'] as String?) ?? 'Tu zona', style: tw(12, weight: bold, color: Tw.amber400)),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ),
        ]),
      ),
    );
  }
}

/// Port of app/local/[venueSlug]/entradas/page.tsx (public ticket wall of a venue, guest checkout).
class LocalEntradasScreen extends StatefulWidget {
  final String slug;
  final String? giftUserId;
  final String refCode;
  const LocalEntradasScreen({super.key, required this.slug, this.giftUserId, this.refCode = ''});

  @override
  State<LocalEntradasScreen> createState() => _LocalEntradasScreenState();
}

class _LocalEntradasScreenState extends State<LocalEntradasScreen> {
  Map<String, dynamic>? _venue;
  bool _loading = true;
  bool _copied = false;
  String? _buying;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  List<Map<String, dynamic>> _defaultTiers(I18n i18n) => [
        {
          'id': 'early',
          'nombre': i18n.t('venue_tickets.tier_early'),
          'precio': 12,
          'descripcion': i18n.t('venue_tickets.tier_early_desc'),
          'incluye': [i18n.t('venue_tickets.perk_priority'), i18n.t('venue_tickets.perk_1drink')],
          'destacado': false,
        },
        {
          'id': 'general',
          'nombre': i18n.t('venue_tickets.tier_general'),
          'precio': 15,
          'descripcion': i18n.t('venue_tickets.tier_general_desc'),
          'incluye': [i18n.t('venue_tickets.perk_main_access'), i18n.t('venue_tickets.perk_premium_drink')],
          'destacado': true,
        },
        {
          'id': 'vip',
          'nombre': i18n.t('venue_tickets.tier_vip'),
          'precio': 30,
          'descripcion': i18n.t('venue_tickets.tier_vip_desc'),
          'incluye': [i18n.t('venue_tickets.perk_fast_pass'), i18n.t('venue_tickets.perk_2premium'), i18n.t('venue_tickets.perk_coat_check')],
          'destacado': false,
        },
      ];

  Future<void> _load() async {
    final i18n = context.read<I18n>();
    try {
      final s = await FirebaseFirestore.instance.collection('venues').where('slug', isEqualTo: widget.slug).get();
      setState(() => _venue = s.docs.isNotEmpty
          ? {'id': s.docs.first.id, ...s.docs.first.data()}
          : {
              'id': widget.slug,
              'nombre': widget.slug.replaceAll('-', ' ').toUpperCase(),
              'ciudad': 'Madrid',
              'direccion': 'Zona Centro / Chueca',
              'fotoUrl': 'https://images.unsplash.com/photo-1566737236500-c8ac43014a67?w=1200&auto=format&fit=crop',
              'description': i18n.t('venue_tickets.fallback_desc'),
              'tickets': _defaultTiers(i18n),
            });
    } catch (e) {
      debugPrint('Error loading venue: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkout(Map<String, dynamic> ticket) async {
    final i18n = context.read<I18n>();
    setState(() => _buying = ticket['id'] as String);
    try {
      final res = await callFn('purchasePublicVenueTicket', {
        'venueId': _venue!['id'],
        'ticketType': ticket['id'],
        'origin': webBase,
        'giftUserId': widget.giftUserId,
        if (widget.refCode.isNotEmpty) 'refCode': widget.refCode,
        'idempotencyKey': uuidV4(),
      });
      if (res['url'] is String) await openInApp(res['url'] as String);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e, i18n.t('venue_tickets.checkout_error')), error: true);
    } finally {
      if (mounted) setState(() => _buying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _venue == null) {
      return const Scaffold(backgroundColor: Tw.slate950, body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)));
    }
    final v = _venue!;
    final sym = currencySymbol(context.watch<CityProvider>().currency);
    final tiers = (v['tickets'] is List ? (v['tickets'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : null) ??
        _defaultTiers(context.read<I18n>());
    final top = MediaQuery.of(context).padding.top;
    Widget pill(IconData icon, String label, VoidCallback onTap, {Color iconColor = Tw.white}) => Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: Tw.slate950.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Label(label, size: 11, color: Tw.white, tracking: 0.05),
            ]),
          ),
        );

    return Scaffold(
      backgroundColor: Tw.slate950,
      body: ListView(padding: EdgeInsets.only(bottom: 96 + MediaQuery.of(context).padding.bottom), children: [
        SizedBox(
          height: max(320, MediaQuery.of(context).size.height * 0.45),
          child: Stack(fit: StackFit.expand, children: [
            NetImage((v['fotoUrl'] as String?) ?? 'https://images.unsplash.com/photo-1566737236500-c8ac43014a67?w=1200&auto=format&fit=crop'),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Tw.slate950, Tw.slate950.withValues(alpha: 0.6), Colors.transparent]),
              ),
            ),
            Positioned(
              top: top + 16,
              left: 16,
              right: 16,
              child: Row(children: [
                pill(Icons.arrow_back, context.t('venue_tickets.back_all'), () => openRoute(context, AppRoute.entradas, replace: true)),
                const Spacer(),
                pill(_copied ? Icons.check : Icons.share, _copied ? context.t('venue_tickets.copied') : context.t('venue_tickets.share'), () async {
                  await Clipboard.setData(ClipboardData(text: '$webBase/local/${widget.slug}/entradas'));
                  setState(() => _copied = true);
                  Future.delayed(const Duration(milliseconds: 2500), () {
                    if (mounted) setState(() => _copied = false);
                  });
                }, iconColor: _copied ? Tw.emerald400 : Tw.white),
              ]),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 32,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Tw.fuchsia500.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified_user, size: 14, color: Tw.fuchsia300),
                    const SizedBox(width: 8),
                    Label(context.t('venue_tickets.official_wall'), color: Tw.fuchsia300),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(((v['nombre'] ?? v['name']) as String? ?? '').toUpperCase(), style: tw(36, weight: black, height: 1)),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.location_on, size: 16, color: Tw.fuchsia400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${v['direccion'] ?? v['address'] ?? ''} • ${v['ciudad'] ?? v['cityId'] ?? ''}', style: tw(14, weight: medium, color: Tw.slate300)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AdminCard(
              color: Tw.slate900.withValues(alpha: 0.6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('venue_tickets.no_registration'), style: tw(18, weight: black)),
                const SizedBox(height: 2),
                Text(context.t('venue_tickets.qr_delivery'), style: tw(12, color: Tw.slate400)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Tw.emerald500.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Tw.emerald500.withValues(alpha: 0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified_user, size: 16, color: Tw.emerald400),
                    const SizedBox(width: 8),
                    Text(context.t('venue_tickets.secure_stripe'), style: tw(12, weight: bold, color: Tw.emerald400)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 32),
            for (final tk in tiers) _tierCard(context, tk, sym),
          ]),
        ),
      ]),
    );
  }

  Widget _tierCard(BuildContext context, Map<String, dynamic> tk, String sym) {
    final featured = tk['destacado'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: featured ? null : Tw.slate900,
            gradient: featured ? LinearGradient(colors: [Tw.fuchsia950.withValues(alpha: 0.3), Tw.slate900, Tw.slate900]) : null,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: featured ? Tw.fuchsia500.withValues(alpha: 0.6) : Tw.w(0.1)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
              Text('${tk['nombre']}', style: tw(24, weight: black)),
              GradientText('${tk['precio']}$sym', align: TextAlign.start, style: tw(30, weight: black), colors: const [Tw.fuchsia400, Tw.indigo400]),
            ]),
            const SizedBox(height: 8),
            Text('${tk['descripcion'] ?? ''}', style: tw(12, color: Tw.slate400, height: 1.6)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final inc in (tk['incluye'] as List? ?? const []))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Tw.w(0.05))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check, size: 12, color: Tw.fuchsia400),
                    const SizedBox(width: 4),
                    Text('$inc', style: tw(10, weight: bold, color: Tw.slate300)),
                  ]),
                ),
            ]),
            const SizedBox(height: 20),
            featured
                ? GradientButton(
                    label: _buying == tk['id'] ? context.t('venue_tickets.processing') : context.t('venue_tickets.buy_ticket'),
                    icon: Icons.shopping_bag,
                    expand: true,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]),
                    onTap: _buying == tk['id'] ? null : () => _checkout(tk),
                  )
                : AdminButton(
                    icon: Icons.shopping_bag,
                    label: _buying == tk['id'] ? context.t('venue_tickets.processing') : context.t('venue_tickets.buy_ticket'),
                    color: Tw.white,
                    textColor: Tw.slate950,
                    expand: true,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    onTap: _buying == tk['id'] ? null : () => _checkout(tk),
                  ),
          ]),
        ),
        if (featured)
          Positioned(
            top: -12,
            left: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome, size: 12, color: Tw.white),
                const SizedBox(width: 4),
                Label(context.t('venue_tickets.best_seller'), size: 9, color: Tw.white),
              ]),
            ),
          ),
      ]),
    );
  }
}
