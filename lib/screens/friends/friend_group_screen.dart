import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../providers/auth_provider.dart';
import '../../services/finder_groups.dart';
import '../../services/finder_native.dart';
import '../../services/proximity.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/basemap.dart';
import '../../widgets/common.dart';
import '../../widgets/location_picker.dart';

/// One friend group: Bluetooth radar with each friend's distance, meeting point, and the invite (QR, code, NFC tap).
class FriendGroupScreen extends StatefulWidget {
  final String code;
  const FriendGroupScreen({super.key, required this.code});

  @override
  State<FriendGroupScreen> createState() => _FriendGroupScreenState();
}

class _FriendGroupScreenState extends State<FriendGroupScreen> with WidgetsBindingObserver {
  FinderGroup? _group;
  bool _loading = true;
  bool _synced = false;
  bool _busy = false;
  StreamSubscription? _sub;
  final _prox = Proximity.instance;

  String get _uid => context.read<AuthProvider>().user?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prox.addListener(_onProximity);
    _prox.refresh();
    _sub = watchGroup(widget.code).listen(_onGroup, onError: (_) => setState(() {
          _group = null;
          _loading = false;
        }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prox.removeListener(_onProximity);
    _sub?.cancel();
    FinderNative.setInvite(null);
    super.dispose();
  }

  void _onProximity() {
    if (mounted) setState(() {});
  }

  /// The invite is only handed out over NFC while this screen is in front.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _prox.refresh();
      _syncKeys();
      final g = _group;
      if (g != null) FinderNative.setInvite(g.invitePayload);
    } else if (state == AppLifecycleState.paused) {
      FinderNative.setInvite(null);
    }
  }

  Future<void> _onGroup(FinderGroup? g) async {
    final uid = _uid;
    if (g != null && !g.memberIds.contains(uid)) g = null;
    setState(() {
      _group = g;
      _loading = false;
    });
    FinderNative.setInvite(g?.invitePayload);
    // Once per visit: fill in a missing profile, and renew/publish this install's BLE key (reinstall, new phone).
    if (g != null && !_synced) {
      _synced = true;
      final mine = g.members[uid];
      if (mine == null || mine.nick.isEmpty) {
        final auth = context.read<AuthProvider>();
        await refreshMyEntry(g.code, uid: uid, nick: auth.profile?.nick ?? auth.user?.displayName ?? '', fotoUrl: auth.profile?.fotoUrl ?? '');
      }
      await _syncKeys();
    }
  }

  /// Renews/publishes this install's BLE key across all my groups, then updates the running radar.
  Future<void> _syncKeys() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    await syncMyBleKeys(uid: uid, nick: auth.profile?.nick ?? auth.user?.displayName ?? '', fotoUrl: auth.profile?.fotoUrl ?? '');
    await _prox.pushKeys();
  }

  Future<void> _startRadar() async {
    final i18n = context.read<I18n>();
    setState(() => _busy = true);
    try {
      var st = await _prox.refresh();
      if (!st.ble) return;
      if (!st.permissions) {
        if (!await FinderNative.requestPermissions()) {
          if (mounted) showToast(context, i18n.t('finder.no_permission'), error: true);
          return;
        }
        st = await _prox.refresh();
      }
      if (!st.enabled) {
        // System dialog; on return, didChangeAppLifecycleState refreshes and the user taps start again.
        await FinderNative.enableBluetooth();
        return;
      }
      final ok = await _prox.start(title: i18n.t('finder.notif_title'), text: i18n.t('finder.notif_text'));
      if (!ok && mounted) showToast(context, i18n.t('finder.error'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final g = _group;
    if (g == null) return;
    final i18n = context.read<I18n>();
    final uid = _uid;
    final lastOne = g.memberIds.length == 1;
    final deleting = lastOne && g.createdBy == uid;
    if (!await confirmDialog(context,
        message: i18n.t(deleting ? 'finder.delete_confirm' : 'finder.leave_confirm'),
        confirmText: i18n.t(deleting ? 'finder.delete' : 'finder.leave'),
        cancelText: i18n.t('finder.cancel'),
        danger: true)) {
      return;
    }
    try {
      await _sub?.cancel();
      deleting ? await deleteGroup(g.code) : await leaveGroup(g.code, uid);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) showToast(context, i18n.t('finder.error'), error: true);
    }
  }

  Future<void> _delete() async {
    final g = _group;
    if (g == null) return;
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context,
        message: i18n.t('finder.delete_confirm'), confirmText: i18n.t('finder.delete'), cancelText: i18n.t('finder.cancel'), danger: true)) {
      return;
    }
    try {
      await _sub?.cancel();
      await deleteGroup(g.code);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) showToast(context, i18n.t('finder.error'), error: true);
    }
  }

  Future<void> _editMeetingPoint() async {
    final g = _group;
    if (g == null) return;
    final result = await showModalBottomSheet<_MeetingEdit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => _MeetingSheet(initial: g.meetingPoint),
    );
    if (result == null || !mounted) return;
    try {
      await setMeetingPoint(g.code, _uid, label: result.label, lat: result.lat, lng: result.lng);
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('finder.error'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2))));
    final g = _group;
    if (g == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.group_off, size: 48, color: Tw.slate600),
                const SizedBox(height: 16),
                Text(context.t('finder.not_found'), textAlign: TextAlign.center, style: tw(15, color: Tw.slate400)),
                const SizedBox(height: 24),
                GradientButton(label: context.t('finder.title'), onTap: () => Navigator.of(context).maybePop()),
              ]),
            ),
          ),
        ),
      );
    }
    final uid = _uid;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 128), children: [
          Row(children: [
            IconButton(padding: EdgeInsets.zero, onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            const SizedBox(width: 4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(22, weight: black)),
                if (g.expiresAt != null)
                  Text(
                    context.t('finder.expires', params: {'date': DateFormat.MMMEd(context.i18n.dateLocale).add_Hm().format(g.expiresAt!)}),
                    style: tw(11, color: Tw.slate500),
                  ),
              ]),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Tw.slate400),
              color: Tw.slate900,
              onSelected: (v) => v == 'delete' ? _delete() : _leave(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'leave', child: Text(context.t('finder.leave'), style: tw(14))),
                if (g.createdBy == uid) PopupMenuItem(value: 'delete', child: Text(context.t('finder.delete'), style: tw(14, color: Tw.red400))),
              ],
            ),
          ]),
          const SizedBox(height: 16),
          _radarCard(context),
          const SizedBox(height: 16),
          _membersCard(context, g, uid),
          const SizedBox(height: 16),
          _meetingCard(context, g),
          const SizedBox(height: 16),
          _inviteCard(context, g),
        ]),
      ),
    );
  }

  Widget _radarCard(BuildContext context) {
    final st = _prox.state;
    final running = st.running;
    String? warning;
    if (!FinderNative.available) {
      warning = context.t('finder.android_only');
    } else if (!st.ble) {
      warning = context.t('finder.no_ble');
    } else if (running && (!st.advertise || _prox.advertiseFailed)) {
      warning = context.t('finder.no_advertise');
    } else if (!running && !st.permissions) {
      warning = context.t('finder.no_permission');
    } else if (!running && !st.enabled) {
      warning = context.t('finder.bt_off');
    }
    final canStart = FinderNative.available && st.ble;
    final startLabel = st.permissions && !st.enabled ? context.t('finder.bt_enable') : (st.permissions ? context.t('finder.radar_start') : context.t('finder.grant'));
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.all(18),
      borderColor: running ? Tw.cyan500.withValues(alpha: 0.4) : null,
      gradient: running ? LinearGradient(colors: [Tw.cyan500.withValues(alpha: 0.15), Tw.indigo600.withValues(alpha: 0.08)]) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Pulse(active: running),
          const SizedBox(width: 12),
          Expanded(child: Label(context.t('finder.radar_title'), color: running ? Tw.cyan400 : Tw.slate400, size: 11)),
          if (running)
            TextButton(
              onPressed: _busy ? null : () => _prox.stop(),
              child: Label(context.t('finder.radar_stop'), color: Tw.slate400),
            ),
        ]),
        const SizedBox(height: 10),
        Text(running ? context.t('finder.radar_on') : context.t('finder.radar_off'), style: tw(13, color: Tw.slate300, height: 1.5)),
        if (warning != null) ...[
          const SizedBox(height: 8),
          Text(warning, style: tw(12, color: Tw.amber400, height: 1.4)),
        ],
        if (!running && canStart) ...[
          const SizedBox(height: 14),
          GradientButton(
            label: startLabel,
            icon: Icons.bluetooth_searching,
            loading: _busy,
            expand: true,
            gradient: const LinearGradient(colors: [Tw.cyan600, Tw.indigo600]),
            onTap: _startRadar,
          ),
        ],
      ]),
    );
  }

  Widget _membersCard(BuildContext context, FinderGroup g, String uid) {
    final others = g.orderedMembers.where((m) => m.uid != uid).toList()
      ..sort((a, b) {
        double score(FinderMember m) {
          final r = _prox.readingFor(m.advertisedIds);
          if (r == null) return -1000;
          return r.band == ProximityBand.lost ? -500 - DateTime.now().difference(r.lastSeen).inSeconds / 1000 : r.rssi;
        }

        return score(b).compareTo(score(a));
      });
    final me = g.members[uid] ?? FinderMember(uid: uid);
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Label('${context.t('finder.members')} · ${g.memberIds.length}/$finderMaxMembers', size: 11),
        const SizedBox(height: 8),
        _MemberRow(member: me, isMe: true, reading: null, radarOn: false),
        for (final m in others) _MemberRow(member: m, isMe: false, reading: _prox.readingFor(m.advertisedIds), radarOn: _prox.running),
      ]),
    );
  }

  Widget _meetingCard(BuildContext context, FinderGroup g) {
    final p = g.meetingPoint;
    final setBy = p == null ? null : g.members[p.setBy]?.nick;
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.place, size: 18, color: Tw.fuchsia400),
          const SizedBox(width: 8),
          Expanded(child: Label(context.t('finder.meeting_title'), size: 11)),
          TextButton(
            onPressed: _editMeetingPoint,
            child: Label(p == null ? context.t('finder.meeting_set') : context.t('finder.meeting_change'), color: Tw.fuchsia400),
          ),
        ]),
        if (p == null)
          Text(context.t('finder.meeting_empty'), style: tw(13, color: Tw.slate400, height: 1.5))
        else ...[
          Text(p.label, style: tw(17, weight: black)),
          if (setBy != null && setBy.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(context.t('finder.meeting_set_by', params: {'nick': setBy}), style: tw(11, color: Tw.slate500)),
            ),
          if (p.hasCoords) ...[
            const SizedBox(height: 12),
            Container(
              height: 170,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(p.lat!, p.lng!),
                  initialZoom: 16,
                  backgroundColor: Basemap.background,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                ),
                children: [
                  const Basemap(),
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(p.lat!, p.lng!),
                      width: 36,
                      height: 36,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.place, size: 34, color: Tw.fuchsia500, shadows: [Shadow(color: Color(0x88000000), blurRadius: 6)]),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GlassCard(
              radius: 12,
              padding: const EdgeInsets.symmetric(vertical: 12),
              onTap: () => launchUrl(
                Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}&travelmode=walking'),
                mode: LaunchMode.externalApplication,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.directions_walk, size: 16, color: Tw.white),
                const SizedBox(width: 8),
                Label(context.t('finder.meeting_directions'), color: Tw.white),
              ]),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _inviteCard(BuildContext context, FinderGroup g) {
    final i18n = context.i18n;
    final st = _prox.state;
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.person_add, size: 18, color: Tw.emerald400),
          const SizedBox(width: 8),
          Expanded(child: Label(context.t('finder.invite_title'), size: 11)),
        ]),
        const SizedBox(height: 8),
        Text(context.t('finder.invite_body'), style: tw(12, color: Tw.slate400, height: 1.5)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(20)),
          child: QrImageView(data: g.invitePayload, size: 180, padding: EdgeInsets.zero, backgroundColor: Tw.white),
        ),
        const SizedBox(height: 14),
        Pressable(
          onTap: () {
            Clipboard.setData(ClipboardData(text: g.code));
            showToast(context, i18n.t('finder.copied'));
          },
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(g.code, style: tw(30, weight: black, tracking: 0.25).copyWith(fontFamily: 'monospace')),
            const SizedBox(width: 8),
            const Icon(Icons.copy, size: 16, color: Tw.slate500),
          ]),
        ),
        if (st.hce && st.nfcOn) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Tw.emerald500.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.nfc, size: 14, color: Tw.emerald400),
              const SizedBox(width: 6),
              Label(context.t('finder.nfc_ready'), size: 9, color: Tw.emerald400, tracking: 0.05),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        GradientButton(
          label: context.t('finder.share'),
          icon: Icons.share,
          expand: true,
          onTap: () => SharePlus.instance.share(ShareParams(text: i18n.t('finder.share_text', params: {'name': g.name, 'code': g.code}))),
        ),
      ]),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final FinderMember member;
  final bool isMe;
  final PeerReading? reading;
  final bool radarOn;
  const _MemberRow({required this.member, required this.isMe, required this.reading, required this.radarOn});

  @override
  Widget build(BuildContext context) {
    final nick = member.nick.isEmpty ? '—' : member.nick;
    Widget? status;
    if (isMe) {
      status = _Chip(context.t('finder.you'), Tw.fuchsia400);
    } else if (reading != null) {
      final r = reading!;
      final (label, color) = switch (r.band) {
        ProximityBand.veryClose => (context.t('finder.very_close'), Tw.emerald400),
        ProximityBand.near => (context.t('finder.near'), Tw.amber400),
        ProximityBand.far => (context.t('finder.far'), Tw.orange400),
        ProximityBand.lost => (
            context.t('finder.seen_ago', params: {'min': DateTime.now().difference(r.lastSeen).inMinutes.clamp(1, 999)}),
            Tw.slate500
          ),
      };
      status = Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _Chip(label, color),
        if (r.band != ProximityBand.lost) ...[
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (r.trend != 0) ...[
              Icon(r.trend > 0 ? Icons.trending_up : Icons.trending_down, size: 14, color: r.trend > 0 ? Tw.emerald400 : Tw.slate500),
              const SizedBox(width: 4),
              Text(context.t(r.trend > 0 ? 'finder.closer' : 'finder.farther'), style: tw(10, color: Tw.slate500)),
              const SizedBox(width: 6),
            ],
            Text(context.t('finder.approx_m', params: {'m': r.approxMeters}), style: tw(11, weight: bold, color: Tw.slate300)),
          ]),
        ],
      ]);
    } else if (radarOn) {
      status = _Chip(context.t('finder.no_signal'), Tw.slate600);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        ClipOval(
          child: SizedBox(
            width: 40,
            height: 40,
            child: member.fotoUrl.isEmpty
                ? Container(
                    color: Tw.w(0.08),
                    alignment: Alignment.center,
                    child: Text(nick.characters.first.toUpperCase(), style: tw(16, weight: black, color: Tw.slate300)),
                  )
                : NetImage(member.fotoUrl, width: 40, height: 40),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(nick, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(15, weight: bold))),
        ?status,
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Label(label, size: 9, color: color, tracking: 0.05),
      );
}

