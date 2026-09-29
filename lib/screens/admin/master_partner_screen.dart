import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';

String centsToEur(num cents, [String locale = 'es']) =>
    NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 2).format(cents / 100);

class _CityRevenue {
  final String cityId, cityName;
  int totalCents = 0, partnerCents = 0, centralCents = 0, splitCount = 0;
  final Map<String, int> sources = {};
  _CityRevenue(this.cityId, this.cityName);
}

class _MpData {
  final int totalRevenueCents, partnerBlockCents, centralBlockCents, mpMarginCents, agentFundCents, splitCount;
  final List<_CityRevenue> cities;
  final String periodLabel;
  const _MpData(this.totalRevenueCents, this.partnerBlockCents, this.centralBlockCents, this.mpMarginCents, this.agentFundCents,
      this.cities, this.periodLabel, this.splitCount);
}

const _months = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

/// Port of app/master-partner/page.tsx + features/master-partner/MasterPartnerDashboard.tsx and its hooks.
class MasterPartnerScreen extends StatefulWidget {
  const MasterPartnerScreen({super.key});

  @override
  State<MasterPartnerScreen> createState() => _MasterPartnerScreenState();
}

class _MasterPartnerScreenState extends State<MasterPartnerScreen> {
  final _db = FirebaseFirestore.instance;
  String _tab = 'overview';
  late String _month = DateFormat('yyyy-MM').format(DateTime.now());

  _MpData? _data;
  bool _loading = true;
  List<Map<String, dynamic>> _subAgents = [];
  bool _agentsLoading = true;
  String? _agentsError;
  List<Map<String, dynamic>> _venues = [];
  bool _venuesLoading = true;
  bool _started = false;

