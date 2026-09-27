import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

/// Port of features/super-admin/RequestsPanel.tsx + hooks/useAdminRequests.ts
class RequestsPanel extends StatefulWidget {
  const RequestsPanel({super.key});

  @override
  State<RequestsPanel> createState() => _RequestsPanelState();
}

class _RequestsPanelState extends State<RequestsPanel> {
  List<Map<String, dynamic>> _venueApps = [];
  List<Map<String, dynamic>> _partnerApps = [];
  List<Map<String, dynamic>> _rrppApps = [];
  List<Map<String, dynamic>> _organizerApps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final db = FirebaseFirestore.instance;
    // Promise.allSettled: a failing query just yields an empty list.
    Future<List<Map<String, dynamic>>> rows(Query<Map<String, dynamic>> q) async {
      try {
        final s = await q.get();
        return [for (final d in s.docs) {'id': d.id, ...d.data()}];
      } catch (_) {
        return [];
      }
    }

    final r = await Future.wait([
      rows(db.collection('partner_applications').where('status', isEqualTo: 'pending').limit(100)),
      rows(db.collection('rrpp_applications').where('status', isEqualTo: 'pending').limit(100)),
      rows(db.collection('organizer_applications').where('status', isEqualTo: 'pending').limit(100)),
      rows(db.collection('cities').limit(100)),
    ]);
    final cities = r[3];
    final venues = <Map<String, dynamic>>[];
    final partners = <Map<String, dynamic>>[];
    for (final app in r[0]) {
      if (app['type'] == 'city_manager') {
        partners.add(app);
      } else if (app['type'] == 'venue') {
        final city = cities.where((c) => c['id'] == app['cityId']).firstOrNull;
        final hasManager = city != null && city['partnerId'] != null;
        if (!hasManager) venues.add(app);
      }
    }
    if (!mounted) return;
    setState(() {
      _venueApps = venues;
      _partnerApps = partners;
      _rrppApps = r[1];
      _organizerApps = r[2];
      _loading = false;
    });
  }

  Future<void> _processRequest(String id, String collection, String action) async {
    await callFn('processApplication', {'applicationId': id, 'collectionName': collection, 'action': action});
    await _fetch();
  }

  Future<void> _approvePartner(Map<String, dynamic> app, String name) async {
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context,
        message: i18n.t('requests.confirm_approve_partner', params: {'name': name}), confirmText: i18n.t('requests.approve_btn'))) {
      return;
    }
    try {
      final data = await callFn('approvePartnerAccess', {'applicationId': app['id'], 'action': 'approve'});
      final link = data['passwordResetLink'];
      if (link is String && link.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: link));
        if (mounted) showToast(context, i18n.t('requests.reset_link_copied', fallback: 'Link de acceso copiado al portapapeles'));
      } else if (mounted) {
        showToast(context, (data['message'] as String?) ?? i18n.t('requests.approve_success'));
      }
      await _fetch();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e, i18n.t('requests.approve_error')), error: true);
    }
  }

  Future<void> _rejectPartner(Map<String, dynamic> app, String name) async {
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context,
        message: i18n.t('requests.confirm_reject', params: {'name': name}), danger: true, confirmText: i18n.t('requests.reject_btn'))) {
      return;
    }
    try {
      await _processRequest(app['id'] as String, 'partner_applications', 'rejected');
      if (mounted) showToast(context, i18n.t('requests.partner_rejected_success', fallback: 'Solicitud rechazada'));
    } catch (_) {
      if (mounted) showToast(context, i18n.t('requests.reject_error', fallback: 'Error al rechazar'), error: true);
    }
  }

  Future<void> _rrpp(Map<String, dynamic> app, bool approve) async {
    final i18n = context.read<I18n>();
    final ok = await confirmDialog(context,
        message: approve
            ? i18n.t('requests.confirm_approve_rrpp', params: {'name': app['name']})
            : i18n.t('requests.confirm_reject', params: {'name': app['name']}),
        danger: !approve,
        confirmText: i18n.t(approve ? 'requests.approve_btn' : 'requests.reject_btn'));
    if (!ok) return;
    try {
      await callFn('approveRRPP', {'applicationId': app['id'], 'action': approve ? 'approve' : 'reject'});
      if (mounted) {
        showToast(context, approve ? i18n.t('requests.rrpp_approved_success') : i18n.t('requests.rrpp_rejected_success', fallback: 'Solicitud rechazada'));
      }
    } catch (_) {
      if (mounted) {
        showToast(context, approve ? i18n.t('requests.approve_error') : i18n.t('requests.reject_error', fallback: 'Error al rechazar'), error: true);
      }
    }
  }

  Future<void> _approveOrganizer(Map<String, dynamic> app) async {
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context, message: i18n.t('requests.confirm_approve_organizer'), confirmText: i18n.t('requests.approve_btn'))) return;
    try {
      await _processRequest(app['id'] as String, 'organizer_applications', 'approved');
      if (mounted) showToast(context, i18n.t('requests.organizer_approved_success'));
    } catch (_) {
      if (mounted) showToast(context, i18n.t('requests.approve_error'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return AdminEmpty(context.t('requests.loading'), loading: true);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminGrid(children: [
        AdminStat(centered: true, label: context.t('requests.stat_venues', fallback: 'Locales'), value: '${_venueApps.length}', icon: Icons.storefront, color: Tw.fuchsia400),
        AdminStat(
            centered: true,
            label: context.t('requests.stat_partners', fallback: 'City Managers / Partners'),
            value: '${_partnerApps.length}',
            icon: Icons.handshake,
            color: Tw.orange400),
        AdminStat(centered: true, label: context.t('requests.stat_rrpp'), value: '${_rrppApps.length}', icon: Icons.badge, color: Tw.pink400),
        AdminStat(centered: true, label: context.t('requests.stat_organizers'), value: '${_organizerApps.length}', icon: Icons.calendar_month, color: Tw.indigo400),
      ]),
      if (_venueApps.isNotEmpty) ...[
        const SizedBox(height: 32),
        _section(
          icon: Icons.storefront,
          color: Tw.fuchsia400,
          border: Tw.fuchsia500,
          title: context.t('requests.section_venues',
              count: _venueApps.length, fallback: 'Solicitudes de locales (${_venueApps.length})'),
          children: [
            for (final app in _venueApps)
              _appCard(
                title: (app['venueName'] ?? app['name'] ?? '') as String,
                subtitle: app['venueAddress'] != null ? '📍 ${app['venueAddress']}' : null,
                badge: AdminBadge(context.t('requests.type_venue', fallback: 'Local'), color: Tw.fuchsia400),
                contact: '${app['phone'] ?? ''} | ${app['email'] ?? ''}',
                note: app['experience'] as String?,
                noteColor: Tw.fuchsia500,
                actions: [
                  AdminButton(
                    label: context.t('requests.approve_btn'),
                    onTap: () => _approvePartner(app, (app['venueName'] ?? app['name'] ?? '') as String),
                  ),
                  AdminButton(
                    label: context.t('requests.reject_btn', fallback: 'Rechazar'),
                    color: Tw.red400,
                    outlined: true,
                    onTap: () => _rejectPartner(app, (app['venueName'] ?? app['name'] ?? '') as String),
                  ),
                ],
              ),
          ],
        ),
      ],
      if (_partnerApps.isNotEmpty) ...[
        const SizedBox(height: 32),
        _section(
          icon: Icons.handshake,
          color: Tw.orange400,
          border: Tw.orange500,
          title: context.t('requests.section_partners',
              count: _partnerApps.length, fallback: 'Solicitudes de City Managers / Partners (${_partnerApps.length})'),
          children: [
            for (final app in _partnerApps)
              _appCard(
                title: (app['name'] ?? '') as String,
                subtitle: app['cityId'] != null
                    ? (app['cityId'] == 'other' ? context.t('requests.other_city') : app['cityId'] as String).toUpperCase()
                    : null,
                subtitleColor: Tw.emerald400,
                badge: AdminBadge(context.t('requests.type_cm', fallback: 'City Manager'), color: Tw.emerald400),
                contact: '${app['phone'] ?? ''} | ${app['email'] ?? ''}',
                note: app['experience'] as String?,
                noteColor: Tw.orange500,
                actions: [
                  AdminButton(
                    label: context.t('requests.approve_btn'),
                    color: Tw.orange600,
                    onTap: () => _approvePartner(app, (app['name'] ?? '') as String),
                  ),
                  AdminButton(
                    label: context.t('requests.reject_btn', fallback: 'Rechazar'),
                    color: Tw.red400,
                    outlined: true,
                    onTap: () => _rejectPartner(app, (app['name'] ?? '') as String),
                  ),
                ],
              ),
          ],
        ),
      ],
      if (_rrppApps.isNotEmpty) ...[
        const SizedBox(height: 32),
        _section(
          icon: Icons.badge,
          color: Tw.fuchsia400,
          border: Tw.fuchsia500,
          title: context.t('requests.section_rrpp', count: _rrppApps.length),
          children: [
            for (final app in _rrppApps)
              _appCard(
                title: '${app['name'] ?? ''} ${app['lastName'] ?? ''}',
                contact: (app['email'] ?? '') as String,
                actions: [
                  AdminButton(label: context.t('requests.approve_btn'), onTap: () => _rrpp(app, true)),
                  AdminButton(
                      label: context.t('requests.reject_btn', fallback: 'Rechazar'), color: Tw.red400, outlined: true, onTap: () => _rrpp(app, false)),
                ],
              ),
          ],
        ),
      ],
      if (_organizerApps.isNotEmpty) ...[
        const SizedBox(height: 32),
        _section(
          icon: Icons.calendar_month,
          color: Tw.indigo400,
          border: Tw.indigo500,
          title: context.t('requests.section_organizers', count: _organizerApps.length),
          children: [
            for (final app in _organizerApps)
              _appCard(
                title: '${app['name'] ?? ''} ${app['lastName'] ?? ''}',
                contact: (app['email'] ?? '') as String,
                actions: [AdminButton(label: context.t('requests.approve_btn'), color: Tw.indigo600, onTap: () => _approveOrganizer(app))],
              ),
          ],
        ),
      ],
    ]);
  }

  Widget _section({required IconData icon, required Color color, required Color border, required String title, required List<Widget> children}) =>
      AdminCard(
        color: Tw.slate900,
        borderColor: border.withValues(alpha: 0.3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: tw(18, weight: black))),
          ]),
          const SizedBox(height: 16),
          for (final c in children) ...[c, const SizedBox(height: 12)],
        ]),
      );

  Widget _appCard({
    required String title,
    String? subtitle,
    Color subtitleColor = Tw.slate400,
    Widget? badge,
    required String contact,
    String? note,
    Color noteColor = Tw.fuchsia500,
    required List<Widget> actions,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tw.w(0.1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: tw(18, weight: bold)),
                if (subtitle != null) Text(subtitle, style: tw(12, weight: subtitleColor == Tw.slate400 ? FontWeight.w400 : bold, color: subtitleColor)),
              ]),
            ),
            ?badge,
          ]),
          const SizedBox(height: 8),
          Text(contact, style: tw(14, color: Tw.slate300)),
          if (note != null && note.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: noteColor.withValues(alpha: 0.3), width: 2))),
              child: Text(note, style: tw(12, color: Tw.slate500, style: FontStyle.italic)),
            ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ]),
      );
}
