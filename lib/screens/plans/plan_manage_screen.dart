import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../providers/auth_provider.dart';
import '../../services/chills.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Port of app/my-plans/[planId]/page.tsx
class PlanManageScreen extends StatefulWidget {
  final String planId;
  const PlanManageScreen({super.key, required this.planId});

  @override
  State<PlanManageScreen> createState() => _PlanManageScreenState();
}

class _PlanManageScreenState extends State<PlanManageScreen> {
  late final _ref = FirebaseFirestore.instance.collection('chills').doc(widget.planId);
  Map<String, dynamic>? _chill;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String _tab = 'info';
  bool _ending = false;
  String? _respondingTo;
  final List<StreamSubscription> _subs = [];
  StreamSubscription? _msgSub;

  @override
  void initState() {
    super.initState();
    _subs.add(_ref.snapshots().listen((s) => setState(() {
          _chill = s.exists ? {'id': s.id, ...?s.data()} : null;
          _loading = false;
        }), onError: (_) => setState(() => _loading = false)));
    _subs.add(_ref.collection('requests').where('status', isEqualTo: 'pending').snapshots().listen(
        (s) => setState(() => _requests = s.docs.map((d) => {'id': d.id, ...d.data()}).toList()),
        onError: (_) {}));
  }

  void _setTab(String t) {
    setState(() => _tab = t);
    if (t == 'chat' && _msgSub == null) {
      _msgSub = _ref.collection('messages').orderBy('created_at').limit(200).snapshots().listen((s) {
        final list = s.docs.map((d) => {'id': d.id, ...d.data()}).toList()
          ..sort((a, b) => (parseDate(a['created_at'])?.millisecondsSinceEpoch ?? 0).compareTo(parseDate(b['created_at'])?.millisecondsSinceEpoch ?? 0));
        setState(() => _messages = list);
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _msgSub?.cancel();
    super.dispose();
  }

  Future<void> _respond(String userId, String action) async {
    setState(() => _respondingTo = userId);
    try {
      await respondChillRequest(widget.planId, userId, action);
    } catch (_) {}
    if (mounted) setState(() => _respondingTo = null);
  }

  Future<void> _end() async {
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context,
        message: i18n.t('plan_manage.confirm_end', fallback: 'Seguro que quieres cerrar este plan?'),
        confirmText: i18n.t('plan_manage.end_plan', fallback: 'Cerrar plan'),
        danger: true)) {
      return;
    }
    setState(() => _ending = true);
    try {
      await endChill(widget.planId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _ending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (_loading || auth.loading) return const Scaffold(body: Center(child: SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2))));
    final c = _chill;
    if (c == null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.event_busy, size: 48, color: Tw.line),
            const SizedBox(height: 16),
            Text(context.t('plan_manage.not_found', fallback: 'Plan no encontrado'), style: tw(20, weight: black)),
            const SizedBox(height: 16),
            Pressable(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(color: Tw.party, borderRadius: BorderRadius.circular(16)),
                child: Label(context.t('plan_manage.back', fallback: 'Mis planes'), size: 12, color: Tw.white),
              ),
            ),
          ]),
        ),
      );
    }
    final status = c['status'] as String? ?? '';
    final statusColor = status == 'active' ? Tw.live : status == 'full' ? Tw.red400 : Tw.inkSoft;
    final isHost = auth.user?.uid == c['host_uid'];
    final isActive = status == 'active' || status == 'full';
    final accepted = c['accepted_users'] is List ? (c['accepted_users'] as List).length : 0;
    final denied = c['denied_users'] is List ? (c['denied_users'] as List).length : 0;

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 128), children: [
          Row(children: [
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.panelSoft, border: Border.all(color: Tw.line)),
                child: const Icon(Icons.arrow_back, color: Tw.white),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(safeStr(c['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(20, weight: black)),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Label(status, size: 9, weight: bold, color: statusColor, tracking: 0),
                  ),
                  const SizedBox(width: 8),
                  Text('$accepted/${asInt(c['max_capacity'])}', style: tw(10, color: Tw.inkDim)),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Tw.panelSoft, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              for (final t in ['info', 'requests', 'chat'])
                Expanded(
                  child: Pressable(
                    onTap: () => _setTab(t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: _tab == t ? Tw.party : null, borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(t == 'info' ? Icons.info : t == 'requests' ? Icons.person_add : Icons.chat, size: 14,
                            color: _tab == t ? Tw.white : Tw.inkDim),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Label(
                            t == 'info'
                                ? context.t('plan_manage.tab_info', fallback: 'Info')
                                : t == 'requests'
                                    ? '${context.t('plan_manage.tab_requests', fallback: 'Solicitudes')}${_requests.isNotEmpty ? ' (${_requests.length})' : ''}'
                                    : context.t('plan_manage.tab_chat', fallback: 'Chat'),
                            color: _tab == t ? Tw.white : Tw.inkDim,
                            maxLines: 1,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 24),
          if (_tab == 'info') ..._info(context, c, accepted, denied, isHost && isActive),
          if (_tab == 'requests') ..._requestsTab(context),
          if (_tab == 'chat') ..._chatTab(context, auth.user?.uid),
        ]),
      ),
    );
  }

  List<Widget> _info(BuildContext context, Map<String, dynamic> c, int accepted, int denied, bool canEnd) {
    final tags = asStringList(c['tags']);
    Widget stat(IconData icon, Color color, int value, String label) => Expanded(
          child: GlassCard(
            radius: 16,
            child: Column(children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text('$value', style: tw(18, weight: black)),
              Label(label, size: 9, weight: FontWeight.w400, color: Tw.inkDim, tracking: 0),
            ]),
          ),
        );
    return [
      if (safeStr(c['description']).isNotEmpty) ...[
        GlassCard(radius: 16, child: Text(safeStr(c['description']), style: tw(14, color: Tw.inkSoft))),
        const SizedBox(height: 16),
      ],
      if (tags.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in tags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Tw.panelSoft, borderRadius: BorderRadius.circular(99), border: Border.all(color: Tw.line)),
              child: Label(t, weight: bold, tracking: 0),
            ),
        ]),
        const SizedBox(height: 16),
      ],
      Row(children: [
        stat(Icons.group, Tw.sun, accepted, context.t('plan_manage.accepted', fallback: 'Aceptados')),
        const SizedBox(width: 12),
        stat(Icons.hourglass_top, Tw.sun, _requests.length, context.t('plan_manage.pending', fallback: 'Pendientes')),
        const SizedBox(width: 12),
        stat(Icons.block, Tw.inkSoft, denied, context.t('plan_manage.denied', fallback: 'Denegados')),
      ]),
      if (canEnd) ...[
        const SizedBox(height: 16),
        Pressable(
          onTap: _ending ? () {} : _end,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Tw.red500.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
            ),
            child: Label(_ending ? context.t('plan_manage.ending', fallback: 'Cerrando...') : context.t('plan_manage.end_plan', fallback: 'Cerrar plan'),
                size: 12, color: Tw.red400, align: TextAlign.center),
          ),
        ),
      ],
    ];
  }

  List<Widget> _requestsTab(BuildContext context) {
    if (_requests.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(children: [
            const Icon(Icons.inbox, size: 36, color: Tw.line),
            const SizedBox(height: 12),
            Text(context.t('plan_manage.no_requests', fallback: 'No hay solicitudes pendientes'), style: tw(14, color: Tw.inkDim)),
          ]),
        ),
      ];
    }
    return [
      for (final r in _requests)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            radius: 16,
            child: Row(children: [
              ClipOval(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: NetImage(
                    r['user_foto'] as String?,
                    placeholder: Container(color: Tw.line, child: const Icon(Icons.person, color: Tw.inkDim)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(safeStr(r['user_nick'] ?? r['userName']), maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(14, weight: black)),
                  if (r['user_edad'] != null) Text('${r['user_edad']} ${context.t('plan_manage.years', fallback: 'anos')}', style: tw(10, color: Tw.inkDim)),
                  if (safeStr(r['user_bio']).isNotEmpty)
                    Text(safeStr(r['user_bio']), maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(10, color: Tw.inkSoft)),
                ]),
              ),
              for (final a in [('accept', Icons.check, Tw.live, Tw.live), ('deny', Icons.close, Tw.red500, Tw.red400)]) ...[
                const SizedBox(width: 8),
                Opacity(
                  opacity: _respondingTo == r['user_uid'] ? 0.5 : 1,
                  child: Pressable(
                    onTap: _respondingTo == r['user_uid'] ? () {} : () => _respond(r['user_uid'] as String, a.$1),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: a.$3.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: a.$3.withValues(alpha: 0.3)),
                      ),
                      child: Icon(a.$2, size: 14, color: a.$4),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
    ];
  }

  List<Widget> _chatTab(BuildContext context, String? uid) {
    if (_messages.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(children: [
            const Icon(Icons.forum, size: 36, color: Tw.line),
            const SizedBox(height: 12),
            Text(context.t('plan_manage.no_messages', fallback: 'No hay mensajes todavia'), style: tw(14, color: Tw.inkDim)),
          ]),
        ),
      ];
    }
    return [
      for (final m in _messages)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: m['uid'] == uid ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (m['uid'] != uid && safeStr(m['foto']).isNotEmpty) ...[
                ClipOval(child: SizedBox(width: 32, height: 32, child: NetImage(m['foto'] as String))),
                const SizedBox(width: 8),
              ],
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75 - 48),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: m['uid'] == uid ? Tw.party.withValues(alpha: 0.3) : Tw.panelSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (m['uid'] != uid) Text(safeStr(m['nick']), style: tw(9, weight: bold, color: Tw.sun)),
                    Text(safeStr(m['text']), style: tw(14, color: m['uid'] == uid ? Tw.white : Tw.inkSoft)),
                  ]),
                ),
              ),
              if (m['uid'] == uid && safeStr(m['foto']).isNotEmpty) ...[
                const SizedBox(width: 8),
                ClipOval(child: SizedBox(width: 32, height: 32, child: NetImage(m['foto'] as String))),
              ],
            ],
          ),
        ),
    ];
  }
}
