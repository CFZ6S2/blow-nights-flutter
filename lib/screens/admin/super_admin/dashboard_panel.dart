import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

/// Port of features/super-admin/DashboardOverview.tsx
class DashboardPanel extends StatefulWidget {
  final Map<String, dynamic>? stats;
  final bool loading;
  final ValueChanged<String> onSelectTab;
  final Future<void> Function() refetch;
  const DashboardPanel({super.key, required this.stats, required this.loading, required this.onSelectTab, required this.refetch});

  @override
  State<DashboardPanel> createState() => _DashboardPanelState();
}

class _DashboardPanelState extends State<DashboardPanel> {
  bool _purging = false;

  @override
  void initState() {
    super.initState();
    // Refetch when the dashboard tab mounts so metrics are synchronized.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.refetch());
  }

  Future<void> _purgePromoters() async {
    final ok = await confirmDialog(context,
        message: context.t('super_admin.confirm_purge_promoters'),
        danger: true,
        confirmText: context.t('super_admin.confirm_purge_btn'));
    if (!ok || !mounted) return;
    setState(() => _purging = true);
    try {
      final res = await callFn('adminDeleteAllPromoters');
      if (mounted) showToast(context, context.read<I18n>().t('super_admin.purged_promoters_success', count: (res['count'] as num?)?.toInt() ?? 0));
      await widget.refetch();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e, context.read<I18n>().t('super_admin.error_purging')), error: true);
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return AdminEmpty(context.t('super_admin.metrics_loading'), loading: true);
    final s = widget.stats;
    if (s == null) return AdminEmpty(context.t('super_admin.metrics_error'));

    int n(String k) => (s[k] as num?)?.toInt() ?? 0;
    final fmt = NumberFormat.decimalPattern(context.read<I18n>().locale.languageCode);
    final total = n('totalUsers');
    double ratio(int v) => total > 0 ? v / total * 100 : 0;

    final tiles = [
      (context.t('super_admin.users_stat'), n('totalUsers'), Icons.people, Tw.fuchsia400, false),
      (context.t('super_admin.online_now_stat'), n('onlineUsers'), Icons.circle, Tw.green400, false),
      (context.t('super_admin.premium_stat'), n('premiumUsers'), Icons.star, Tw.yellow400, false),
      (context.t('super_admin.venues_stat'), n('totalVenues'), Icons.storefront, Tw.indigo400, false),
      (context.t('super_admin.cities_stat'), n('totalCities'), Icons.location_city, Tw.blue400, false),
      (context.t('super_admin.promoters_stat'), n('totalPromoters'), Icons.badge, Tw.purple400, true),
      (context.t('super_admin.pending_partners_stat'), n('pendingPartnerApps'), Icons.pending, Tw.orange400, false),
      (context.t('super_admin.pending_rrpp_stat'), n('pendingRrppApps'), Icons.pending_actions, Tw.amber400, false),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminGrid(children: [
        for (final (label, value, icon, color, purgeable) in tiles)
          AdminStat(
            label: label,
            value: fmt.format(value),
            icon: icon,
            color: color,
            trailing: purgeable && value > 0
                ? GestureDetector(
                    onTap: _purging ? null : _purgePromoters,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Tw.red500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                      child: Text(_purging ? '...' : context.t('super_admin.purge_btn'), style: tw(10, weight: bold, color: Tw.red400)),
                    ),
                  )
                : null,
          ),
      ]),
      if (n('pendingReports') > 0 || n('pendingVerifications') > 0) ...[
        const SizedBox(height: 24),
        AdminCard(
          radius: 16,
          padding: const EdgeInsets.all(20),
          color: Tw.red500.withValues(alpha: 0.1),
          borderColor: Tw.red500.withValues(alpha: 0.3),
          child: Row(children: [
            const Icon(Icons.warning, color: Tw.red400, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('super_admin.attention_required'), style: tw(15, weight: bold, color: Tw.red400)),
                Text(
                  [
                    if (n('pendingReports') > 0) context.t('super_admin.pending_reports_notice', count: n('pendingReports')),
                    if (n('pendingVerifications') > 0)
                      context.t('super_admin.pending_verifications_notice', count: n('pendingVerifications')),
                  ].join(' '),
                  style: tw(14, color: Tw.slate400),
                ),
              ]),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 24),
      AdminCard(
        radius: 16,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(context.t('super_admin.platform_summary'), size: 13),
          const SizedBox(height: 16),
          _ratio(context.t('super_admin.online_ratio'), ratio(n('onlineUsers')), Tw.green500),
          const SizedBox(height: 12),
          _ratio(context.t('super_admin.premium_ratio'), ratio(n('premiumUsers')), Tw.yellow500),
        ]),
      ),
      const SizedBox(height: 24),
      AdminCard(
        radius: 16,
        color: Tw.slate900,
        borderColor: Tw.fuchsia500.withValues(alpha: 0.2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Label(context.t('super_admin.modules_control'), size: 13, color: Tw.fuchsia400)),
            Pressable(
              onTap: () => widget.onSelectTab('modulos'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Tw.fuchsia500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.2)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.tune, size: 12, color: Tw.fuchsia400),
                  const SizedBox(width: 4),
                  Label(context.t('super_admin.open_modules_panel'), color: Tw.fuchsia400, tracking: 0.05),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
            child: Row(children: [
              const PulseDot(color: Tw.emerald400),
              const SizedBox(width: 8),
              Expanded(child: Text(context.t('super_admin.granular_management'), style: tw(12, weight: medium, color: Tw.slate300))),
              Flexible(child: Label(context.t('super_admin.ticketing_cashless_sub'), tracking: 0.05, align: TextAlign.end)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 24),
      AdminCard(
        radius: 16,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(context.t('super_admin.quick_actions'), size: 13),
          const SizedBox(height: 16),
          AdminGrid(children: [
            _quick(Icons.handshake, Tw.orange400, '${context.t('super_admin.quick_requests')} (${n('pendingPartnerApps') + n('pendingRrppApps')})', 'solicitudes'),
            _quick(Icons.storefront, Tw.indigo400, '${context.t('super_admin.quick_venues')} (${n('totalVenues')})', 'locales'),
            _quick(Icons.people, Tw.blue400, '${context.t('super_admin.quick_users')} (${n('totalUsers')})', 'usuarios'),
            _quick(Icons.location_city, Tw.green400, '${context.t('super_admin.quick_cities')} (${n('totalCities')})', 'ciudades'),
          ]),
        ]),
      ),
    ]);
  }

  Widget _ratio(String label, double pct, Color color) => Column(children: [
        Row(children: [
          Expanded(child: Text(label, style: tw(14, color: Tw.slate400))),
          Text('${pct.toStringAsFixed(1)}%', style: tw(14, weight: bold)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0, 1),
            minHeight: 8,
            backgroundColor: Tw.w(0.05),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ]);

  Widget _quick(IconData icon, Color color, String label, String tab) => Pressable(
        onTap: () => widget.onSelectTab(tab),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(label, style: tw(12, weight: bold)),
          ]),
        ),
      );
}
