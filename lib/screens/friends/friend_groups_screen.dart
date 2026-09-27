import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/finder_groups.dart';
import '../../services/finder_native.dart';
import '../../services/proximity.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import '../admin/scanner_screens.dart' show QrCamera;

/// Friend finder home: my groups (live), create one, join one by code / QR / NFC tap. App-only, no web equivalent.
class FriendGroupsScreen extends StatefulWidget {
  final String? joinCode;
  const FriendGroupsScreen({super.key, this.joinCode});

  @override
  State<FriendGroupsScreen> createState() => _FriendGroupsScreenState();
}

class _FriendGroupsScreenState extends State<FriendGroupsScreen> {
  List<FinderGroup>? _groups;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openRoute(context, AppRoute.login, replace: true);
      });
      return;
    }
    _sub = watchMyGroups(uid).listen((g) => setState(() => _groups = g), onError: (_) => setState(() => _groups = const []));
    // Renew / publish the BLE key while we're probably online (see ble_identity.dart).
    final auth = context.read<AuthProvider>();
    syncMyBleKeys(uid: uid, nick: auth.profile?.nick ?? auth.user?.displayName ?? '', fotoUrl: auth.profile?.fotoUrl ?? '')
        .then((_) => Proximity.instance.pushKeys(), onError: (_) {});
    if (widget.joinCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _join(widget.joinCode!));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  ({String uid, String nick, String foto})? get _me {
    final auth = context.read<AuthProvider>();
    final u = auth.user;
    if (u == null) return null;
    return (uid: u.uid, nick: auth.profile?.nick ?? u.displayName ?? '', foto: auth.profile?.fotoUrl ?? '');
  }

  void _openGroup(String code) => openRoute(context, AppRoute.friendGroup, args: {'code': code});

  Future<void> _create() async {
    final i18n = context.read<I18n>();
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: Tw.slate900,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Tw.w(0.1))),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(i18n.t('finder.create'), style: tw(18, weight: black)),
            const SizedBox(height: 16),
            Label(i18n.t('finder.group_name')),
            const SizedBox(height: 8),
            TextField(
              controller: name,
              autofocus: true,
              maxLength: 40,
              style: tw(14),
              cursorColor: Tw.fuchsia500,
              decoration: adminInputDecoration(i18n.t('finder.group_name_hint')),
              onSubmitted: (_) => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Label(i18n.t('finder.cancel'), color: Tw.slate400),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(label: i18n.t('finder.create_cta'), onTap: () => Navigator.of(ctx).pop(true), padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ]),
          ]),
        ),
      ),
    );
    final me = _me;
    final text = name.text.trim();
    name.dispose();
    if (ok != true || me == null || !mounted) return;
    try {
      final code = await createGroup(uid: me.uid, name: text.isEmpty ? i18n.t('finder.title') : text, nick: me.nick, fotoUrl: me.foto);
      if (mounted) _openGroup(code);
    } catch (_) {
      if (mounted) showToast(context, i18n.t('finder.error'), error: true);
    }
  }

  Future<void> _join(String raw) async {
    final i18n = context.read<I18n>();
    final code = parseInviteCode(raw);
    final me = _me;
    if (me == null) return;
    if (code == null) {
      showToast(context, i18n.t('finder.invalid_code'), error: true);
      return;
    }
    final res = await joinGroup(code: code, uid: me.uid, nick: me.nick, fotoUrl: me.foto);
    if (!mounted) return;
    switch (res) {
      case JoinResult.invalid:
        showToast(context, i18n.t('finder.invalid_code'), error: true);
      case JoinResult.joined:
        showToast(context, i18n.t('finder.joined'));
        _openGroup(code);
      case JoinResult.alreadyMember:
        showToast(context, i18n.t('finder.already_member'));
        _openGroup(code);
    }
  }

  Future<void> _openJoinSheet() async {
    final raw = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => const _JoinSheet(),
    );
    if (raw != null && mounted) await _join(raw);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 128), children: [
          Row(children: [
            IconButton(padding: EdgeInsets.zero, onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('finder.title'), style: tw(24, weight: black)),
                Text(context.t('finder.subtitle'), style: tw(12, color: Tw.slate500)),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
          GlassCard(
            radius: 20,
            padding: const EdgeInsets.all(20),
            gradient: LinearGradient(colors: [Tw.cyan500.withValues(alpha: 0.15), Tw.indigo600.withValues(alpha: 0.1)]),
            borderColor: Tw.cyan500.withValues(alpha: 0.3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.bluetooth_searching, color: Tw.cyan400, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Label(context.t('finder.how_title'), color: Tw.cyan400),
                  const SizedBox(height: 6),
                  Text(context.t('finder.how_body'), style: tw(13, color: Tw.slate300, height: 1.5)),
                  if (!FinderNative.available) ...[
                    const SizedBox(height: 8),
                    Text(context.t('finder.android_only'), style: tw(12, color: Tw.amber400)),
                  ],
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GradientButton(label: context.t('finder.create'), icon: Icons.group_add, onTap: _create, expand: true, padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12))),
            const SizedBox(width: 12),
            Expanded(
              child: GlassCard(
                onTap: _openJoinSheet,
                radius: 16,
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.login, size: 16, color: Tw.white),
                  const SizedBox(width: 8),
                  Flexible(child: Label(context.t('finder.join'), color: Tw.white, maxLines: 1)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 32),
          if (groups == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(children: [
                const Icon(Icons.groups, size: 48, color: Tw.slate700),
                const SizedBox(height: 12),
                Text(context.t('finder.empty'), style: tw(15, color: Tw.slate500)),
              ]),
            )
          else
            for (final g in groups) _GroupCard(group: g, onTap: () => _openGroup(g.code)),
        ]),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final FinderGroup group;
  final VoidCallback onTap;
  const _GroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final expires = group.expiresAt == null ? '' : DateFormat.MMMEd(i18n.dateLocale).add_Hm().format(group.expiresAt!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        onTap: onTap,
        radius: 16,
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Tw.cyan500.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.groups, color: Tw.cyan400),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(15, weight: black)),
              const SizedBox(height: 4),
              Text(
                [
                  i18n.t('finder.members_count', params: {'count': group.memberIds.length}),
                  if (group.meetingPoint != null) '📍 ${group.meetingPoint!.label}',
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tw(12, color: Tw.slate400),
              ),
              if (expires.isNotEmpty) Text(i18n.t('finder.expires', params: {'date': expires}), style: tw(11, color: Tw.slate600)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Tw.slate600),
        ]),
      ),
    );
  }
}

