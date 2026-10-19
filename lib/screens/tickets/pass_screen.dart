import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/dynamic_qr.dart';

/// sessionStorage 'lastGuestAccess' equivalent: lives for the app session.
String? _lastGuestAccess;

/// Port of app/pass/page.tsx
class PassScreen extends StatefulWidget {
  final String? id;
  final String? accessToken;
  const PassScreen({super.key, this.id, this.accessToken});

  @override
  State<PassScreen> createState() => _PassScreenState();
}

class _PassScreenState extends State<PassScreen> {
  Map<String, dynamic>? _ticket;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.accessToken ?? _lastGuestAccess;
    if (widget.accessToken != null) _lastGuestAccess = widget.accessToken;
    try {
      if (token != null) {
        final res = await FirebaseFunctions.instance.httpsCallable('getGuestTicket').call({'accessToken': token});
        if (res.data is Map) _ticket = Map<String, dynamic>.from(res.data as Map);
      } else if (widget.id != null) {
        final db = FirebaseFirestore.instance;
        final snap = await db.collection('tickets').doc(widget.id).get();
        if (snap.exists) {
          final t = <String, dynamic>{'id': snap.id, ...?snap.data()};
          // Only the key that draws the dynamic QR: no static code or PIN is shown (2026-10-13).
          final secrets = await db.doc('tickets/${widget.id}/private/secrets').get();
          if (secrets.exists) t['secretKey'] = secrets.data()?['secretKey'];
          _ticket = t;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Widget _error(BuildContext context, IconData icon, String title, String desc) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 48, color: Tw.red500),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: tw(20, weight: bold)),
              const SizedBox(height: 8),
              Text(desc, textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
              const SizedBox(height: 24),
              GlassCard(
                onTap: () => Navigator.of(context).maybePop(),
                radius: 12,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text(context.t('pass.go_back', fallback: 'Volver'), style: tw(14, weight: bold)),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final t = _ticket;
    if (t == null) return _error(context, Icons.error_outline, context.t('pass.error.not_found_title'), context.t('pass.error.not_found_desc'));
    final uid = context.watch<AuthProvider>().user?.uid;
    if (uid != null && t['userId'] != null && t['userId'] != uid && widget.accessToken == null) {
      return _error(context, Icons.lock, context.t('pass.error.access_denied_title'), context.t('pass.error.access_denied_desc'));
    }
    final flyer = t['flyerUrl'] as String?;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 400),
              builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 20 * (1 - v)), child: c)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 384),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Tw.slate900,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Tw.slate800),
                  boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 25))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    height: 192,
                    child: Stack(fit: StackFit.expand, children: [
                      flyer != null && flyer.isNotEmpty
                          ? NetImage(flyer)
                          : Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFF701A75), Color(0xFF3B0764), Tw.slate950],
                                ),
                              ),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Text('🪩', style: TextStyle(fontSize: 36)),
                                const SizedBox(height: 4),
                                Label(context.t('pass_brand_title', fallback: 'Blow Nights Pass'), color: Tw.slate500),
                              ]),
                            ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Tw.slate900, Colors.transparent, Color(0x4D000000)],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Tw.fuchsia600.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(99)),
                          child: Label(context.t('pass.official_pass'), color: Tw.white, tracking: 0.05),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(safeStr(t['eventTitle']).isNotEmpty ? safeStr(t['eventTitle']) : context.t('pass.default_event_title'),
                          style: tw(20, weight: black, tracking: -0.025)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.location_on, size: 14, color: Tw.fuchsia400),
                        const SizedBox(width: 4),
                        Text(safeStr(t['venueName']).isNotEmpty ? safeStr(t['venueName']) : context.t('pass.default_venue_name'),
                            style: tw(12, weight: semibold, color: Tw.fuchsia400)),
                      ]),
                      if (safeStr(t['eventDate']).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.event, size: 14, color: Tw.slate400),
                          const SizedBox(width: 4),
                          Text(safeStr(t['eventDate']), style: tw(12, weight: medium, color: Tw.slate400)),
                          if (safeStr(t['eventTime']).isNotEmpty) ...[
                            Text('  •  ', style: tw(12, color: Tw.slate400)),
                            const Icon(Icons.schedule, size: 14, color: Tw.slate400),
                            const SizedBox(width: 4),
                            Text('${t['eventTime']}h', style: tw(12, weight: medium, color: Tw.slate400)),
                          ],
                        ]),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Tw.w(0.05)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Label(context.t('pass.ticket_type_label'), color: Tw.slate500, tracking: 0.05),
                          Text(safeStr(t['tierName'] ?? t['ticketType']).isNotEmpty ? safeStr(t['tierName'] ?? t['ticketType']) : context.t('pass.default_tier_name'),
                              style: tw(12, weight: bold, color: Tw.emerald400, tracking: 0.025)),
                          const SizedBox(height: 2),
                          Text('${context.t('pass.guest_prefix')}${safeStr(t['client_name']).isNotEmpty ? safeStr(t['client_name']) : context.t('pass.anonymous')}',
                              style: tw(10, weight: medium, color: Tw.slate400)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Label('RRPP', color: Tw.slate500, tracking: 0.05),
                        Text(safeStr(t['promoter_name']).isNotEmpty ? safeStr(t['promoter_name']) : context.t('pass.official_promoter'),
                            style: tw(12, weight: bold, color: Tw.slate300)),
                      ]),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Column(children: [
                      if (t['status'] == 'used')
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(children: [
                            const Icon(Icons.check_circle, size: 48, color: Tw.emerald500),
                            const SizedBox(height: 8),
                            Text(context.t('wallet.ticket_used', fallback: 'Entrada usada'), style: tw(14, weight: bold, color: Tw.emerald400)),
                          ]),
                        )
                      else if (t['secretKey'] != null)
                        DynamicQR(ticketId: safeStr(t['id']), secretKey: t['secretKey'] as String?, size: 170)
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(context.t('pass.no_qr', fallback: 'QR no disponible'), style: tw(12, color: Tw.slate500)),
                        ),
                      if (t['status'] == 'valid') ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(context.t('pass.presentation_instruction'),
                              textAlign: TextAlign.center, style: tw(10, weight: medium, color: Tw.slate500, height: 1.25)),
                        ),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