  bool _hasAccess(AuthProvider a) => (a.isMasterPartner && !a.isCityManager) || a.isSuperAdmin;

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
    if (auth.isCityManager) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openRoute(context, AppRoute.cityManager, replace: true);
      });
      return;
    }
    if (!_hasAccess(auth)) return;
    _fetchData();
    _fetchSubAgents();
    _fetchVenues();
  }

  String get _uid => context.read<AuthProvider>().user!.uid;

  // useMasterPartnerData
  Future<void> _fetchData() async {
    setState(() => _loading = true);
    try {
      final parts = _month.split('-').map(int.parse).toList();
      final (year, month) = (parts[0], parts[1]);
      final start = DateTime(year, month);
      final end = DateTime(year, month + 1, 0, 23, 59, 59);
      final period = '${_months[month - 1]} $year';

      final cities = await _db.collection('cities').get();
      final mine = [
        for (final d in cities.docs)
          if (d.data()['masterPartnerId'] == _uid || d.data()['partnerId'] == _uid) _CityRevenue(d.id, (d.data()['name'] as String?) ?? d.id),
      ];
      if (mine.isEmpty) {
        setState(() => _data = _MpData(0, 0, 0, 0, 0, const [], period, 0));
        return;
      }
      final byId = {for (final c in mine) c.cityId: c};
      final splits = await _db
          .collection('territorial_splits')
          .where('masterPartnerId', isEqualTo: _uid)
          .where('status', isEqualTo: 'completed')
          .orderBy('timestamp', descending: true)
          .get();
      var total = 0, partner = 0, central = 0, count = 0;
      for (final doc in splits.docs) {
        final d = doc.data();
        final city = byId[d['cityId']];
        if (city == null) continue;
        final ts = parseDate(d['timestamp']);
        if (ts != null && (ts.isBefore(start) || ts.isAfter(end))) continue;
        final amount = (d['amountCents'] as num?)?.toInt() ?? 0;
        final payouts = (d['payouts'] as List?)?.whereType<Map>() ?? const <Map>[];
        final cm = (payouts.where((p) => p['role'] == 'city_manager').firstOrNull?['amountCents'] as num?)?.toInt() ?? 0;
        final ce = (payouts.where((p) => p['role'] == 'central').firstOrNull?['amountCents'] as num?)?.toInt() ?? 0;
        city.totalCents += amount;
        city.partnerCents += cm;
        city.centralCents += ce;
        city.splitCount++;
        final source = (d['sourceType'] as String?) ?? 'other';
        city.sources[source] = (city.sources[source] ?? 0) + amount;
        total += amount;
        partner += cm;
        central += ce;
        count++;
      }
      final margin = (partner * (15 / 55)).round();
      mine.sort((a, b) => b.partnerCents - a.partnerCents);
      setState(() => _data = _MpData(total, partner, central, margin, partner - margin, mine, period, count));
    } catch (e) {
      debugPrint('Error fetching MP data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchSubAgents() async {
    setState(() {
      _agentsLoading = true;
      _agentsError = null;
    });
    try {
      final res = await callFn('listSubAgentsPerformance', {});
      final list = res['subAgents'];
      if (list is List) setState(() => _subAgents = [for (final a in list) Map<String, dynamic>.from(a as Map)]);
    } catch (e) {
      setState(() => _agentsError = errorMessage(e, 'Error al cargar subagentes.'));
    } finally {
      if (mounted) setState(() => _agentsLoading = false);
    }
  }

  Future<void> _fetchVenues() async {
    setState(() => _venuesLoading = true);
    try {
      final res = await callFn('listAttributedVenues', {});
      final list = res['venues'];
      if (list is List) setState(() => _venues = [for (final v in list) Map<String, dynamic>.from(v as Map)]);
    } catch (e) {
      debugPrint('Error fetching attributed venues: $e');
    } finally {
      if (mounted) setState(() => _venuesLoading = false);
    }
  }

  Future<void> _addSubAgent(Map<String, Object?> data) async {
    setState(() => _agentsError = null);
    try {
      await callFn('createSubAgent', data);
      await _fetchSubAgents();
    } catch (e) {
      final msg = errorMessage(e, 'Error al crear subagente.');
      setState(() => _agentsError = msg);
      throw Exception(msg);
    }
  }

  Future<void> _toggleSubAgent(String id, String status) async {
    setState(() => _agentsError = null);
    try {
      await callFn('toggleSubAgent', {'subAgentId': id, 'newStatus': status});
      await _fetchSubAgents();
    } catch (e) {
      setState(() => _agentsError = errorMessage(e, 'Error al cambiar estado del subagente.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loadingShell = const Scaffold(backgroundColor: Tw.slate950, body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)));
    if (auth.loading || auth.isCityManager) return loadingShell;
    if (!auth.isMasterPartner && !auth.isSuperAdmin) {
      return Scaffold(
        backgroundColor: Tw.slate950,
        body: Center(child: Text(context.t('admin.access_denied', fallback: 'Acceso no autorizado.'), style: tw(15, color: Tw.slate400))),
      );
    }
    if (!_hasAccess(auth)) {
      return Scaffold(
        backgroundColor: Tw.slate950,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(context.t('master_partner.access_restricted'), style: tw(24, weight: black)),
            const SizedBox(height: 8),
            Text(context.t('master_partner.access_restricted_desc'), style: tw(15, color: Tw.slate400)),
          ]),
        ),
      );
    }
    final data = _data;
    if (_loading || data == null) return loadingShell;

    final locale = context.read<I18n>().locale.languageCode;
    final top = MediaQuery.of(context).padding.top;
    final tabs = [
      ('overview', context.t('master_partner.tab_overview')),
      ('cities', context.t('master_partner.tab_cities')),
      ('team', context.t('master_partner.tab_team')),
      ('pipeline', context.t('master_partner.tab_pipeline', fallback: 'Pipeline')),
      ('transparency', context.t('master_partner.tab_transparency')),
    ];

    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(8, top + 8, 16, 0),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), border: Border(bottom: BorderSide(color: Tw.w(0.1)))),
          child: Column(children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('master_partner.title'), style: tw(20, weight: black)),
                  Text(context.t('master_partner.subtitle'), style: tw(12, color: Tw.slate400)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: AdminSelect<String>(
                dense: true,
                value: _month,
                items: [
                  for (var i = 0; i < 12; i++)
                    () {
                      final now = DateTime.now();
                      final d = DateTime(now.year, now.month - i);
                      return (DateFormat('yyyy-MM').format(d), DateFormat.yMMMM(locale).format(d));
                    }(),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _month = v);
                  _fetchData();
                },
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (id, label) in tabs)
                  GestureDetector(
                    onTap: () => setState(() => _tab = id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: _tab == id ? Tw.w(0.1) : Colors.transparent,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        border: _tab == id ? const Border(bottom: BorderSide(color: Tw.fuchsia500, width: 2)) : null,
                      ),
                      child: Text(label, style: tw(14, weight: bold, color: _tab == id ? Tw.fuchsia400 : Tw.slate500)),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 40 + MediaQuery.of(context).padding.bottom),
            children: [
              Text(data.periodLabel, style: tw(14, color: Tw.slate400)),
              const SizedBox(height: 24),
              switch (_tab) {
                'cities' => _citiesTab(context, data, locale),
                'team' => _teamTab(context, data),
                'pipeline' => _PipelineView(venues: _venues, loading: _venuesLoading, subAgents: _subAgents),
                'transparency' => _transparencyTab(context, data, locale),
                _ => _overviewTab(context, data, locale),
              },
            ],
          ),
        ),
      ]),
    );
  }

  Widget _statCard(String title, String value, String subtitle, Color color) => AdminCard(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
          Color.alphaBlend(color.withValues(alpha: 0.25), Tw.black).withValues(alpha: 0.4),
          Tw.black,
        ]),
        borderColor: color.withValues(alpha: 0.3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(title, size: 12, weight: bold, color: color),
          const SizedBox(height: 8),
          Text.rich(TextSpan(children: [
            TextSpan(text: '$value ', style: tw(28, weight: black).copyWith(fontFamily: 'monospace')),
            TextSpan(text: '€', style: tw(18, color: color)),
          ])),
          const SizedBox(height: 8),
          Text(subtitle, style: tw(10, color: Tw.slate400)),
        ]),
      );

  Widget _overviewTab(BuildContext context, _MpData d, String locale) {
    final maxCents = d.cities.fold<int>(1, (m, c) => c.partnerCents > m ? c.partnerCents : m);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _statCard(context.t('master_partner.total_revenue'), centsToEur(d.totalRevenueCents, locale),
          context.t('master_partner.operations_count', count: d.splitCount), Tw.fuchsia400),
      const SizedBox(height: 16),
      _statCard(context.t('master_partner.partner_block'), centsToEur(d.partnerBlockCents, locale),
          context.t('master_partner.partner_block_subtitle'), Tw.green400),
      const SizedBox(height: 16),
      _statCard(context.t('master_partner.mp_margin'), centsToEur(d.mpMarginCents, locale), context.t('master_partner.mp_margin_subtitle'), Tw.blue400),
      const SizedBox(height: 16),
      _statCard(context.t('master_partner.agent_fund'), centsToEur(d.agentFundCents, locale), context.t('master_partner.agent_fund_subtitle'), Tw.amber400),
      if (d.cities.isNotEmpty) ...[
        const SizedBox(height: 32),
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AdminSectionTitle(context.t('master_partner.city_ranking')),
            const SizedBox(height: 24),
            for (final c in d.cities)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  SizedBox(width: 90, child: Text(c.cityName, overflow: TextOverflow.ellipsis, style: tw(14, weight: bold))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        height: 16,
                        color: Colors.black.withValues(alpha: 0.3),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: c.partnerCents / maxCents,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.fuchsia400]),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${centsToEur(c.partnerCents, locale)} €', style: tw(13, color: Tw.green400).copyWith(fontFamily: 'monospace')),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }

  Widget _citiesTab(BuildContext context, _MpData d, String locale) {
    if (d.cities.isEmpty) return AdminEmpty(context.t('master_partner.no_cities'));
    final sourceLabels = {
      'ticket': context.t('master_partner.source_ticketing'),
      'subscription': context.t('master_partner.source_saas'),
      'qr': context.t('master_partner.source_qr'),
      'vip': context.t('master_partner.source_vip'),
      'other': context.t('master_partner.source_other'),
    };
    Widget figure(String label, String value, Color labelColor, Color valueColor) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label(label, color: labelColor, weight: FontWeight.w400),
            Text(value, style: tw(20, weight: black, color: valueColor).copyWith(fontFamily: 'monospace')),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final c in d.cities) ...[
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(c.cityName, style: tw(18, weight: black))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Tw.fuchsia500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                child: Text('${c.splitCount} ${context.t('master_partner.ops')}', style: tw(12, color: Tw.fuchsia300).copyWith(fontFamily: 'monospace')),
              ),
            ]),
            const SizedBox(height: 16),
            figure(context.t('master_partner.total_income'), centsToEur(c.totalCents, locale), Tw.slate500, Tw.white),
            figure(context.t('master_partner.your_block'), centsToEur(c.partnerCents, locale), Tw.green500, Tw.green400),
            figure(context.t('master_partner.central_block'), centsToEur(c.centralCents, locale), Tw.slate500, Tw.slate400),
            if (c.sources.isNotEmpty) ...[
              Divider(height: 1, color: Tw.w(0.05)),
              const SizedBox(height: 12),
              Label(context.t('master_partner.by_source'), color: Tw.slate500, weight: FontWeight.w400),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in c.sources.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8), border: Border.all(color: Tw.w(0.05))),
                    child: Text('${sourceLabels[e.key] ?? e.key}: ${centsToEur(e.value, locale)}€', style: tw(12).copyWith(fontFamily: 'monospace')),
                  ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 24),
      ],
    ]);
  }

  Widget _teamTab(BuildContext context, _MpData d) {
    final active = _subAgents.where((a) => a['status'] == 'active').length;
    final totalVenues = _subAgents.fold<int>(0, (acc, a) => acc + ((a['venuesCaptured'] as num?)?.toInt() ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _AddSubAgentForm(cities: d.cities, onSubmit: _addSubAgent),
      if (_agentsError != null) ...[
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Tw.red500.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Tw.red500.withValues(alpha: 0.3)),
          ),
          child: Text(_agentsError!, style: tw(12, color: Tw.red400)),
        ),
      ],
      const SizedBox(height: 24),
      if (_agentsLoading)
        const AdminEmpty('', loading: true)
      else if (_subAgents.isEmpty)
        AdminCard(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          borderColor: Tw.w(0.05),
          child: Column(children: [
            Text(context.t('master_partner.no_subagents_title', fallback: 'Aún no tienes subagentes comerciales'),
                textAlign: TextAlign.center, style: tw(18, weight: bold)),
            const SizedBox(height: 8),
            Text(
              context.t('master_partner.no_subagents_desc',
                  fallback:
                      'Genera códigos y enlaces personalizados para tu equipo de comerciales de calle. Cada local captado quedará atribuido de forma inmutable a tu cuenta y a su subagente.'),
              textAlign: TextAlign.center,
              style: tw(14, color: Tw.slate500),
            ),
          ]),
        )
      else ...[
        Label(
          '${context.t('master_partner.network_title', fallback: 'Tu Red Comercial')} (${context.t('master_partner.network_active_count', fallback: '{{active}} activos / {{total}} total', params: {'active': active, 'total': _subAgents.length})})',
          size: 13,
          color: Tw.slate300,
        ),
        const SizedBox(height: 4),
        Text.rich(TextSpan(style: tw(12, color: Tw.slate500), children: [
          TextSpan(text: '${context.t('master_partner.total_venues_label', fallback: 'Total Venues:')} '),
          TextSpan(text: '$totalVenues', style: tw(12, weight: bold)),
        ])),
        const SizedBox(height: 12),
        for (final a in _subAgents) _SubAgentCard(agent: a, onToggle: _toggleSubAgent),
      ],
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Tw.amber500.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Tw.amber500.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(context.t('master_partner.blackbox_title', fallback: 'Principio de Caja Negra & Liquidación Territorial'), size: 12, weight: bold, color: Tw.amber500),
          const SizedBox(height: 8),
          Text(
            context.t('master_partner.blackbox_text',
                fallback:
                    'Blow Nights liquida el split territorial (50/50) íntegramente a tu cuenta de Stripe Connect. Los acuerdos, porcentajes y pagos internos con tus subagentes o comerciales de calle dependen exclusivamente de ti como Master Partner de la plaza.'),
            style: tw(14, color: Tw.slate300, height: 1.6),
          ),
        ]),
      ),
    ]);
  }

  Widget _transparencyTab(BuildContext context, _MpData d, String locale) {
    Widget block(String label, int cents, Color color) {
      final pct = d.totalRevenueCents > 0 ? cents / d.totalRevenueCents * 100 : 0.0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(label, style: tw(14, weight: bold, color: color))),
            Text('${pct.toStringAsFixed(1)}%', style: tw(10, color: Tw.slate500)),
            const SizedBox(width: 12),
            Text('${centsToEur(cents, locale)} €', style: tw(14, weight: bold).copyWith(fontFamily: 'monospace')),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1),
              minHeight: 24,
              backgroundColor: Colors.black.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation(color == Tw.fuchsia400 ? Tw.fuchsia500 : color == Tw.blue400 ? Tw.blue500 : Tw.amber500),
            ),
          ),
        ]),
      );
    }

    Widget explainer(String pct, String title, String desc, Color color) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pct, style: tw(30, weight: black, color: color)),
            const SizedBox(height: 4),
            Text(title, style: tw(14, weight: bold)),
            const SizedBox(height: 8),
            Text(desc, style: tw(12, color: Tw.slate400)),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminCard(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle(context.t('master_partner.revenue_breakdown')),
          const SizedBox(height: 8),
          Text(context.t('master_partner.revenue_breakdown_desc', params: {'amount': centsToEur(d.totalRevenueCents, locale)}),
              style: tw(12, color: Tw.slate500)),
          const SizedBox(height: 32),
          block(context.t('master_partner.central_label'), d.centralBlockCents, Tw.fuchsia400),
          block(context.t('master_partner.your_margin_label'), d.mpMarginCents, Tw.blue400),
          block(context.t('master_partner.agent_fund_label'), d.agentFundCents, Tw.amber400),
        ]),
      ),
      const SizedBox(height: 32),
      AdminCard(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle(context.t('master_partner.how_it_works')),
          const SizedBox(height: 24),
          explainer(context.t('master_partner.central_pct'), context.t('master_partner.central_title'), context.t('master_partner.central_desc'), Tw.fuchsia400),
          explainer(context.t('master_partner.mp_pct'), context.t('master_partner.mp_title'), context.t('master_partner.mp_desc'), Tw.blue400),
          explainer(context.t('master_partner.agent_pct'), context.t('master_partner.agent_title'), context.t('master_partner.agent_desc'), Tw.amber400),
        ]),
      ),
      const SizedBox(height: 32),
      AdminCard(
        color: Tw.green500.withValues(alpha: 0.05),
        borderColor: Tw.green500.withValues(alpha: 0.2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(context.t('master_partner.note_title'), size: 12, weight: bold, color: Tw.green500),
          const SizedBox(height: 8),
          Text(context.t('master_partner.note_text'), style: tw(14, color: Tw.slate300)),
        ]),
      ),
    ]);
  }
}

