import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/city_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/dynamic_qr.dart';
import '../../widgets/ticket_modals.dart';

String currencySymbol(String c) => switch (c.toLowerCase()) { 'eur' => '€', 'gbp' => '£', _ => c.toUpperCase() };

/// Port of app/tickets/page.tsx (+ hooks/useTickets.ts)
class WalletScreen extends StatefulWidget {
  final String? claimTicketId;
  const WalletScreen({super.key, this.claimTicketId});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _transferred = [];
  bool _loading = true;
  String _tab = 'valid';
  final Map<String, Map<String, dynamic>> _venueCache = {};
  final List<StreamSubscription> _subs = [];
  String? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid != null) {
      _subs.add(_db
          .collection('tickets')
          .where('userId', isEqualTo: uid)
          .orderBy('purchasedAt', descending: true)
          .limit(200)
          .snapshots()
          .listen((s) {
        setState(() {
          _tickets = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _loading = false;
        });
        _cacheVenues();
      }, onError: (_) => setState(() => _loading = false)));
      _subs.add(_db.collection('tickets').where('transferredFrom', isEqualTo: uid).limit(50).snapshots().listen((s) {
        setState(() => _transferred = s.docs.map((d) => {'id': d.id, ...d.data()}).where((t) => t['userId'] != uid).toList());
        _cacheVenues();
      }, onError: (_) {}));
    }
    if (widget.claimTicketId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openClaim(widget.claimTicketId!));
    }
  }

  Future<void> _cacheVenues() async {
    final ids = {for (final t in [..._tickets, ..._transferred]) t['venueId']}.whereType<String>().where((id) => !_venueCache.containsKey(id));
    if (ids.isEmpty) return;
    final snaps = await Future.wait(ids.map((id) => _db.collection('venues').doc(id).get()));
    if (!mounted) return;
    setState(() {
      for (final s in snaps) {
        if (s.exists) _venueCache[s.id] = s.data()!;
      }
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toast = msg);
    _toastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _openClaim([String initial = '']) async {
    final msg = await showWebModal<String>(context, ClaimTicketModal(initialTicketId: initial));
    if (msg != null) _showToast(msg.isEmpty ? '¡Entrada vinculada con éxito!' : msg);
  }

  List<Map<String, dynamic>> get _valid => _tickets.where((t) => t['status'] == 'valid' || t['status'] == 'buyback_listed').toList();
  List<Map<String, dynamic>> get _used => _tickets.where((t) => t['status'] == 'used').toList();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading || auth.profile == null) return const _WalletSkeleton();
    final display = _tab == 'valid' ? _valid : _tab == 'used' ? _used : _transferred;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(children: [
        Positioned(top: -size.height * 0.1, left: -size.width * 0.2, child: Orb(color: const Color(0xFFCA8A04).withValues(alpha: 0.1), size: size.width * 0.8)),
        Positioned(top: size.height * 0.2, right: -size.width * 0.2, child: Orb(color: Tw.fuchsia600.withValues(alpha: 0.1), size: size.width * 0.7)),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 128), children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: Tw.slate400),
              ),
            ),
            Row(children: [
              const Icon(Icons.confirmation_number, color: Color(0xFFEAB308)),
              const SizedBox(width: 12),
              Text(context.t('wallet.title', fallback: 'Mis entradas'), style: tw(24, weight: black, tracking: -0.025)),
            ]),
            const SizedBox(height: 8),
            Text(context.t('wallet.subtitle', fallback: 'Tus entradas compradas y transferencias'), style: tw(12, color: Tw.slate500)),
            const SizedBox(height: 24),
            _banner(
              gradient: LinearGradient(colors: [const Color(0x804A044E), const Color(0x663B0764), Tw.slate900.withValues(alpha: 0.8)]),
              border: Tw.fuchsia500.withValues(alpha: 0.3),
              leading: const Text('🍹', style: TextStyle(fontSize: 20)),
              title: context.t('wallet.bar_drinks_title', fallback: '¿Tienes consumiciones o copas?'),
              sub: context.t('wallet.bar_drinks_desc', fallback: 'Sin recargas de saldo: muestra tu QR en la barra'),
              button: _pillButton(
                context.t('wallet.bar_drinks_btn', fallback: 'Mis Copas →'),
                const LinearGradient(colors: [Tw.fuchsia600, Tw.amber500]),
                () => openRoute(context, AppRoute.consumption),
              ),
            ),
            const SizedBox(height: 24),
            _banner(
              gradient: LinearGradient(colors: [const Color(0x4D581C87), const Color(0x33701A75)]),
              border: Tw.purple500.withValues(alpha: 0.2),
              leading: const Icon(Icons.mark_email_read, size: 18, color: Tw.fuchsia400),
              title: context.t('wallet.guest_prompt', fallback: '¿Compraste como invitado en la web?'),
              sub: context.t('wallet.guest_prompt_sub', fallback: 'Reclámala para cederla gratis o revenderla a 0€ comisión'),
              button: _pillButton('${context.t('wallet.claim_action', fallback: 'Reclamar')} →', null, _openClaim, color: Tw.fuchsia600),
            ),
            const SizedBox(height: 24),
            Row(children: [
              _tabBtn('valid', '${context.t('wallet.tab_active', fallback: 'Activas')} (${_valid.length})', Tw.green500, Tw.green400),
              const SizedBox(width: 8),
              _tabBtn('used', '${context.t('wallet.tab_used', fallback: 'Usadas')} (${_used.length})', Tw.slate500, Tw.slate400),
              const SizedBox(width: 8),
              _tabBtn('transferred', '${context.t('wallet.tab_transferred', fallback: 'Cedidas')} (${_transferred.length})', Tw.fuchsia500, Tw.fuchsia400),
            ]),
            const SizedBox(height: 24),
            if (_loading)
              for (var i = 0; i < 2; i++)
                Container(
                  height: 112,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24)),
                )
            else if (display.isEmpty)
              _empty(context)
            else
              for (final t in display)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TicketCard(
                    ticket: t,
                    tab: _tab,
                    venue: _venueCache[t['venueId']],
                    onSelect: () {
                      if (_tab != 'transferred') _openTicket(t);
                    },
                    onReportFraud: () async {
                      final msg = await showWebModal<String>(context, ReportFraudModal(ticket: t));
                      if (msg != null) _showToast(msg);
                    },
                  ),
                ),
          ]),
        ),
        if (_toast != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 24,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF059669),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Tw.emerald400.withValues(alpha: 0.3)),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 25)],
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Tw.white),
                const SizedBox(width: 12),
                Expanded(child: Text(_toast!, style: tw(12, weight: bold))),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _banner({required Gradient gradient, required Color border, required Widget leading, required String title, required String sub, required Widget button}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
        child: Row(children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(12, weight: bold)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(10, color: Tw.slate400)),
            ]),
          ),
          const SizedBox(width: 12),
          button,
        ]),
      );

  Widget _pillButton(String label, Gradient? gradient, VoidCallback onTap, {Color? color}) => Pressable(
        onTap: onTap,
        scale: 0.95,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: color, gradient: gradient, borderRadius: BorderRadius.circular(12)),
          child: Label(label, color: Tw.white, tracking: 0.05),
        ),
      );

  Widget _tabBtn(String id, String label, Color bg, Color fg) {
    final on = _tab == id;
    return Expanded(
      child: Pressable(
        onTap: () => setState(() => _tab = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: on ? bg.withValues(alpha: 0.2) : Tw.w(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? bg.withValues(alpha: 0.3) : Tw.w(0.1)),
          ),
          child: Label(label, color: on ? fg : Tw.slate500, align: TextAlign.center, maxLines: 1, tracking: 0.05),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(children: [
          Icon(_tab == 'valid' ? Icons.confirmation_number : _tab == 'used' ? Icons.history : Icons.send, size: 48, color: Tw.slate700),
          const SizedBox(height: 16),
          Text(
            _tab == 'valid'
                ? context.t('wallet.empty_active', fallback: 'No tienes entradas activas')
                : _tab == 'used'
                    ? context.t('wallet.empty_used', fallback: 'No tienes entradas usadas')
                    : context.t('wallet.empty_transferred', fallback: 'No has cedido ninguna entrada'),
            style: tw(14, color: Tw.slate500),
          ),
          if (_tab == 'valid') ...[
            const SizedBox(height: 24),
            Pressable(
              onTap: () => openRoute(context, AppRoute.events),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.circular(16)),
                child: Label(context.t('events.explore', fallback: 'Explorar eventos'), size: 12, color: Tw.white),
              ),
            ),
            const SizedBox(height: 12),
            Pressable(
              onTap: _openClaim,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.download, size: 14, color: Tw.fuchsia400),
                  const SizedBox(width: 8),
                  Label(context.t('wallet.claim_button', fallback: 'Reclamar entrada web'), size: 12, color: Tw.white),
                ]),
              ),
            ),
          ],
        ]),
      );

  Future<void> _openTicket(Map<String, dynamic> ticket) async {
    final currency = context.read<CityProvider>().currency;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ticket',
      barrierColor: Colors.black.withValues(alpha: 0.9),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) => _TicketDetail(
        ticket: ticket,
        venue: _venueCache[ticket['venueId']],
        currency: currency,
        onToast: _showToast,
      ),
      transitionBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: c)),
    );
  }
}

