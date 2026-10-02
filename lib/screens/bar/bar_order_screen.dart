import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../tickets/consumption_screen.dart' show checkinStream, checkinExpired;

const _categoryEmoji = {
  'beer': '🍺',
  'cocktail': '🍸',
  'soft_drink': '🥤',
  'water': '💧',
  'pack': '📦',
  'spirit': '🥃',
  'wine': '🍷',
};

const _categoryLabel = {
  'beer': 'Cerveza',
  'cocktail': 'Copas',
  'soft_drink': 'Refrescos',
  'water': 'Agua',
  'pack': 'Packs',
  'spirit': 'Destilados',
  'wine': 'Vino',
};

enum _State { initializing, noVenue, venueNotFound, closed, catalogUnavailable, open }

/// Port of app/bar/order/page.tsx (Barra Digital)
class BarOrderScreen extends StatefulWidget {
  final String? venueId;
  const BarOrderScreen({super.key, this.venueId});

  @override
  State<BarOrderScreen> createState() => _BarOrderScreenState();
}

class _BarOrderScreenState extends State<BarOrderScreen> {
  final _db = FirebaseFirestore.instance;
  String? _uid;
  bool _subscribed = false;
  late String _venueId = widget.venueId ?? '';
  Map<String, dynamic>? _venue;
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  String _category = 'all';
  final Map<String, String> _mixers = {};
  String? _buyingId;
  String? _error;