class _AddSubAgentForm extends StatefulWidget {
  final List<_CityRevenue> cities;
  final Future<void> Function(Map<String, Object?> data) onSubmit;
  const _AddSubAgentForm({required this.cities, required this.onSubmit});

  @override
  State<_AddSubAgentForm> createState() => _AddSubAgentFormState();
}

class _AddSubAgentFormState extends State<_AddSubAgentForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _suffix = TextEditingController();
  late String _city = widget.cities.firstOrNull?.cityId ?? '';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _suffix.dispose();
    super.dispose();
  }

  String get _preview {
    final city = _city.toUpperCase();
    if (_suffix.text.trim().isNotEmpty) return 'MP_${city}_${_suffix.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_]'), '')}';
    if (_name.text.trim().isNotEmpty) {
      final n = _name.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      return 'MP_${city}_${n.length > 10 ? n.substring(0, 10) : n}';
    }
    return 'MP_${city}_...';
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit({
        'displayName': _name.text.trim(),
        'phone': _phone.text.trim(),
        if (_suffix.text.trim().isNotEmpty) 'codeSuffix': _suffix.text.trim().toUpperCase(),
        'cityId': _city,
        'notes': '',
      });
      _name.clear();
      _phone.clear();
      _suffix.clear();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 4, top: 12), child: Label(t, weight: bold));

  @override
  Widget build(BuildContext context) => AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle(context.t('master_partner.add_agent', fallback: 'Crear Nuevo Subagente Comercial')),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Tw.fuchsia500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
              ),
              child: Text('${context.t('master_partner.code_preview', fallback: 'Código previsto:')} $_preview',
                  style: tw(12, color: Tw.fuchsia300).copyWith(fontFamily: 'monospace')),
            ),
          ),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Tw.red500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.red500.withValues(alpha: 0.3)),
              ),
              child: Text(_error!, style: tw(12, color: Tw.red400)),
            ),
          _label(context.t('master_partner.label_display_name', fallback: 'Nombre Comercial')),
          AdminInput(controller: _name, hint: 'Ej: Juan Pérez'),
          _label(context.t('master_partner.label_phone', fallback: 'Teléfono / WhatsApp')),
          AdminInput(controller: _phone, hint: '+34 600...', keyboardType: TextInputType.phone),
          _label(context.t('master_partner.label_city', fallback: 'Ciudad Asignada')),
          AdminSelect<String>(
            value: _city,
            items: widget.cities.isEmpty
                ? [('', context.t('master_partner.no_cities'))]
                : [for (final c in widget.cities) (c.cityId, c.cityName)],
            onChanged: (v) => setState(() => _city = v ?? _city),
          ),
          _label(context.t('master_partner.label_code_suffix', fallback: 'Sufijo del Código (Opcional)')),
          TextField(
            controller: _suffix,
            style: tw(14).copyWith(fontFamily: 'monospace'),
            decoration: adminInputDecoration('JUAN (O auto)'),
            onChanged: (v) {
              final clean = v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_]'), '');
              if (clean != v) _suffix.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: AdminButton(
              label: _saving ? context.t('master_partner.saving', fallback: 'Creando...') : context.t('master_partner.add_agent_btn', fallback: '+ Generar Subagente y Enlace'),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              onTap: _saving || _name.text.trim().isEmpty ? null : _submit,
            ),
          ),
        ]),
      );
}

