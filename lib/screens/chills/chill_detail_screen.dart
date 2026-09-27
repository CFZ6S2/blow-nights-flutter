import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/chills.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chill_paywall.dart';
import '../../widgets/common.dart';
import '../../widgets/profile_overlay.dart';

/// Port of app/[city]/chills/detail/ChillDetailClient.tsx
class ChillDetailScreen extends StatefulWidget {
  final String chillId;
  const ChillDetailScreen({super.key, required this.chillId});

  @override
  State<ChillDetailScreen> createState() => _ChillDetailScreenState();
}

class _ChillDetailScreenState extends State<ChillDetailScreen> {
  late final _ref = FirebaseFirestore.instance.collection('chills').doc(widget.chillId);
  Map<String, dynamic>? _chill;
  bool _loading = true;
  bool _requesting = false;
  String _error = '';
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _messages = [];
  final _msg = TextEditingController();
  String _tab = 'info';
  String? _exactAddress;
  bool _addressLoaded = false;
  StreamSubscription? _chillSub, _reqSub, _msgSub;

  @override
  void initState() {
    super.initState();
    _msg.addListener(() => setState(() {}));
    _chillSub = _ref.snapshots().listen((s) {
      setState(() {
        _chill = s.exists ? {'id': s.id, ...?s.data()} : null;
        _loading = false;
      });
      _syncAccess();
    }, onError: (_) => setState(() => _loading = false));
    _reqSub = _ref.collection('requests').where('status', isEqualTo: 'pending').snapshots().listen(
        (s) => setState(() => _requests = s.docs.map((d) => {'id': d.id, ...d.data()}).toList()),
        onError: (_) {});
  }

  bool _in(String key) {
    final uid = context.read<AuthProvider>().user?.uid;
    final l = _chill?[key];
    return uid != null && l is List && l.contains(uid);
  }

  bool get _isHost => _chill?['host_uid'] != null && _chill?['host_uid'] == context.read<AuthProvider>().user?.uid;
  bool get _canSee => _isHost || _in('accepted_users');

  void _syncAccess() {
    if (!_canSee) return;
    if (!_addressLoaded) {
      _addressLoaded = true;
      _ref.collection('private').doc('info').get().then((s) {
        if (mounted && s.exists) setState(() => _exactAddress = s.data()?['exact_address'] as String?);
      }).catchError((_) {
        if (mounted) setState(() => _exactAddress = _chill?['exact_address'] as String?);
      });
    }
    _msgSub ??= _ref.collection('messages').orderBy('created_at').snapshots().listen(
        (s) => setState(() => _messages = s.docs.map((d) => {'id': d.id, ...d.data()}).toList()),
        onError: (_) {});
  }

  @override
  void dispose() {
    _chillSub?.cancel();
    _reqSub?.cancel();
    _msgSub?.cancel();
    _msg.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final i18n = context.read<I18n>();
    if (context.read<AuthProvider>().user == null) {
      openRoute(context, AppRoute.login);
      return;
    }
    setState(() {
      _requesting = true;
      _error = '';
    });
    try {
      await requestChillAccess(widget.chillId);
    } catch (e) {
      setState(() => _error = fnMessage(e, i18n.t('chill.error_requesting')));
    }
    if (mounted) setState(() => _requesting = false);
  }

