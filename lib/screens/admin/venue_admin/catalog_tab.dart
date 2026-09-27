import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

const _categories = [
  ('beer', 'Cerveza', '🍺'),
  ('cocktail', 'Combinado / Copa', '🍸'),
  ('spirit', 'Chupito', '🥃'),
  ('soft_drink', 'Refresco', '🥤'),
  ('water', 'Agua', '💧'),
  ('wine', 'Vino', '🍷'),
  ('pack', 'Pack / Botella', '🍾'),
];

(String, String, String) _category(Object? c) => _categories.where((x) => x.$1 == c).firstOrNull ?? ('$c', '$c', '🍹');

/// Port of components/venue-admin/VenueCatalogTab.tsx (bar menu, `products` collection).
class VenueCatalogTab extends StatefulWidget {
  final String venueId;
  final String? eventId;
  const VenueCatalogTab({super.key, required this.venueId, this.eventId});

  @override
  State<VenueCatalogTab> createState() => _VenueCatalogTabState();
}

class _VenueCatalogTabState extends State<VenueCatalogTab> {
  StreamSubscription? _sub;
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance.collection('products').where('venueId', isEqualTo: widget.venueId).snapshots().listen((s) {
      final items = [for (final d in s.docs) <String, dynamic>{'id': d.id, ...d.data()}]
        ..sort((a, b) => ((a['name'] as String?) ?? '').compareTo((b['name'] as String?) ?? ''));
      setState(() {
        _products = items;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _openEditor([Map<String, dynamic>? product]) {
    showAdminSheet<void>(
      context,
      title: product != null ? 'Editar producto' : 'Nuevo producto',
      builder: (_) => _ProductForm(venueId: widget.venueId, eventId: widget.eventId, product: product),
    );
  }

  Future<void> _toggle(Map<String, dynamic> p) async {
    try {
      await FirebaseFirestore.instance.collection('products').doc(p['id'] as String).update({'active': p['active'] != true, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e, 'Error'), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    if (!await confirmDialog(context, message: '¿Eliminar "${p['name']}"?', danger: true, confirmText: 'Eliminar')) return;
    try {
      await FirebaseFirestore.instance.collection('products').doc(p['id'] as String).delete();
      if (mounted) showToast(context, 'Producto eliminado');
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e, 'Error'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminEmpty('', loading: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Carta de Barra', style: tw(20, weight: black)),
            const SizedBox(height: 4),
            Text('${_products.length} producto${_products.length != 1 ? 's' : ''} · Venta directa con QR', style: tw(12, color: Tw.slate500)),
          ]),
        ),
        AdminButton(icon: Icons.add, label: 'Añadir producto', onTap: _openEditor),
      ]),
      const SizedBox(height: 24),
      if (_products.isEmpty)
        Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
          child: Column(children: [
            const Icon(Icons.liquor, size: 40, color: Tw.slate600),
            const SizedBox(height: 12),
            Text('Aún no tienes productos en la carta', style: tw(14, color: Tw.slate400)),
            const SizedBox(height: 12),
            GestureDetector(onTap: _openEditor, child: Text('Crear el primero', style: tw(12, weight: bold, color: Tw.fuchsia400))),
          ]),
        )
      else
        for (final p in _products) _card(p),
    ]);
  }

