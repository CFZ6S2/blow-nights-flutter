import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

class _MenuItem {
  final String id, name, category;
  final double price;
  final bool popular;
  final String? description;
  final List<String>? mixers;
  final ({String title, String description, double addon, String target})? upsell;
  const _MenuItem(this.id, this.name, this.category, this.price, {this.popular = false, this.description, this.mixers, this.upsell});
}

const _venueInfo = {
  'chueca-club': ('Boite Chueca Live', 'Madrid', 'Calle de Tetuan 20, Chueca', 'Barra Express Online'),
  'sala-malasana': ('Mala Bar & Club', 'Madrid', 'Calle del Barco 34, Malasana', 'Carta Movil Activa'),
  'default': ('Local Asociado Madrid', 'Madrid', 'Zona Centro, Madrid', 'Carta Digital Directa'),
};

const _venueMenu = [
  _MenuItem('v-c1', 'Ginebra Hendrick Tonic', 'copa', 12,
      popular: true,
      mixers: ['Tonica Schweppes', 'Tonica Zero'],
      upsell: (title: 'Subir a Copa Balon Especial', description: 'Servicio con rodaja de pepino fresco y enebro', addon: 3, target: 'Hendrick Grand Tonic')),
  _MenuItem('v-c2', 'Ron Flor de Cana 12 Anos', 'copa', 11.5,
      popular: true,
      mixers: ['Coca-Cola', 'Coca-Cola Zero', 'Sprite'],
      upsell: (title: 'Zacapa 23 Gran Reserva', description: 'Ron ultra premium envejecido en roble', addon: 3.5, target: 'Zacapa 23 Gran Reserva')),
  _MenuItem('v-c3', 'Vodka Grey Goose', 'copa', 12,
      mixers: ['Tonica', 'Limon', 'Red Bull (+1€)'],
      upsell: (title: 'Anadir 2 Chupitos Jager', description: 'Pide el combo completo para tu grupo', addon: 5, target: 'Grey Goose + 2 Shots Jager')),
  _MenuItem('v-b1', 'Cerveza Mahou 5 Estrellas (Grifo)', 'cerveza', 4.5, popular: true),
  _MenuItem('v-b2', 'Alhambra Reserva 1925', 'cerveza', 5.5),
  _MenuItem('v-s1', 'Ronda 5 Chupitos Tequila Reposado', 'chupito', 16, popular: true, description: '100% Agave servido con sal y lima'),
  _MenuItem('v-p1', 'Pack Previa: 3 Copas Bar', 'pack', 27, popular: true, description: '3 Tokens independientes para consumir a tu ritmo'),
  _MenuItem('v-vip', 'Botella Ruinart Blanc de Blancs', 'vip', 160, description: 'Servicio con copas de cristal y hielera exclusiva'),
];

/// Port of app/venue/[venueId]/menu/page.tsx (demo mobile bar menu with simulated Apple/Google Pay & Bizum).
class VenueMenuScreen extends StatefulWidget {
  final String venueId;
  const VenueMenuScreen({super.key, required this.venueId});

  @override
  State<VenueMenuScreen> createState() => _VenueMenuScreenState();
}

class _VenueMenuScreenState extends State<VenueMenuScreen> {
  final _rand = Random();
  String _cat = 'all';
  List<({String id, String name, double price, String? mixer, bool premium})> _cart = [];
  String _step = 'catalog';
  List<({String tokenId, String name, String? mixer})> _tokens = [];

  (String, String, String, String) get _venue => _venueInfo[widget.venueId] ?? _venueInfo['default']!;
  double get _total => _cart.fold(0, (s, i) => s + i.price);