  Future<void> _respond(String userId, String action) async {
    try {
      await respondChillRequest(widget.chillId, userId, action);
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('chill_action_error', fallback: 'Error al procesar la acción. Inténtalo de nuevo.'), error: true);
    }
  }

  Future<void> _end() async {
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context, message: i18n.t('chill.confirm_close'), confirmText: i18n.t('chill.close_chill'), danger: true)) return;
    try {
      await endChill(widget.chillId);
    } catch (_) {
      if (mounted) showToast(context, i18n.t('chill_action_error', fallback: 'Error al procesar la acción. Inténtalo de nuevo.'), error: true);
    }
  }

  Future<void> _send() async {
    final auth = context.read<AuthProvider>();
    final text = _msg.text.trim();
    if (text.isEmpty || auth.user == null || auth.profile == null) return;
    _msg.clear();
    await _ref.collection('messages').add({
      'uid': auth.user!.uid,
      'nick': auth.profile!.nick.isNotEmpty ? auth.profile!.nick : context.read<I18n>().t('chill.anon'),
      'foto': auth.profile!.fotoUrl,
      'text': text,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (_loading) return const Scaffold(backgroundColor: Tw.black, body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final c = _chill;
    if (c == null) {
      return Scaffold(
        backgroundColor: Tw.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.explore_off, size: 60, color: Tw.slate700),
              const SizedBox(height: 16),
              Text(context.t('chill.not_found'), style: tw(20, weight: black)),
              const SizedBox(height: 8),
              Text(context.t('chill.expired_or_deleted'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
              const SizedBox(height: 24),
              Pressable(
                onTap: () => openRoute(context, AppRoute.chills, replace: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.circular(12)),
                  child: Text(context.t('chill.back_to_radar'), style: tw(14, weight: bold)),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    final isHost = _isHost;
    final accepted = _in('accepted_users'), pending = _in('pending_users'), denied = _in('denied_users');
    final canChat = isHost || accepted;
    final status = c['status'] as String? ?? '';
    final acceptedCount = c['accepted_users'] is List ? (c['accepted_users'] as List).length : 0;
    final max = asInt(c['max_capacity']);
    final spots = max - acceptedCount;
    final tags = asStringList(c['tags']);
    final tabs = ['info', if (isHost) 'requests', if (canChat) 'chat'];

    return Scaffold(
      backgroundColor: Tw.black,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 24), children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_back, size: 14, color: Tw.slate500),
                    const SizedBox(width: 4),
                    Text(context.t('chill.back'), style: tw(12, weight: bold, color: Tw.slate500)),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Tw.slate900.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Tw.w(0.05)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    GestureDetector(
                      onTap: () => showProfileOverlay(context, c['host_uid'] as String),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.4), width: 2)),
                        child: ClipOval(
                          child: NetImage(
                            c['host_foto'] as String?,
                            placeholder: Container(color: const Color(0x66701A75), child: const Icon(Icons.person, color: Tw.fuchsia400)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(safeStr(c['title']), style: tw(20, weight: black, height: 1.2)),
                        const SizedBox(height: 4),
                        Text.rich(TextSpan(children: [
                          TextSpan(text: '${context.t('chill.organized_by')} '),
                          TextSpan(text: safeStr(c['host_nick']), style: tw(12, weight: bold, color: Tw.fuchsia400)),
                        ]), style: tw(12, weight: bold, color: Tw.slate500)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == 'ended' ? Tw.slate700 : (spots <= 0 ? Tw.red500 : Tw.green500).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          status == 'ended' ? context.t('chill.status_closed') : spots <= 0 ? context.t('chill.status_full') : '$spots ${context.t('chill.spots')}',
                          style: tw(10, weight: black, color: status == 'ended' ? Tw.slate400 : spots <= 0 ? Tw.red400 : Tw.green400),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('$acceptedCount/$max', style: tw(10, weight: bold, color: Tw.slate500)),
                    ]),
                  ]),
                  if (safeStr(c['description']).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(safeStr(c['description']), style: tw(14, color: Tw.slate300)),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final t in tags)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(99)),
                          child: Text(t, style: tw(10, weight: bold, color: Tw.slate400)),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  _canSee
                      ? _infoBox(Icons.location_on, Tw.green400, Tw.green500, context.t('chill.address'), _exactAddress ?? context.t('chill.loading'), bold: true)
                      : _infoBox(Icons.lock, Tw.slate600, Tw.slate800, context.t('chill.location'), context.t('chill.location_hidden')),
                ]),
              ),
              const SizedBox(height: 16),
              if (status != 'ended' && !isHost) ...[
                if (accepted)
                  _statusCard(Icons.check_circle, Tw.green400, Tw.green500, context.t('chill.has_pass'))
                else if (denied)
                  _statusCard(Icons.block, Tw.red400, Tw.red500, context.t('chill.request_denied'))
                else if (pending)
                  _statusCard(Icons.hourglass_top, const Color(0xFFFACC15), const Color(0xFFEAB308), context.t('chill.waiting_approval'))
                else ...[
                  _requestButton(context, auth.hasChillAccess, status == 'full'),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_error, textAlign: TextAlign.center, style: tw(12, color: Tw.red400)),
                  ],
                ],
                const SizedBox(height: 16),
              ],
              if (isHost && status != 'ended') ...[
                Pressable(
                  onTap: _end,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0x4D7F1D1D),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.cancel, size: 14, color: Tw.red400),
                      const SizedBox(width: 8),
                      Label(context.t('chill.close_chill'), size: 12, weight: bold, color: Tw.red400),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (isHost || accepted) ...[
                Row(children: [
                  for (final t in tabs) ...[
                    Stack(clipBehavior: Clip.none, children: [
                      Pressable(
                        onTap: () => setState(() => _tab = t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _tab == t ? Tw.fuchsia500 : Tw.w(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _tab == t ? Tw.fuchsia500 : Tw.w(0.05)),
                          ),
                          child: Label(
                            context.t(t == 'info' ? 'chill.tab_info' : t == 'requests' ? 'chill.tab_requests' : 'chill.tab_chat'),
                            color: _tab == t ? Tw.white : Tw.slate500,
                          ),
                        ),
                      ),
                      if (t == 'requests' && _requests.isNotEmpty)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            width: 16,
                            height: 16,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Tw.red500),
                            child: Text('${_requests.length}', style: tw(8, weight: black)),
                          ),
                        ),
                    ]),
                    const SizedBox(width: 8),
                  ],
                ]),
                const SizedBox(height: 16),
                if (_tab == 'requests' && isHost) ..._requestsTab(context),
                if (_tab == 'chat' && canChat) ..._chatMessages(context, auth.user?.uid),
              ],
            ]),
          ),
          if ((isHost || accepted) && _tab == 'chat' && canChat) _chatInput(context),
        ]),
      ),
    );
  }

  Widget _infoBox(IconData icon, Color fg, Color bg, String title, String body, {bool bold = false}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg.withValues(alpha: bold ? 0.1 : 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: bold ? bg.withValues(alpha: 0.2) : Tw.w(0.05)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Label(title, size: 12, weight: FontWeight.w700, color: bold ? fg : Tw.slate500),
              const SizedBox(height: 4),
              Text(body, style: bold ? tw(14, weight: FontWeight.w700) : tw(12, color: Tw.slate500)),
            ]),
          ),
        ]),
      );

  Widget _statusCard(IconData icon, Color fg, Color bg, String text) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: bg.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Icon(icon, size: 30, color: fg),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: tw(14, weight: black, color: fg)),
        ]),
      );

  Widget _requestButton(BuildContext context, bool hasAccess, bool full) {
    final disabled = _requesting || full;
    return Pressable(
      onTap: disabled
          ? () {}
          : () {
              if (!hasAccess) {
                showChillPaywall(context);
              } else {
                _request();
              }
            },
      scale: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: disabled ? Tw.slate800 : Tw.fuchsia600,
          borderRadius: BorderRadius.circular(16),
          boxShadow: disabled ? null : [BoxShadow(color: Tw.fuchsia600.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: -10)],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_requesting ? Icons.sync : hasAccess ? Icons.vpn_key : Icons.lock, color: disabled ? Tw.slate600 : Tw.white),
          const SizedBox(width: 8),
          Text(
            _requesting ? context.t('chill.requesting') : hasAccess ? context.t('chill.request_pass') : context.t('chill.unlock_access'),
            style: tw(18, weight: black, color: disabled ? Tw.slate600 : Tw.white),
          ),
        ]),
      ),
    );
  }

  List<Widget> _requestsTab(BuildContext context) {
    if (_requests.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(children: [
            const Icon(Icons.inbox, size: 36, color: Tw.slate700),
            const SizedBox(height: 8),
            Text(context.t('chill.no_requests'), style: tw(14, weight: bold, color: Tw.slate500)),
          ]),
        ),
      ];
    }
    return [
      for (final r in _requests)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Tw.slate900.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Tw.w(0.05)),
          ),
          child: Column(children: [
            Row(children: [
              GestureDetector(
                onTap: () => showProfileOverlay(context, r['user_uid'] as String),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Tw.w(0.1), width: 2)),
                  child: ClipOval(
                    child: NetImage(r['user_foto'] as String?, placeholder: Container(color: Tw.slate800, child: const Icon(Icons.person, color: Tw.slate600))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(safeStr(r['user_nick']), style: tw(14, weight: black)),
                  if (r['user_edad'] != null) Text('${r['user_edad']} ${context.t('chill.years_old')}', style: tw(10, weight: bold, color: Tw.slate500)),
                  if (safeStr(r['user_bio']).isNotEmpty)
                    Text(safeStr(r['user_bio']), maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(12, color: Tw.slate400)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Pressable(
                  onTap: () => _respond(r['user_uid'] as String, 'accept'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(12)),
                    child: Label(context.t('chill.accept'), size: 12, color: Tw.white, align: TextAlign.center),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Pressable(
                  onTap: () => _respond(r['user_uid'] as String, 'deny'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0x667F1D1D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
                    ),
                    child: Label(context.t('chill.deny'), size: 12, color: Tw.red400, align: TextAlign.center),
                  ),
                ),
              ),
            ]),
          ]),
        ),
    ];
  }

  List<Widget> _chatMessages(BuildContext context, String? uid) {
    if (_messages.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(children: [
            const Icon(Icons.forum, size: 36, color: Tw.slate700),
            const SizedBox(height: 8),
            Text(context.t('chill.no_messages'), style: tw(14, weight: bold, color: Tw.slate500)),
            Text(context.t('chill.start_conversation'), style: tw(12, color: Tw.slate600)),
          ]),
        ),
      ];
    }
    return [
      for (final m in _messages)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Builder(builder: (context) {
            final me = m['uid'] == uid;
            final time = parseDate(m['created_at']);
            return Row(
              mainAxisAlignment: me ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!me) ...[
                  GestureDetector(
                    onTap: () => showProfileOverlay(context, m['uid'] as String),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Tw.w(0.1))),
                      child: ClipOval(
                        child: NetImage(m['foto'] as String?, placeholder: Container(color: Tw.slate800, child: const Icon(Icons.person, size: 12, color: Tw.slate600))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75 - 40),
                  child: Column(crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                    if (!me)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        child: Text(safeStr(m['nick']), style: tw(10, weight: bold, color: Tw.fuchsia400)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: me ? Tw.fuchsia600 : Tw.slate800,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(me ? 16 : 2),
                          bottomRight: Radius.circular(me ? 2 : 16),
                        ),
                      ),
                      child: Text(safeStr(m['text']), style: tw(14, color: me ? Tw.white : const Color(0xFFE2E8F0))),
                    ),
                    if (time != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(DateFormat('HH:mm').format(time), style: tw(9, color: Tw.slate600)),
                      ),
                  ]),
                ),
              ],
            );
          }),
        ),
    ];
  }

  Widget _chatInput(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _msg,
              style: tw(14),
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: context.t('chill.write_message'),
                fillColor: Tw.slate900,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Tw.w(0.1))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.fuchsia500)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: _msg.text.trim().isEmpty ? () {} : _send,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: _msg.text.trim().isEmpty ? Tw.slate800 : Tw.fuchsia600, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.send, color: Tw.white),
            ),
          ),
        ]),
      );
}
