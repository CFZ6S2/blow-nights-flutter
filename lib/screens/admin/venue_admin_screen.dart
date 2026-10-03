import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/platform_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import 'venue_admin/benefit_rules_tab.dart';
import 'venue_admin/catalog_tab.dart';
import 'venue_admin/config_tab.dart';
import 'venue_admin/door_promoters_tabs.dart';
import 'venue_admin/events_tab.dart';
import 'venue_admin/setup_wizard.dart';

String _hhmm(Object? ts) {
  final d = parseDate(ts);
  return d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Port of app/venue-admin/page.tsx (B2B venue panel: sidebar drawer + tabs).
class VenueAdminScreen extends StatefulWidget {
  const VenueAdminScreen({super.key});

  @override
  State<VenueAdminScreen> createState() => _VenueAdminScreenState();
}

class _VenueAdminScreenState extends State<VenueAdminScreen> {
  final _db = FirebaseFirestore.instance;
  final _scaffold = GlobalKey<ScaffoldState>();
  StreamSubscription? _venuesSub, _checkinsSub, _ticketsSub;
  List<Map<String, dynamic>> _venues = [];
  bool _venuesLoaded = false;
  String? _selectedId;
  List<Map<String, dynamic>> _checkins = [];
  List<Map<String, dynamic>> _tickets = [];
  String _ticketFilter = 'all';
  final Set<String> _collapsed = {};
  final _promo = TextEditingController();
  int _promoRadius = 5;
  bool _sendingPromo = false;
  /// What sendPromoNotification wrote back on the promo ({status, delivered}); {'status': 'pending'} until then.
  Map<String, dynamic>? _promoResult;
  StreamSubscription? _promoWatch;
  Timer? _promoGiveUp;
  String _tab = 'overview';
  bool _checkingOut = false;
  bool _updatingTier = false;
  bool _started = false;

  Map<String, dynamic>? get _venue => _venues.where((v) => v['id'] == _selectedId).firstOrNull;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (_started || auth.loading) return;
    _started = true;
    if (auth.user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openRoute(context, AppRoute.login, replace: true);
      });
      return;
    }
    if (!const ['venue', 'venueOwner', 'cityAdmin', 'admin', 'superadmin'].contains(auth.role)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
      return;
    }
    _listenVenues(auth);
  }

  @override
  void dispose() {
    _venuesSub?.cancel();
    _checkinsSub?.cancel();
    _ticketsSub?.cancel();
    _stopPromoWatch();
    _promo.dispose();
    super.dispose();
  }

  void _listenVenues(AuthProvider auth) {
    final p = auth.profile?.data ?? const {};
    Query<Map<String, dynamic>> q;
    if (auth.isAdmin) {
      q = _db.collection('venues').where('isActive', isEqualTo: true);
    } else if (p['role'] == 'cityAdmin' && p['cityId'] != null) {
      q = _db.collection('venues').where('cityId', isEqualTo: p['cityId']).where('isActive', isEqualTo: true);
    } else {
      q = _db.collection('venues').where('ownerId', isEqualTo: auth.user!.uid);
    }
    _venuesSub = q.snapshots().listen((s) {
      final list = [for (final d in s.docs) <String, dynamic>{'id': d.id, ...d.data()}];
      setState(() {
        _venues = list;
        _venuesLoaded = true;
        if (list.isNotEmpty && _selectedId == null) _select(list.first['id'] as String);
      });
    }, onError: (_) => setState(() => _venuesLoaded = true));
  }

  void _select(String id) {
    _selectedId = id;
    _checkinsSub?.cancel();
    _ticketsSub?.cancel();
    final auth = context.read<AuthProvider>();
    _checkinsSub = _db
        .collection('checkins')
        .where('venueId', isEqualTo: id)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .listen((s) => setState(() => _checkins = [for (final d in s.docs) {'id': d.id, ...d.data()}]), onError: (_) {});
    var tq = _db.collection('tickets').where('venueId', isEqualTo: id);
    if (!auth.isAdmin) tq = tq.where('venueOwnerId', isEqualTo: auth.user!.uid);
    _ticketsSub = tq.limit(100).snapshots().listen((s) {
      final list = [for (final d in s.docs) <String, dynamic>{'id': d.id, ...d.data()}];
      int ms(Object? v) => parseDate(v)?.millisecondsSinceEpoch ?? 0;
      list.sort((a, b) => ms(b['purchasedAt']) - ms(a['purchasedAt']));
      setState(() => _tickets = list);
    }, onError: (e) => debugPrint('Error loading tickets for venue: $e'));
  }

  Future<void> _subscribe(String tier) async {
    final v = _venue;
    if (v == null || _checkingOut) return;
    setState(() => _checkingOut = true);
    try {
      final res = await callFn('createVenueSubscriptionCheckout', {'venueId': v['id'], 'tier': tier, 'origin': webBase});
      await openInApp(res['url'] as String);
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('venue_admin_error_checkout'), error: true);
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _manageSubscription() async {
    final v = _venue;
    if (v == null || _checkingOut) return;
    setState(() => _checkingOut = true);
    try {
      final res = await callFn('createStripePortalSession', {'venueId': v['id']});
      await openInApp(res['url'] as String);
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('venue_admin_error_stripe'), error: true);
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _setTestTier(String tier) async {
    final v = _venue;
    if (v == null || _updatingTier) return;
    setState(() => _updatingTier = true);
    try {
      await callFn('setVenueTestTier', {'venueId': v['id'], 'tier': tier});
      if (mounted) showToast(context, tier == 'none' ? 'Plan desactivado (Modo Pruebas 0€)' : 'Plan ${tier.toUpperCase()} activado (Modo Pruebas 0€)');
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e, 'Error al cambiar plan de prueba'), error: true);
    } finally {
      if (mounted) setState(() => _updatingTier = false);
    }
  }

  void _stopPromoWatch() {
    _promoWatch?.cancel();
    _promoWatch = null;
    _promoGiveUp?.cancel();
    _promoGiveUp = null;
  }

  String _promoResultText(BuildContext context, Map<String, dynamic> r) {
    final delivered = asInt(r['delivered']);
    return switch (r['status']) {
      'pending' => context.t('venue_admin_promo_sending'),
      'no_location' => context.t('venue_admin_promo_no_location',
          fallback: 'El local no tiene ubicación en el mapa, así que no se puede saber quién está cerca.'),
      _ when delivered > 0 =>
        context.t('venue_admin_promo_reached', fallback: 'Enviada a {{count}} personas cerca', count: delivered),
      _ => context.t('venue_admin_promo_nobody',
          fallback: 'Ahora mismo no hay nadie cerca con las notificaciones activadas: no ha llegado a nadie.'),
    };
  }

  Future<void> _sendPromotion() async {
    final v = _venue;
    if (v == null || _promo.text.trim().isEmpty || _sendingPromo) return;
    setState(() => _sendingPromo = true);
    try {
      final ref = await _db.collection('promotions').add({
        'venueId': v['id'],
        'venueOwnerId': context.read<AuthProvider>().user!.uid,
        'cityId': v['cityId'] ?? '',
        'text': _promo.text.trim(),
        'radiusKm': _promoRadius,
        'validUntil': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 2))),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _promo.clear();
      _stopPromoWatch();
      setState(() => _promoResult = {'status': 'pending'});
      // The server answers in seconds; past 30 s the panel stops waiting.
      _promoGiveUp = Timer(const Duration(seconds: 30), () {
        _stopPromoWatch();
        if (mounted) setState(() => _promoResult = null);
      });
      _promoWatch = ref.snapshots().listen((snap) {
        final data = snap.data();
        if (data?['status'] == null) return;
        _stopPromoWatch();
        if (mounted) setState(() => _promoResult = {'status': data!['status'], 'delivered': asInt(data['delivered'])});
      }, onError: (_) {
        _stopPromoWatch();
        if (mounted) setState(() => _promoResult = null);
      });
    } catch (e) {
      debugPrint('Error sending promotion: $e');
    } finally {
      if (mounted) setState(() => _sendingPromo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loading = const Scaffold(backgroundColor: Tw.slate950, body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)));
    if (auth.loading || auth.profile == null || !_venuesLoaded) return loading;
    final canBypass = auth.isAdmin;

    if (_venues.isEmpty) {
      if (auth.profile!.data['delegatedManagement'] == true) {
        return _emptyState(Icons.handshake, Tw.indigo500, context.t('venue_admin_delegated_title'), context.t('venue_admin_delegated_desc'));
      }
      if (canBypass || auth.isCityAdmin) {
        return _emptyState(Icons.storefront, Tw.slate500, context.t('venue_admin_no_venues_zone'), context.t('venue_admin_no_venues_zone_desc'),
            action: AdminButton(
              label: context.t('venue_admin_back_panel'),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onTap: () => openRoute(context, auth.isAdmin ? AppRoute.admin : AppRoute.cityManager, replace: true),
            ));
      }
      return SetupWizard(onReload: () => setState(() {}));
    }

    final v = _venue;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      key: _scaffold,
      backgroundColor: Tw.slate950,
      drawer: _sidebar(context, canBypass),
      body: Stack(children: [
        ListView(
          padding: EdgeInsets.fromLTRB(20, top + 68, 20, 80 + MediaQuery.of(context).padding.bottom),
          children: [
            if (v != null) ...[
              _header(context, v),
              const SizedBox(height: 24),
              if (v['subscriptionTier'] == null && v['ownerId'] != 'community' && !canBypass) ...[_pricing(context), const SizedBox(height: 24)],
              _tabBody(context, v, canBypass),
            ],
          ],
        ),
        Positioned(
          top: top + 12,
          left: 16,
          child: Pressable(
            onTap: () => _scaffold.currentState?.openDrawer(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
              child: const Icon(Icons.menu, size: 20, color: Tw.white),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _emptyState(IconData icon, Color color, String title, String desc, {Widget? action}) => Scaffold(
        backgroundColor: Tw.slate950,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(color: color == Tw.slate500 ? Tw.slate800 : color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, size: 36, color: color),
              ),
              const SizedBox(height: 24),
              Text(title, textAlign: TextAlign.center, style: tw(24, weight: black)),
              const SizedBox(height: 8),
              Text(desc, textAlign: TextAlign.center, style: tw(15, color: Tw.slate400)),
              if (action != null) ...[const SizedBox(height: 32), action],
            ]),
          ),
        ),
      );

  Widget _sidebar(BuildContext context, bool canBypass) {
    final v = _venue;
    final nav = [
      ('overview', context.t('tab_overview'), Icons.dashboard),
      ('config', context.t('tab_config'), Icons.tune),
      ('catalog', context.t('tab_catalog'), Icons.menu_book),
      ('events', context.t('tab_venue_events'), Icons.event),
      ('door', context.t('tab_door'), Icons.door_front_door),
      ('promoters', context.t('tab_promoters'), Icons.groups),
      ('tickets', context.t('tab_ticketing'), Icons.confirmation_number),
      ('promos', context.t('tab_promos'), Icons.campaign),
      ('benefits', context.t('tab_benefits', fallback: 'Cortesías'), Icons.card_giftcard),
    ];
    Widget item(String label, IconData icon, bool active, VoidCallback onTap, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Pressable(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: active ? Tw.fuchsia600.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? Tw.fuchsia500.withValues(alpha: 0.3) : Colors.transparent),
              ),
              child: Row(children: [
                Icon(icon, size: 18, color: color ?? (active ? Tw.fuchsia400 : Tw.slate500)),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: tw(14, weight: semibold, color: color ?? (active ? Tw.fuchsia400 : Tw.slate400)))),
              ]),
            ),
          ),
        );

    return Drawer(
      width: 256,
      backgroundColor: Tw.slate900.withValues(alpha: 0.97),
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
            child: Row(children: [
              Pressable(
                onTap: () => Navigator.of(context)
                  ..pop()
                  ..maybePop(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.arrow_back, size: 16, color: Tw.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('venue_admin_title'), style: tw(16, weight: black, color: Tw.fuchsia400)),
                  Text((v?['name'] as String?) ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(10, color: Tw.slate500)),
                ]),
              ),
            ]),
          ),
          if (_venues.length > 1)
            Container(
              constraints: const BoxConstraints(maxHeight: 128),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
                for (final x in _venues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Pressable(
                      onTap: () {
                        setState(() => _select(x['id'] as String));
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: x['id'] == _selectedId ? Tw.fuchsia600.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: x['id'] == _selectedId ? Tw.fuchsia500.withValues(alpha: 0.3) : Colors.transparent),
                        ),
                        child: Text((x['name'] as String?) ?? '',
                            style: tw(12, weight: semibold, color: x['id'] == _selectedId ? Tw.fuchsia400 : Tw.slate400)),
                      ),
                    ),
                  ),
              ]),
            ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final (key, label, icon) in nav)
                item(label, icon, _tab == key, () {
                  setState(() => _tab = key);
                  Navigator.of(context).pop();
                }),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.w(0.05)))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (v?['subscriptionTier'] != null && !canBypass && context.watch<PlatformSettings>().flag('moduleAppPremium'))
                item(context.t('venue_admin_manage_plan'), Icons.settings, false, _checkingOut ? () {} : _manageSubscription),
              if (v?['subscriptionTier'] == 'ticketing' || canBypass)
                item(context.t('venue_admin_scan'), Icons.qr_code_scanner, false, () => openRoute(context, AppRoute.scanner), color: Tw.fuchsia400),
              if (v?['id'] is String && context.watch<PlatformSettings>().flag('moduleCashless'))
                item(context.t('venue_admin_scan_drinks', fallback: 'Escanear consumiciones'), Icons.local_bar, false,
                    () => openRoute(context, AppRoute.barScanner, args: {'venue': v!['id'] as String}), color: Tw.emerald400),
              const SizedBox(height: 8),
              const AdminTopBar(),
              const SizedBox(height: 8),
              const Label('Blow Nights Venue v2', size: 9, weight: FontWeight.w400, color: Tw.slate600, align: TextAlign.center),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context, Map<String, dynamic> v) {
    final tier = v['subscriptionTier'] as String?;
    final tierColor = switch (tier) { 'ticketing' => Tw.fuchsia400, 'promo' => Tw.indigo400, 'basico' => Tw.cyan400, _ => Tw.slate400 };
    Widget tierBtn(String value, String label, Color active) {
      final on = value == 'none' ? tier == null : tier == value;
      return GestureDetector(
        onTap: _updatingTier ? null : () => _setTestTier(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: on ? active : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: on && value != 'none' ? [BoxShadow(color: active.withValues(alpha: 0.5), blurRadius: 10)] : null,
          ),
          child: Text(label, style: tw(12, weight: semibold, color: on ? Tw.white : Tw.slate400)),
        ),
      );
    }

    return AdminCard(
      radius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text((v['name'] as String?) ?? '', style: tw(18, weight: black)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: tier == null ? Tw.slate700.withValues(alpha: 0.5) : tierColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: tierColor.withValues(alpha: 0.3)),
            ),
            child: Text((tier != null ? 'Plan $tier' : 'Sin plan activo').toUpperCase(), style: tw(10, weight: bold, color: tierColor)),
          ),
        ]),
        Text((v['address'] as String?) ?? context.t('venue_admin_no_address'), style: tw(10, color: Tw.slate500)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Tw.slate900.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
          ),
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.science, size: 14, color: Tw.fuchsia400),
              const SizedBox(width: 4),
              Text('Pruebas (0€):', style: tw(11, weight: bold, color: Tw.fuchsia400)),
            ]),
            tierBtn('none', 'Sin Plan', Tw.slate700),
            tierBtn('basico', 'Básico', const Color(0xFF0891B2)),
            tierBtn('promo', 'Promo', Tw.fuchsia600),
            tierBtn('ticketing', 'Ticketing', Tw.indigo600),
          ]),
        ),
      ]),
    );
  }

  Widget _pricing(BuildContext context) {
    Widget plan(String key, String tier, Color btnColor, {bool featured = false}) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: featured ? null : Tw.slate900,
            gradient: featured
                ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.fuchsia900.withValues(alpha: 0.4), Tw.indigo900.withValues(alpha: 0.4)])
                : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: featured ? Tw.fuchsia500.withValues(alpha: 0.5) : Tw.slate700),
          ),
          child: Column(children: [
            Text(context.t('venue_admin_tier_$key'), style: tw(18, weight: black)),
            Text('${context.t('venue_admin_tier_${key}_price')}${context.t('venue_admin_per_month')}',
                style: tw(14, color: Tw.slate500, decoration: TextDecoration.lineThrough)),
            Text.rich(TextSpan(children: [
              TextSpan(text: context.t('venue_admin_tier_${key}_promo'), style: tw(20, weight: black, color: Tw.fuchsia400)),
              TextSpan(text: context.t('venue_admin_per_month'), style: tw(14, color: Tw.slate500)),
            ])),
            const SizedBox(height: 8),
            Text(context.t('venue_admin_tier_${key}_desc'), textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
            const SizedBox(height: 16),
            AdminButton(
              icon: Icons.science,
              label: 'Activar ${tier == 'basico' ? 'Básico' : tier == 'promo' ? 'Promo' : 'Ticketing'} (Prueba 0€)',
              color: btnColor,
              outlined: !featured,
              textColor: Tw.white,
              expand: true,
              padding: const EdgeInsets.symmetric(vertical: 10),
              onTap: _updatingTier ? null : () => _setTestTier(tier),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Tw.fuchsia600.withValues(alpha: 0.2), Tw.indigo600.withValues(alpha: 0.2)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
        ),
        child: Text(context.t('venue_admin_launch_promo'), textAlign: TextAlign.center, style: tw(14, weight: black, color: Tw.fuchsia400)),
      ),
      plan('basic', 'basico', Tw.cyan400),
      plan('promo', 'promo', Tw.fuchsia600, featured: true),
      plan('ticketing', 'ticketing', Tw.indigo500),
    ]);
  }

  Widget _upgrade(BuildContext context, String titleKey, String descKey, String tier) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.slate800)),
        child: Column(children: [
          Text(context.t(titleKey), textAlign: TextAlign.center, style: tw(20, weight: black)),
          const SizedBox(height: 8),
          Text(context.t(descKey), textAlign: TextAlign.center, style: tw(15, color: Tw.slate400)),
          const SizedBox(height: 24),
          // Plans are a digital service: bought in the app only while super-admin has moduleAppPremium on
          // (Google Play payments policy).
          if (context.watch<PlatformSettings>().flag('moduleAppPremium'))
            AdminButton(
              label: context.t('venue_admin_upgrade_plan'),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              onTap: _checkingOut ? null : () => _subscribe(tier),
            )
          else
            Text(context.t('venue_admin_plans_unavailable_app'), textAlign: TextAlign.center, style: tw(13, color: Tw.slate500)),
        ]),
      );

  Widget _tabBody(BuildContext context, Map<String, dynamic> v, bool canBypass) {
    final id = v['id'] as String;
    final tier = v['subscriptionTier'];
    return switch (_tab) {
      'door' => DoorTab(key: ValueKey('door-$id'), venueId: id),
      'promoters' => PromotersTab(key: ValueKey('promoters-$id'), venueId: id),
      'config' => VenueConfigTab(key: ValueKey('config-$id'), venue: v),
      'catalog' => VenueCatalogTab(key: ValueKey('catalog-$id'), venueId: id),
      'events' => tier == 'ticketing' || canBypass
          ? VenueEventsTab(key: ValueKey('events-$id'), venue: v)
          : _upgrade(context, 'venue_admin_requires_ticketing', 'venue_admin_upgrade_ticketing_desc', 'ticketing'),
      'tickets' => tier != 'ticketing' && !canBypass
          ? _upgrade(context, 'venue_admin_requires_ticketing', 'venue_admin_upgrade_ticketing_tickets_desc', 'ticketing')
          : _ticketsTab(context),
      'promos' => ['promo', 'ticketing'].contains(tier) || canBypass
          ? _promosTab(context)
          : _upgrade(context, 'venue_admin_requires_promo', 'venue_admin_upgrade_promo_desc', 'promo'),
      'benefits' => BenefitRulesTab(key: ValueKey('benefits-$id'), venueId: id),
      _ => _overviewTab(context, v),
    };
  }

  int get _used => _tickets.where((t) => t['status'] == 'used').length;
  int get _valid => _tickets.where((t) => t['status'] == 'valid').length;
  num get _revenue => _tickets.where((t) => t['status'] != 'cancelled').fold<num>(0, (s, t) => s + ((t['amount'] as num?) ?? 0));

  Widget _overviewTab(BuildContext context, Map<String, dynamic> v) {
    final now = [_checkins.length, (v['currentCount'] as num?)?.toInt() ?? 0].reduce((a, b) => a > b ? a : b);
    final stats = [
      (context.t('venue_admin_stat_now'), '$now', Icons.people, Tw.green400),
      (context.t('venue_admin_stat_sold'), '${_tickets.length}', Icons.confirmation_number, Tw.yellow400),
      ('Picadas en puerta', '$_used', Icons.check_circle, Tw.emerald400),
      (context.t('venue_admin_stat_revenue'), _revenue > 0 ? '${(_revenue / 100).toStringAsFixed(0)}€' : '0€', Icons.payments, Tw.blue400),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminGrid(children: [
        for (final (label, value, icon, color) in stats)
          AdminCard(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(value, style: tw(24, weight: black)),
              const SizedBox(height: 4),
              Label(label, size: 8, color: Tw.slate500),
            ]),
          ),
      ]),
      if (_checkins.isNotEmpty) ...[
        const SizedBox(height: 16),
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label(context.t('venue_admin_people_now'), size: 12, color: Tw.slate500),
            const SizedBox(height: 12),
            for (final c in _checkins)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
                child: Row(children: [
                  const PulseDot(color: Tw.green400),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text((c['nick'] ?? c['client_name'] ?? context.t('venue_admin_anonymous')) as String, style: tw(12, weight: bold)),
                  ),
                  Label(c['visibility'] == 'ghost' ? context.t('venue_admin_ghost') : context.t('venue_admin_public'),
                      size: 9, color: c['visibility'] == 'ghost' ? Tw.indigo400 : Tw.slate500),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }

  Widget _ticketsTab(BuildContext context) {
    Widget kpi(String label, String value, String note, IconData icon, Color color, {bool tinted = false}) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tinted ? color.withValues(alpha: 0.1) : Tw.w(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tinted ? color.withValues(alpha: 0.2) : Tw.w(0.1)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Label(label, color: tinted ? color : Tw.slate400, tracking: 0.05, maxLines: 1)),
              Icon(icon, size: 14, color: color),
            ]),
            const SizedBox(height: 4),
            Text(value, style: tw(24, weight: black, color: tinted || color == Tw.fuchsia400 ? color : Tw.white)),
            Text(note, style: tw(9, weight: medium, color: tinted ? color.withValues(alpha: 0.8) : Tw.slate500)),
          ]),
        );

    final filtered = _tickets.where((t) => _ticketFilter == 'all' || t['status'] == _ticketFilter).toList();
    final groups = <String, ({String title, Object? date, List<Map<String, dynamic>> tickets})>{};
    for (final tk in filtered) {
      final key = (tk['eventId'] as String?) ?? '__no_event__';
      final g = groups[key] ?? (title: (tk['eventTitle'] as String?) ?? '', date: tk['eventDate'], tickets: <Map<String, dynamic>>[]);
      g.tickets.add(tk);
      groups[key] = g;
    }
    final entries = groups.entries.toList()
      ..sort((a, b) {
        if (a.key == '__no_event__') return 1;
        if (b.key == '__no_event__') return -1;
        return (parseDate(b.value.date)?.millisecondsSinceEpoch ?? 0) - (parseDate(a.value.date)?.millisecondsSinceEpoch ?? 0);
      });

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminGrid(children: [
        kpi('Total Emitidas', '${_tickets.length}', 'De pago y gratuitas', Icons.confirmation_number, Tw.yellow400),
        kpi('Picadas en Puerta', '$_used', _tickets.isNotEmpty ? '${(_used / _tickets.length * 100).round()}% validadas' : '0%', Icons.check_circle,
            Tw.emerald400,
            tinted: true),
        kpi('Pendientes', '$_valid', 'Por entrar al local', Icons.schedule, Tw.blue400, tinted: true),
        kpi('Recaudación', _revenue > 0 ? '${(_revenue / 100).toStringAsFixed(2)}€' : '0,00€', 'Stripe / Pagos', Icons.payments, Tw.fuchsia400),
      ]),
      const SizedBox(height: 16),
      AdminChips(
        items: [('all', 'Todas (${_tickets.length})'), ('used', 'Picadas / Dentro ($_used)'), ('valid', 'Pendientes ($_valid)')],
        selected: _ticketFilter,
        onSelect: (f) => setState(() => _ticketFilter = f),
      ),
      const SizedBox(height: 16),
      if (_tickets.isEmpty)
        AdminCard(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          borderColor: Tw.w(0.05),
          child: Column(children: [
            const Icon(Icons.receipt_long, size: 48, color: Tw.slate700),
            const SizedBox(height: 12),
            Text(context.t('venue_admin_no_tickets'), style: tw(14, weight: bold, color: Tw.slate400)),
            const SizedBox(height: 4),
            Text('Las entradas emitidas y picadas en puerta se contabilizarán aquí en tiempo real.',
                textAlign: TextAlign.center, style: tw(12, color: Tw.slate600)),
          ]),
        )
      else
        for (final e in entries) _ticketGroup(context, e.key, e.value.title, e.value.date, e.value.tickets),
    ]);
  }

  Widget _ticketGroup(BuildContext context, String key, String eventTitle, Object? date, List<Map<String, dynamic>> tickets) {
    final collapsed = _collapsed.contains(key);
    final used = tickets.where((t) => t['status'] == 'used').length;
    final valid = tickets.where((t) => t['status'] == 'valid').length;
    final revenue = tickets.where((t) => t['status'] != 'cancelled').fold<num>(0, (s, t) => s + ((t['amount'] as num?) ?? 0));
    final title = key == '__no_event__' ? context.t('venue_admin_no_event', fallback: 'Sin evento') : (eventTitle.isNotEmpty ? eventTitle : key);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Tw.w(0.02), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => collapsed ? _collapsed.remove(key) : _collapsed.add(key)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(key == '__no_event__' ? Icons.local_activity : Icons.event, color: Tw.fuchsia400, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(14, weight: black)),
                  if (date != null && key != '__no_event__') Text(_hhmm(date), style: tw(10, weight: medium, color: Tw.slate500)),
                  const SizedBox(height: 2),
                  Text.rich(TextSpan(style: tw(10, weight: bold), children: [
                    TextSpan(text: '$used picadas', style: tw(10, weight: bold, color: Tw.emerald400)),
                    TextSpan(text: ' | ', style: tw(10, color: Tw.slate600)),
                    TextSpan(text: '$valid pend.', style: tw(10, weight: bold, color: Tw.blue400)),
                    if (revenue > 0) ...[
                      TextSpan(text: ' | ', style: tw(10, color: Tw.slate600)),
                      TextSpan(text: '${(revenue / 100).toStringAsFixed(0)}€', style: tw(10, weight: bold, color: Tw.fuchsia400)),
                    ],
                  ])),
                ]),
              ),
              AnimatedRotation(turns: collapsed ? 0 : 0.5, duration: const Duration(milliseconds: 200), child: const Icon(Icons.expand_more, color: Tw.slate500)),
            ]),
          ),
        ),
        if (!collapsed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: [for (final tk in tickets) _ticketRow(context, tk)]),
          ),
      ]),
    );
  }

  Widget _ticketRow(BuildContext context, Map<String, dynamic> tk) {
    final used = tk['status'] == 'used';
    final valid = tk['status'] == 'valid';
    final color = used ? Tw.emerald400 : valid ? Tw.blue400 : Tw.red400;
    final isTest = tk['channel'] == 'test_pass' || ((tk['tierName'] as String?)?.contains('prueba') ?? false);
    final isFree = tk['channel'] == 'free_claim' || tk['price'] == 0;
    final amount = tk['amount'] as num?;
    final dateStr = tk['usedAt'] != null
        ? 'Picada a las ${_hhmm(tk['usedAt'])}'
        : tk['purchasedAt'] != null
            ? 'Emitida: ${_hhmm(tk['purchasedAt'])}'
            : '';
    Widget chip(String t, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
          child: Text(t.toUpperCase(), style: tw(9, weight: black, color: c)),
        );
    return Opacity(
      opacity: used || valid ? 1 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: used ? Tw.emerald500.withValues(alpha: 0.05) : valid ? Tw.w(0.05) : Tw.red500.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: used ? Tw.emerald500.withValues(alpha: 0.2) : valid ? Tw.w(0.1) : Tw.red500.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
            child: Icon(used ? Icons.check_circle : valid ? Icons.confirmation_number : Icons.cancel, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text((tk['client_name'] ?? tk['customerEmail'] ?? context.t('venue_admin_anonymous')) as String, style: tw(14, weight: bold)),
                if (isTest)
                  chip('Test', const Color(0xFFFCD34D))
                else if (isFree)
                  chip('Gratis', const Color(0xFF93C5FD))
                else if (amount != null && amount != 0)
                  chip('${(amount / 100).toStringAsFixed(2)}€', const Color(0xFF6EE7B7)),
              ]),
              Text((tk['tierName'] ?? tk['ticketType'] ?? 'Entrada General') as String, style: tw(12, color: Tw.slate400)),
              if (dateStr.isNotEmpty)
                Row(children: [
                  const Icon(Icons.schedule, size: 11, color: Tw.slate500),
                  const SizedBox(width: 4),
                  Text(dateStr, style: tw(10, weight: medium, color: Tw.slate500)),
                ]),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (used) const PulseDot(color: Tw.emerald400, size: 6),
              if (valid) Container(width: 6, height: 6, decoration: const BoxDecoration(color: Tw.blue400, shape: BoxShape.circle)),
              if (used || valid) const SizedBox(width: 6),
              Label(used ? 'Picada' : valid ? 'Pendiente' : 'Cancelada', color: color, tracking: 0.05),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _promosTab(BuildContext context) => AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.campaign, size: 14, color: Tw.yellow500),
            const SizedBox(width: 4),
            Label(context.t('venue_admin_new_promo'), size: 12, color: Tw.slate500),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _promo,
            maxLines: 3,
            maxLength: 200,
            onChanged: (_) => setState(() {}),
            style: tw(14),
            decoration: adminInputDecoration(context.t('venue_admin_promo_placeholder')).copyWith(counterText: ''),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Text(context.t('venue_admin_promo_radius'), style: tw(10, weight: bold, color: Tw.slate500)),
            const SizedBox(width: 12),
            AdminSelect<int>(
              dense: true,
              value: _promoRadius,
              items: const [(1, '1 km'), (3, '3 km'), (5, '5 km'), (10, '10 km'), (25, '25 km')],
              onChanged: (v) => setState(() => _promoRadius = v ?? 5),
            ),
            const Spacer(),
            Text('${_promo.text.length}/200', style: tw(9, color: Tw.slate600)),
          ]),
          const SizedBox(height: 16),
          GradientButton(
            label: _sendingPromo ? context.t('venue_admin_promo_sending') : context.t('venue_admin_promo_send'),
            expand: true,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(vertical: 16),
            gradient: const LinearGradient(colors: [Tw.yellow500, Color(0xFFD97706)]),
            onTap: _promo.text.trim().isEmpty || _sendingPromo ? null : _sendPromotion,
          ),
          AnimatedOpacity(
            opacity: _promoResult != null ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _promoResult == null
                  ? const SizedBox.shrink()
                  : Text(
                      _promoResultText(context, _promoResult!),
                      textAlign: TextAlign.center,
                      style: tw(12,
                          weight: bold,
                          color: _promoResult!['status'] == 'sent' && asInt(_promoResult!['delivered']) > 0 ? Tw.green400 : Tw.amber400),
                    ),
            ),
          ),
        ]),
      );
}