  Future<void> _add(_MenuItem item) async {
    final mixer = item.mixers?.first;
    final up = item.upsell;
    var premium = false;
    if (up != null) {
      final accepted = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.amber500.withValues(alpha: 0.4))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Label(ctx.t('venue_menu_upsell', fallback: 'MEJORA TU COPA'), color: Tw.amber400, tracking: 0.05),
              const SizedBox(height: 4),
              Text(up.title, style: tw(18, weight: black, height: 1.2)),
              const SizedBox(height: 4),
              Text(up.description, style: tw(12, color: Tw.slate300)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Tw.slate800.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.slate700.withValues(alpha: 0.6))),
                child: Row(children: [
                  Text(ctx.t('venue_menu_supplement', fallback: 'Suplemento'), style: tw(12, color: Tw.slate400)),
                  const Spacer(),
                  Text('+${up.addon.toStringAsFixed(2)} €', style: tw(14, weight: black, color: Tw.amber400)),
                ]),
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: ctx.t('venue_menu_upsell_accept', fallback: 'SI, MEJORAR MI BEBIDA ✨'),
                fontSize: 12,
                radius: 12,
                padding: const EdgeInsets.symmetric(vertical: 12),
                gradient: const LinearGradient(colors: [Tw.amber400, Tw.yellow500]),
                onTap: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 8),
              AdminButton(
                label: '${ctx.t('venue_menu_upsell_decline', fallback: 'Mantener opcion')} (${item.price.toStringAsFixed(2)} €)',
                color: Tw.slate800,
                textColor: Tw.slate400,
                expand: true,
                onTap: () => Navigator.of(ctx).pop(false),
              ),
            ]),
          ),
        ),
      );
      if (accepted == null) return;
      premium = accepted;
    }
    setState(() => _cart = [
          ..._cart,
          (
            id: _rand.nextInt(1 << 32).toRadixString(36),
            name: premium ? up!.target : item.name,
            price: premium ? item.price + up!.addon : item.price,
            mixer: mixer,
            premium: premium,
          ),
        ]);
  }

  void _pay() {
    if (_cart.isEmpty) return;
    Navigator.of(context).pop();
    setState(() => _step = 'processing');
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _tokens = [for (final c in _cart) (tokenId: 'MAD-${100000 + _rand.nextInt(900000)}', name: c.name, mixer: c.mixer)];
        _step = 'wallet';
      });
    });
  }

  void _openCart() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Tw.slate900,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).padding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.shopping_bag, size: 16, color: Tw.rose500),
                const SizedBox(width: 8),
                Expanded(child: Text('${_venue.$1} - ${ctx.t('venue_menu_menu', fallback: 'Carta')}', style: tw(16, weight: black))),
                IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close, color: Tw.slate400)),
              ]),
              Divider(color: Tw.slate800),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
                child: ListView(shrinkWrap: true, children: [
                  for (final c in _cart)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Tw.slate800.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(c.name, style: tw(12, weight: bold))),
                              if (c.premium) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(color: Tw.amber500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                  child: Text('PREMIUM', style: tw(9, weight: black, color: const Color(0xFFFCD34D))),
                                ),
                              ],
                            ]),
                            if (c.mixer != null) Text('+ ${c.mixer}', style: tw(11, color: Tw.slate400)),
                            Text('${c.price.toStringAsFixed(2)} €', style: tw(12, weight: black, color: Tw.amber400)),
                          ]),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() => _cart = _cart.where((x) => x.id != c.id).toList());
                            setLocal(() {});
                          },
                          icon: const Icon(Icons.close, size: 16, color: Tw.slate500),
                        ),
                      ]),
                    ),
                ]),
              ),
              Divider(color: Tw.slate800),
              Row(children: [
                Text(ctx.t('venue_menu_total', fallback: 'Total a Pagar'), style: tw(12, color: Tw.slate400)),
                const Spacer(),
                Text('${_total.toStringAsFixed(2)} €', style: tw(24, weight: black)),
              ]),
              const SizedBox(height: 12),
              AdminButton(
                icon: Icons.credit_card,
                label: ctx.t('venue_menu_pay_apple_google', fallback: 'Pagar con Apple / Google Pay'),
                color: Tw.white,
                textColor: Tw.black,
                expand: true,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(vertical: 14),
                onTap: _pay,
              ),
              const SizedBox(height: 10),
              AdminButton(
                label: ctx.t('venue_menu_pay_bizum', fallback: 'Pagar con Bizum'),
                color: const Color(0xFF00A499),
                expand: true,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(vertical: 12),
                onTap: _pay,
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final (name, city, address, badge) = _venue;
    final top = MediaQuery.of(context).padding.top;
    final list = _cat == 'all' ? _venueMenu : _venueMenu.where((i) => i.category == _cat).toList();
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Stack(children: [
        Column(children: [
          Container(
            padding: EdgeInsets.fromLTRB(8, top + 10, 16, 10),
            decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.95), border: const Border(bottom: BorderSide(color: Tw.slate800))),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Tw.amber500, Tw.rose500]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.store, color: Tw.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: tw(16, weight: black, height: 1)),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on, size: 12, color: Tw.rose400),
                    const SizedBox(width: 4),
                    Expanded(child: Text('$city • $address', maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(11, weight: medium, color: Tw.slate400))),
                  ]),
                ]),
              ),
              if (_step == 'catalog' && _cart.isNotEmpty)
                Pressable(
                  onTap: _openCart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFE11D48), borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.shopping_bag, size: 16, color: Tw.white),
                      const SizedBox(width: 6),
                      Text('${_total.toStringAsFixed(2)} €', style: tw(12, weight: bold)),
                      const SizedBox(width: 6),
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: Tw.white, shape: BoxShape.circle),
                        child: Text('${_cart.length}', style: tw(10, weight: black, color: const Color(0xFFE11D48))),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.7), border: Border(bottom: BorderSide(color: Tw.slate800.withValues(alpha: 0.8)))),
            child: Row(children: [
              const PulseDot(color: Tw.emerald400),
              const SizedBox(width: 8),
              Expanded(child: Text(context.t('venue_menu_bar_active', fallback: 'Barra Activa: Pide en tu movil y recoge en barra'), style: tw(12, weight: bold, color: Tw.slate300))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Tw.amber500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Tw.amber500.withValues(alpha: 0.3)),
                ),
                child: Label(badge, color: Tw.amber400, weight: bold, tracking: 0.05),
              ),
            ]),
          ),
          Expanded(child: _step == 'wallet' ? _wallet(context, name) : _catalog(context, list)),
        ]),
        if (_step == 'catalog' && _cart.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(color: Tw.slate950.withValues(alpha: 0.95), border: Border(top: BorderSide(color: Tw.slate800.withValues(alpha: 0.9)))),
              child: Pressable(
                onTap: _openCart,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Tw.emerald500, Tw.teal500]), borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Icon(Icons.shopping_bag, size: 16, color: Tw.slate950),
                    const SizedBox(width: 8),
                    Text('${context.t('venue_menu_view_order', fallback: 'Ver Pedido')} (${_cart.length})', style: tw(14, weight: black, color: Tw.slate950)),
                    const Spacer(),
                    Text('${_total.toStringAsFixed(2)} €', style: tw(16, weight: black, color: Tw.slate950)),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward, size: 16, color: Tw.slate950),
                  ]),
                ),
              ),
            ),
          ),
        if (_step == 'processing')
          Container(
            color: Colors.black.withValues(alpha: 0.95),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 4, color: Tw.emerald400)),
              const SizedBox(height: 16),
              Text(context.t('venue_menu_confirming', fallback: 'Confirmando Pago Seguro'), style: tw(20, weight: black)),
              const SizedBox(height: 4),
              Text(context.t('venue_menu_sending', fallback: 'Enviando orden a la barra de {{venue}}...', params: {'venue': name}),
                  textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
            ]),
          ),
      ]),
    );
  }

  Widget _catalog(BuildContext context, List<_MenuItem> list) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 112), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final c in const ['all', 'copa', 'cerveza', 'chupito', 'pack', 'vip'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Pressable(
                  onTap: () => setState(() => _cat = c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _cat == c ? const Color(0xFFE11D48) : Tw.slate900,
                      borderRadius: BorderRadius.circular(12),
                      border: _cat == c ? null : Border.all(color: Tw.slate800),
                    ),
                    child: Text(c == 'all' ? context.t('venue_menu_category_all', fallback: '✨ Todo') : c[0].toUpperCase() + c.substring(1),
                        style: tw(12, weight: bold, color: _cat == c ? Tw.white : Tw.slate300)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        for (final item in list)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.slate800)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.name, style: tw(16, weight: FontWeight.w800)),
                    if (item.description != null) Text(item.description!, style: tw(12, color: Tw.slate400)),
                  ]),
                ),
                if (item.popular)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Tw.amber500.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Tw.amber500.withValues(alpha: 0.3)),
                    ),
                    child: Label(context.t('venue_menu_top_local', fallback: 'Top Local'), size: 9, color: Tw.amber400, tracking: 0),
                  ),
              ]),
              if (item.mixers != null) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final m in item.mixers!)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(6)),
                      child: Text(m, style: tw(10, color: Tw.slate300)),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              Divider(height: 1, color: Tw.slate800.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              Row(children: [
                Text('${item.price.toStringAsFixed(2)} €', style: tw(18, weight: black, color: Tw.amber400)),
                const Spacer(),
                GradientButton(
                  label: context.t('venue_menu_order_drink', fallback: 'Pedir copa +'),
                  fontSize: 11,
                  radius: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  gradient: const LinearGradient(colors: [Color(0xFFE11D48), Tw.amber500]),
                  onTap: () => _add(item),
                ),
              ]),
            ]),
          ),
      ]);

  Widget _wallet(BuildContext context, String venue) => ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 40), children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: Tw.emerald500.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Tw.emerald500.withValues(alpha: 0.4))),
            child: const Icon(Icons.check_circle, size: 30, color: Tw.emerald400),
          ),
        ),
        const SizedBox(height: 12),
        Text(context.t('venue_menu_confirmed', fallback: '¡PAGO CONFIRMADO!'), textAlign: TextAlign.center, style: tw(24, weight: black)),
        const SizedBox(height: 4),
        Text(
          context.t('venue_menu_hint',
              fallback: 'Acercate a la barra de {{venue}} y muestra estos codigos para que el camarero te sirva al instante.', params: {'venue': venue}),
          textAlign: TextAlign.center,
          style: tw(12, color: Tw.slate400),
        ),
        const SizedBox(height: 24),
        for (final t in _tokens)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.slate700, width: 2)),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(data: t.tokenId, size: 150, padding: EdgeInsets.zero),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(99)),
                child: Text(t.tokenId, style: tw(11, weight: bold, color: Tw.amber400).copyWith(fontFamily: 'monospace')),
              ),
              const SizedBox(height: 6),
              Text(t.name, style: tw(16, weight: black)),
              if (t.mixer != null) Text('Con ${t.mixer}', style: tw(12, color: Tw.slate400)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: Tw.emerald500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.verified_user, size: 12, color: Tw.emerald400),
                  const SizedBox(width: 4),
                  Text(context.t('venue_menu_valid_at', fallback: 'Valido en barra de {{venue}}', params: {'venue': venue}), style: tw(10, weight: bold, color: Tw.emerald400)),
                ]),
              ),
            ]),
          ),
        AdminButton(
          label: context.t('venue_menu_order_more', fallback: 'Pedir mas consumiciones'),
          color: Tw.slate800,
          expand: true,
          padding: const EdgeInsets.symmetric(vertical: 14),
          onTap: () => setState(() {
            _cart = [];
            _step = 'catalog';
          }),
        ),
      ]);
}