class _TicketDetail extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final Map<String, dynamic>? venue;
  final String currency;
  final void Function(String) onToast;
  const _TicketDetail({required this.ticket, required this.venue, required this.currency, required this.onToast});

  @override
  State<_TicketDetail> createState() => _TicketDetailState();
}

class _TicketDetailState extends State<_TicketDetail> {
  late final Map<String, dynamic> _t = {...widget.ticket};
  Map<String, dynamic>? _secrets;
  bool _secretsLoaded = false;
  bool _cancellingListing = false;
  bool _cancellingBuyback = false;

  @override
  void initState() {
    super.initState();
    if (_t['status'] == 'valid') {
      FirebaseFirestore.instance.doc('tickets/${_t['id']}/private/secrets').get().then((s) {
        if (mounted) {
          setState(() {
            _secrets = s.exists ? s.data() : null;
            _secretsLoaded = true;
          });
        }
      }).catchError((_) {
        if (mounted) setState(() => _secretsLoaded = true);
      });
    }
  }

  Future<void> _cancelListing() async {
    if (_cancellingListing) return;
    final i18n = context.read<I18n>();
    setState(() => _cancellingListing = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('cancelTicketListing').call({'ticketId': _t['id']});
      widget.onToast(i18n.t('wallet.listing_cancelled', fallback: 'Entrada retirada del mercado de la comunidad.'));
      setState(() => _t['isListedForResale'] = false);
    } on FirebaseFunctionsException catch (e) {
      widget.onToast(e.message ?? 'Error al retirar la entrada.');
    }
    if (mounted) setState(() => _cancellingListing = false);
  }