  Widget _card(Map<String, dynamic> p) {
    final cat = _category(p['category']);
    final active = p['active'] == true;
    final price = (p['price'] as num?) ?? 0;
    return Opacity(
      opacity: active ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: active ? Tw.w(0.1) : Tw.w(0.05))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cat.$3, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((p['name'] as String?) ?? '', style: tw(14, weight: black)),
                Label(cat.$2, color: Tw.slate500, weight: FontWeight.w400, tracking: 0.05),
              ]),
            ),
            Text('${price.toStringAsFixed(2)}€', style: tw(18, weight: black, color: Tw.fuchsia400)),
          ]),
          if ((p['description'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(p['description'] as String, style: tw(12, color: Tw.slate400, height: 1.6)),
          ],
          if (p['stock'] != null) ...[
            const SizedBox(height: 12),
            Text.rich(TextSpan(style: tw(10, color: Tw.slate500), children: [
              const TextSpan(text: 'Stock: '),
              TextSpan(text: '${p['stock']}', style: tw(10, weight: bold)),
              const TextSpan(text: ' unidades'),
            ])),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: Tw.w(0.05)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: AdminButton(icon: Icons.edit, label: 'Editar', color: Tw.w(0.05), textColor: Tw.slate300, fontSize: 10, expand: true, onTap: () => _openEditor(p))),
            const SizedBox(width: 8),
            Expanded(
              child: AdminButton(
                icon: active ? Icons.visibility : Icons.visibility_off,
                label: active ? 'Activo' : 'Oculto',
                color: active ? Tw.emerald400 : Tw.red400,
                outlined: true,
                fontSize: 10,
                expand: true,
                onTap: () => _toggle(p),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(onPressed: () => _delete(p), icon: const Icon(Icons.delete, size: 16, color: Tw.slate500)),
          ]),
        ]),
      ),
    );
  }
}

class _ProductForm extends StatefulWidget {
  final String venueId;
  final String? eventId;
  final Map<String, dynamic>? product;
  const _ProductForm({required this.venueId, this.eventId, this.product});

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late final _name = TextEditingController(text: (widget.product?['name'] as String?) ?? '');
  late final _price = TextEditingController(text: widget.product?['price'] != null && widget.product!['price'] != 0 ? '${widget.product!['price']}' : '');
  late final _desc = TextEditingController(text: (widget.product?['description'] as String?) ?? '');
  late final _stock = TextEditingController(text: widget.product?['stock'] != null ? '${widget.product!['stock']}' : '');
  late String _category = (widget.product?['category'] as String?) ?? 'beer';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _price, _desc, _stock]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.replaceAll(',', '.')) ?? 0;
    if (_name.text.trim().isEmpty || price == 0) {
      showToast(context, 'Nombre y precio son obligatorios', error: true);
      return;
    }
    setState(() => _saving = true);
    final p = widget.product;
    try {
      final data = {
        'venueId': widget.venueId,
        'eventId': widget.eventId,
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'category': _category,
        'price': price,
        'currency': 'EUR',
        'active': p?['active'] != false,
        'stock': _stock.text.isEmpty ? null : int.tryParse(_stock.text),
        'mixerOptions': p?['mixerOptions'] ?? const [],
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final col = FirebaseFirestore.instance.collection('products');
      if (p != null) {
        await col.doc(p['id'] as String).update(data);
        if (mounted) showToast(context, 'Producto actualizado');
      } else {
        await col.doc().set({...data, 'createdAt': FieldValue.serverTimestamp()});
        if (mounted) showToast(context, 'Producto creado');
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e, 'Error al guardar'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 4, top: 16), child: Label(t, weight: bold));

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('Nombre'),
        AdminInput(controller: _name, hint: 'Ej: Gin-Tonic Premium'),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('Precio (€)'),
              AdminInput(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('Categoría'),
              AdminSelect<String>(
                value: _category,
                items: [for (final c in _categories) (c.$1, '${c.$3} ${c.$2}')],
                onChanged: (v) => setState(() => _category = v ?? 'beer'),
              ),
            ]),
          ),
        ]),
        _label('Descripción (opcional)'),
        AdminInput(controller: _desc, hint: 'Ej: Bombay Sapphire + tónica Fever-Tree'),
        _label('Stock (vacío = ilimitado)'),
        AdminInput(controller: _stock, hint: 'Ilimitado', keyboardType: TextInputType.number),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: AdminButton(
              label: 'Cancelar',
              color: Tw.w(0.05),
              textColor: Tw.slate400,
              expand: true,
              padding: const EdgeInsets.symmetric(vertical: 14),
              onTap: _saving ? null : () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GradientButton(
              label: _saving ? 'Guardando...' : widget.product != null ? 'Guardar' : 'Crear',
              fontSize: 12,
              padding: const EdgeInsets.symmetric(vertical: 14),
              gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]),
              onTap: _saving ? null : _save,
            ),
          ),
        ]),
      ]);
}
