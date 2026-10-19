import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/dynamic_qr.dart';

/// Port of app/ticket/page.tsx (chill access pass for an accepted request).
class ChillTicketScreen extends StatefulWidget {
  final String id;
  const ChillTicketScreen({super.key, required this.id});

  @override
  State<ChillTicketScreen> createState() => _ChillTicketScreenState();
}

class _ChillTicketScreenState extends State<ChillTicketScreen> {
  final _db = FirebaseFirestore.instance;
  StreamSubscription? _sub;
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _chill;
  Map<String, dynamic>? _secrets;
  String? _exactAddress;
  bool _loading = true;
  bool _secretsRequested = false;

  bool get _accepted => safeStr(_request?['status']).toLowerCase() == 'accepted';
  bool get _checkedIn => _request?['checkedIn'] == true;

  @override
  void initState() {
    super.initState();
    if (widget.id.isEmpty) {
      _loading = false;
      return;
    }
    _sub = _db.collection('chill_requests').doc(widget.id).snapshots().listen((snap) async {
      if (snap.exists) {
        _request = {'id': snap.id, ...?snap.data()};
        if (_chill == null) {
          final chillId = safeStr(_request!['chill_id'] ?? _request!['chillId']);
          if (chillId.isNotEmpty) {
            final c = await _db.collection('chills').doc(chillId).get();
            if (c.exists) {
              _chill = {'id': c.id, ...?c.data()};
              _loadAddress();
            }
          }
        }
        _loadSecrets();
      } else {
        final ticket = await _db.collection('tickets').doc(widget.id).get();
        if (ticket.exists) {
          if (mounted) openRoute(context, AppRoute.pass, args: {'id': widget.id}, replace: true);
          return;
        }
        _request = null;
      }
      if (mounted) setState(() => _loading = false);
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _loadSecrets() {
    if (_secretsRequested || !_accepted || _checkedIn) return;
    _secretsRequested = true;
    // Only the key that draws the dynamic QR: never the static code, nor a PIN (2026-10-13).
    _db.doc('chill_requests/${widget.id}/private/secrets').get().then((s) {
      _secrets = {'secretKey': s.exists ? (s.data()?['secretKey']) : null};
      if (mounted) setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _secrets = const {});
    });
  }

  void _loadAddress() {
    final chill = _chill!;
    final fallback = chill['exact_address'] as String?;
    _db.doc('chills/${chill['id']}/private/info').get().then((s) {
      _exactAddress = s.exists ? (s.data()?['exact_address'] as String?) : fallback;
      if (mounted) setState(() {});
    }).catchError((_) {
      if (fallback != null && mounted) setState(() => _exactAddress = fallback);
    });
  }

  Widget _state(IconData icon, Color color, String title, String desc) => Scaffold(
        backgroundColor: Tw.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: tw(20, weight: black)),
              const SizedBox(height: 8),
              Text(desc, textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: Tw.black, body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final r = _request;
    final chill = _chill;
    if (r == null || chill == null) {
      return _state(Icons.error_outline, Tw.red500, context.t('ticket.passNotFoundTitle'), context.t('ticket.passNotFoundDesc'));
    }
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return _state(Icons.login, Tw.amber500, context.t('ticket.loginRequired', fallback: 'Inicia sesion'),
          context.t('ticket.loginRequiredDesc', fallback: 'Necesitas iniciar sesion para ver tu pase.'));
    }
    if (r['user_uid'] != user.uid) {
      return _state(Icons.lock, Tw.red500, context.t('ticket.accessDeniedTitle'), context.t('ticket.accessDeniedDesc'));
    }
    if (!_accepted) {
      return _state(Icons.cancel, Tw.amber500, context.t('ticket.passRevokedTitle'), context.t('ticket.passRevokedDesc'));
    }

    final hasQr = r['qr_code'] != null;
    final address = _exactAddress;
    final mapsQuery = address != null ? Uri.encodeComponent(address) : '${chill['approx_lat']},${chill['approx_lng']}';
    final nick = safeStr(r['user_nick']).isNotEmpty ? safeStr(r['user_nick']) : safeStr(r['userName']);

    return Scaffold(
      backgroundColor: Tw.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 384),
              child: Column(children: [
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.purple600]),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.2), blurRadius: 20)],
                  ),
                  child: Column(children: [
                    Label(context.t('ticket.digitalAccessPass'), color: Tw.w(0.8), tracking: 0.2),
                    const SizedBox(height: 4),
                    Text(safeStr(chill['title']), textAlign: TextAlign.center, style: tw(20, weight: black)),
                    const SizedBox(height: 4),
                    Text(
                      chill['type'] == 'commercial' ? context.t('ticket.privateParty') : context.t('ticket.socialChill'),
                      style: tw(12, color: Tw.w(0.9)),
                    ),
                  ]),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Tw.slate900.withValues(alpha: 0.8),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    border: Border(
                      left: BorderSide(color: Tw.w(0.05)),
                      right: BorderSide(color: Tw.w(0.05)),
                      bottom: BorderSide(color: Tw.w(0.05)),
                    ),
                  ),
                  child: Column(children: [
                    if (hasQr) ...[
                      if (_checkedIn)
                        Container(
                          width: 192,
                          height: 192,
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: Tw.emerald500.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Tw.emerald500.withValues(alpha: 0.5), width: 2),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.check_circle, size: 48, color: Tw.emerald400),
                            const SizedBox(height: 8),
                            Text(context.t('ticket.passValidated'), textAlign: TextAlign.center, style: tw(14, weight: bold, color: Tw.emerald400)),
                          ]),
                        )
                      else if (_secrets != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: DynamicQR(ticketId: widget.id, secretKey: _secrets!['secretKey'] as String?, size: 180),
                        )
                      else
                        Container(
                          width: 192,
                          height: 192,
                          margin: const EdgeInsets.only(bottom: 24),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(16)),
                          child: Text(context.t('ticket.loadingQR', fallback: 'Cargando QR...'), style: tw(12, color: Tw.slate500)),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 240),
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Tw.amber500.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Tw.amber500.withValues(alpha: 0.2)),
                        ),
                        child: Column(children: [
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.warning, size: 10, color: Tw.amber500),
                            const SizedBox(width: 4),
                            Flexible(child: Label(context.t('ticket.attendeeNotice'), size: 9, weight: bold, color: Tw.amber500)),
                          ]),
                          const SizedBox(height: 4),
                          Text(context.t('ticket.disclaimer'),
                              textAlign: TextAlign.center, style: tw(10, color: const Color(0xB3FDE68A), height: 1.25)),
                        ]),
                      ),
                    ] else
                      Container(
                        width: 96,
                        height: 96,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Tw.fuchsia500.withValues(alpha: 0.1),
                          border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.vpn_key, size: 36, color: Tw.fuchsia500),
                      ),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Label(context.t('ticket.yourName'), size: 9, weight: bold, tracking: 0.05),
                      const SizedBox(height: 4),
                      SizedBox(width: double.infinity, child: Text(nick, style: tw(14, weight: bold))),
                      const SizedBox(height: 16),
                      Divider(color: Tw.w(0.1), height: 1),
                      const SizedBox(height: 16),
                      Label(context.t('ticket.unlockedLocation'), size: 9, weight: bold, color: Tw.emerald400, tracking: 0.05),
                      const SizedBox(height: 4),
                      Text(address ?? context.t('ticket.loadingAddress'), style: tw(14, weight: medium, color: const Color(0xFFE2E8F0))),
                      const SizedBox(height: 12),
                      GlassCard(
                        onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$mapsQuery'),
                            mode: LaunchMode.externalApplication),
                        radius: 12,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.map, size: 16, color: Tw.blue400),
                          const SizedBox(width: 8),
                          Text(context.t('ticket.openInMaps'), style: tw(12, weight: bold)),
                        ]),
                      ),
                      if (safeStr(chill['instructions']).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Divider(color: Tw.w(0.1), height: 1),
                        const SizedBox(height: 16),
                        Label(context.t('ticket.arrivalInstructions'), size: 9, weight: bold, color: Tw.amber400, tracking: 0.05),
                        const SizedBox(height: 4),
                        Text('"${chill['instructions']}"', style: tw(12, color: Tw.slate300, style: FontStyle.italic)),
                      ],
                    ]),
                  ]),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => openRoute(context, AppRoute.home),
                  child: Label(context.t('ticket.viewRadar').replaceAll('&rarr;', '→'), size: 12, weight: bold, color: Tw.purple400, tracking: 0.05),
                ),
                const SizedBox(height: 24),
                Text(context.t('ticket.selfDestruct'), textAlign: TextAlign.center, style: tw(10, color: Tw.slate600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
