import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/city_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import '../tickets/wallet_screen.dart' show currencySymbol;

/// Roles allowed by useRequireRole(['cityAdmin', 'admin', 'superadmin', 'masterPartner']); others go home.
bool _allowed(String? role) => const ['cityAdmin', 'admin', 'superadmin', 'masterPartner'].contains(role);

/// Port of app/city-manager/page.tsx
class CityManagerScreen extends StatefulWidget {
  const CityManagerScreen({super.key});

  @override
  State<CityManagerScreen> createState() => _CityManagerScreenState();
}

class _CityManagerScreenState extends State<CityManagerScreen> {
  final _db = FirebaseFirestore.instance;
  bool _loading = true;
  Map<String, dynamic>? _city;
  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _applications = [];
  int _activeVenues = 0;
  int _gross = 0;
  int _users = 0;
  bool _started = false;

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
    if (!_allowed(auth.role)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
      return;
    }
    _fetch(auth);
  }

  Future<void> _fetch(AuthProvider auth) async {
    try {
      final uid = auth.user!.uid;
      final mine = await _db.collection('cities').where('partnerId', isEqualTo: uid).get();
      DocumentSnapshot<Map<String, dynamic>>? cityDoc;
      if (mine.docs.isNotEmpty) {
        cityDoc = mine.docs.first;
      } else if (auth.isSuperAdmin) {
        final all = await _db.collection('cities').get();
        if (all.docs.isNotEmpty) cityDoc = all.docs.first;
      }
      if (cityDoc == null) return;
      final city = <String, dynamic>{'id': cityDoc.id, ...?cityDoc.data()};

      final vSnap = await _db.collection('venues').where('cityId', isEqualTo: city['id']).get();
      var gross = 0, active = 0;
      final venues = <Map<String, dynamic>>[];
      for (final d in vSnap.docs) {
        final v = {'id': d.id, ...d.data()};
        venues.add(v);
        if (v['isActive'] == true) active++;
        gross += switch (v['subscriptionTier']) { 'ticketing' => 180, 'promo' => 100, 'basico' => 50, _ => 0 };
      }
      // Real earnings are read like the web does (not shown; the payout is the 50% MRR estimate).
      await _db.collection('cities').doc(city['id'] as String).collection('earnings').get();
      final uSnap = await _db.collection('users').where('cityId', isEqualTo: city['id']).get();
      final aSnap = await _db.collection('partner_applications').where('cityId', isEqualTo: city['id']).get();
      final apps = [
        for (final d in aSnap.docs)
          if (d.data()['status'] == 'pending' && d.data()['type'] == 'venue') {'id': d.id, ...d.data()},
      ];
      if (!mounted) return;
      setState(() {
        _city = city;
        _venues = venues;
        _applications = apps;
        _activeVenues = active;
        _gross = gross;
        _users = uSnap.size;
      });
    } catch (e) {
      debugPrint('Error cargando dashboard: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteVenue(String id, String name) async {
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context,
        message: i18n.t('city_manager.confirm_delete', params: {'name': name}), danger: true, confirmText: i18n.t('city_manager.delete_btn'))) {
      return;
    }
    try {
      await callFn('deleteVenue', {'venueId': id});
      setState(() => _venues.removeWhere((v) => v['id'] == id));
    } catch (_) {
      if (mounted) showToast(context, i18n.t('city_manager.action_error'), error: true);
    }
  }

  Future<void> _approve(Map<String, dynamic> app) async {
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context,
        message: i18n.t('city_manager.confirm_approve', params: {'name': app['name']}), confirmText: i18n.t('city_manager.approve_btn'))) {
      return;
    }
    try {
      final data = await callFn('approvePartnerAccess', {'applicationId': app['id'], 'action': 'approve'});
      if (mounted) showToast(context, (data['message'] as String?) ?? '');
      final link = data['passwordResetLink'];
      if (link is String) await Clipboard.setData(ClipboardData(text: link));
      setState(() => _applications.removeWhere((a) => a['id'] == app['id']));
    } catch (_) {
      if (mounted) showToast(context, i18n.t('city_manager.action_error'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading || _loading) {
      return const Scaffold(backgroundColor: Tw.slate950, body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)));
    }
    final city = _city;
    if (city == null) {
      return Scaffold(
        backgroundColor: Tw.slate950,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.warning, size: 64, color: Tw.yellow500),
              const SizedBox(height: 16),
              Text(context.t('city_manager_access_denied'), textAlign: TextAlign.center, style: tw(24, weight: bold)),
              const SizedBox(height: 8),
              Text(context.t('city_manager_no_franchise'), textAlign: TextAlign.center, style: tw(15, color: Tw.slate400)),
              const SizedBox(height: 32),
              AdminButton(
                label: context.t('city_manager_back_home'),
                color: Tw.w(0.1),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
              ),
            ]),
          ),
        ),
      );
    }

    final sym = currencySymbol(context.watch<CityProvider>().currency);
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, top + 12, 16, 12),
          decoration: const BoxDecoration(color: Tw.slate900, border: Border(bottom: BorderSide(color: Tw.slate800))),
          child: Row(children: [
            IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.fuchsia600, Tw.indigo600]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.2), blurRadius: 12)],
              ),
              child: const Icon(Icons.business, size: 20, color: Tw.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('city_manager_title'), style: tw(18, weight: black, height: 1)),
                Label((city['name'] ?? city['id']) as String, size: 12, weight: bold),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Tw.green500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Tw.green500.withValues(alpha: 0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const PulseDot(color: Tw.green500),
                const SizedBox(width: 6),
                Label(context.t('city_manager_active_license'), color: Tw.green400, tracking: 0.05),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 80 + MediaQuery.of(context).padding.bottom),
            children: [
              if (_applications.isNotEmpty) ...[_applicationsCard(context), const SizedBox(height: 40)],
              Label(context.t('city_manager_financial_metrics'), size: 13, color: Tw.slate500),
              const SizedBox(height: 16),
              AdminGrid(gap: 16, children: [
                _metric(context.t('city_manager.active_venues'), '$_activeVenues', context.t('city_manager.active_b2b_subs'), Icons.business),
                _metric(context.t('city_manager.local_users'), '$_users', context.t('city_manager.city_base_users'), Icons.group),
                _metric(context.t('city_manager.local_mrr'), '$_gross $sym', context.t('city_manager_saas_footer'), Icons.trending_up),
                _metric(context.t('city_manager.estimated_commission'), '${(_gross * 0.5).toStringAsFixed(2)} $sym',
                    '50% MRR ${context.t('city_manager.local_mrr')}', null,
                    highlight: true),
              ]),
              const SizedBox(height: 40),
              Row(children: [
                Expanded(child: Label(context.t('city_manager_venues_census'), size: 13, color: Tw.slate500)),
                AdminButton(
                  label: context.t('city_manager_copy_affiliate'),
                  color: Tw.fuchsia400,
                  outlined: true,
                  fontSize: 11,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: '$webBase/business?city=${city['id']}&ref=${auth.user?.uid}'));
                    if (context.mounted) showToast(context, context.read<I18n>().t('city_manager_affiliate_copied'));
                  },
                ),
              ]),
              const SizedBox(height: 16),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.slate800)),
                child: _venues.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(context.t('city_manager_no_venues'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
                      )
                    : Column(children: [
                        for (var i = 0; i < _venues.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: Tw.slate800.withValues(alpha: 0.5)),
                          _venueRow(context, _venues[i]),
                        ],
                      ]),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _applicationsCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.5), width: 2)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('💼', style: TextStyle(fontSize: 36)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(context.t('city_manager_pending_apps'), style: tw(20, weight: black, height: 1)),
              const SizedBox(height: 4),
              Text(context.t('city_manager_pending_apps_desc'), style: tw(14, color: Tw.slate400)),
              const SizedBox(height: 16),
              for (final app in _applications)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((app['name'] as String?) ?? '', style: tw(18, weight: bold)),
                    Text(((app['cityId'] as String?) ?? '').toUpperCase(), style: tw(12, weight: bold, color: Tw.fuchsia400)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, children: [
                      AdminBadge(context.t('city_manager_local_label'), color: Tw.fuchsia400),
                      AdminBadge(context.t('city_manager_pending_label'), color: Tw.yellow500),
                    ]),
                    const SizedBox(height: 8),
                    Text('📞 ${app['phone'] ?? ''} | ✉️ ${app['email'] ?? ''}', style: tw(14, color: Tw.slate300)),
                    if (app['venueName'] != null) Text('🍸 ${app['venueName']}', style: tw(14, weight: bold, color: Tw.fuchsia300)),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      AdminButton(label: context.t('city_manager_approve_venue'), onTap: () => _approve(app)),
                      AdminButton(
                        label: 'WhatsApp',
                        color: Tw.green600,
                        onTap: () => launchUrl(
                          Uri.parse('https://wa.me/${((app['phone'] as String?) ?? '').replaceAll(RegExp(r'\D'), '')}'
                              '?text=${Uri.encodeComponent('Hola ${app['name']}, te escribo desde Blow Nights...')}'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ]),
                  ]),
                ),
            ]),
          ),
        ]),
      );

  Widget _metric(String label, String value, String footer, IconData? icon, {bool highlight = false}) => Container(
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: highlight ? null : Tw.slate900,
          gradient: highlight
              ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.fuchsia900.withValues(alpha: 0.4), Tw.indigo900.withValues(alpha: 0.4)])
              : null,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: highlight ? Tw.fuchsia500.withValues(alpha: 0.2) : Tw.slate800),
        ),
        child: Stack(children: [
          if (icon != null) Positioned(top: -8, right: -8, child: Icon(icon, size: 72, color: Tw.w(0.05))),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: tw(13, weight: bold, color: highlight ? Tw.fuchsia300 : Tw.slate400)),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: tw(26, weight: black))),
            const SizedBox(height: 12),
            Divider(height: 1, color: highlight ? Tw.fuchsia500.withValues(alpha: 0.2) : Tw.slate800.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(footer, style: tw(11, weight: medium, color: highlight ? const Color(0x80F5D0FE) : Tw.slate500)),
          ]),
        ]),
      );

  Widget _venueRow(BuildContext context, Map<String, dynamic> v) {
    final tier = v['subscriptionTier'];
    final (tierLabel, tierColor) = switch (tier) {
      'ticketing' => ('TICKETING', Tw.indigo400),
      'promo' => ('PROMO', Tw.fuchsia400),
      'basico' => ('BÁSICO', Tw.blue400),
      _ => ('FREE', Tw.slate400),
    };
    final active = v['isActive'] == true;
    final created = parseDate(v['createdAt']) ?? DateTime.now();
    final type = (v['type'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(12)),
            child: (v['coverImage'] as String?)?.isNotEmpty == true
                ? NetImage(v['coverImage'] as String)
                : const Icon(Icons.business, size: 20, color: Tw.slate600),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((v['name'] as String?) ?? '', style: tw(15, weight: bold)),
              Text(
                '${context.t('city_manager_venue_type_$type', fallback: type)} • Creado el ${created.day}/${created.month}/${created.year}',
                style: tw(12, color: Tw.slate400),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: active ? Tw.green500.withValues(alpha: 0.1) : Tw.slate800, borderRadius: BorderRadius.circular(99)),
            child: Label(active ? context.t('city_manager_venue_active') : context.t('city_manager_venue_inactive'),
                size: 12, weight: bold, color: active ? Tw.green400 : Tw.slate400, tracking: 0.05),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: tier == null ? Tw.slate800 : tierColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
            child: Label(tierLabel, size: 12, weight: bold, color: tierColor, tracking: 0.05),
          ),
          AdminButton(
            label: context.t('city_manager_manage'),
            color: Tw.slate800,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            onTap: () => openRoute(context, AppRoute.venueAdmin),
          ),
          AdminButton(
            label: context.t('city_manager_delete'),
            color: Tw.red900.withValues(alpha: 0.5),
            textColor: Tw.red400,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            onTap: () => _deleteVenue(v['id'] as String, (v['name'] as String?) ?? ''),
          ),
        ]),
      ]),
    );
  }
}