class _SubAgentCard extends StatefulWidget {
  final Map<String, dynamic> agent;
  final void Function(String id, String status) onToggle;
  const _SubAgentCard({required this.agent, required this.onToggle});

  @override
  State<_SubAgentCard> createState() => _SubAgentCardState();
}

class _SubAgentCardState extends State<_SubAgentCard> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.agent;
    final code = (a['code'] as String?) ?? '';
    final url = '$webBase/business/login?ref=$code';
    final active = a['status'] == 'active';
    final last = a['lastVenueAttributedAt'] is String ? DateTime.tryParse(a['lastVenueAttributedAt'] as String) : null;
    final mrr = a['estimatedMrr'] ?? a['attributedMrr'] ?? 0;

    Widget stat(Object value, String label, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
            child: Column(children: [
              Text('$value', style: tw(16, weight: black, color: color).copyWith(fontFamily: 'monospace')),
              Label(label, size: 9, weight: bold, color: Tw.slate500, align: TextAlign.center, maxLines: 1),
            ]),
          ),
        );

    return Opacity(
      opacity: active ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: active ? Tw.w(0.1) : Tw.w(0.05))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text((a['displayName'] as String?) ?? '', style: tw(16, weight: black)),
            AdminBadge(active ? context.t('master_partner.active', fallback: 'Activo') : context.t('master_partner.inactive', fallback: 'Inactivo'),
                color: active ? Tw.green400 : Tw.red400),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Tw.fuchsia500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
              child: Text(code, style: tw(12, weight: bold, color: Tw.fuchsia300).copyWith(fontFamily: 'monospace')),
            ),
          ]),
          const SizedBox(height: 6),
          Text.rich(TextSpan(style: tw(12, color: Tw.slate500), children: [
            const TextSpan(text: 'Ciudad: '),
            TextSpan(text: ((a['cityId'] as String?) ?? '').toUpperCase(), style: tw(12, weight: semibold, color: Tw.slate300)),
            if ((a['phone'] as String?)?.isNotEmpty == true) TextSpan(text: ' · Tel: ${a['phone']}'),
            if (last != null) TextSpan(text: ' · Última captación: ${last.day}/${last.month}/${last.year}'),
          ])),
          const SizedBox(height: 12),
          Row(children: [
            stat(a['venuesCaptured'] ?? 0, context.t('master_partner.stat_captured', fallback: 'Captados'), Tw.fuchsia400),
            const SizedBox(width: 8),
            stat(a['activeVenues'] ?? 0, context.t('master_partner.stat_active', fallback: 'Activos'), Tw.green400),
            const SizedBox(width: 8),
            stat('$mrr €', context.t('master_partner.stat_mrr', fallback: 'MRR Estimado'), Tw.amber400),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AdminButton(
              label: _copied ? '✓ ${context.t('master_partner.copied_btn', fallback: '¡Copiado!')}' : context.t('master_partner.copy_link_btn', fallback: 'Copiar Enlace'),
              color: Tw.fuchsia400,
              outlined: true,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: url));
                setState(() => _copied = true);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _copied = false);
                });
              },
            ),
            AdminButton(
              icon: Icons.qr_code_2,
              label: 'QR',
              color: Tw.w(0.1),
              onTap: () => showDialog(context: context, builder: (_) => _QrDialog(url: url, agentName: (a['displayName'] as String?) ?? '', code: code)),
            ),
            AdminButton(
              label: context.t('master_partner.share_whatsapp', fallback: 'WhatsApp'),
              color: Tw.green400,
              outlined: true,
              onTap: () {
                final msg = context.read<I18n>().t('master_partner.whatsapp_venue_invite',
                    fallback:
                        'Hola, te comparto el enlace oficial para dar de alta tu local en Blow Nights. Desde ahí podrás crear tu perfil de venue y acceder a las herramientas de eventos, promoción y ticketing:');
                launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent('$msg\n$url')}'), mode: LaunchMode.externalApplication);
              },
            ),
            AdminButton(
              label: active ? context.t('master_partner.deactivate', fallback: 'Desactivar') : context.t('master_partner.activate', fallback: 'Activar'),
              color: Tw.slate500,
              outlined: true,
              onTap: () => widget.onToggle(a['id'] as String, active ? 'inactive' : 'active'),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// QR modal with PNG (1024px, white, code caption) and SVG exports, shared through the system sheet.
class _QrDialog extends StatelessWidget {
  final String url, agentName, code;
  const _QrDialog({required this.url, required this.agentName, required this.code});

  Future<void> _sharePng() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1024, 1024), Paint()..color = Colors.white);
    canvas.save();
    canvas.translate(64, 64);
    QrPainter(data: url, version: QrVersions.auto, errorCorrectionLevel: QrErrorCorrectLevel.H).paint(canvas, const Size(896, 896));
    canvas.restore();
    final tp = TextPainter(
      text: TextSpan(text: code, style: const TextStyle(color: Colors.black, fontSize: 32, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(512 - tp.width / 2, 1000 - tp.height));
    final image = await recorder.endRecording().toImage(1024, 1024);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${(await getTemporaryDirectory()).path}/qr-$code.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')]));
  }

  Future<void> _shareSvg() async {
    final qr = QrImage(QrCode.fromData(data: url, errorCorrectLevel: QrErrorCorrectLevel.H));
    final n = qr.moduleCount;
    final rects = StringBuffer();
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (qr.isDark(r, c)) rects.write('<rect x="$c" y="$r" width="1" height="1"/>');
      }
    }
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-4 -4 ${n + 8} ${n + 12}" width="256" height="${(256 * (n + 12) / (n + 8)).round()}">'
        '<rect x="-4" y="-4" width="${n + 8}" height="${n + 12}" fill="#fff"/><g fill="#000">$rects</g>'
        '<text x="${n / 2}" y="${n + 5}" text-anchor="middle" font-size="3" font-family="system-ui, sans-serif" font-weight="bold">$code</text></svg>';
    final file = File('${(await getTemporaryDirectory()).path}/qr-$code.svg');
    await file.writeAsString(svg);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/svg+xml')]));
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Tw.slate900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Tw.w(0.1))),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(context.t('master_partner.qr_title', fallback: 'Código QR'), style: tw(18, weight: black))),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t('master_partner.close', fallback: 'Cerrar'), style: tw(14, color: Tw.slate500)),
              ),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(16)),
              child: Center(child: QrImageView(data: url, size: 220, padding: EdgeInsets.zero, errorCorrectionLevel: QrErrorCorrectLevel.H)),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(style: tw(12, color: Tw.slate400), children: [
                TextSpan(text: '$agentName · '),
                TextSpan(text: code, style: tw(12, color: Tw.fuchsia300).copyWith(fontFamily: 'monospace')),
              ]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: AdminButton(
                  label: context.t('master_partner.download_png', fallback: 'Descargar PNG'),
                  expand: true,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onTap: _sharePng,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminButton(
                  label: context.t('master_partner.download_svg', fallback: 'Descargar SVG'),
                  color: Tw.w(0.1),
                  expand: true,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onTap: _shareSvg,
                ),
              ),
            ]),
          ]),
        ),
      );
}

