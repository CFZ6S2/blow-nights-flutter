import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/nfc_pass.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/dynamic_qr.dart' show NfcPassHint;

/// Listens to `checkins/{uid}`; shared by Mis Copas and the bar order page.
Stream<Map<String, dynamic>?> checkinStream(String uid) =>
    FirebaseFirestore.instance.collection('checkins').doc(uid).snapshots().map((s) => s.exists ? s.data() : null);

bool checkinExpired(Map<String, dynamic> c) {
  final exp = parseDate(c['expiresAt']);
  return exp == null || !exp.isAfter(DateTime.now());
}

/// Port of app/tickets/consumption/page.tsx (Mis Copas)
class ConsumptionScreen extends StatefulWidget {
  final bool success;
  const ConsumptionScreen({super.key, this.success = false});

  @override
  State<ConsumptionScreen> createState() => _ConsumptionScreenState();
}

class _ConsumptionScreenState extends State<ConsumptionScreen> {
  StreamSubscription? _ticketsSub;
  StreamSubscription? _checkinSub;
  String? _uid;
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  bool _usedTab = false;
  bool _showToast = false;
  ({String venueId, String venueName})? _checkin;

  @override
  void initState() {
    super.initState();
    if (widget.success) {
      _showToast = true;
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) setState(() => _showToast = false);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthProvider>().user?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _ticketsSub?.cancel();
    _checkinSub?.cancel();
    if (uid == null) {
      _tickets = [];
      _checkin = null;
      _loading = false;
      return;
    }
    _checkinSub = checkinStream(uid).listen((c) {
      final active = c != null && !checkinExpired(c) && safeStr(c['venueId']).isNotEmpty;
      setState(() => _checkin = active
          ? (venueId: safeStr(c['venueId']), venueName: safeStr(c['venueName']).isNotEmpty ? safeStr(c['venueName']) : 'el local')
          : null);
    }, onError: (_) {});
    _ticketsSub = FirebaseFirestore.instance
        .collection('consumption_tickets')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      final list = snap.docs.map((d) => <String, dynamic>{'id': d.id, 'ticketId': d.id, ...d.data()}).toList();
      int ms(Map<String, dynamic> t) => (parseDate(t['createdAt']) ?? parseDate(t['purchasedAt']))?.millisecondsSinceEpoch ?? 0;
      list.sort((a, b) => ms(b) - ms(a));
      setState(() {
        _tickets = list;
        _loading = false;
      });
    }, onError: (_) => setState(() => _loading = false));
  }

  @override
  void dispose() {
    _ticketsSub?.cancel();
    _checkinSub?.cancel();
    super.dispose();
  }

  void _order() => openRoute(context, AppRoute.barOrder, args: _checkin != null ? {'venueId': _checkin!.venueId} : const {});

  void _back() {
    final nav = Navigator.of(context);
    nav.canPop() ? nav.pop() : openRoute(context, AppRoute.tickets, replace: true);
  }

  static bool _isUsed(Map<String, dynamic> t) => t['status'] == 'redeemed' || t['status'] == 'used';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading) return const Scaffold(backgroundColor: Tw.black, body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (auth.user == null) return _loginPrompt(context);

    final available = _tickets.where((t) => t['status'] == 'issued' || t['status'] == 'valid').toList();
    final used = _tickets.where(_isUsed).toList();
    final list = _usedTab ? used : available;

    return Scaffold(
      backgroundColor: Tw.black,
      body: Stack(children: [
        Column(children: [
          _header(context),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, 96 + MediaQuery.of(context).padding.bottom), children: [
              if (_checkin != null) ...[const SizedBox(height: 12), _checkinBanner(_checkin!)],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Tw.slate900, Color(0xE60F172A), Tw.slate950]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Tw.slate800),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.verified_user, size: 20, color: Tw.emerald400)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${context.t('consumption_philosophy_title', fallback: 'Cero dinero atrapado en pulseras')}\n',
                          style: tw(11, weight: bold, height: 1.8),
                        ),
                        TextSpan(
                            text: context.t('consumption_philosophy_desc',
                                fallback:
                                    'Solo pagas lo que consumes. Muestra el código en la barra: el camarero lo escanea en 1 segundo y te sirve al momento.')),
                      ]),
                      style: tw(11, color: Tw.slate300, height: 1.6),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _tab('${context.t('consumption_tab_available', fallback: 'Disponibles')} (${available.length})', !_usedTab, () => setState(() => _usedTab = false))),
                const SizedBox(width: 8),
                Expanded(child: _tab('${context.t('consumption_tab_used', fallback: 'Ya Servidas')} (${used.length})', _usedTab, () => setState(() => _usedTab = true))),
              ]),
              const SizedBox(height: 16),
              if (_loading)
                for (var i = 0; i < 3; i++)
                  Container(
                    height: 80,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16)),
                  )
              else if (!_usedTab && available.isEmpty)
                _emptyAvailable(context)
              else if (_usedTab && used.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 64),
                  child: Text(context.t('consumption_no_used', fallback: 'Aún no has canjeado ninguna consumición hoy.'),
                      textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
                )
              else
                for (final t in list) _ticketCard(context, t),
            ]),
          ),
        ]),
        if (_showToast) _successToast(context),
      ]),
    );
  }

  Widget _loginPrompt(BuildContext context) => Scaffold(
        backgroundColor: Tw.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.05))),
                child: const Icon(Icons.wine_bar, size: 30, color: Tw.fuchsia400),
              ),
              const SizedBox(height: 16),
              Text(context.t('consumption_login_title', fallback: 'Inicia sesión para ver tus copas'),
                  textAlign: TextAlign.center, style: tw(20, weight: black)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  context.t('consumption_login_desc', fallback: 'Tus consumiciones unitarias compradas aparecen aquí directamente en tu pantalla.'),
                  textAlign: TextAlign.center,
                  style: tw(12, color: Tw.slate400),
                ),
              ),
              const SizedBox(height: 24),
              GradientButton(
                label: context.t('login_btn', fallback: 'Iniciar Sesión'),
                gradient: const LinearGradient(colors: [Tw.fuchsia600, Color(0xFFDB2777)]),
                radius: 12,
                fontSize: 14,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                onTap: () => openRoute(context, AppRoute.login),
              ),
            ]),
          ),
        ),
      );

  Widget _header(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 14, 16, 14),
        decoration: BoxDecoration(
          color: Tw.slate950.withValues(alpha: 0.9),
          border: Border(bottom: BorderSide(color: Tw.slate800.withValues(alpha: 0.8))),
        ),
        child: Row(children: [
          Pressable(
            onTap: _back,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.slate800)),
              child: const Icon(Icons.arrow_back, size: 16, color: Tw.slate400),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                Text(context.t('consumption_title', fallback: 'MIS COPAS'), style: tw(16, weight: black, tracking: -0.025, height: 1)),
                _pill('CASHLESS V1', Tw.fuchsia400, Tw.fuchsia500),
              ]),
              const SizedBox(height: 2),
              Text(context.t('consumption_subtitle', fallback: '1 Ticket = 1 Copa • Sin recargas ni comisiones'),
                  style: tw(11, weight: medium, color: Tw.slate400)),
            ]),
          ),
          Pressable(
            onTap: _order,
            scale: 0.95,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.amber500]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Tw.fuchsia600.withValues(alpha: 0.2), blurRadius: 10)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add, size: 14, color: Tw.white),
                const SizedBox(width: 6),
                Text(context.t('consumption_order_btn', fallback: 'Pedir'), style: tw(12, weight: black)),
              ]),
            ),
          ),
        ]),
      );

  Widget _checkinBanner(({String venueId, String venueName}) c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF022C22).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Tw.emerald500.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: Tw.emerald400)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Check-in activo: ${c.venueName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(12, weight: bold)),
              Text('Barra digital abierta para pedir', style: tw(10, color: const Color(0xCC6EE7B7))),
            ]),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: () => openRoute(context, AppRoute.barOrder, args: {'venueId': c.venueId}),
            scale: 0.95,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Tw.emerald500, borderRadius: BorderRadius.circular(12)),
              child: Text('Pedir copa', style: tw(12, weight: black, color: Tw.black)),
            ),
          ),
        ]),
      );

  Widget _tab(String label, bool active, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: active ? Tw.white : Tw.slate900, borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: tw(12, weight: black, color: active ? Tw.black : Tw.slate400)),
        ),
      );

  Widget _emptyAvailable(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.slate800)),
            child: const Icon(Icons.wine_bar, size: 30, color: Tw.slate600),
          ),
          const SizedBox(height: 12),
          Text(context.t('consumption_empty_title', fallback: 'No tienes copas pendientes'), style: tw(16, weight: black)),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              context.t('consumption_empty_desc',
                  fallback: 'Pide tu copa directamente desde el móvil con Apple Pay, Google Pay o tarjeta, sin esperar colas.'),
              textAlign: TextAlign.center,
              style: tw(12, color: Tw.slate400),
            ),
          ),
          const SizedBox(height: 24),
          GradientButton(
            label: context.t('consumption_empty_action', fallback: 'Ver Carta de Bebidas'),
            gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.amber400]),
            radius: 12,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onTap: _order,
          ),
        ]),
      );

  Widget _ticketCard(BuildContext context, Map<String, dynamic> t) {
    final name = safeStr(t['productName'] ?? t['itemName']).isNotEmpty ? safeStr(t['productName'] ?? t['itemName']) : 'Consumición';
    final used = _isUsed(t);
    final beer = t['category'] == 'cerveza';
    final premium = t['isPremium'] == true;
    final iconColor = beer ? Tw.amber400 : (premium ? Tw.purple400 : Tw.fuchsia400);
    return Opacity(
      opacity: used ? 0.6 : 1,
      child: Pressable(
        onTap: () => _openTicket(t),
        scale: 0.98,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: used ? Tw.slate950.withValues(alpha: 0.6) : Tw.slate900.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: used ? Tw.slate800.withValues(alpha: 0.6) : Tw.slate800),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: Icon(beer ? Icons.sports_bar : Icons.wine_bar, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                  Text(name, style: tw(14, weight: black)),
                  if (premium) _pill('PREMIUM', const Color(0xFFD8B4FE), Tw.purple500, radius: 4),
                ]),
                if (safeStr(t['selectedMixer']).isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text('Con ${t['selectedMixer']}', style: tw(11, color: Tw.slate400))),
                if (safeStr(t['venueName']).isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text(safeStr(t['venueName']), style: tw(10, color: Tw.slate500))),
                if (t['isGift'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _pill(
                        '🎁 Invitación de @${safeStr(t['giftedByNick']).isNotEmpty ? t['giftedByNick'] : 'un amigo'}', const Color(0xFFF9A8D4), Tw.pink500),
                  ),
              ]),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: used ? Tw.slate800 : Tw.emerald500.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                  border: used ? null : Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!used) ...[
                    Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Tw.emerald400)),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    used
                        ? '✓ ${context.t('consumption_status_used', fallback: 'Servida')}'
                        : context.t('consumption_status_ready', fallback: 'Ver QR'),
                    style: tw(10, weight: bold, color: used ? Tw.slate400 : Tw.emerald400),
                  ),
                ]),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _openTicket(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => _ConsumptionQrSheet(ticket: t),
    );
  }

  Widget _successToast(BuildContext context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 300),
          builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, -20 * (1 - v)), child: c)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF022C22).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.emerald500.withValues(alpha: 0.5)),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 25))],
            ),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 24, color: Tw.emerald400),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('consumption_toast_title', fallback: '¡Consumición adquirida!'), style: tw(12, weight: black)),
                  Text(
                    context.t('consumption_toast_desc',
                        fallback: 'Sin saldos atrapados. Muestra el QR en la barra para que te la sirvan.'),
                    style: tw(11, color: const Color(0xE66EE7B7)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
}

Widget _pill(String text, Color fg, Color base, {double radius = 99}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: base.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: tw(9, weight: bold, color: fg)),
    );

