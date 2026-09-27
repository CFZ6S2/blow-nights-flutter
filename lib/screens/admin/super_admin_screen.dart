import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import 'super_admin/cities_panel.dart';
import 'super_admin/dashboard_panel.dart';
import 'super_admin/events_panel.dart';
import 'super_admin/feature_flags_panel.dart';
import 'super_admin/finance_panel.dart';
import 'super_admin/partners_panel.dart';
import 'super_admin/requests_panel.dart';
import 'super_admin/tenants_panel.dart';
import 'super_admin/users_panel.dart';
import 'super_admin/venues_panel.dart';

/// Port of app/super-admin/page.tsx (web mobile layout: hamburger + sidebar drawer + "App" button).
class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _NavEntry {
  final String key;
  final String label;
  final IconData icon;
  final String accent;
  final int badge;
  const _NavEntry(this.key, this.label, this.icon, {this.accent = 'fuchsia', this.badge = 0});
}

class _SuperAdminScreenState extends State<SuperAdminScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  String _tab = 'dashboard';

  Map<String, dynamic>? _dashStats;
  bool _dashLoading = false;
  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _cities = [];
  List<Map<String, dynamic>> _allUsers = [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded && context.read<AuthProvider>().isSuperAdmin) {
      _loaded = true;
      _fetchAnalytics();
      _fetchData();
    }
  }

  // useAdminAnalytics: getAdminAnalytics callable.
  Future<void> _fetchAnalytics() async {
    setState(() => _dashLoading = true);
    try {
      final res = await callFn('getAdminAnalytics');
      if (mounted && res['success'] == true) setState(() => _dashStats = Map<String, dynamic>.from(res['stats'] as Map));
    } catch (e) {
      debugPrint('getAdminAnalytics: $e');
    } finally {
      if (mounted) setState(() => _dashLoading = false);
    }
  }

  Future<void> _fetchData() async {
    final db = FirebaseFirestore.instance;
    try {
      final r = await Future.wait([
        db.collection('venues').limit(100).get(),
        db.collection('cities').limit(100).get(),
        db.collection('users').orderBy('createdAt', descending: true).limit(150).get(),
      ]);
      List<Map<String, dynamic>> rows(QuerySnapshot<Map<String, dynamic>> s) => [for (final d in s.docs) {'id': d.id, ...d.data()}];
      if (!mounted) return;
      setState(() {
        _venues = rows(r[0]);
        _cities = rows(r[1]);
        _allUsers = rows(r[2]);
      });
    } catch (e) {
      debugPrint('Error fetching super-admin data: $e');
    }
  }

  void _goToApp() => Navigator.of(context).popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF07080D),
        body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)),
      );
    }
    if (!auth.isSuperAdmin) return const ForbiddenScreen(messageKey: 'super_admin_forbidden');

    final s = _dashStats;
    final pendingTotal =
        s == null ? 0 : asNum(s['pendingPartnerApps']) + asNum(s['pendingRrppApps']) + asNum(s['pendingOrganizerApps']);
    final nav = [
      const _NavEntry('dashboard', 'Dashboard', Icons.dashboard),
      const _NavEntry('modulos', 'Módulos & Features', Icons.tune),
      _NavEntry('solicitudes', 'Solicitudes', Icons.pending_actions, accent: 'orange', badge: pendingTotal.toInt()),
      _NavEntry('usuarios', context.t('tab_users'), Icons.people),
      _NavEntry('roles', context.t('tab_roles'), Icons.admin_panel_settings),
      _NavEntry('ciudades', context.t('tab_cities'), Icons.location_city),
      _NavEntry('facturacion', context.t('tab_billing'), Icons.receipt_long),
      _NavEntry('locales', context.t('tab_venues'), Icons.storefront),
      _NavEntry('eventos', context.t('tab_events'), Icons.event, accent: 'indigo'),
      const _NavEntry('partners', 'Partners', Icons.handshake, accent: 'orange'),
      const _NavEntry('tenants', 'Marcas Blancas', Icons.branding_watermark, accent: 'fuchsia'),
    ];

    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      key: _scaffold,
      backgroundColor: Tw.slate950,
      drawer: _sidebar(context, nav),
      body: Stack(children: [
        RefreshIndicator(
          color: Tw.fuchsia500,
          onRefresh: () async {
            await Future.wait([_fetchAnalytics(), _fetchData()]);
            if (mounted) setState(() {});
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, top + 72, 20, 40 + MediaQuery.of(context).padding.bottom),
            children: [_panel()],
          ),
        ),
        // Mobile hamburger + "App" button (fixed top-4 left-4 / right-4).
        Positioned(
          top: top + 12,
          left: 16,
          child: _floatingButton(child: const Icon(Icons.menu, size: 20, color: Tw.white), onTap: () => _scaffold.currentState?.openDrawer()),
        ),
        Positioned(
          top: top + 12,
          right: 16,
          child: _floatingButton(
            border: Tw.fuchsia500.withValues(alpha: 0.3),
            onTap: _goToApp,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.radar, size: 16, color: Tw.fuchsia400),
              const SizedBox(width: 6),
              Text('App', style: tw(12, weight: bold, color: Tw.fuchsia400)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _floatingButton({required Widget child, required VoidCallback onTap, Color? border}) => Pressable(
        onTap: onTap,
        child: Container(
          height: 40,
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Tw.slate900.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border ?? Tw.w(0.1)),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12)],
          ),
          child: child,
        ),
      );

  Widget _sidebar(BuildContext context, List<_NavEntry> nav) => Drawer(
        width: 256,
        backgroundColor: Tw.slate900.withValues(alpha: 0.97),
        shape: const RoundedRectangleBorder(),
        child: SafeArea(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
              child: Row(children: [
                Pressable(
                  onTap: () => Navigator.of(context)
                    ..pop()
                    ..pop(),
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
                    Text(context.t('super_admin_title'), style: tw(16, weight: black, color: Tw.fuchsia400)),
                    Text(context.t('super_admin_subtitle'), style: tw(10, color: Tw.slate500)),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                children: [
                  for (final item in nav) _navButton(item),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.w(0.05)))),
              child: Column(children: [
                Pressable(
                  onTap: _goToApp,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Tw.fuchsia600.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.radar, size: 18, color: Tw.fuchsia400),
                      const SizedBox(width: 8),
                      Text(context.t('super_admin_go_to_app', fallback: 'Ir a la App'), style: tw(14, weight: bold, color: Tw.fuchsia400)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                const Label('Blow Nights Admin v2', size: 9, weight: FontWeight.w400, color: Tw.slate600),
              ]),
            ),
          ]),
        ),
      );

  Widget _navButton(_NavEntry item) {
    final active = _tab == item.key;
    final accent = switch (item.accent) {
      'orange' => (Tw.orange600, Tw.orange400, Tw.orange500),
      'indigo' => (Tw.indigo600, Tw.indigo400, Tw.indigo500),
      _ => (Tw.fuchsia600, Tw.fuchsia400, Tw.fuchsia500),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Pressable(
        onTap: () {
          setState(() => _tab = item.key);
          Navigator.of(context).pop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? accent.$1.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? accent.$3.withValues(alpha: 0.3) : Colors.transparent),
          ),
          child: Row(children: [
            Icon(item.icon, size: 18, color: active ? accent.$2 : Tw.slate500),
            const SizedBox(width: 12),
            Expanded(child: Text(item.label, style: tw(14, weight: semibold, color: active ? accent.$2 : Tw.slate400))),
            if (item.badge > 0)
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Tw.red500, shape: BoxShape.circle),
                child: Text('${item.badge}', style: tw(9, weight: black)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _panel() => switch (_tab) {
        'dashboard' => DashboardPanel(
            stats: _dashStats,
            loading: _dashLoading,
            onSelectTab: (t) => setState(() => _tab = t),
            refetch: _fetchAnalytics,
          ),
        'modulos' => const FeatureFlagsPanel(),
        'solicitudes' => const RequestsPanel(),
        'usuarios' => UsersPanel(mode: UsersPanelMode.users, cities: _cities, venues: _venues),
        'roles' => UsersPanel(mode: UsersPanelMode.roles, cities: _cities, venues: _venues),
        'ciudades' => const CitiesPanel(),
        'facturacion' => const FinancePanel(),
        'locales' => const VenuesPanel(),
        'eventos' => EventsPanel(allUsers: _allUsers),
        'partners' => const PartnersPanel(),
        'tenants' => const TenantsPanel(),
        _ => const SizedBox.shrink(),
      };
}

num asNum(Object? v) => v is num ? v : 0;

/// The web's 403 page (gpp_bad icon + "403 Forbidden" + go-home button).
class ForbiddenScreen extends StatelessWidget {
  final String messageKey;
  const ForbiddenScreen({super.key, required this.messageKey});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF07080D),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.gpp_bad, size: 60, color: Tw.red500),
              const SizedBox(height: 16),
              Text('403 Forbidden', style: tw(30, weight: black)),
              const SizedBox(height: 8),
              Text(context.t(messageKey), textAlign: TextAlign.center, style: tw(15, color: Tw.slate400)),
              const SizedBox(height: 24),
              AdminButton(
                label: context.t('super_admin_go_home'),
                color: Tw.w(0.1),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                onTap: () => openRoute(context, AppRoute.home),
              ),
            ]),
          ),
        ),
      );
}
