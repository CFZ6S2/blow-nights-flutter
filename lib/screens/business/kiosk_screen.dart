import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../i18n/i18n.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class _Upsell {
  final String title, description, targetName;
  final double addonPrice;
  const _Upsell(this.title, this.description, this.addonPrice, this.targetName);
}

class _Drink {
  final String id, name, category;
  final double price;
  final bool popular;
  final List<String>? mixers;
  final _Upsell? upsell;
  const _Drink(this.id, this.name, this.category, this.price, {this.popular = false, this.mixers, this.upsell});
}

class _CartItem {
  final String cartId, name;
  final double price;
  final String? mixer;
  final bool premium;
  const _CartItem(this.cartId, this.name, this.price, this.mixer, this.premium);
}

const _menu = [
  _Drink('c1', 'Ginebra Beefeater', 'copa', 10,
      popular: true, mixers: ['Tonica', 'Coca-Cola', 'Zero'], upsell: _Upsell('Subir a Hendrick Gin Premium', 'Infusion de pepino y rosas', 2.5, 'Hendrick Gin Premium')),
  _Drink('c2', 'Ron Barcelo Anejo', 'copa', 10,
      popular: true,
      mixers: ['Coca-Cola', 'Zero', 'Limon'],
      upsell: _Upsell('Subir a Zacapa 23 Gran Reserva', 'Envejecido en roble blanco a gran altitud', 3.5, 'Zacapa 23 Reserva')),
  _Drink('c3', 'Vodka Absolut', 'copa', 10,
      mixers: ['Tonica', 'Limon', 'Red Bull (+1€)'], upsell: _Upsell('Pasar a Grey Goose Ultra', 'Trigo frances y agua pura de Gensac', 3.0, 'Grey Goose Ultra')),
  _Drink('b1', 'Cerveza Estrella Damm', 'cerveza', 5, popular: true),
  _Drink('s1', 'Tequila Don Julio Reposado', 'chupito', 4.5, upsell: _Upsell('Ronda x5 Chupitos', 'Ahorra 4.50€ con la ronda para grupo', 13.5, 'Ronda x5 Don Julio')),
  _Drink('s2', 'Jager Shot Helado', 'chupito', 4, popular: true),
  _Drink('p1', 'Pack 2 Copas Directas', 'pack', 18, popular: true),
  _Drink('v1', 'Botella VIP Moet Brut', 'vip', 120),
];