/// The dynamic QR sheet: token signed by getConsumptionEntitlementQr, rotated every 60s. On Android the same token is
/// also handed over by NFC while the sheet is open (services/nfc_pass.dart).
class _ConsumptionQrSheet extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const _ConsumptionQrSheet({required this.ticket});

  @override
  State<_ConsumptionQrSheet> createState() => _ConsumptionQrSheetState();
}

class _ConsumptionQrSheetState extends State<_ConsumptionQrSheet> {
  /// Seconds between new signed QRs (each is valid 60 s at the bar), like the tickets' (widgets/dynamic_qr.dart).
  static const _period = 15;
  String? _qr;
  bool _qrLoading = false;
  bool _qrError = false;
  int _countdown = _period;
  Timer? _timer;

  String get _id => widget.ticket['id'] as String;
  bool get _used => widget.ticket['status'] == 'used' || widget.ticket['status'] == 'redeemed';

  @override
  void initState() {
    super.initState();
    _fetch();
    if (!_used) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_countdown <= 1) {
          _fetch();
        } else {
          setState(() => _countdown--);
        }
      });
    }
  }

  @override
  void dispose() {
    NfcPass.hide(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _qrLoading = true;
      _qrError = false;
    });
    final fn = FirebaseFunctions.instance;
    try {
      try {
        final res = await fn.httpsCallable('getConsumptionEntitlementQr').call({'entitlementId': _id});
        final d = res.data is Map ? res.data as Map : const {};
        if (d['dynamicToken'] is String) {
          _qr = d['dynamicToken'] as String;
          _countdown = _period;
          return;
        }
      } catch (_) {
        final res = await fn.httpsCallable('getConsumptionTicketQr').call({'ticketId': _id});
        final d = res.data is Map ? res.data as Map : const {};
        if (d['dynamicQr'] is String) {
          _qr = d['dynamicQr'] as String;
          _countdown = _period;
          return;
        }
      }
    } catch (_) {
      // No QR is made up here: the bar only accepts the signed one (until 2026-10-13 an unsigned code was shown).
      _qr = null;
      _qrError = true;
      _countdown = _period;
    } finally {
      if (mounted) {
        setState(() => _qrLoading = false);
        if (!_used && _qr != null) {
          NfcPass.show(this, _qr);
        } else {
          NfcPass.hide(this);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final name = safeStr(t['productName'] ?? t['itemName']).isNotEmpty ? safeStr(t['productName'] ?? t['itemName']) : 'Consumición';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Tw.slate900,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Tw.slate700.withValues(alpha: 0.8)),
                boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 25))],
              ),
              child: Stack(children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: Tw.emerald500.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
                    ),
                    child: Text(_used ? 'COPA YA CONSUMIDA' : 'LISTO PARA LA BARRA',
                        style: tw(10, weight: black, color: Tw.emerald400, tracking: 0.05)),
                  ),
                  const SizedBox(height: 8),
                  Text(name, textAlign: TextAlign.center, style: tw(18, weight: black)),
                  if (safeStr(t['selectedMixer']).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 16),
                      child: Text('Con ${t['selectedMixer']}', style: tw(12, color: Tw.slate300)),
                    ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Tw.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 25))],
                    ),
                    child: SizedBox(
                      width: 180,
                      height: 180,
                      child: _qrLoading
                          ? Container(decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)))
                          : _qr != null
                              ? QrImageView(data: _qr!, size: 180, padding: EdgeInsets.zero)
                              : _qrError
                                  ? GestureDetector(
                                      onTap: _fetch,
                                      child: Center(
                                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                                          const Icon(Icons.refresh, size: 28, color: Tw.slate500),
                                          const SizedBox(height: 8),
                                          Text('No se ha podido generar el QR. Toca para reintentar.',
                                              textAlign: TextAlign.center, style: tw(12, weight: bold, color: Tw.black)),
                                        ]),
                                      ),
                                    )
                                  : Center(child: Text('Cargando QR...', style: tw(12, weight: bold, color: Tw.black))),
                    ),
                  ),
                  if (!_used && NfcPass.available) const NfcPassHint(),
                  if (!_used)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.schedule, size: 14, color: Tw.emerald400),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: '${context.t('consumption_qr_refresh', fallback: 'Código dinámico seguro')} '),
                              TextSpan(text: '(${_countdown}s)', style: tw(11, weight: bold).copyWith(fontFamily: 'monospace')),
                            ]),
                            style: tw(11, color: Tw.slate400),
                          ),
                        ),
                        IconButton(
                          onPressed: _fetch,
                          tooltip: 'Regenerar ahora',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.refresh, size: 14, color: Tw.slate400),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      context.t('consumption_qr_hint',
                          fallback: 'Muestra esta pantalla al camarero. El QR cambia cada pocos segundos y solo vale en pantalla.'),
                      textAlign: TextAlign.center,
                      style: tw(10, color: Tw.slate500, height: 1.25),
                    ),
                  ),
                ]),
                Positioned(
                  top: -8,
                  right: -8,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Tw.slate800, shape: BoxShape.circle),
                      child: const Icon(Icons.close, size: 14, color: Tw.slate400),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