/// Radar dot: pulses while scanning.
class _Pulse extends StatefulWidget {
  final bool active;
  const _Pulse({required this.active});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? Tw.cyan400 : Tw.slate600;
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(alignment: Alignment.center, children: [
          if (widget.active)
            Container(
              width: 8 + 14 * _c.value,
              height: 8 + 14 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.4 * (1 - _c.value))),
            ),
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        ]),
      ),
    );
  }
}

class _MeetingEdit {
  final String? label;
  final double? lat;
  final double? lng;
  const _MeetingEdit(this.label, this.lat, this.lng);
}

/// Label + optional map pin. Pops a [_MeetingEdit]; a null label clears the meeting point.
class _MeetingSheet extends StatefulWidget {
  final MeetingPoint? initial;
  const _MeetingSheet({this.initial});

  @override
  State<_MeetingSheet> createState() => _MeetingSheetState();
}

class _MeetingSheetState extends State<_MeetingSheet> {
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  late double? _lat = widget.initial?.lat;
  late double? _lng = widget.initial?.lng;
  final _picker = LocationPickerController();
  bool _locating = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 10)));
      _picker.flyTo(pos.latitude, pos.longitude);
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('finder.error'), error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _label.text.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: BoxDecoration(
          color: Tw.slate900,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Tw.w(0.1)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Tw.w(0.2), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(context.t('finder.meeting_title'), style: tw(20, weight: black)),
              const SizedBox(height: 16),
              Label(context.t('finder.meeting_label')),
              const SizedBox(height: 8),
              TextField(
                controller: _label,
                maxLength: 60,
                style: tw(14),
                cursorColor: Tw.fuchsia500,
                decoration: adminInputDecoration(context.t('finder.meeting_label_hint')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Label(context.t('finder.meeting_pick_map'))),
                TextButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  icon: _locating
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 16, color: Tw.cyan400),
                  label: Label(context.t('finder.meeting_my_location'), color: Tw.cyan400),
                ),
              ]),
              const SizedBox(height: 8),
              VenueLocationPicker(
                initialLat: _lat,
                initialLng: _lng,
                controller: _picker,
                height: 220,
                onLocationChange: (lat, lng) => setState(() {
                  _lat = lat;
                  _lng = lng;
                }),
              ),
              const SizedBox(height: 20),
              Row(children: [
                if (widget.initial != null) ...[
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(const _MeetingEdit(null, null, null)),
                      child: Label(context.t('finder.meeting_clear'), color: Tw.red400),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: GradientButton(
                    label: context.t('finder.save'),
                    expand: true,
                    onTap: label.isEmpty ? null : () => Navigator.of(context).pop(_MeetingEdit(label, _lat, _lng)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