  StreamSubscription? _checkinSub;
  StreamSubscription? _venueSub;
  StreamSubscription? _productsSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthProvider>().user?.uid;
    if (_subscribed && uid == _uid) return;
    _subscribed = true;
    _uid = uid;
    _checkinSub?.cancel();
    if (uid != null) {
      // Only to open the bar of the venue you're checked in at: buying needs no presence (decided 2026-10-02).
      _checkinSub = checkinStream(uid).listen((c) {
        final hasParam = widget.venueId != null && widget.venueId!.isNotEmpty;
        final vid = safeStr(c?['venueId']);
        if (!hasParam && c != null && vid.isNotEmpty && !checkinExpired(c) && vid != _venueId) _selectVenue(vid);
      }, onError: (_) {});
    }
    _selectVenue(_venueId);
  }

  void _selectVenue(String id) {
    _venueId = id;
    _venueSub?.cancel();
    _productsSub?.cancel();
    _products = [];
    if (id.isEmpty) {
      _venue = null;
      _loading = false;
      return;
    }
    _loading = true;
    _venueSub = _db.collection('venues').doc(id).snapshots().listen((s) {
      setState(() {
        _venue = s.exists ? {'id': s.id, ...?s.data()} : null;
        _loading = false;
      });
    }, onError: (_) => setState(() => _loading = false));
    _productsSub = _db
        .collection('products')
        .where('venueId', isEqualTo: id)
        .where('active', isEqualTo: true)
        .snapshots()
        // Sorted here, not in the query: venueId + active + orderBy(category, name) needs a composite index production
        // doesn't have, so the query failed and the bar showed no products (as on the web).
        .listen((snap) => setState(() => _products = snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList()
              ..sort((a, b) {
                final c = safeStr(a['category']).compareTo(safeStr(b['category']));
                return c != 0 ? c : safeStr(a['name']).compareTo(safeStr(b['name']));
              })),
            onError: (_) {});
  }

  @override
  void dispose() {
    _checkinSub?.cancel();
    _venueSub?.cancel();
    _productsSub?.cancel();
    super.dispose();
  }

  _State _state(bool authLoading) {
    if (authLoading || _loading) return _State.initializing;
    if (_venueId.isEmpty) return _State.noVenue;
    final v = _venue;
    if (v == null) return _State.venueNotFound;
    final cashless = v['cashless'] is Map ? v['cashless'] as Map : const {};
    if (v['isActive'] == false || cashless['enabled'] == false || cashless['kioskOpen'] == false) return _State.closed;
    if (_products.isEmpty) return _State.catalogUnavailable;
    return _State.open;
  }

  Future<void> _buy(Map<String, dynamic> product) async {
    final uid = _uid;
    if (uid == null || _venueId.isEmpty) return;
    final id = product['id'] as String;
    setState(() {
      _buyingId = id;
      _error = null;
    });
    try {
      final rand = List.generate(8, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[math.Random().nextInt(36)]).join();
      final res = await FirebaseFunctions.instance.httpsCallable('createConsumptionCheckoutSession').call({
        'venueId': _venueId,
        'items': [
          {'productId': id, 'quantity': 1, 'selectedMixer': _mixers[id]},
        ],
        'origin': webBase,
        'idempotencyKey': 'ord_${uid}_${DateTime.now().millisecondsSinceEpoch}_$rand',
      });
      final url = res.data is Map ? (res.data as Map)['url'] as String? : null;
      if (url != null && url.isNotEmpty) {
        await openInApp(url);
      } else if (mounted) {
        openRoute(context, AppRoute.consumption, args: {'success': 'true'}, replace: true);
      }
    } on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? '';
      final code = e.code;
      if (msg.contains('CASHLESS_CLOSED')) {
        _error = 'La barra digital está temporalmente cerrada en este local.';
      } else if (code == 'resource-exhausted' || msg.contains('Stock')) {
        _error = 'No queda stock disponible de este producto.';
      } else {
        _error = msg.isNotEmpty ? msg : 'Error al procesar la compra.';
      }
    } catch (_) {
      _error = 'Error al procesar la compra.';
    }
    if (mounted) setState(() => _buyingId = null);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final state = _state(auth.loading);

    if (state == _State.initializing) return _skeleton();
    if (auth.user == null) {
      return _message(
        icon: Icons.lock,
        iconColor: Tw.amber400,
        title: 'Inicia sesión',
        desc: 'Para acceder a la barra digital y pedir consumiciones necesitas identificarte con tu cuenta.',
        action: GradientButton(
          label: 'Iniciar sesión',
          gradient: const LinearGradient(colors: [Tw.fuchsia600, Color(0xFFDB2777)]),
          radius: 12,
          fontSize: 14,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          onTap: () => openRoute(context, AppRoute.login),
        ),
      );
    }
    if (state == _State.noVenue) {
      return _message(
        boxedIcon: Icons.local_bar,
        title: 'Barra Digital',
        desc: 'No estás registrado en ningún local ahora mismo. Escanea el QR del local o valida tu entrada en puerta para acceder a su carta.',
        action: _slateButton('Explorar locales y eventos', () => openRoute(context, AppRoute.events)),
      );
    }
    if (state == _State.venueNotFound) {
      return _message(
        icon: Icons.error_outline,
        iconColor: const Color(0xFFF43F5E),
        title: 'Local no disponible',
        desc: 'No hemos podido encontrar el local solicitado o ya no está en la plataforma.',
        action: _slateButton('Volver', () => openRoute(context, AppRoute.events)),
      );
    }

    final venueName = safeStr(_venue?['name']).isNotEmpty ? safeStr(_venue!['name']) : 'Local';
    final closed = state == _State.closed;
    final categories = ['all', ...{for (final p in _products) safeStr(p['category'])}];
    final filtered = _category == 'all' ? _products : _products.where((p) => p['category'] == _category).toList();

    return Scaffold(
      backgroundColor: Tw.black,
      body: Column(children: [
        _header(context, venueName, closed),
        Expanded(
          child: ListView(padding: EdgeInsets.only(bottom: 32 + MediaQuery.of(context).padding.bottom), children: [
            if (closed)
              _alert(
                color: const Color(0xFFF43F5E),
                bg: const Color(0xFF4C0519),
                icon: Icons.lock_clock,
                title: 'Barra Digital Cerrada',
                desc: 'El servicio cashless no está recibiendo pedidos en este momento en $venueName.',
              ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF881337).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.5)),
                ),
                child: Row(children: [
                  Expanded(child: Text(_error!, style: tw(12, color: const Color(0xFFFECDD3)))),
                  GestureDetector(
                    onTap: () => setState(() => _error = null),
                    child: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.close, size: 14, color: Color(0xFFFB7185))),
                  ),
                ]),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 36,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Pressable(
                      onTap: () => setState(() => _category = c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _category == c ? Tw.fuchsia600 : Tw.slate900,
                          borderRadius: BorderRadius.circular(12),
                          border: _category == c ? null : Border.all(color: Tw.slate800),
                        ),
                        child: Text(
                          c == 'all' ? '✨ Todo' : '${_categoryEmoji[c] ?? ''} ${_categoryLabel[c] ?? c}',
                          style: tw(12, weight: bold, color: _category == c ? Tw.white : Tw.slate300),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            if (_products.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 80),
                child: Column(children: [
                  const Icon(Icons.inventory_2, size: 36, color: Tw.slate600),
                  const SizedBox(height: 12),
                  Text('No hay productos disponibles en este local ahora mismo.', textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
                ]),
              )
            else
              for (final p in filtered) _productCard(p, closed),
          ]),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context, String venueName, bool closed) => Container(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 14, 16, 14),
        decoration: BoxDecoration(
          color: Tw.slate950.withValues(alpha: 0.9),
          border: Border(bottom: BorderSide(color: Tw.slate800.withValues(alpha: 0.8))),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Tw.fuchsia600, Tw.amber400]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Tw.fuchsia600.withValues(alpha: 0.3), blurRadius: 15)],
            ),
            child: const Icon(Icons.local_bar, color: Tw.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(venueName.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(14, weight: black, height: 1)),
                ),
                const SizedBox(width: 8),
                if (closed)
                  _badge('CERRADA', const Color(0xFFFB7185), const Color(0xFFF43F5E))
                else
                  _badge('ABIERTA', Tw.emerald400, Tw.emerald500, dot: true),
              ]),
              const SizedBox(height: 2),
              Text('Barra Digital Cashless • 1 Ticket = 1 Copa',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(11, weight: medium, color: Tw.slate400)),
            ]),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: () => openRoute(context, AppRoute.consumption),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.slate700)),
              child: Text('Mis copas', style: tw(12, weight: bold)),
            ),
          ),
        ]),
      );

  Widget _badge(String text, Color fg, Color base, {bool dot = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: base.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: fg)),
            const SizedBox(width: 4),
          ],
          Text(text, style: tw(9, weight: bold, color: fg)),
        ]),
      );

  Widget _alert({required Color color, required Color bg, required IconData icon, required String title, required String desc, Widget? action}) =>
      Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 20, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: tw(12, weight: bold)),
                const SizedBox(height: 2),
                Text(desc, style: tw(11, color: color.withValues(alpha: 0.8))),
              ]),
            ),
          ]),
          if (action != null) ...[const SizedBox(height: 12), action],
        ]),
      );

  Widget _productCard(Map<String, dynamic> p, bool closed) {
    final id = p['id'] as String;
    final buying = _buyingId == id;
    final stock = p['stock'];
    final outOfStock = stock is num && stock <= 0;
    final mixers = asStringList(p['mixerOptions']);
    final selected = _mixers[id] ?? (mixers.isNotEmpty ? mixers.first : '');
    final price = asDouble(p['price']) ?? 0;
    final disabled = buying || closed;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Tw.slate900.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Tw.slate800.withValues(alpha: 0.8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(_categoryEmoji[p['category']] ?? '🍹', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text(safeStr(p['name']), style: tw(16, weight: FontWeight.w800))),
          if (p['isPremium'] == true) _badge('PREMIUM', const Color(0xFFD8B4FE), Tw.purple500),
        ]),
        if (safeStr(p['description']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 4),
            child: Text(safeStr(p['description']), style: tw(12, color: Tw.slate400)),
          ),
        if (mixers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Label('Elige mezclador:', weight: bold, tracking: 0.05),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in mixers)
                  GestureDetector(
                    onTap: () => setState(() => _mixers[id] = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: selected == m ? Tw.fuchsia600 : Tw.slate800, borderRadius: BorderRadius.circular(8)),
                      child: Text(m, style: tw(11, weight: selected == m ? bold : medium, color: selected == m ? Tw.white : Tw.slate300)),
                    ),
                  ),
              ]),
            ]),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.slate800.withValues(alpha: 0.6)))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${price.toStringAsFixed(2)} €', style: tw(18, weight: black, color: Tw.amber400)),
            if (outOfStock)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(12)),
                child: Text('Agotado', style: tw(12, weight: bold, color: Tw.slate500)),
              )
            else
              Opacity(
                opacity: disabled ? 0.4 : 1,
                child: Pressable(
                  onTap: disabled ? () {} : () => _buy(p),
                  scale: 0.95,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Tw.fuchsia600, Color(0xFFDB2777)]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (buying) ...[const Icon(Icons.sync, size: 14, color: Tw.white), const SizedBox(width: 6)],
                      Text(
                        buying
                            ? 'Procesando...'
                            : closed
                                ? 'Cerrado'
                                : 'Pedir',
                        style: tw(12, weight: black, color: Tw.white),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _skeleton() => Scaffold(
        backgroundColor: Tw.black,
        body: Padding(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [_box(32, 32, 12), const SizedBox(width: 12), _box(128, 20, 4)]),
            const SizedBox(height: 24),
            Row(children: [for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(right: 8), child: _box(80, 32, 99))]),
            const SizedBox(height: 12),
            for (var i = 0; i < 4; i++) Padding(padding: const EdgeInsets.only(bottom: 12), child: _box(double.infinity, 96, 16)),
          ]),
        ),
      );

  Widget _box(double w, double h, double r) =>
      Container(width: w, height: h, decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(r)));

  Widget _slateButton(String label, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.slate700)),
          child: Text(label, style: tw(14, weight: bold)),
        ),
      );

  Widget _message({IconData? icon, Color? iconColor, IconData? boxedIcon, required String title, required String desc, required Widget action}) =>
      Scaffold(
        backgroundColor: Tw.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) Icon(icon, size: 48, color: iconColor),
              if (boxedIcon != null)
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.slate800)),
                  child: Icon(boxedIcon, size: 30, color: Tw.fuchsia400),
                ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: tw(20, weight: black)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 384),
                child: Text(desc, textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
              ),
              const SizedBox(height: 24),
              action,
            ]),
          ),
        ),
      );
}