  Future<void> _cancelBuyback() async {
    if (_cancellingBuyback) return;
    final i18n = context.read<I18n>();
    setState(() => _cancellingBuyback = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('cancelBuybackListing').call({'ticketId': _t['id']});
      widget.onToast(i18n.t('buyback.cancelled', fallback: 'Recompra cancelada. Tu entrada vuelve a estar activa.'));
      setState(() => _t['status'] = 'valid');
    } on FirebaseFunctionsException catch (e) {
      widget.onToast(e.message ?? 'Error al cancelar la recompra.');
    }
    if (mounted) setState(() => _cancellingBuyback = false);
  }

  Widget _gradBtn(IconData icon, String label, Gradient g, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 14, color: Tw.white),
              const SizedBox(width: 8),
              Flexible(child: Text(label, textAlign: TextAlign.center, style: tw(12, weight: bold))),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final v = widget.venue;
    final pricing = v?['ticketPricing'] is Map ? (v!['ticketPricing'] as Map)[t['ticketType']] : null;
    final price = pricing is Map ? asDouble(pricing['amount']) : null;
    final status = t['status'];
    final valid = status == 'valid';
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(maxWidth: 384, maxHeight: MediaQuery.of(context).size.height * 0.92),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Tw.slate900,
                borderRadius: BorderRadius.circular(48),
                border: Border.all(color: Tw.w(0.1)),
                boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 100, offset: Offset(0, 40))],
              ),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (v?['coverImage'] is String && (v!['coverImage'] as String).isNotEmpty)
                    SizedBox(
                      height: 144,
                      child: Stack(fit: StackFit.expand, children: [
                        NetImage(v['coverImage'] as String),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Tw.slate900]),
                          ),
                        ),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(safeStr(v?['name'] ?? t['venueName'] ?? t['venueId']), textAlign: TextAlign.center, style: tw(20, weight: black)),
                      const SizedBox(height: 8),
                      Text(_cap(safeStr(t['tierName'] ?? t['ticketType'])), textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
                      if (safeStr(t['eventTitle']).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(safeStr(t['eventTitle']), textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
                      ],
                      if (safeStr(t['transferredFromName']).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: Tw.fuchsia500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.card_giftcard, size: 12, color: Tw.fuchsia300),
                              const SizedBox(width: 4),
                              Text('Recibida de @${t['transferredFromName']}', style: tw(10, weight: bold, color: Tw.fuchsia300)),
                            ]),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (t['channel'] == 'free_claim')
                        Text(context.t('buy.free', fallback: 'GRATIS'), textAlign: TextAlign.center, style: tw(18, weight: black, color: Tw.emerald400))
                      else if (price != null && price > 0)
                        Text('${(price / 100).toStringAsFixed(2)} ${currencySymbol(widget.currency)}',
                            textAlign: TextAlign.center, style: tw(18, weight: black, color: Tw.fuchsia400)),
                      if (pricing is Map && safeStr(pricing['description']).isNotEmpty)
                        Text(safeStr(pricing['description']), textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: valid ? Tw.green500.withValues(alpha: 0.2) : Tw.slate800, borderRadius: BorderRadius.circular(99)),
                          child: Label(valid ? context.t('wallet.ticket_valid', fallback: 'Válida') : context.t('wallet.ticket_used', fallback: 'Usada'),
                              color: valid ? Tw.green400 : Tw.slate500),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (valid && _secrets != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Center(
                            child: DynamicQR(ticketId: t['id'] as String, secretKey: _secrets!['secretKey'] as String?),
                          ),
                        )
                      else if (valid && !_secretsLoaded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Center(
                            child: Container(width: 232, height: 232, decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(24))),
                          ),
                        ),
                      if (status == 'used')
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(children: [
                            const Icon(Icons.check_circle, size: 48, color: Tw.slate600),
                            const SizedBox(height: 8),
                            Text(context.t('wallet.ticket_already_scanned', fallback: 'Esta entrada ya fue escaneada'), style: tw(14, color: Tw.slate500)),
                          ]),
                        ),
                      if (valid) ...[
                        if (t['isListedForResale'] == true)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Tw.emerald500.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Tw.emerald500.withValues(alpha: 0.2)),
                            ),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    const Icon(Icons.storefront, size: 12, color: Tw.emerald400),
                                    const SizedBox(width: 4),
                                    Label('En venta pública', color: Tw.emerald400, tracking: 0),
                                  ]),
                                  Text(
                                    '${t['resalePrice'] != null ? '${(asInt(t['resalePrice']) / 100).toStringAsFixed(2)}€' : ''} (0% comisión)',
                                    style: tw(12, weight: bold),
                                  ),
                                ]),
                              ),
                              Pressable(
                                onTap: _cancelListing,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(8)),
                                  child: Label(_cancellingListing ? '...' : 'Retirar', weight: bold, color: Tw.slate300, tracking: 0.05),
                                ),
                              ),
                            ]),
                          )
                        else
                          _gradBtn(Icons.storefront, context.t('wallet.list_ticket', fallback: 'Poner en venta en el feed (0% comisión)'),
                              const LinearGradient(colors: [Color(0xFF059669), Color(0xFF0D9488)]), () async {
                            final r = await showWebModal<(String, int)>(context, ListTicketModal(ticket: t));
                            if (r != null) {
                              setState(() {
                                _t['isListedForResale'] = true;
                                _t['resalePrice'] = r.$2;
                              });
                              widget.onToast(r.$1);
                            }
                          }),
                        _gradBtn(Icons.send, context.t('wallet.transfer_ticket', fallback: 'Transferir entrada gratis a un colega'),
                            const LinearGradient(colors: [Tw.fuchsia600, Color(0xFFDB2777)]), () async {
                          final msg = await showWebModal<String>(context, TransferTicketModal(ticket: t));
                          if (msg != null && mounted) {
                            Navigator.of(this.context).pop();
                            widget.onToast(msg.isEmpty ? '¡Entrada transferida con éxito a tu colega!' : msg);
                          }
                        }),
                        if (t['channel'] == 'stripe' && asInt(t['priceCents']) > 0 && status != 'buyback_listed')
                          _gradBtn(Icons.undo, context.t('buyback.button', fallback: 'No puedo ir — solicitar recompra'),
                              const LinearGradient(colors: [Color(0xFFD97706), Color(0xFFEA580C)]), () async {
                            final msg = await showWebModal<String>(
                                context, BuybackListModal(ticket: t, currencySymbol: currencySymbol(widget.currency)));
                            if (msg != null) {
                              setState(() => _t['status'] = 'buyback_listed');
                              widget.onToast(msg);
                            }
                          }),
                      ],
                      if (status == 'buyback_listed')
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Tw.amber500.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Tw.amber500.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  const Icon(Icons.hourglass_top, size: 12, color: Tw.amber400),
                                  const SizedBox(width: 4),
                                  Flexible(child: Text(context.t('buyback.pending_label', fallback: 'En espera de comprador'), style: tw(12, weight: bold, color: Tw.amber400))),
                                ]),
                                const SizedBox(height: 2),
                                Text(context.t('buyback.pending_description', fallback: 'Recibirás tu reembolso cuando alguien compre esta entrada.'),
                                    style: tw(10, color: const Color(0xFFA1A1AA))),
                              ]),
                            ),
                            Pressable(
                              onTap: _cancelBuyback,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Label(_cancellingBuyback ? '...' : context.t('buyback.cancel_button', fallback: 'Cancelar'),
                                    weight: bold, color: Tw.slate300, tracking: 0.05),
                              ),
                            ),
                          ]),
                        ),
                      Opacity(
                        opacity: 0.5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(color: Tw.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.2))),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.account_balance_wallet, size: 14, color: Tw.slate500),
                            const SizedBox(width: 8),
                            Text(context.t('wallet.add_to_apple_wallet', fallback: 'Añadir a Apple Wallet'), style: tw(12, weight: bold, color: Tw.slate500)),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 128),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Tw.slate950, borderRadius: BorderRadius.circular(12)),
                        child: SingleChildScrollView(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Label(context.t('wallet.conditions_title', fallback: 'Condiciones'), size: 8, weight: bold, color: Tw.slate400, tracking: 0),
                            const SizedBox(height: 8),
                            for (final k in [
                              ('wallet.conditions_1', 'Entrada con traspaso P2P instantáneo y sin comisiones intermediarias.'),
                              ('wallet.conditions_2', 'Válida para una sola entrada.'),
                              ('wallet.conditions_3', 'No se admiten devoluciones directas en taquilla.'),
                            ]) ...[
                              Text(context.t(k.$1, fallback: k.$2), style: tw(8, color: Tw.slate500, height: 1.25)),
                              const SizedBox(height: 8),
                            ],
                          ]),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Pressable(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16)),
                          child: Label(context.t('wallet.close', fallback: 'Cerrar'), size: 12, tracking: 0.2, align: TextAlign.center),
                        ),
                      ),
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

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final String tab;
  final Map<String, dynamic>? venue;
  final VoidCallback onSelect;
  final VoidCallback onReportFraud;
  const _TicketCard({required this.ticket, required this.tab, required this.venue, required this.onSelect, required this.onReportFraud});

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final currency = context.watch<CityProvider>().currency;
    final pricing = venue?['ticketPricing'] is Map ? (venue!['ticketPricing'] as Map)[t['ticketType']] : null;
    final amount = pricing is Map ? asDouble(pricing['amount']) : null;
    final transferredTab = tab == 'transferred';
    final valid = t['status'] == 'valid';
    final accent = valid ? (transferredTab ? Tw.fuchsia400 : Tw.green400) : Tw.slate600;
    final accentBg = valid ? (transferredTab ? Tw.fuchsia500.withValues(alpha: 0.2) : Tw.green500.withValues(alpha: 0.2)) : Tw.slate800;
    final border = valid ? (transferredTab ? Tw.fuchsia500.withValues(alpha: 0.3) : Tw.green500.withValues(alpha: 0.2)) : Tw.w(0.1);
    final purchased = parseDate(t['purchasedAt']);

    final String statusLabel;
    if (transferredTab) {
      statusLabel = valid && t['isUsed'] != true
          ? 'En posesión del receptor'
          : t['status'] == 'used'
              ? 'Usada en puerta'
              : 'Bloqueada';
    } else {
      statusLabel = valid ? context.t('wallet.ticket_valid', fallback: 'Válida') : context.t('wallet.ticket_used', fallback: 'Usada');
    }

    return Opacity(
      opacity: valid ? 1 : 0.7,
      child: Pressable(
        onTap: onSelect,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (venue?['coverImage'] is String && (venue!['coverImage'] as String).isNotEmpty) NetImage(venue!['coverImage'] as String, height: 80),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: accentBg, borderRadius: BorderRadius.circular(16)),
                    child: Icon(transferredTab ? Icons.send : valid ? Icons.qr_code_2 : Icons.check_circle, color: accent),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(safeStr(venue?['name'] ?? t['venueName'] ?? t['venueId']), style: tw(14, weight: black)),
                      Text(_cap(safeStr(t['tierName'] ?? (pricing is Map ? pricing['name'] : null) ?? t['ticketType'])), style: tw(10, color: Tw.slate500)),
                      if (safeStr(t['eventTitle']).isNotEmpty) Text(safeStr(t['eventTitle']), style: tw(10, color: Tw.slate400)),
                      if (t['isListedForResale'] == true && !transferredTab)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Tw.emerald500.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: Tw.emerald500.withValues(alpha: 0.2)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.storefront, size: 10, color: Tw.emerald400),
                            const SizedBox(width: 4),
                            Label('En venta ${t['resalePrice'] != null ? '${(asInt(t['resalePrice']) / 100).toStringAsFixed(2)}€' : ''}',
                                size: 9, color: Tw.emerald400, tracking: 0.05),
                          ]),
                        ),
                      if (safeStr(t['transferredFromName']).isNotEmpty && !transferredTab)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(children: [
                            const Icon(Icons.card_giftcard, size: 10, color: Tw.fuchsia400),
                            const SizedBox(width: 4),
                            Text('Recibida de @${t['transferredFromName']}', style: tw(9, weight: bold, color: Tw.fuchsia400)),
                          ]),
                        ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (t['channel'] == 'free_claim')
                      Text(context.t('buy.free', fallback: 'GRATIS'), style: tw(14, weight: black, color: Tw.emerald400))
                    else if (amount != null && amount > 0)
                      Text('${(amount / 100).toStringAsFixed(2)} ${currencySymbol(currency)}', style: tw(14, weight: black, color: Tw.fuchsia400)),
                    Label(statusLabel, color: valid ? accent : Tw.slate500),
                    if (purchased != null) Text(DateFormat('d/M/yyyy').format(purchased), style: tw(9, color: Tw.slate600)),
                  ]),
                ]),
                if (transferredTab) ...[
                  const SizedBox(height: 12),
                  Divider(color: Tw.w(0.05), height: 1),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.person, size: 12, color: Tw.fuchsia400),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        const TextSpan(text: 'Cedida a: '),
                        TextSpan(text: '@${safeStr(t['client_name']).isEmpty ? 'Amigo' : safeStr(t['client_name'])}', style: tw(11, weight: bold, color: Tw.slate300)),
                      ]), style: tw(11, color: Tw.slate300)),
                    ),
                    if (valid && t['isUsed'] != true)
                      Pressable(
                        onTap: onReportFraud,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Tw.red500.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.shield, size: 12, color: Tw.red400),
                            const SizedBox(width: 6),
                            Text('Reportar impago / Recuperar', style: tw(10, weight: black, color: Tw.red400)),
                          ]),
                        ),
                      )
                    else if (t['status'] == 'disputed')
                      Row(children: [
                        const Icon(Icons.lock, size: 12, color: Tw.amber400),
                        const SizedBox(width: 4),
                        Text('Bloqueada por reporte', style: tw(10, weight: bold, color: Tw.amber400)),
                      ]),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _WalletSkeleton extends StatelessWidget {
  const _WalletSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w, double r = 12}) =>
        Container(height: h, width: w, decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(r)));
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), children: [
          box(28, w: 192),
          const SizedBox(height: 8),
          box(16, w: 256),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: box(48, r: 16)),
            const SizedBox(width: 8),
            Expanded(child: box(48, r: 16)),
            const SizedBox(width: 8),
            Expanded(child: box(48, r: 16)),
          ]),
          const SizedBox(height: 24),
          for (var i = 0; i < 3; i++) ...[box(140, r: 24), const SizedBox(height: 24)],
        ]),
      ),
    );
  }
}
