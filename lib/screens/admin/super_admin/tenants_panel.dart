import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../navigation.dart' show webBase;
import '../../../models/firestore_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

Color? hexColor(String? hex) {
  final h = (hex ?? '').replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String colorHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Port of features/super-admin/TenantsPanel.tsx (white-label tenants, live `tenants` collection).
class TenantsPanel extends StatefulWidget {
  const TenantsPanel({super.key});

  @override
  State<TenantsPanel> createState() => _TenantsPanelState();
}

class _TenantsPanelState extends State<TenantsPanel> {
  StreamSubscription? _sub;
  List<Map<String, dynamic>> _tenants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance.collection('tenants').snapshots().listen((s) {
      setState(() {
        _tenants = [for (final d in s.docs) {...d.data(), 'tenantId': d.id}];
        _loading = false;
      });
    }, onError: (e) {
      debugPrint('Error listening to tenants: $e');
      setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _toggle(Map<String, dynamic> t) async {
    final current = t['enabled'] != false && t['isActive'] != false;
    try {
      await FirebaseFirestore.instance.collection('tenants').doc(t['tenantId'] as String).update({
        'enabled': !current,
        'isActive': !current,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) showToast(context, 'Tenant ${t['displayName']} ${!current ? 'activado' : 'desactivado'}.');
    } catch (e) {
      if (mounted) showToast(context, 'Error al actualizar estado: ${errorMessage(e, '')}', error: true);
    }
  }

  Future<void> _delete(String id, String name) async {
    if (!await confirmDialog(context,
        message: '¿Estás seguro de que deseas eliminar la marca blanca "$name" ($id)? Esta acción no se puede deshacer.',
        confirmText: 'Eliminar',
        danger: true)) {
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('tenants').doc(id).delete();
      if (mounted) showToast(context, 'Marca blanca eliminada con éxito.');
    } catch (e) {
      if (mounted) showToast(context, 'Error al eliminar: ${errorMessage(e, '')}', error: true);
    }
  }

  void _openForm({Map<String, dynamic>? tenant, bool demo = false}) {
    showAdminSheet<void>(
      context,
      title: tenant != null ? 'Editar Marca Blanca' : 'Nueva Marca Blanca',
      builder: (_) => _TenantForm(tenant: tenant, demo: demo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminCard(
        color: Tw.slate900.withValues(alpha: 0.6),
        borderColor: Tw.w(0.05),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Icon(Icons.branding_watermark, color: Tw.fuchsia400, size: 24),
            Text('Marcas Blancas (White-Label)', style: tw(20, weight: black)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Tw.fuchsia500.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
              ),
              child: Label('${_tenants.length} ${_tenants.length == 1 ? 'tenant' : 'tenants'}', color: Tw.fuchsia300, tracking: 0.05),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Gestiona la identidad visual, subdominios y dominios personalizados para locales, promotores y Master Partners.',
              style: tw(12, color: Tw.slate400)),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Nueva Marca Blanca',
            icon: Icons.add,
            expand: true,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(vertical: 14),
            gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]),
            onTap: () => _openForm(),
          ),
        ]),
      ),
      const SizedBox(height: 24),
      if (_loading)
        const AdminEmpty('', loading: true)
      else if (_tenants.isEmpty)
        AdminCard(
          padding: const EdgeInsets.all(48),
          color: Tw.slate900.withValues(alpha: 0.4),
          borderColor: Tw.w(0.05),
          child: Column(children: [
            const Icon(Icons.palette, size: 48, color: Tw.slate600),
            const SizedBox(height: 16),
            Text('No hay marcas blancas configuradas', style: tw(16, weight: bold)),
            const SizedBox(height: 4),
            Text('Crea tu primer tenant white-label o usa el botón de prueba para instanciar el tenant test.',
                textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
            const SizedBox(height: 16),
            AdminButton(
              icon: Icons.auto_fix_high,
              label: 'Crear Tenant de Prueba ("test")',
              color: Tw.w(0.1),
              onTap: () => _openForm(demo: true),
            ),
          ]),
        )
      else
        for (final t in _tenants) ...[_card(t), const SizedBox(height: 16)],
    ]);
  }

  Widget _card(Map<String, dynamic> t) {
    final id = t['tenantId'] as String;
    final name = (t['displayName'] as String?) ?? id;
    final theme = t['theme'] is Map ? t['theme'] as Map : const {};
    final colors = theme['colors'] is Map ? theme['colors'] as Map : const {'primary': '#d946ef', 'accent': '#8b5cf6', 'bgDark': '#020617', 'text': '#ffffff'};
    final enabled = t['enabled'] != false;
    final logo = theme['logoUrl'] as String?;
    final domains = asStringList(t['allowedDomains']);
    final primary = hexColor(colors['primary'] as String?) ?? Tw.fuchsia500;

    Widget swatch(String key) => Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: hexColor(colors[key] as String?) ?? Tw.slate800,
            shape: BoxShape.circle,
            border: Border.all(color: Tw.w(0.2)),
          ),
        );

    return AdminCard(
      padding: const EdgeInsets.all(20),
      color: Tw.slate900.withValues(alpha: 0.8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: tw(16, weight: black))),
                const SizedBox(width: 8),
                AdminBadge(enabled ? 'Activo' : 'Inactivo', color: enabled ? Tw.emerald400 : Tw.red400),
              ]),
              const SizedBox(height: 4),
              Text('ID: $id', style: tw(11, color: Tw.fuchsia400.withValues(alpha: 0.8)).copyWith(fontFamily: 'monospace')),
            ]),
          ),
          const SizedBox(width: 12),
          if (logo != null && logo.isNotEmpty)
            Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8), border: Border.all(color: Tw.w(0.1))),
              child: NetImage(logo, fit: BoxFit.contain),
            )
          else
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.2))),
              child: Text(name.length >= 2 ? name.substring(0, 2).toUpperCase() : 'WL', style: tw(14, weight: black)),
            ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.language, size: 12, color: Tw.slate500),
          const SizedBox(width: 6),
          Expanded(
            child: Text((t['hostname'] as String?)?.isNotEmpty == true ? t['hostname'] as String : 'Sin hostname',
                overflow: TextOverflow.ellipsis, style: tw(12, color: Tw.slate300)),
          ),
        ]),
        if (domains.isNotEmpty)
          Row(children: [
            const Icon(Icons.dns, size: 12, color: Tw.slate600),
            const SizedBox(width: 6),
            Expanded(child: Text(domains.join(', '), overflow: TextOverflow.ellipsis, style: tw(11, color: Tw.slate400))),
          ]),
        const SizedBox(height: 12),
        Divider(height: 1, color: Tw.w(0.05)),
        const SizedBox(height: 12),
        Row(children: [
          const Label('Paleta:', color: Tw.slate500, weight: bold, tracking: 0.05),
          const SizedBox(width: 8),
          for (final k in const ['primary', 'accent', 'bgDark', 'text']) swatch(k),
        ]),
        const SizedBox(height: 12),
        Divider(height: 1, color: Tw.w(0.05)),
        const SizedBox(height: 12),
        Row(children: [
          AdminButton(
            icon: Icons.visibility,
            label: 'Ver',
            color: Tw.w(0.05),
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            onTap: () => openInApp('$webBase/?tenant=$id'),
          ),
          const SizedBox(width: 4),
          AdminButton(
            label: enabled ? 'Desactivar' : 'Activar',
            color: enabled ? Tw.amber400 : Tw.emerald400,
            outlined: true,
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            onTap: () => _toggle(t),
          ),
          const Spacer(),
          IconButton(onPressed: () => _openForm(tenant: t), icon: const Icon(Icons.edit, size: 18, color: Tw.slate400)),
          IconButton(onPressed: () => _delete(id, name), icon: const Icon(Icons.delete, size: 18, color: Tw.slate400)),
        ]),
      ]),
    );
  }
}