const _lifecycle = {
  'captured': ('Captado', Tw.blue400, Tw.blue500, Icons.person_add),
  'trialing': ('En Prueba', Tw.amber400, Tw.amber500, Icons.hourglass_top),
  'active_subscription': ('Suscripción Activa', Tw.green400, Tw.green500, Icons.verified),
  'churned': ('Churn / Cancelado', Tw.red400, Tw.red500, Icons.cancel),
};

class _PipelineView extends StatefulWidget {
  final List<Map<String, dynamic>> venues;
  final bool loading;
  final List<Map<String, dynamic>> subAgents;
  const _PipelineView({required this.venues, required this.loading, required this.subAgents});

  @override
  State<_PipelineView> createState() => _PipelineViewState();
}

class _PipelineViewState extends State<_PipelineView> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const AdminEmpty('', loading: true);
    final counts = {for (final k in _lifecycle.keys) k: widget.venues.where((v) => v['lifecycle'] == k).length};
    final total = widget.venues.length;
    final agentNames = {for (final a in widget.subAgents) a['id']: a['displayName']};
    final filtered = _filter == 'all' ? widget.venues : widget.venues.where((v) => v['lifecycle'] == _filter).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminGrid(children: [
        for (final e in _lifecycle.entries)
          Pressable(
            onTap: () => setState(() => _filter = _filter == e.key ? 'all' : e.key),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _filter == e.key ? e.value.$3.withValues(alpha: 0.2) : Tw.w(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _filter == e.key ? e.value.$3.withValues(alpha: 0.3) : Tw.w(0.1)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(e.value.$4, size: 18, color: e.value.$2),
                const SizedBox(height: 8),
                Text('${counts[e.key]}', style: tw(24, weight: black, color: e.value.$2).copyWith(fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Label(context.t('master_partner.lifecycle_${e.key}', fallback: e.value.$1), weight: bold, maxLines: 2),
              ]),
            ),
          ),
      ]),
      if (total > 0) ...[
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 12,
            child: Row(children: [
              for (final e in _lifecycle.entries)
                if (counts[e.key]! > 0) Expanded(flex: counts[e.key]!, child: Container(color: e.value.$3)),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 32),
      if (filtered.isEmpty)
        AdminCard(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          borderColor: Tw.w(0.05),
          child: Column(children: [
            const Icon(Icons.storefront, size: 40, color: Tw.slate600),
            const SizedBox(height: 12),
            Text(context.t('master_partner.no_venues_title', fallback: 'Sin venues atribuidos'), style: tw(18, weight: bold)),
            const SizedBox(height: 8),
            Text(
              context.t('master_partner.no_venues_desc',
                  fallback: 'Los venues captados por tus subagentes aparecerán aquí con su estado de suscripción.'),
              textAlign: TextAlign.center,
              style: tw(14, color: Tw.slate500),
            ),
          ]),
        )
      else
        for (final v in filtered) _venueRow(context, v, agentNames),
    ]);
  }

  Widget _venueRow(BuildContext context, Map<String, dynamic> v, Map<Object?, Object?> agentNames) {
    final cfg = _lifecycle[v['lifecycle']] ?? _lifecycle['captured']!;
    final attributed = v['attributedAt'] is String ? DateTime.tryParse(v['attributedAt'] as String) : null;
    final sub = v['subAgentId'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
      child: Row(children: [
        Icon(cfg.$4, size: 18, color: cfg.$2),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((v['name'] as String?) ?? '', overflow: TextOverflow.ellipsis, style: tw(14, weight: bold)),
            Text(
              [
                ((v['cityId'] as String?) ?? '').toUpperCase(),
                if (sub != null) '${agentNames[sub] ?? sub}',
                if (attributed != null) '${attributed.day}/${attributed.month}/${attributed.year}',
              ].join(' · '),
              style: tw(12, color: Tw.slate500),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: cfg.$3.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: cfg.$3.withValues(alpha: 0.3)),
                ),
                child: Label(context.t('master_partner.lifecycle_${v['lifecycle']}', fallback: cfg.$1), color: cfg.$2, weight: bold),
              ),
              if (v['subscriptionTier'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text('${v['subscriptionTier']}'.toUpperCase(), style: tw(10, color: Tw.slate300).copyWith(fontFamily: 'monospace')),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
