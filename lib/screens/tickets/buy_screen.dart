import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/event.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/city_provider.dart';
import '../../providers/platform_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../venues/venues_screen.dart' show formatPrice;

const _platformFee = 1.00;

/// Port of app/buy/page.tsx
class BuyScreen extends StatefulWidget {
  final String? venueId;
  final String? eventId;
  final String? rrppId;
  final String refCode;
  const BuyScreen({super.key, this.venueId, this.eventId, this.rrppId, this.refCode = ''});

  @override
  State<BuyScreen> createState() => _BuyScreenState();
}

class _BuyScreenState extends State<BuyScreen> {
  final _db = FirebaseFirestore.instance;
  bool _loading = false;
  String _error = '';
  String _venueName = '';
  Map<String, dynamic>? _venue;
  String _eventTitle = '';
  List<Map<String, dynamic>> _tiers = [];
  String _selectedTier = '';
  bool _pageLoading = true;
  bool _expired = false;
  List<Map<String, dynamic>> _buyback = [];
  String? _selectedBuyback;
  final _guestName = TextEditingController();
  final _guestEmail = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _guestName.dispose();
    _guestEmail.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final vid = widget.venueId, eid = widget.eventId;
    if (vid == null || vid.isEmpty || eid == null || eid.isEmpty) {
      setState(() => _pageLoading = false);
      return;
    }
    try {
      final results = await Future.wait([
        _db.collection('venues').doc(vid).get(),
        _db.collection('venues').doc(vid).collection('events').doc(eid).get(),
      ]);
      final v = results[0], e = results[1];
      if (v.exists) {
        _venue = v.data();
        _venueName = safeStr(_venue?['name']);
        final ext = _venue?['externalTicketUrl'] as String?;
        if (ext != null && ext.isNotEmpty) {
          await openInApp(ext);
          if (mounted) Navigator.of(context).pop();
          return;
        }
      }
      if (e.exists) {
        final data = e.data()!;
        _eventTitle = safeStr(data['title']);
        if (!Event(e.id, data).isVisible) _expired = true;
        final tiers = data['ticket_tiers'] is List
            ? (data['ticket_tiers'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
            : <Map<String, dynamic>>[];
        _tiers = tiers.where((t) => asInt(t['sold']) < asInt(t['quota'])).toList();
        if (_tiers.isNotEmpty) _selectedTier = safeStr(_tiers.first['id']);
      }
      try {
        final bb = await _db.collection('buyback_pool').where('eventId', isEqualTo: eid).where('status', isEqualTo: 'available').get();
        _buyback = bb.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      } catch (_) {
        _buyback = [];
      }
    } catch (_) {}
    if (mounted) setState(() => _pageLoading = false);
  }

  Map<String, dynamic>? get _currentTier => _tiers.where((t) => safeStr(t['id']) == _selectedTier).firstOrNull;
  Map<String, dynamic>? get _currentBuyback => _buyback.where((b) => b['id'] == _selectedBuyback).firstOrNull;
  double get _ticketPrice => _currentBuyback != null
      ? asInt(_currentBuyback!['currentTierPriceCents']) / 100
      : (asDouble(_currentTier?['price']) ?? 0);
  double get _total => _ticketPrice == 0 ? 0 : _ticketPrice + _platformFee;
  bool get _hasStripe => (_venue?['stripeAccountId'] as String?)?.isNotEmpty == true;
  bool get _freeOrTest => _total == 0 || !_hasStripe;

  Future<void> _buy() async {
    final vid = widget.venueId, eid = widget.eventId;
    if (vid == null || eid == null || _expired) return;
    if (_selectedTier.isEmpty && _selectedBuyback == null) return;
    final i18n = context.read<I18n>();
    final user = context.read<AuthProvider>().user;
    if (user == null && !_freeOrTest && _guestEmail.text.trim().isEmpty) {
      setState(() => _error = i18n.t('buy.error.email_required', fallback: 'Introduce tu email para recibir la entrada.'));
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    final fn = FirebaseFunctions.instance;
    try {
      if (_freeOrTest) {
        final res = await fn.httpsCallable('claimFreeTicket').call<Map<String, dynamic>>({
          'venueId': vid,
          'eventId': eid,
          'ticketType': _selectedTier,
          if (_guestName.text.trim().isNotEmpty) 'guestName': _guestName.text.trim(),
          if (_guestEmail.text.trim().isNotEmpty) 'guestEmail': _guestEmail.text.trim(),
          'isTestPass': !_hasStripe,
        });
        final d = res.data;
        if (d['success'] == true) {
          if (!mounted) return;
          if (d['accessToken'] is String) {
            openRoute(context, AppRoute.pass, args: {'access': d['accessToken'] as String}, replace: true);
          } else if (d['ticketId'] is String) {
            openRoute(context, AppRoute.pass, args: {'id': d['ticketId'] as String}, replace: true);
          } else {
            openRoute(context, AppRoute.tickets, replace: true);
          }
        } else {
          setState(() {
            _error = 'No se pudo reclamar la entrada.';
            _loading = false;
          });
        }
        return;
      }

      final Map<String, dynamic> res;
      if (_selectedBuyback != null) {
        res = (await fn.httpsCallable('createBuybackCheckout').call<Map<String, dynamic>>({
          'ticketId': _selectedBuyback,
          'origin': webBase,
          'idempotencyKey': uuidV4(),
        }))
            .data;
      } else {
        res = (await fn.httpsCallable('createTicketCheckout').call<Map<String, dynamic>>({
          'venueId': vid,
          'eventId': eid,
          'ticketType': _selectedTier,
          'rrppId': widget.rrppId ?? '',
          'origin': webBase,
          if (user == null) 'guestEmail': _guestEmail.text.trim(),
          if (user == null && _guestName.text.trim().isNotEmpty) 'guestName': _guestName.text.trim(),
          if (widget.refCode.isNotEmpty) 'refCode': widget.refCode,
          'idempotencyKey': uuidV4(),
        }))
            .data;
      }
      final url = res['url'] as String?;
      if (url != null) {
        await openInApp(url);
        if (mounted) setState(() => _loading = false);
      } else {
        setState(() {
          _error = _selectedBuyback != null ? i18n.t('buy.error.payment_init_error', fallback: 'No se pudo generar el pago.') : 'No se pudo generar el pago.';
          _loading = false;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? i18n.t('buy.error.payment_init_error');
      setState(() {
        if (msg.contains('agotadas')) {
          _error = i18n.t('buy.error.tier_sold_out');
          final remaining = _tiers.where((t) => safeStr(t['id']) != _selectedTier).toList();
          _tiers = remaining;
          _selectedTier = remaining.isNotEmpty ? safeStr(remaining.first['id']) : '';
        } else {
          _error = msg;
        }
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = i18n.t('buy.error.payment_init_error');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pageLoading) return const _BuySkeleton();
    if (widget.venueId == null || widget.venueId!.isEmpty || widget.eventId == null || widget.eventId!.isEmpty) {
      return _message(context, Icons.error_outline, Tw.red500, context.t('buy.invalid_link.title'), context.t('buy.invalid_link.description'));
    }
    if (_tiers.isEmpty) {
      return _message(context, Icons.confirmation_number, Tw.slate700, context.t('buy.sold_out.title'), context.t('buy.sold_out.description'));
    }
    final currency = context.watch<CityProvider>().currency;
    final user = context.watch<AuthProvider>().user;
    final noStripe = !_hasStripe;

    return Scaffold(
      backgroundColor: Tw.black,
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 448),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Tw.slate900.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Tw.w(0.05)),
                  boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 25))],
                ),
                child: Stack(children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SizedBox(height: 16),
                      Label(_venueName.isNotEmpty ? _venueName : context.t('buy.buy_ticket'), size: 24, color: Tw.fuchsia400),
                      const SizedBox(height: 4),
                      if (_eventTitle.isNotEmpty) Text(_eventTitle, style: tw(14, weight: bold)),
                      const SizedBox(height: 4),
                      Text(context.t('buy.qr_generated_instantly'), style: tw(12, color: Tw.slate500)),
                      const SizedBox(height: 24),
                      if (noStripe) ...[_testModeBanner(context), const SizedBox(height: 24)],
                      if (_error.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Tw.red500.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Tw.red500.withValues(alpha: 0.5)),
                          ),
                          child: Text(_error, style: tw(14, weight: bold, color: Tw.red400)),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (_tiers.length > 1) ...[
                        Label(context.t('buy.ticket_type_label'), size: 12, weight: bold, color: Tw.slate500),
                        const SizedBox(height: 8),
                        for (final tier in _tiers) _tierOption(context, tier, currency),
                        const SizedBox(height: 16),
                      ],
                      if (_buyback.isNotEmpty) ...[
                        Label(context.t('buyback.available_label', fallback: 'Entradas por recompra'), size: 12, weight: bold, color: Tw.amber400),
                        const SizedBox(height: 8),
                        for (final bb in _buyback) _buybackOption(context, bb, currency),
                        const SizedBox(height: 16),
                      ],
                      if (user == null) ...[
                        Label(context.t('buy.guest_name', fallback: 'Tu nombre'), size: 12, weight: bold, color: Tw.slate500),
                        const SizedBox(height: 4),
                        TextField(controller: _guestName, style: tw(14), decoration: _dec('Nombre para la entrada')),
                        const SizedBox(height: 12),
                        Label(
                          '${context.t('buy.guest_email', fallback: 'Email')} '
                          '(${_freeOrTest ? context.t('buy.optional', fallback: 'opcional') : context.t('buy.required_for_receipt', fallback: 'para recibir tu entrada')})',
                          size: 12,
                          weight: bold,
                          color: Tw.slate500,
                        ),
                        const SizedBox(height: 4),
                        TextField(controller: _guestEmail, keyboardType: TextInputType.emailAddress, style: tw(14), decoration: _dec('tu@email.com')),
                        const SizedBox(height: 24),
                      ],
                      _summary(context, currency, noStripe),
                      const SizedBox(height: 24),
                      if (_expired) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Tw.red500.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            context.t('buy.event_expired',
                                fallback: 'La venta de entradas para este evento ha finalizado (cierra 1 hora antes del fin de la fiesta).'),
                            textAlign: TextAlign.center,
                            style: tw(12, weight: bold, color: Tw.red400),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buyButton(context, currency, noStripe),
                      if (_total > 0 && _hasStripe) ...[
                        const SizedBox(height: 16),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.lock, size: 12, color: Tw.slate600),
                          const SizedBox(width: 8),
                          Text(context.t('buy.secure_payment_stripe'), style: tw(10, weight: bold, color: Tw.slate600)),
                        ]),
                      ],
                    ]),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: const BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16))),
                      child: Label(context.t('buy.secure_purchase'), color: Tw.white),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
          ),
        ]),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );

  Widget _testModeBanner(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tw.amber500.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Tw.amber500.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.science, size: 14, color: Tw.amber400),
            const SizedBox(width: 8),
            Flexible(child: Label(context.t('buy.test_mode_title', fallback: 'Modo de prueba (Local sin Stripe)'), size: 12, weight: bold, color: Tw.amber400, tracking: 0.05)),
          ]),
          const SizedBox(height: 4),
          Text(
            context.t('buy.test_mode_desc',
                fallback:
                    'Este local aún no tiene Stripe vinculado para cobros bancarios. Puedes emitir un Pase de Prueba gratis para verificar el acceso y el escáner QR de puerta.'),
            style: tw(12, color: Tw.slate300),
          ),
        ]),
      );

  Widget _tierOption(BuildContext context, Map<String, dynamic> tier, String currency) {
    final id = safeStr(tier['id']);
    final quota = asInt(tier['quota']), sold = asInt(tier['sold']);
    final remaining = quota - sold;
    final almost = quota > 0 && sold / quota >= 0.8 && remaining > 0;
    final on = _selectedTier == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: () => setState(() {
          _selectedTier = id;
          _selectedBuyback = null;
        }),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: on ? Tw.fuchsia500.withValues(alpha: 0.1) : Tw.w(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? Tw.fuchsia500.withValues(alpha: 0.5) : Tw.w(0.05)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(safeStr(tier['name']), style: tw(14, weight: bold)),
                const SizedBox(height: 2),
                Row(children: [
                  Text('$remaining ${context.t('buy.available')}', style: tw(10, color: Tw.slate500)),
                  if (almost) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Tw.amber500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
                      child: Text(context.t('events.spots_left', count: remaining, fallback: '$remaining left'), style: tw(9, weight: bold, color: Tw.amber400)),
                    ),
                  ],
                ]),
              ]),
            ),
            Text(formatPrice(asDouble(tier['price']) ?? 0, currency), style: tw(18, weight: black)),
          ]),
        ),
      ),
    );
  }

  Widget _buybackOption(BuildContext context, Map<String, dynamic> bb, String currency) {
    final on = _selectedBuyback == bb['id'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: () => setState(() {
          _selectedBuyback = bb['id'] as String;
          _selectedTier = '';
        }),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: on ? Tw.amber500.withValues(alpha: 0.1) : Tw.w(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? Tw.amber500.withValues(alpha: 0.5) : Tw.w(0.05)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(safeStr(bb['tierName']).isNotEmpty ? safeStr(bb['tierName']) : 'General', style: tw(14, weight: bold)),
                Text(context.t('buyback.badge', fallback: 'Recompra oficial'), style: tw(10, color: Tw.amber400)),
              ]),
            ),
            Text(formatPrice(asInt(bb['currentTierPriceCents']) / 100, currency), style: tw(18, weight: black)),
          ]),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, String currency, bool noStripe) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Text(safeStr(_currentTier?['name']).isNotEmpty ? safeStr(_currentTier?['name']) : context.t('buy.default_ticket_name'),
                  style: tw(14, color: Tw.slate300)),
            ),
            Text(formatPrice(_ticketPrice, currency), style: tw(14, weight: bold, color: Tw.slate300)),
          ]),
          if (_total > 0 && !noStripe) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(context.t('buy.platform_fee'), style: tw(14, color: Tw.slate500))),
              Text(formatPrice(_platformFee, currency), style: tw(14, weight: bold, color: Tw.slate500)),
            ]),
          ],
          const SizedBox(height: 8),
          Divider(color: Tw.w(0.1), height: 16),
          Row(children: [
            Expanded(child: Text(context.t('buy.total'), style: tw(16, weight: black))),
            Text(
              noStripe ? '0 € (Pase de prueba)' : (_total == 0 ? context.t('buy.free', fallback: 'GRATIS') : formatPrice(_total, currency)),
              style: tw(20, weight: black, color: Tw.fuchsia400),
            ),
          ]),
        ]),
      );

  Widget _buyButton(BuildContext context, String currency, bool noStripe) {
    final disabled = _loading || (_selectedTier.isEmpty && _selectedBuyback == null) || _expired;
    final String label;
    if (_expired) {
      label = context.t('buy.sales_closed', fallback: 'Venta finalizada');
    } else if (_loading) {
      label = _freeOrTest
          ? context.t('buy.generating_pass', fallback: 'Generando pase...')
          : context.t('buy.redirecting_to_stripe', fallback: 'Conectando con Stripe...');
    } else if (noStripe) {
      label = context.t('buy.get_test_pass', fallback: 'Obtener pase de prueba (0 €)');
    } else if (_total == 0) {
      label = context.t('buy.claim_free', fallback: 'Reservar entrada gratis');
    } else {
      label = '${context.t('buy.pay')} ${formatPrice(_total, currency)}';
    }
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Pressable(
        onTap: disabled ? () {} : _buy,
        scale: 0.95,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Tw.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 15, offset: Offset(0, 5))],
          ),
          child: Label(label, size: 14, color: Tw.black, align: TextAlign.center),
        ),
      ),
    );
  }

  Widget _message(BuildContext context, IconData icon, Color color, String title, String desc) => Scaffold(
        backgroundColor: Tw.black,
        body: SafeArea(
          child: Stack(children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 60, color: color),
                  const SizedBox(height: 16),
                  Text(title, textAlign: TextAlign.center, style: tw(20, weight: black)),
                  const SizedBox(height: 8),
                  Text(desc, textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
                ]),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            ),
          ]),
        ),
      );
}

class _BuySkeleton extends StatelessWidget {
  const _BuySkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w, double r = 8, Color? c}) =>
        Container(height: h, width: w, decoration: BoxDecoration(color: c ?? Tw.w(0.05), borderRadius: BorderRadius.circular(r)));
    return Scaffold(
      backgroundColor: Tw.black,
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 448),
          decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.05))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.centerRight, child: box(16, w: 80, r: 99, c: Tw.fuchsia500.withValues(alpha: 0.2))),
            const SizedBox(height: 24),
            FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0.66, child: box(24)),
            const SizedBox(height: 8),
            FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0.5, child: box(16)),
            const SizedBox(height: 24),
            box(64, r: 16),
            const SizedBox(height: 12),
            box(64, r: 16),
            const SizedBox(height: 24),
            box(48, r: 12, c: Tw.w(0.1)),
            const SizedBox(height: 24),
            box(56, r: 12),
          ]),
        ),
      ),
    );
  }
}
