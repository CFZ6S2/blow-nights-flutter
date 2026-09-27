import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../providers/auth_provider.dart';
import '../../models/firestore_utils.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import 'super_admin_screen.dart' show ForbiddenScreen;

/// Port of app/admin/page.tsx (moderation dashboard for admin + superadmin).
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _db = FirebaseFirestore.instance;
  Map<String, dynamic> _stats = const {'totalUsers': 0, 'onlineUsers': 0, 'premiumUsers': 0, 'pendingReports': 0, 'pendingVerifications': 0};
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _verifications = [];
  List<Map<String, dynamic>> _applications = [];
  List<Map<String, dynamic>> _rrppApps = [];
  List<Map<String, dynamic>> _users = [];
  DocumentSnapshot? _lastVisible;
  bool _loadingUsers = false;
  String? _processingRrpp;
  String _tab = 'stats';
  String _search = '';
  final _subs = <StreamSubscription>[];
  bool _started = false;

  I18n get _i18n => context.read<I18n>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && context.read<AuthProvider>().isAdmin) {
      _started = true;
      _start();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(QuerySnapshot<Map<String, dynamic>> s) => [for (final d in s.docs) {'id': d.id, ...d.data()}];

  void _start() {
    callFn('getAdminAnalytics').then((res) {
      if (mounted && res['success'] == true) setState(() => _stats = Map<String, dynamic>.from(res['stats'] as Map));
    }).catchError((Object e) => debugPrint('Error cargando analytics: $e'));

    void listen(Query<Map<String, dynamic>> q, void Function(List<Map<String, dynamic>>) onData) {
      _subs.add(q.snapshots().listen((s) {
        if (mounted) setState(() => onData(_rows(s)));
      }, onError: (e) => debugPrint('Snapshot error $e')));
    }

    listen(_db.collection('reports').orderBy('timestamp', descending: true).limit(50), (r) => _reports = r);
    listen(_db.collection('verifications').orderBy('timestamp', descending: true).limit(50), (r) => _verifications = r);
    listen(_db.collection('rrpp_applications').where('status', isEqualTo: 'pending'), (r) => _rrppApps = r);
    listen(
      _db.collection('partner_applications').where('status', isEqualTo: 'pending').where('type', isEqualTo: 'venue').limit(50),
      (r) => _applications = r,
    );
    _loadMoreUsers(reset: true);
  }

  Future<void> _loadMoreUsers({bool reset = false}) async {
    if (_loadingUsers) return;
    setState(() => _loadingUsers = true);
    try {
      var q = _db.collection('users').orderBy('createdAt', descending: true).limit(25);
      if (!reset && _lastVisible != null) q = q.startAfterDocument(_lastVisible!);
      final s = await q.get();
      setState(() {
        _lastVisible = s.docs.isEmpty ? null : s.docs.last;
        _users = reset ? _rows(s) : [..._users, ..._rows(s)];
      });
    } catch (e) {
      debugPrint('Error cargando usuarios paginados: $e');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  bool _isPremium(Map<String, dynamic> u) => ['plus', 'black'].contains(u['membershipTier']);

  Future<void> _togglePremium(Map<String, dynamic> u) async {
    final tier = _isPremium(u) ? null : 'plus';
    try {
      await _db.collection('users').doc(u['id'] as String).update({'membershipTier': tier});
      setState(() => _users = [for (final x in _users) x['id'] == u['id'] ? {...x, 'membershipTier': tier} : x]);
    } catch (e) {
      debugPrint('Error updating premium status: $e');
    }
  }

  Future<void> _deleteUser(String uid) async {
    if (!await confirmDialog(context,
        message: _i18n.t('admin.users.confirm_delete'), danger: true, confirmText: _i18n.t('admin.users.delete_btn'))) {
      return;
    }
    try {
      await callFn('adminDeleteUser', {'uid': uid});
      if (mounted) showToast(context, _i18n.t('admin.users.delete_success'));
      setState(() => _users.removeWhere((u) => u['id'] == uid));
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('admin.users.error'), error: true);
    }
  }

  Future<void> _banUser(String uid) async {
    final reason = await promptInput(context,
        message: _i18n.t('admin.users.ban_reason_prompt'),
        placeholder: _i18n.t('admin.users.ban_reason_placeholder'),
        confirmText: _i18n.t('admin.users.ban_btn'));
    if (reason == null) return;
    try {
      await callFn('banUser', {'uid': uid, 'reason': reason});
      if (mounted) showToast(context, _i18n.t('admin.users.ban_success'));
      setState(() => _users = [for (final u in _users) u['id'] == uid ? {...u, 'banned': true, 'bannedReason': reason} : u]);
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('admin.users.error'), error: true);
    }
  }

  Future<void> _verification(String userId, String status) async {
    try {
      await _db.collection('verifications').doc(userId).update({'status': status});
      await _db.collection('users').doc(userId).update({'verified': status == 'approved', 'verificationStatus': status});
    } catch (e) {
      debugPrint('Error handling verification: $e');
    }
  }

  Future<void> _rrpp(String appId, String action) async {
    final label = action == 'approve' ? _i18n.t('admin.rrpp_action_approve') : _i18n.t('admin.rrpp_action_reject');
    if (!await confirmDialog(context,
        message: _i18n.t('admin.rrpp_confirm_action', params: {'action': label}),
        danger: action == 'reject',
        confirmText: action == 'approve' ? _i18n.t('admin.approve_btn') : _i18n.t('admin.reject_btn'))) {
      return;
    }
    setState(() => _processingRrpp = appId);
    try {
      await callFn('approveRRPP', {'applicationId': appId, 'action': action});
      if (mounted) showToast(context, action == 'approve' ? _i18n.t('admin.rrpp_approved_success') : _i18n.t('admin.rrpp_rejected_success'));
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('admin.action_error'), error: true);
    } finally {
      if (mounted) setState(() => _processingRrpp = null);
    }
  }

  Future<void> _venueApp(Map<String, dynamic> app, bool approve) async {
    final ok = await confirmDialog(context,
        message: _i18n.t(approve ? 'admin.confirm_approve_venue_app' : 'admin.confirm_reject_venue_app', params: {'name': app['name']}),
        danger: !approve,
        confirmText: _i18n.t(approve ? 'admin.approve_btn' : 'admin.reject_btn'));
    if (!ok) return;
    try {
      final data = await callFn('approvePartnerAccess', {'applicationId': app['id'], 'action': approve ? 'approve' : 'reject'});
      if (!mounted) return;
      if (approve) {
        final link = data['passwordResetLink'];
        showToast(context, '${data['message'] ?? ''}${link != null ? ' ${_i18n.t('admin.recovery_link')}: $link' : ''}');
      } else {
        showToast(context, _i18n.t('admin.rejected_success'));
      }
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('admin.action_error'), error: true);
    }
  }

  void _whatsApp(String? phone, String text) {
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    launchUrl(Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF07080D),
        body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)),
      );
    }
    if (!auth.isAdmin) return const ForbiddenScreen(messageKey: 'admin.access_denied');

    int n(String k) => (_stats[k] as num?)?.toInt() ?? 0;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, top + 16, 16, 96 + MediaQuery.of(context).padding.bottom),
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [Tw.fuchsia500, Tw.indigo500]).createShader(r),
                  child: Text('ADMIN DASHBOARD', style: tw(26, weight: black)),
                ),
                Text(context.t('admin.subtitle'), style: tw(14, color: Tw.slate400)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          const Align(alignment: Alignment.centerRight, child: AdminTopBar(showAdmin: false)),
          const SizedBox(height: 24),
          AdminGrid(gap: 16, children: [
            _statCard(context.t('admin.users'), n('totalUsers'), Icons.people, Tw.fuchsia500),
            _statCard(context.t('admin.online'), n('onlineUsers'), Icons.sensors, Tw.emerald500),
            _statCard(context.t('admin.premium'), n('premiumUsers'), Icons.star, Tw.amber500),
            _statCard(context.t('admin.reports'), n('pendingReports'), Icons.report_problem, const Color(0xFFF43F5E)),
          ]),
          const SizedBox(height: 32),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _tabButton('stats', context.t('admin.general'), Icons.dashboard),
              _tabButton('users', context.t('admin.users'), Icons.group),
              _tabButton('reports', context.t('admin.reports'), Icons.gavel),
              _tabButton('verifications', context.t('admin.verifications'), Icons.verified),
              _tabButton('rrpps', '${context.t('admin.rrpp')} (${_rrppApps.length})', Icons.assignment_ind),
            ]),
          ),
          const SizedBox(height: 24),
          switch (_tab) {
            'rrpps' => _rrppTab(context),
            'users' => _usersTab(context),
            'reports' => _reportsTab(context),
            'verifications' => _verificationsTab(context),
            _ => _statsTab(context, n),
          },
        ],
      ),
    );
  }

  Widget _statCard(String label, int value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.05)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Icon(icon, size: 20, color: Tw.w(0.6)),
          const SizedBox(height: 4),
          Text('$value', style: tw(24, weight: black)),
          Label(label, color: Tw.w(0.6), weight: bold, align: TextAlign.center),
        ]),
      );

  Widget _tabButton(String key, String label, IconData icon) {
    final active = _tab == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Pressable(
        onTap: () => setState(() => _tab = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Tw.fuchsia600 : Tw.w(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? Tw.fuchsia600 : Tw.w(0.05)),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: active ? Tw.white : Tw.slate400),
            const SizedBox(width: 8),
            Text(label, style: tw(14, weight: bold, color: active ? Tw.white : Tw.slate400)),
          ]),
        ),
      ),
    );
  }

  Widget _statsTab(BuildContext context, int Function(String) n) {
    final total = n('totalUsers');
    int pct(int v) => total > 0 ? (v / total * 100).round() : 0;
    Widget box(int value, Color color, String label) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
          child: Column(children: [
            Text('$value%', style: tw(30, weight: black, color: color)),
            const SizedBox(height: 4),
            Label(label, color: Tw.slate500, weight: FontWeight.w400, align: TextAlign.center),
          ]),
        );
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.trending_up, color: Tw.fuchsia400),
          const SizedBox(width: 8),
          Text(context.t('admin.system_ratios'), style: tw(20, weight: bold)),
        ]),
        const SizedBox(height: 16),
        AdminGrid(gap: 16, children: [
          box(pct(n('premiumUsers')), Tw.amber400, context.t('admin.conversion_premium')),
          box(pct(n('onlineUsers')), Tw.emerald400, context.t('admin.users_online')),
        ]),
      ]),
    );
  }

  Widget _rrppTab(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_rrppApps.isEmpty) Text(context.t('admin.no_rrpp'), style: tw(14, color: Tw.slate500)),
        for (final app in _rrppApps)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((app['nick'] as String?) ?? 'Sin nick', style: tw(18, weight: bold)),
                    Text((app['email'] as String?) ?? '', style: tw(12, color: Tw.slate400)),
                  ]),
                ),
                AdminBadge(context.t('admin.pending'), color: Tw.yellow500),
              ]),
              const SizedBox(height: 8),
              Text('📞 ${app['phone'] ?? ''} | 📍 ${app['city'] ?? ''}', style: tw(14, color: Tw.slate300)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                AdminButton(
                  label: _processingRrpp == app['id'] ? '...' : context.t('admin.approve_btn'),
                  color: Tw.green600,
                  onTap: _processingRrpp == app['id'] ? null : () => _rrpp(app['id'] as String, 'approve'),
                ),
                AdminButton(
                  label: context.t('admin.reject_btn'),
                  color: Tw.red600,
                  onTap: _processingRrpp == app['id'] ? null : () => _rrpp(app['id'] as String, 'reject'),
                ),
                AdminButton(
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => _whatsApp(app['phone'] as String?,
                      'Hola ${app['nick'] ?? ''}, te escribo desde Blow Nights sobre tu solicitud RRPP...'),
                ),
              ]),
            ]),
          ),
      ]);

  Widget _usersTab(BuildContext context) {
    final q = _search.toLowerCase();
    final filtered =
        _users.where((u) => ((u['nick'] as String?)?.toLowerCase().contains(q) ?? false) || (u['id'] as String).contains(_search)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        onChanged: (v) => setState(() => _search = v),
        style: tw(14),
        decoration: InputDecoration(
          hintText: context.t('admin.filter_nick'),
          hintStyle: tw(14, color: Tw.slate500),
          prefixIcon: const Icon(Icons.search, color: Tw.slate500),
          filled: true,
          fillColor: Tw.w(0.05),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tw.w(0.1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tw.fuchsia500.withValues(alpha: 0.5))),
        ),
      ),
      const SizedBox(height: 16),
      for (final u in filtered) _userRow(context, u),
      if (_lastVisible != null)
        Pressable(
          onTap: _loadingUsers ? () {} : () => _loadMoreUsers(),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
            child: Text(_loadingUsers ? context.t('admin.loading') : context.t('admin.load_more_users'),
                textAlign: TextAlign.center, style: tw(12, weight: bold, color: Tw.slate300)),
          ),
        ),
    ]);
  }

  Widget _userRow(BuildContext context, Map<String, dynamic> u) {
    final premium = _isPremium(u);
    final banned = u['banned'] == true;
    Widget pill(String label, Color fg, Color bg, Color border, VoidCallback? onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: Border.all(color: border)),
            child: Text(label, style: tw(10, weight: bold, color: fg)),
          ),
        );
    final id = u['id'] as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ClipOval(child: NetImage(u['fotoUrl'] as String?, width: 40, height: 40)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((u['nick'] as String?) ?? context.t('admin.no_nick'), style: tw(14, weight: bold)),
              Text('${id.length > 8 ? id.substring(0, 8) : id}...', style: tw(10, color: Tw.slate500).copyWith(fontFamily: 'monospace')),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 6, children: [
          pill(
            premium ? context.t('admin.is_premium') : context.t('admin.make_premium'),
            premium ? Tw.amber500 : Tw.slate400,
            premium ? Tw.amber500.withValues(alpha: 0.2) : Tw.w(0.05),
            premium ? Tw.amber500.withValues(alpha: 0.3) : Tw.w(0.1),
            () => _togglePremium(u),
          ),
          pill(
            banned ? context.t('admin.banned') : context.t('admin.ban'),
            banned ? Tw.red500 : Tw.orange400,
            banned ? Tw.red900.withValues(alpha: 0.3) : Tw.orange500.withValues(alpha: 0.1),
            banned ? Tw.red900.withValues(alpha: 0.5) : Tw.orange500.withValues(alpha: 0.2),
            banned ? null : () => _banUser(id),
          ),
          pill(context.t('admin.delete'), Tw.red400, Tw.red500.withValues(alpha: 0.1), Tw.red500.withValues(alpha: 0.2), () => _deleteUser(id)),
        ]),
      ]),
    );
  }

  Widget _reportsTab(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in _reports)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x1AF43F5E))),
            child: Row(children: [
              Expanded(child: Text(((r['reason'] as String?) ?? '').toUpperCase(), style: tw(12, weight: bold, color: const Color(0xFFFB7185)))),
              if (r['status'] == 'pending')
                GestureDetector(
                  onTap: () => _db.collection('reports').doc(r['id'] as String).update({'status': 'resolved'}).catchError((Object e) {
                    debugPrint('Error resolving report: $e');
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Tw.emerald500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                    child: Text(context.t('admin.resolve'), style: tw(10, weight: bold, color: Tw.emerald500)),
                  ),
                )
              else
                Text(context.t('admin.resolved'), style: tw(10, weight: bold, color: Tw.emerald500)),
            ]),
          ),
      ]);

  Widget _verificationsTab(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.store, color: Tw.fuchsia400),
          const SizedBox(width: 8),
          Expanded(child: Label(context.t('admin.venue_requests_title'), size: 18, color: Tw.fuchsia400, tracking: 0.05)),
        ]),
        const SizedBox(height: 16),
        if (_applications.isEmpty) Text(context.t('admin.no_venue_requests'), style: tw(14, color: Tw.slate500)),
        for (final app in _applications)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((app['name'] as String?) ?? '', style: tw(18, weight: bold)),
                    Text(((app['cityId'] as String?) ?? '').toUpperCase(), style: tw(12, weight: bold, color: Tw.fuchsia400)),
                  ]),
                ),
                AdminBadge(context.t('admin.pending'), color: Tw.yellow500),
              ]),
              const SizedBox(height: 8),
              Text('📞 ${app['phone'] ?? ''} | ✉️ ${app['email'] ?? ''}', style: tw(14, color: Tw.slate300)),
              if (app['venueName'] != null) Text('🍸 ${app['venueName']}', style: tw(14, weight: bold, color: Tw.fuchsia300)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                AdminButton(label: context.t('admin.approve_venue_btn'), onTap: () => _venueApp(app, true)),
                AdminButton(label: context.t('admin.reject_btn'), color: Tw.red600, onTap: () => _venueApp(app, false)),
                AdminButton(
                  label: 'WhatsApp',
                  color: Tw.green600,
                  onTap: () => _whatsApp(app['phone'] as String?, 'Hola ${app['name']}, te escribo desde Blow Nights...'),
                ),
              ]),
            ]),
          ),
        const SizedBox(height: 32),
        Row(children: [
          const Icon(Icons.verified_user, color: Tw.emerald400),
          const SizedBox(width: 8),
          Expanded(child: Label(context.t('admin.user_verifications_title'), size: 18, color: Tw.emerald400, tracking: 0.05)),
        ]),
        const SizedBox(height: 16),
        if (_verifications.isEmpty) Text(context.t('admin.no_user_verifications'), style: tw(14, color: Tw.slate500)),
        for (final v in _verifications)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('admin.user_id_label', params: {'id': v['id']}), style: tw(18, weight: bold)),
              for (final img in asStringList(v['images']))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: NetImage(img, width: double.infinity)),
                ),
              const SizedBox(height: 16),
              Wrap(spacing: 8, children: [
                AdminButton(label: context.t('admin.approve_verification_btn'), color: Tw.emerald600, onTap: () => _verification(v['id'] as String, 'approved')),
                AdminButton(label: context.t('admin.reject_btn'), color: Tw.red600, onTap: () => _verification(v['id'] as String, 'rejected')),
              ]),
            ]),
          ),
      ]);
}