/// Port of app/kiosk/page.tsx (self-service drinks totem demo: mock menu, upsell, simulated contactless payment).
class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  final _rand = Random();
  String _cat = 'all';
  List<_CartItem> _cart = [];
  String _step = 'browse';
  List<({String tokenId, String name, String? mixer})> _tokens = [];

  double get _total => _cart.fold(0, (s, i) => s + i.price);

  Future<void> _add(_Drink d) async {
    final mixer = d.mixers?.first;
    final up = d.upsell;
    if (up != null) {
      final premium = await showDialog<bool>(context: context, barrierColor: Colors.black.withValues(alpha: 0.8), builder: (_) => _UpsellDialog(drink: d));
      if (premium == null) return;
      _push(premium ? up.targetName : d.name, premium ? d.price + up.addonPrice : d.price, mixer, premium);
      return;
    }
    _push(d.name, d.price, mixer, false);
  }

  void _push(String name, double price, String? mixer, bool premium) =>
      setState(() => _cart = [..._cart, _CartItem(_rand.nextInt(1 << 32).toRadixString(36), name, price, mixer, premium)]);

  void _pay() {
    if (_cart.isEmpty) return;
    setState(() => _step = 'paying');
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _tokens = [for (final c in _cart) (tokenId: 'DRK-${100000 + _rand.nextInt(900000)}', name: c.name, mixer: c.mixer)];
        _step = 'success';
      });
    });
  }

  void _reset() => setState(() {
        _cart = [];
        _tokens = [];
        _step = 'browse';
        _cat = 'all';
      });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Stack(children: [
        Column(children: [
          Container(
            padding: EdgeInsets.fromLTRB(12, top + 12, 16, 12),
            decoration: const BoxDecoration(color: Tw.slate900, border: Border(bottom: BorderSide(color: Tw.slate800))),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Tw.fuchsia600, Color(0xFFDB2777), Tw.amber400]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.wine_bar, color: Tw.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(context.t('kiosk_title', fallback: 'BARRA DIGITAL'), style: tw(18, weight: black)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Tw.emerald500.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
                      ),
                      child: Text(context.t('kiosk_badge', fallback: 'TOTEM TACTICO'), style: tw(10, color: Tw.emerald400)),
                    ),
                  ]),
                  Text(context.t('kiosk_subtitle', fallback: 'Pide en pantalla • Paga con Contactless • Recoge en barra'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(11, color: Tw.slate400)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Label(context.t('kiosk_total_order', fallback: 'Total Orden'), weight: bold, tracking: 0),
                Text('${_total.toStringAsFixed(2)} €', style: tw(18, weight: black, color: Tw.amber400)),
              ]),
              const SizedBox(width: 8),
              IconButton(onPressed: _reset, icon: const Icon(Icons.refresh, color: Tw.slate300)),
            ]),
          ),
          Expanded(child: _step == 'success' ? _success(context) : _browse(context)),
        ]),
        if (_step == 'paying')
          Container(
            color: Colors.black.withValues(alpha: 0.9),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.slate800)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 4, color: Tw.emerald400)),
                const SizedBox(height: 20),
                Text(context.t('kiosk_processing', fallback: 'PROCESANDO COBRO'), style: tw(22, weight: black)),
                const SizedBox(height: 4),
                Text(context.t('kiosk_processing_hint', fallback: 'Acerque tarjeta o telefono al terminal contactless...'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _browse(BuildContext context) {
    final list = _cat == 'all' ? _menu : _menu.where((d) => d.category == _cat).toList();
    return Column(children: [
      SizedBox(
        height: 64,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), children: [
          for (final c in const ['all', 'copa', 'cerveza', 'chupito', 'pack', 'vip'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Pressable(
                onTap: () => setState(() => _cat = c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _cat == c ? Tw.fuchsia600 : Tw.slate800.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
                  child: Text(c == 'all' ? context.t('kiosk_category_all', fallback: '✨ Todos') : c[0].toUpperCase() + c.substring(1),
                      style: tw(14, weight: bold, color: _cat == c ? Tw.white : Tw.slate300)),
                ),
              ),
            ),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [for (final d in list) _drinkCard(context, d)]),
      ),
      _cartPanel(context),
    ]);
  }

  Widget _drinkCard(BuildContext context, _Drink d) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.slate800)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(d.name, style: tw(18, weight: black))),
            if (d.popular)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Tw.amber500.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Tw.amber500.withValues(alpha: 0.3)),
                ),
                child: Label(context.t('kiosk_top_sales', fallback: 'Top Ventas'), color: const Color(0xFFFCD34D), tracking: 0),
              ),
          ]),
          if (d.mixers != null) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final m in d.mixers!)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(4)),
                  child: Text(m, style: tw(10, color: Tw.slate400)),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: Tw.slate800),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('kiosk_price', fallback: 'Precio'), style: tw(12, color: Tw.slate400)),
                Text('${d.price.toStringAsFixed(2)} €', style: tw(22, weight: black)),
              ]),
            ),
            GradientButton(
              label: context.t('kiosk_add', fallback: 'Anadir +'),
              fontSize: 13,
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              gradient: const LinearGradient(colors: [Tw.fuchsia600, Color(0xFFDB2777)]),
              onTap: () => _add(d),
            ),
          ]),
        ]),
      );

  Widget _cartPanel(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(color: Tw.slate900, border: Border(top: BorderSide(color: Tw.slate800))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.shopping_bag, size: 18, color: Tw.fuchsia500),
            const SizedBox(width: 8),
            Expanded(child: Text('${context.t('kiosk_your_order', fallback: 'Tu Pedido')} (${_cart.length})', style: tw(16, weight: black))),
            if (_cart.isNotEmpty)
              GestureDetector(onTap: () => setState(() => _cart = []), child: Text(context.t('kiosk_clear', fallback: 'Vaciar'), style: tw(12, color: Tw.red400))),
          ]),
          if (_cart.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(top: 8), children: [
                for (final c in _cart)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Tw.slate800.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.slate700.withValues(alpha: 0.6))),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(c.name, style: tw(13, weight: bold))),
                            if (c.premium) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(color: Tw.amber500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                child: Text('PREMIUM', style: tw(9, weight: black, color: const Color(0xFFFCD34D))),
                              ),
                            ],
                          ]),
                          if (c.mixer != null) Text('+ ${c.mixer}', style: tw(11, color: Tw.slate400)),
                        ]),
                      ),
                      Text('${c.price.toStringAsFixed(2)} €', style: tw(13, weight: black, color: Tw.amber400)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _cart = _cart.where((x) => x.cartId != c.cartId).toList()),
                        icon: const Icon(Icons.close, size: 16, color: Tw.slate500),
                      ),
                    ]),
                  ),
              ]),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Text(context.t('kiosk_total_to_pay', fallback: 'Total a Pagar'), style: tw(14, color: Tw.slate400)),
            const Spacer(),
            Text('${_total.toStringAsFixed(2)} €', style: tw(26, weight: black)),
          ]),
          const SizedBox(height: 8),
          Opacity(
            opacity: _cart.isEmpty ? 0.3 : 1,
            child: GradientButton(
              label: context.t('kiosk_pay_contactless', fallback: 'PAGAR CON CONTACTLESS'),
              icon: Icons.credit_card,
              expand: true,
              fontSize: 15,
              padding: const EdgeInsets.symmetric(vertical: 16),
              gradient: const LinearGradient(colors: [Tw.emerald500, Tw.teal500, Tw.cyan500]),
              onTap: _cart.isEmpty ? null : _pay,
            ),
          ),
          const SizedBox(height: 6),
          Text(context.t('kiosk_pay_hint', fallback: 'Acerca tu Tarjeta, Movil o Apple Pay al datafono inferior'), textAlign: TextAlign.center, style: tw(11, color: Tw.slate400)),
        ]),
      );

  Widget _success(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: Tw.emerald500.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Tw.emerald500.withValues(alpha: 0.4))),
            child: const Icon(Icons.check_circle, size: 36, color: Tw.emerald400),
          ),
        ),
        const SizedBox(height: 16),
        Text(context.t('kiosk_payment_complete', fallback: 'PAGO COMPLETADO'), textAlign: TextAlign.center, style: tw(28, weight: black)),
        const SizedBox(height: 8),
        Text(context.t('kiosk_payment_hint', fallback: 'Muestra los codigos QR en barra para retirar tus consumiciones al instante.'),
            textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
        const SizedBox(height: 32),
        for (final t in _tokens)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.slate700, width: 2)),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(16)),
                child: QrImageView(data: t.tokenId, size: 140, padding: EdgeInsets.zero),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(99)),
                child: Text(t.tokenId, style: tw(12, weight: bold, color: Tw.amber400).copyWith(fontFamily: 'monospace')),
              ),
              const SizedBox(height: 8),
              Text(t.name, style: tw(18, weight: black)),
              if (t.mixer != null) Text('Con ${t.mixer}', style: tw(12, color: Tw.slate400)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Tw.emerald500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(context.t('kiosk_ready_for_bar', fallback: 'Listo para barra'), style: tw(10, weight: bold, color: Tw.emerald400)),
              ),
            ]),
          ),
        const SizedBox(height: 16),
        Pressable(
          onTap: _reset,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(context.t('kiosk_finish', fallback: 'FINALIZAR Y LIBERAR TOTEM'), textAlign: TextAlign.center, style: tw(15, weight: black, color: Tw.slate950))),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, color: Tw.slate950),
            ]),
          ),
        ),
      ]);
}