class _TenantForm extends StatefulWidget {
  final Map<String, dynamic>? tenant;
  final bool demo;
  const _TenantForm({this.tenant, this.demo = false});

  @override
  State<_TenantForm> createState() => _TenantFormState();
}

class _TenantFormState extends State<_TenantForm> {
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _domains = TextEditingController();
  final _logo = TextEditingController();
  final _favicon = TextEditingController(text: '/favicon-32x32.png');
  final _seoTitle = TextEditingController();
  final _seoDesc = TextEditingController();
  final _colors = <String, String>{'primary': '#ff0055', 'accent': '#7c3aed', 'bgDark': '#0b0f19', 'text': '#ffffff'};
  bool _enabled = true;
  bool _saving = false;
  late final bool _editing = widget.tenant != null;

  @override
  void initState() {
    super.initState();
    final t = widget.tenant;
    if (t != null) {
      final theme = t['theme'] is Map ? t['theme'] as Map : const {};
      final c = theme['colors'] is Map ? theme['colors'] as Map : const {};
      final seo = t['seo'] is Map ? t['seo'] as Map : const {};
      _id.text = t['tenantId'] as String;
      _name.text = (t['displayName'] as String?) ?? '';
      _host.text = (t['hostname'] as String?) ?? '';
      _domains.text = asStringList(t['allowedDomains']).join(', ');
      for (final k in _colors.keys.toList()) {
        if (c[k] is String && (c[k] as String).isNotEmpty) _colors[k] = c[k] as String;
      }
      _logo.text = (theme['logoUrl'] as String?) ?? '';
      _favicon.text = (theme['faviconUrl'] as String?) ?? '/favicon-32x32.png';
      _seoTitle.text = (seo['title'] as String?) ?? '';
      _seoDesc.text = (seo['description'] as String?) ?? '';
      _enabled = t['enabled'] != false;
    } else if (widget.demo) {
      _fillDemo();
    }
  }