/// Code field + QR camera + NFC tap. Pops with the raw text read; the caller parses and joins.
class _JoinSheet extends StatefulWidget {
  const _JoinSheet();

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

enum _JoinMode { code, qr, nfc }

class _JoinSheetState extends State<_JoinSheet> {
  final _code = TextEditingController();
  var _mode = _JoinMode.code;
  bool _nfcOk = true;
  bool _done = false;

  @override
  void dispose() {
    FinderNative.stopReading();
    _code.dispose();
    super.dispose();
  }

  void _finish(String raw) {
    if (_done || parseInviteCode(raw) == null) return;
    _done = true;
    Navigator.of(context).pop(raw);
  }

  Future<void> _setMode(_JoinMode m) async {
    if (m == _mode) return;
    await FinderNative.stopReading();
    setState(() => _mode = m);
    if (m == _JoinMode.nfc) {
      final ok = await FinderNative.readInvites((p) {
        if (mounted) _finish(p);
      });
      if (mounted) setState(() => _nfcOk = ok);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tab(_JoinMode m, IconData icon, String label) => Expanded(
          child: Pressable(
            onTap: () => _setMode(m),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _mode == m ? Tw.fuchsia600.withValues(alpha: 0.2) : Tw.w(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _mode == m ? Tw.fuchsia500.withValues(alpha: 0.5) : Tw.w(0.1)),
              ),
              child: Column(children: [
                Icon(icon, size: 18, color: _mode == m ? Tw.fuchsia400 : Tw.slate400),
                const SizedBox(height: 4),
                Label(label, size: 9, color: _mode == m ? Tw.white : Tw.slate400, align: TextAlign.center, maxLines: 1),
              ]),
            ),
          ),
        );

    final body = switch (_mode) {
      _JoinMode.code => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: tw(28, weight: black, tracking: 0.3).copyWith(fontFamily: 'monospace'),
            cursorColor: Tw.fuchsia500,
            decoration: adminInputDecoration('K7QX2M'),
            onChanged: (_) => setState(() {}),
            onSubmitted: _finish,
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: context.t('finder.join_cta'),
            expand: true,
            onTap: parseInviteCode(_code.text) == null ? null : () => _finish(_code.text),
          ),
        ]),
      _JoinMode.qr => ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(height: 300, child: QrCamera(onCode: _finish)),
        ),
      _JoinMode.nfc => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            Icon(_nfcOk ? Icons.nfc : Icons.portable_wifi_off, size: 56, color: _nfcOk ? Tw.cyan400 : Tw.red400),
            const SizedBox(height: 16),
            Text(_nfcOk ? context.t('finder.nfc_waiting') : context.t('finder.nfc_unavailable'),
                textAlign: TextAlign.center, style: tw(14, color: Tw.slate300, height: 1.5)),
            if (_nfcOk) ...[
              const SizedBox(height: 16),
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.cyan400)),
            ],
          ]),
        ),
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: BoxDecoration(
          color: Tw.slate900,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Tw.w(0.1)),
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Tw.w(0.2), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(context.t('finder.join'), style: tw(20, weight: black)),
            const SizedBox(height: 16),
            Row(children: [
              tab(_JoinMode.code, Icons.keyboard, context.t('finder.code_label')),
              const SizedBox(width: 8),
              tab(_JoinMode.qr, Icons.qr_code_scanner, context.t('finder.scan_qr')),
              if (FinderNative.available) ...[
                const SizedBox(width: 8),
                tab(_JoinMode.nfc, Icons.nfc, context.t('finder.tap_nfc')),
              ],
            ]),
            const SizedBox(height: 20),
            body,
          ]),
        ),
      ),
    );
  }
}