class _UpsellDialog extends StatelessWidget {
  final _Drink drink;
  const _UpsellDialog({required this.drink});

  @override
  Widget build(BuildContext context) {
    final up = drink.upsell!;
    return Dialog(
      backgroundColor: Tw.slate900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Tw.amber500.withValues(alpha: 0.4), width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Tw.amber500.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Tw.amber500.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.auto_awesome, color: Tw.amber400),
            ),
          ),
          const SizedBox(height: 16),
          Label(context.t('kiosk_upsell_title', fallback: 'MEJORA TU EXPERIENCIA'), size: 12, color: Tw.amber400, tracking: 0.05),
          const SizedBox(height: 4),
          Text(up.title, style: tw(20, weight: black, height: 1.2)),
          const SizedBox(height: 8),
          Text(up.description, style: tw(12, color: Tw.slate300)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.slate700)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('kiosk_supplement', fallback: 'Suplemento'), style: tw(12, color: Tw.slate400)),
                  Text('+${up.addonPrice.toStringAsFixed(2)} €', style: tw(20, weight: black, color: Tw.amber400)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Tw.slate700, borderRadius: BorderRadius.circular(8)),
                child: Text('Total: ${(drink.price + up.addonPrice).toStringAsFixed(2)} €', style: tw(12, weight: bold)),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          GradientButton(
            label: context.t('kiosk_upsell_accept', fallback: 'SI, HACERLO PREMIUM ✨'),
            fontSize: 13,
            radius: 12,
            padding: const EdgeInsets.symmetric(vertical: 14),
            gradient: const LinearGradient(colors: [Tw.amber400, Tw.yellow500]),
            onTap: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 10),
          Pressable(
            onTap: () => Navigator.of(context).pop(false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(12)),
              child: Text('${context.t('kiosk_upsell_decline', fallback: 'Mantener estandar')} (${drink.price.toStringAsFixed(2)} €)',
                  textAlign: TextAlign.center, style: tw(12, weight: bold, color: Tw.slate400)),
            ),
          ),
        ]),
      ),
    );
  }
}