  void _fillDemo() {
    _id.text = 'test';
    _name.text = 'Garito Amigo VIP';
    _host.text = 'test.blownights.com';
    _domains.text = 'app.garitoamigo.com';
    _colors.addAll({'primary': '#ff0055', 'accent': '#7c3aed', 'bgDark': '#0b0f19', 'text': '#ffffff'});
    _logo.clear();
    _favicon.text = '/favicon-32x32.png';
    _seoTitle.text = 'Garito Amigo VIP - Noches Exclusivas';
    _seoDesc.text = 'Club nocturno exclusivo en tu ciudad.';
    _enabled = true;
    setState(() {});
  }

  Future<void> _save() async {
    final rawId = _id.text.trim().toLowerCase();
    if (rawId.isEmpty) {
      showToast(context, 'El ID de Marca Blanca es obligatorio.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final name = _name.text.trim().isEmpty ? rawId : _name.text.trim();
      await FirebaseFirestore.instance.collection('tenants').doc(rawId).set({
        'tenantId': rawId,
        'displayName': name,
        'hostname': _host.text.trim().toLowerCase(),
        'allowedDomains': _domains.text.split(',').map((d) => d.trim().toLowerCase()).where((d) => d.isNotEmpty).toList(),
        'theme': {
          'colors': Map.of(_colors),
          'logoUrl': _logo.text.trim(),
          'faviconUrl': _favicon.text.trim().isEmpty ? '/favicon-32x32.png' : _favicon.text.trim(),
        },
        'seo': {
          'title': _seoTitle.text.trim().isEmpty ? '${_name.text} | Powered by Blow Nights' : _seoTitle.text.trim(),
          'description': _seoDesc.text.trim(),
          'ogImage': (widget.tenant?['seo'] is Map ? (widget.tenant!['seo'] as Map)['ogImage'] as String? : null) ?? '',
        },
        'enabled': _enabled,
        'isActive': _enabled,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!_editing) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      showToast(context, 'Marca blanca "$name" guardada correctamente.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showToast(context, 'Error al guardar: ${errorMessage(e, '')}', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickColor(String key) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _HsvPicker(initial: hexColor(_colors[key]) ?? Tw.white),
    );
    if (picked != null) setState(() => _colors[key] = colorHex(picked));
  }

  Widget _field(String label, TextEditingController c, {String? hint, bool enabled = true, int lines = 1, ValueChanged<String>? onChanged}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(bottom: 4, top: 12), child: Label(label)),
        TextField(
          controller: c,
          enabled: enabled,
          maxLines: lines,
          onChanged: onChanged,
          style: tw(14, color: enabled ? Tw.white : Tw.slate500),
          decoration: adminInputDecoration(hint),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    const colorLabels = {'primary': 'Primario', 'accent': 'Acento', 'bgDark': 'Fondo Oscuro', 'text': 'Texto'};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!_editing)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Tw.fuchsia950.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Expanded(
              child: Text.rich(TextSpan(style: tw(12, color: const Color(0xFFF5D0FE)), children: [
                const TextSpan(text: '¿Quieres rellenar con datos de prueba predeterminados para el tenant '),
                TextSpan(text: 'test', style: tw(12, weight: bold, color: const Color(0xFFF5D0FE))),
                const TextSpan(text: '?'),
              ])),
            ),
            const SizedBox(width: 8),
            AdminButton(label: 'Rellenar Demo', fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), onTap: _fillDemo),
          ]),
        ),
      _field('Tenant ID (Slug único) *', _id, hint: 'ej: test, garitoamigo', enabled: !_editing, onChanged: (v) {
        final clean = v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
        if (clean != v) {
          _id.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
        }
      }),
      _field('Nombre Público *', _name, hint: 'ej: Garito Amigo VIP'),
      _field('Hostname (Subdominio)', _host, hint: 'ej: test.blownights.com'),
      _field('Dominios Propios (separados por coma)', _domains, hint: 'ej: app.garitoamigo.com, vip.garitoamigo.com'),
      const Padding(padding: EdgeInsets.only(bottom: 8, top: 16), child: Label('Paleta de Colores (Variables CSS)')),
      AdminGrid(children: [
        for (final k in colorLabels.keys)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(colorLabels[k]!, style: tw(10, color: Tw.slate500)),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _pickColor(k),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
                child: Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: hexColor(_colors[k]) ?? Tw.white, borderRadius: BorderRadius.circular(8)),
                  ),
                  const SizedBox(width: 8),
                  Text(_colors[k]!, style: tw(12).copyWith(fontFamily: 'monospace')),
                ]),
              ),
            ),
          ]),
      ]),
      _field('Logo URL (PNG/SVG)', _logo, hint: 'https://...'),
      _field('Favicon URL (ICO/PNG)', _favicon, hint: '/favicon-32x32.png'),
      _field('Título SEO (Pestaña del Navegador)', _seoTitle, hint: 'ej: Garito Amigo VIP - Noches Exclusivas'),
      _field('Descripción SEO', _seoDesc, hint: 'Breve descripción para buscadores...', lines: 2),
      const SizedBox(height: 20),
      Divider(height: 1, color: Tw.w(0.1)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: AdminButton(label: 'Cancelar', color: Tw.w(0.05), textColor: Tw.slate300, expand: true, onTap: () => Navigator.of(context).pop()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GradientButton(
            label: 'Guardar Marca Blanca',
            loading: _saving,
            fontSize: 11,
            padding: const EdgeInsets.symmetric(vertical: 12),
            gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]),
            onTap: _saving ? null : _save,
          ),
        ),
      ]),
    ]);
  }
}

