import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class _Upsell {
  final String title;
  final String description;
  final double addonPrice;
  final String targetName;
  const _Upsell(this.title, this.description, this.addonPrice, this.targetName);
}

class _Drink {
  final String id;
  final String name;
  final String category;
  final double price;
  final bool popular;
  final List<String> mixers;
  final _Upsell? upsell;
  const _Drink(this.id, this.name, this.category, this.price, {this.popular = false, this.mixers = const [], this.upsell});

  factory _Drink.fromMap(String id, Map<String, dynamic> d) {
    final u = d['upsellOption'];
    return _Drink(
      id,
      safeStr(d['name']),
      safeStr(d['category']),
      asDouble(d['price']) ?? 0,
      popular: d['isPopular'] == true,
      mixers: asStringList(d['mixerOptions']),
      upsell: u is Map
          ? _Upsell(safeStr(u['title']), safeStr(u['description']), asDouble(u['addonPrice']) ?? 0, safeStr(u['targetName']))
          : null,
    );
  }
}

const _defaultMenu = [
  _Drink('c1', 'Ginebra Beefeater', 'copa', 10,
      popular: true,
      mixers: ['Tónica Schweppes', 'Coca-Cola', 'Coca-Cola Zero', 'Sprite'],
      upsell: _Upsell('Subir a Hendrick Gin Premium', 'Infusión de pepino y pétalos de rosa búlgara', 2.5, 'Hendrick Gin Premium')),
  _Drink('c2', 'Ron Barceló Añejo', 'copa', 10,
      popular: true,
      mixers: ['Coca-Cola', 'Coca-Cola Zero', 'Limón'],
      upsell: _Upsell('Subir a Zacapa 23 Gran Reserva', 'Envejecido en barricas de roble blanco', 3.5, 'Zacapa 23 Reserva')),
  _Drink('c3', 'Vodka Absolut', 'copa', 10,
      mixers: ['Tónica', 'Limón', 'Naranja', 'Red Bull (+1€)'],
      upsell: _Upsell('Mejorar a Grey Goose Ultra', 'Trigo francés y agua pura de manantial de Gensac', 3.0, 'Grey Goose Ultra')),
  _Drink('b1', 'Cerveza Estrella Damm', 'cerveza', 5, popular: true),
  _Drink('s1', 'Tequila Don Julio Reposado', 'chupito', 4.5),
  _Drink('s2', 'Jäger Shot Helado (-18°C)', 'chupito', 4, popular: true),
  _Drink('w1', 'Agua Mineral 50cl', 'soft_drink', 2.5),
  _Drink('p1', 'Pack 2 Copas Directas', 'pack', 18, popular: true),
];

const _categories = [
  ('all', 'Todo'),
  ('copa', 'Copas 🍸'),
  ('cerveza', 'Cervezas 🍺'),
  ('chupito', 'Chupitos 🔥'),
  ('pack', 'Packs ⚡'),
];

/// Port of app/events/[eventId]/bar/EventBarClient.tsx. eventId '_' = generic bar (gift drink from a profile/chat).
class EventBarScreen extends StatefulWidget {
  final String eventId;
  final String giftNick;
  const EventBarScreen({super.key, this.eventId = '_', this.giftNick = ''});

  @override
  State<EventBarScreen> createState() => _EventBarScreenState();
}