/// Minimal `<input type="color">`: hue / saturation / brightness sliders + hex preview.
class _HsvPicker extends StatefulWidget {
  final Color initial;
  const _HsvPicker({required this.initial});

  @override
  State<_HsvPicker> createState() => _HsvPickerState();
}

class _HsvPickerState extends State<_HsvPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Widget _slider(String label, double value, double max, ValueChanged<double> onChanged) => Row(children: [
        SizedBox(width: 24, child: Text(label, style: tw(12, weight: bold, color: Tw.slate400))),
        Expanded(child: Slider(value: value, max: max, activeColor: _hsv.toColor(), onChanged: onChanged)),
      ]);

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Tw.slate900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Tw.w(0.1))),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(height: 56, decoration: BoxDecoration(color: _hsv.toColor(), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.2)))),
            const SizedBox(height: 8),
            Text(colorHex(_hsv.toColor()), style: tw(14, weight: bold).copyWith(fontFamily: 'monospace')),
            const SizedBox(height: 8),
            _slider('H', _hsv.hue, 360, (v) => setState(() => _hsv = _hsv.withHue(v))),
            _slider('S', _hsv.saturation, 1, (v) => setState(() => _hsv = _hsv.withSaturation(v))),
            _slider('V', _hsv.value, 1, (v) => setState(() => _hsv = _hsv.withValue(v))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: AdminButton(label: 'Cancelar', color: Tw.w(0.05), expand: true, onTap: () => Navigator.of(context).pop())),
              const SizedBox(width: 12),
              Expanded(child: AdminButton(label: 'OK', expand: true, onTap: () => Navigator.of(context).pop(_hsv.toColor()))),
            ]),
          ]),
        ),
      );
}