class _EventBarScreenState extends State<EventBarScreen> {
  Map<String, dynamic>? _event;
  List<_Drink> _menu = _defaultMenu;
  String _cat = 'all';
  String? _purchasingId;
  String? _error;
  late bool _gifting = widget.giftNick.isNotEmpty;
  late final _nick = TextEditingController(text: widget.giftNick);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nick.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.eventId.isEmpty || widget.eventId == '_') return;
    final db = FirebaseFirestore.instance;
    try {
      final ev = await db.collection('events').doc(widget.eventId).get();
      if (!ev.exists) return;
      final data = ev.data()!;
      if (mounted) setState(() => _event = data);
      final vid = safeStr(data['venueId']);
      if (vid.isNotEmpty) {
        final prods = await db.collection('products').where('venueId', isEqualTo: vid).where('active', isEqualTo: true).get();
        if (prods.docs.isNotEmpty && mounted) {
          setState(() => _menu = prods.docs.map((d) => _Drink.fromMap(d.id, d.data())).toList());
        }
      }
    } catch (_) {}
  }

  void _select(_Drink item) {
    if (item.mixers.isNotEmpty) {
      _customize(item);
    } else {
      _checkout(item, null, false);
    }
  }

  Future<void> _checkout(_Drink item, String? mixer, bool premium) async {
    if (context.read<AuthProvider>().user == null) {
      openRoute(context, AppRoute.login);
      return;
    }
    final upsell = premium ? item.upsell : null;
    setState(() {
      _purchasingId = item.id;
      _error = null;
    });
    try {
      final nick = _nick.text.trim();
      final res = await FirebaseFunctions.instance.httpsCallable('createConsumptionTicket').call({
        'productId': item.id,
        'venueId': safeStr(_event?['venueId']).isNotEmpty ? safeStr(_event!['venueId']) : 'venue_default',
        if (widget.eventId != '_') 'eventId': widget.eventId,
        'name': upsell?.targetName ?? item.name,
        'price': item.price + (upsell?.addonPrice ?? 0),
        'category': item.category,
        'selectedMixer': mixer,
        'isPremium': premium,
        if (_gifting && nick.isNotEmpty) 'recipientNick': nick,
        'origin': webBase,
      });
      final url = res.data is Map ? (res.data as Map)['url'] as String? : null;
      if (url != null && url.isNotEmpty) {
        await openInApp(url);
      } else if (mounted) {
        openRoute(context, AppRoute.consumption, args: {'success': 'true'}, replace: true);
        return;
      }
    } on FirebaseFunctionsException catch (e) {
      _error = e.message ?? 'Error al iniciar el pago. Inténtalo de nuevo.';
    } catch (_) {
      _error = 'Error al iniciar el pago. Inténtalo de nuevo.';
    }
    if (mounted) setState(() => _purchasingId = null);
  }

  void _customize(_Drink item) {
    var mixer = item.mixers.first;
    var premium = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final total = item.price + (premium && item.upsell != null ? item.upsell!.addonPrice : 0);
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Tw.slate900,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Tw.slate700.withValues(alpha: 0.8)),
                ),
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Expanded(child: Text(item.name, style: tw(16, weight: black))),
                      GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Tw.slate800, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Tw.slate400),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Text(ctx.t('bar_select_mixer', fallback: 'Elige tu acompañamiento / refresco:'), style: tw(12, weight: bold, color: Tw.slate400)),
                    const SizedBox(height: 8),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 4,
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (final m in item.mixers)
                          GestureDetector(
                            onTap: () => setSheet(() => mixer = m),
                            child: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: mixer == m ? Tw.white : Tw.slate800,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: mixer == m ? Tw.white : Tw.slate700),
                              ),
                              child: Text(m, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: tw(12, weight: bold, color: mixer == m ? Tw.black : Tw.slate300)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (item.upsell != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF451A03).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Tw.amber500.withValues(alpha: 0.4)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(
                              child: Label(ctx.t('bar_premium_upgrade', fallback: '¿MEJORAR A PREMIUM?'), color: Tw.amber400, tracking: 0.025),
                            ),
                            Text('+${item.upsell!.addonPrice.toStringAsFixed(2)} €', style: tw(12, weight: black, color: Tw.amber400)),
                          ]),
                          const SizedBox(height: 4),
                          Text(item.upsell!.title, style: tw(12, weight: bold, color: const Color(0xFFE2E8F0))),
                          const SizedBox(height: 2),
                          Text(item.upsell!.description, style: tw(11, color: Tw.slate400)),
                          const SizedBox(height: 10),
                          Pressable(
                            onTap: () => setSheet(() => premium = !premium),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: premium ? Tw.amber400 : Tw.slate800,
                                borderRadius: BorderRadius.circular(12),
                                border: premium ? null : Border.all(color: Tw.slate700),
                              ),
                              child: Text(premium ? '✓ Premium Activada' : '+ Añadir mejora Premium',
                                  style: tw(12, weight: black, color: premium ? Tw.black : Tw.slate300)),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Tw.slate800.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Tw.slate700.withValues(alpha: 0.6)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        GestureDetector(
                          onTap: () => setSheet(() => setState(() => _gifting = !_gifting)),
                          child: Row(children: [
                            Expanded(
                              child: Text('🎁 ${ctx.t('bar_gift_toggle', fallback: '¿Es para regalar a un colega?')}',
                                  style: tw(12, weight: bold)),
                            ),
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: _gifting,
                                activeColor: Tw.fuchsia500,
                                onChanged: (v) => setSheet(() => setState(() => _gifting = v ?? false)),
                              ),
                            ),
                          ]),
                        ),
                        if (_gifting) ...[
                          const SizedBox(height: 10),
                          Text(ctx.t('bar_gift_nick_label', fallback: '@nick del colega (debe tener la app):'),
                              style: tw(11, color: Tw.slate400)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _nick,
                            style: tw(12),
                            decoration: InputDecoration(
                              hintText: '@usuario',
                              isDense: true,
                              fillColor: Tw.slate900,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.slate700)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.fuchsia500)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(ctx.t('bar_gift_hint', fallback: 'El ticket QR llegará directo a su app para que lo canjee en la barra.'),
                              style: tw(10, color: Tw.slate400, height: 1.25)),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.only(top: 8),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tw.slate800))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                        Expanded(child: Text('Total a pagar:', style: tw(12, color: Tw.slate400))),
                        Text('${total.toStringAsFixed(2)} €', style: tw(20, weight: black)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Pressable(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _checkout(item, mixer, premium);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.amber500]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Tw.fuchsia600.withValues(alpha: 0.3), blurRadius: 25)],
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.credit_card, size: 16, color: Tw.white),
                          const SizedBox(width: 8),
                          Text(ctx.t('bar_confirm_and_pay', fallback: 'Pagar con Apple / Tarjeta'), style: tw(14, weight: black)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _cat == 'all' ? _menu : _menu.where((i) => i.category == _cat).toList();
    return Scaffold(
      backgroundColor: Tw.black,
      body: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 14, 16, 14),
          decoration: BoxDecoration(
            color: Tw.slate950.withValues(alpha: 0.9),
            border: Border(bottom: BorderSide(color: Tw.slate800.withValues(alpha: 0.8))),
          ),
          child: Row(children: [
            Pressable(
              onTap: () => Navigator.of(context).maybePop(),
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
                  Text(context.t('event_bar_title', fallback: 'BARRA DEL EVENTO'), style: tw(16, weight: black, tracking: -0.025, height: 1)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Tw.emerald500.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
                    ),
                    child: Text('PAGO DIRECTO', style: tw(10, weight: bold, color: Tw.emerald400)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(
                  safeStr(_event?['title']).isNotEmpty
                      ? safeStr(_event!['title'])
                      : context.t('event_bar_subtitle', fallback: 'Pide en el móvil • Cero colas • Solo pagas lo que bebes'),
                  style: tw(11, weight: medium, color: Tw.slate400),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Pressable(
              onTap: () => openRoute(context, AppRoute.consumption),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A044E).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF86198F).withValues(alpha: 0.6)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wine_bar, size: 16, color: Tw.fuchsia400),
                  const SizedBox(width: 6),
                  Text(context.t('event_bar_my_drinks', fallback: 'Mis Copas'), style: tw(12, weight: bold, color: Tw.fuchsia400)),
                ]),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: EdgeInsets.only(bottom: 112 + MediaQuery.of(context).padding.bottom), children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.slate900, Color(0xE60F172A), Tw.slate950]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Tw.slate800),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.bolt, size: 16, color: Tw.amber400),
                  const SizedBox(width: 8),
                  Expanded(child: Label(context.t('bar_manifesto_badge', fallback: 'Sin pulseras ni saldos atrapados'), size: 12, color: Tw.amber400, tracking: 0.05)),
                ]),
                const SizedBox(height: 4),
                Text(
                  context.t('bar_manifesto_text',
                      fallback:
                          'En Blow Nights solo pagas la copa que quieres tomarte. Sin recargas mínimas de 20€ ni 2€ perdidos al final de la noche. Pagas con Apple/Google Pay o tarjeta y te la sirven en 1 segundo.'),
                  style: tw(12, color: Tw.slate300, height: 1.6),
                ),
              ]),
            ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF450A0A).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF991B1B)),
                ),
                child: Text(_error!, style: tw(12, weight: medium, color: const Color(0xFFFCA5A5))),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 32,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                for (final (id, label) in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Pressable(
                      onTap: () => setState(() => _cat = id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _cat == id ? Tw.white : Tw.slate900,
                          borderRadius: BorderRadius.circular(12),
                          border: _cat == id ? null : Border.all(color: Tw.slate800),
                        ),
                        child: Text(label, style: tw(12, weight: bold, color: _cat == id ? Tw.black : Tw.slate400)),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            for (final item in items) _drinkCard(context, item),
          ]),
        ),
      ]),
    );
  }

  Widget _drinkCard(BuildContext context, _Drink item) {
    final buying = _purchasingId == item.id;
    final color = item.category == 'cerveza'
        ? Tw.amber400
        : item.category == 'chupito'
            ? const Color(0xFFFB923C)
            : Tw.fuchsia400;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Tw.slate900.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Tw.slate800),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
          child: Icon(item.category == 'cerveza' ? Icons.sports_bar : Icons.wine_bar, size: 24, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
              Text(item.name, style: tw(14, weight: black)),
              if (item.popular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Tw.amber500.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Tw.amber500.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.local_fire_department, size: 12, color: Tw.amber400),
                    const SizedBox(width: 2),
                    Text('TOP', style: tw(9, weight: bold, color: Tw.amber400)),
                  ]),
                ),
            ]),
            if (item.mixers.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text('Elige refresco al pedir', style: tw(11, color: Tw.slate400))),
            const SizedBox(height: 4),
            Text('${item.price.toStringAsFixed(2)} €', style: tw(14, weight: black, color: Tw.emerald400)),
          ]),
        ),
        const SizedBox(width: 12),
        Opacity(
          opacity: buying ? 0.5 : 1,
          child: Pressable(
            onTap: buying ? () {} : () => _select(item),
            scale: 0.95,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.amber500]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Tw.fuchsia600.withValues(alpha: 0.2), blurRadius: 15)],
              ),
              child: buying
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.credit_card, size: 16, color: Tw.white),
                      const SizedBox(width: 6),
                      Text(context.t('bar_buy_now', fallback: 'Comprar'), style: tw(12, weight: black)),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}
