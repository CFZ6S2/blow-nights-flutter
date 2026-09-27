import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../../models/firestore_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

const _dayLabels = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];

class _Grant {
  final TextEditingController id, name, qty;
  _Grant({String id = '', String name = '', int qty = 1})
      : id = TextEditingController(text: id),
        name = TextEditingController(text: name),
        qty = TextEditingController(text: '$qty');
  void dispose() {
    id.dispose();
    name.dispose();
    qty.dispose();
  }
}

/// Port of components/venue-admin/BenefitRulesTab.tsx (door courtesy rules via callables).
class BenefitRulesTab extends StatefulWidget {
  final String venueId;
  const BenefitRulesTab({super.key, required this.venueId});

  @override
  State<BenefitRulesTab> createState() => _BenefitRulesTabState();
}

class _BenefitRulesTabState extends State<BenefitRulesTab> {
  List<Map<String, dynamic>> _rules = [];
  bool _loading = true;
  bool _showForm = false;
  Map<String, dynamic>? _editing;
  bool _saving = false;

  final _name = TextEditingController();
  final _types = TextEditingController();
  String? _before;
  String? _after;
  List<int>? _days;
  List<_Grant> _grants = [_Grant()];
  final _grace = TextEditingController(text: '60');
  String _stacking = 'exclusive';
  final _priority = TextEditingController(text: '0');
  Map<String, dynamic> _extra = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _types, _grace, _priority]) {
      c.dispose();
    }
    for (final g in _grants) {
      g.dispose();
    }
    super.dispose();
  }

  void _toast(String m, {bool error = false}) {
    if (mounted) showToast(context, m, error: error);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await callFn('listBenefitRules', {'venueId': widget.venueId});
      final list = res['rules'];
      setState(() => _rules = list is List ? [for (final r in list) Map<String, dynamic>.from(r as Map)] : []);
    } catch (e) {
      _toast(errorMessage(e, 'Error al cargar reglas'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open([Map<String, dynamic>? rule]) {
    for (final g in _grants) {
      g.dispose();
    }
    setState(() {
      _editing = rule;
      _name.text = (rule?['name'] as String?) ?? '';
      _types.text = asStringList(rule?['ticketTypes']).join(', ');
      _before = rule?['checkInBefore'] as String?;
      _after = rule?['checkInAfter'] as String?;
      final days = rule?['daysOfWeek'];
      _days = days is List && days.isNotEmpty ? days.whereType<num>().map((d) => d.toInt()).toList() : null;
      final grants = (rule?['grants'] as List? ?? const []).whereType<Map>().toList();
      _grants = grants.isEmpty
          ? [_Grant()]
          : [for (final g in grants) _Grant(id: '${g['productId'] ?? ''}', name: '${g['productName'] ?? ''}', qty: (g['quantity'] as num?)?.toInt() ?? 1)];
      _grace.text = '${rule?['gracePeriodSeconds'] ?? 60}';
      _stacking = (rule?['stackingPolicy'] as String?) ?? 'exclusive';
      _priority.text = '${rule?['priority'] ?? 0}';
      // Fields the form doesn't edit but sends back unchanged (description, expiration, active).
      _extra = {
        'description': (rule?['description'] as String?) ?? '',
        'expirationMode': (rule?['expirationMode'] as String?) ?? 'event_end',
        'expirationFixedTime': rule?['expirationFixedTime'],
        'active': rule == null ? true : rule['active'] == true,
      };
      _showForm = true;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return _toast('El nombre es obligatorio', error: true);
    final types = _types.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (types.isEmpty) return _toast('Añade al menos un tipo de entrada', error: true);
    final grants = [
      for (final g in _grants)
        if (g.id.text.trim().isNotEmpty) {'productId': g.id.text, 'productName': g.name.text, 'quantity': int.tryParse(g.qty.text) ?? 1},
    ];
    if (grants.isEmpty) return _toast('Añade al menos un producto de cortesía', error: true);

    setState(() => _saving = true);
    try {
      final payload = {
        'name': _name.text,
        ..._extra,
        'ticketTypes': types,
        'checkInBefore': _before,
        'checkInAfter': _after,
        'daysOfWeek': _days,
        'grants': grants,
        'gracePeriodSeconds': int.tryParse(_grace.text) ?? 0,
        'stackingPolicy': _stacking,
        'priority': int.tryParse(_priority.text) ?? 0,
        'venueId': widget.venueId,
      };
      if (_editing != null) {
        await callFn('updateBenefitRule', {'ruleId': _editing!['id'], ...payload});
        _toast('Regla actualizada');
      } else {
        await callFn('createBenefitRule', payload);
        _toast('Regla creada');
      }
      setState(() => _showForm = false);
      _load();
    } catch (e) {
      _toast(errorMessage(e, 'Error al guardar'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id) async {
    if (!await confirmDialog(context, message: '¿Eliminar esta regla de beneficio?', danger: true, confirmText: 'Eliminar')) return;
    try {
      await callFn('deleteBenefitRule', {'ruleId': id});
      _toast('Regla eliminada');
      _load();
    } catch (e) {
      _toast(errorMessage(e, 'Error al eliminar'), error: true);
    }
  }

  Future<void> _toggle(Map<String, dynamic> r) async {
    try {
      await callFn('updateBenefitRule', {'ruleId': r['id'], 'active': r['active'] != true});
      _toast(r['active'] == true ? 'Regla desactivada' : 'Regla activada');
      _load();
    } catch (e) {
      _toast(errorMessage(e, 'Error'), error: true);
    }
  }

  Future<void> _pickTime(bool before) async {
    final current = before ? _before : _after;
    final parts = (current ?? '00:00').split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts.last) ?? 0),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => before ? _before = v : _after = v);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminEmpty('', loading: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('benefit_rules_title', fallback: 'Reglas de Cortesías en Puerta'), style: tw(18, weight: black)),
            const SizedBox(height: 4),
            Text(context.t('benefit_rules_subtitle', fallback: 'Consumiciones automáticas por tipo de entrada y hora de check-in'),
                style: tw(12, color: Tw.slate500)),
          ]),
        ),
        AdminButton(label: '+ ${context.t('benefit_rules_new', fallback: 'Nueva Regla')}', color: Tw.yellow400, textColor: Tw.black, onTap: _open),
      ]),
      const SizedBox(height: 24),
      if (_rules.isEmpty && !_showForm)
        AdminCard(
          radius: 16,
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Column(children: [
            const Icon(Icons.card_giftcard, size: 40, color: Tw.slate600),
            const SizedBox(height: 12),
            Text(context.t('benefit_rules_empty', fallback: 'No hay reglas de cortesía configuradas.'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
            const SizedBox(height: 4),
            Text(context.t('benefit_rules_empty_hint', fallback: 'Crea una regla para otorgar consumiciones automáticas al hacer check-in.'),
                textAlign: TextAlign.center, style: tw(12, color: Tw.slate600)),
          ]),
        ),
      for (final r in _rules) _ruleCard(r),
      if (_showForm) ...[const SizedBox(height: 12), _form(context)],
    ]);
  }

  Widget _ruleCard(Map<String, dynamic> r) {
    final grants = (r['grants'] as List? ?? const []).whereType<Map>();
    return Opacity(
      opacity: r['active'] == true ? 1 : 0.4,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text((r['name'] as String?) ?? '', style: tw(14, weight: semibold))),
            if (r['stackingPolicy'] == 'additive') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Tw.blue500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                child: Text('Aditiva', style: tw(9, color: Tw.blue400)),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          Text(asStringList(r['ticketTypes']).join(', '), style: tw(12, color: Tw.slate400)),
          Text.rich(TextSpan(style: tw(12, color: Tw.slate400), children: [
            if (r['checkInBefore'] != null) ...[const TextSpan(text: 'Antes de '), TextSpan(text: '${r['checkInBefore']} ', style: tw(12, color: Tw.yellow400))],
            if (r['checkInAfter'] != null) ...[const TextSpan(text: 'Después de '), TextSpan(text: '${r['checkInAfter']}', style: tw(12, color: Tw.yellow400))],
            if (r['checkInBefore'] == null && r['checkInAfter'] == null) TextSpan(text: 'Sin límite', style: tw(12, color: Tw.slate600)),
            TextSpan(text: ' · ${r['gracePeriodSeconds'] ?? 0}s', style: tw(12, color: Tw.slate500)),
          ])),
          const SizedBox(height: 6),
          for (final g in grants) Text('${g['quantity']} × ${(g['productName'] as String?)?.isNotEmpty == true ? g['productName'] : g['productId']}', style: tw(12)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => _toggle(r), child: Text(r['active'] == true ? 'Desactivar' : 'Activar', style: tw(12, color: Tw.slate400))),
            TextButton(onPressed: () => _open(r), child: Text('Editar', style: tw(12, color: Tw.blue400))),
            TextButton(onPressed: () => _delete(r['id'] as String), child: Text('Eliminar', style: tw(12, color: Tw.red400))),
          ]),
        ]),
      ),
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 4, top: 16), child: Label(t, color: Tw.slate500, weight: FontWeight.w400, tracking: 0.05));

  Widget _timeField(String? value, VoidCallback onTap, VoidCallback onClear) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
          child: Row(children: [
            Expanded(child: Text(value ?? '--:--', style: tw(14, color: value == null ? Tw.slate500 : Tw.white))),
            if (value != null) GestureDetector(onTap: onClear, child: const Icon(Icons.close, size: 14, color: Tw.slate500)),
          ]),
        ),
      );

  Widget _form(BuildContext context) => AdminCard(
        radius: 16,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Label(_editing != null ? 'Editar Regla' : 'Nueva Regla de Cortesía', size: 13, tracking: 0.05)),
            IconButton(onPressed: () => setState(() => _showForm = false), icon: const Icon(Icons.close, color: Tw.slate500)),
          ]),
          _label('Nombre de la regla'),
          AdminInput(controller: _name, hint: 'Ej: Early Bird Copa Gratis'),
          _label('Tipos de entrada (separados por coma, * = todos)'),
          AdminInput(controller: _types, hint: 'Early Bird, VIP, General'),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label('Check-in antes de'),
                _timeField(_before, () => _pickTime(true), () => setState(() => _before = null)),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label('Check-in después de'),
                _timeField(_after, () => _pickTime(false), () => setState(() => _after = null)),
              ]),
            ),
          ]),
          _label('Días activos (vacío = todos)'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var d = 0; d < 7; d++)
              GestureDetector(
                onTap: () => setState(() {
                  final cur = _days ?? [];
                  final next = cur.contains(d) ? cur.where((x) => x != d).toList() : [...cur, d];
                  _days = next.isEmpty ? null : next;
                }),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _days?.contains(d) == true ? Tw.fuchsia600 : Tw.w(0.05), borderRadius: BorderRadius.circular(8)),
                  child: Text(_dayLabels[d], style: tw(12, weight: bold, color: _days?.contains(d) == true ? Tw.white : Tw.slate500)),
                ),
              ),
          ]),
          _label('Productos de cortesía'),
          for (var i = 0; i < _grants.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: TextField(controller: _grants[i].id, style: tw(12), decoration: adminInputDecoration('ID del producto'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _grants[i].name, style: tw(12), decoration: adminInputDecoration('Nombre del producto'))),
                const SizedBox(width: 8),
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _grants[i].qty,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: tw(12),
                    decoration: adminInputDecoration(null),
                  ),
                ),
                if (_grants.length > 1)
                  IconButton(
                    onPressed: () => setState(() {
                      _grants[i].dispose();
                      _grants = [..._grants]..removeAt(i);
                    }),
                    icon: const Icon(Icons.close, size: 16, color: Tw.red400),
                  ),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => setState(() => _grants = [..._grants, _Grant()]),
              child: Text('+ Añadir producto', style: tw(12, color: Tw.fuchsia400)),
            ),
          ),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label('Tolerancia (segundos)'),
                AdminInput(controller: _grace, keyboardType: TextInputType.number),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label('Acumulación'),
                AdminSelect<String>(
                  value: _stacking,
                  items: const [('exclusive', 'Exclusiva (solo la de mayor prioridad)'), ('additive', 'Aditiva (todas las que coincidan)')],
                  onChanged: (v) => setState(() => _stacking = v ?? 'exclusive'),
                ),
              ]),
            ),
          ]),
          _label('Prioridad (mayor = preferencia)'),
          SizedBox(width: 128, child: AdminInput(controller: _priority, keyboardType: TextInputType.number)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => setState(() => _showForm = false), child: Text('Cancelar', style: tw(14, color: Tw.slate400))),
            const SizedBox(width: 8),
            AdminButton(
              label: _saving ? 'Guardando...' : _editing != null ? 'Guardar Cambios' : 'Crear Regla',
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              onTap: _saving ? null : _save,
            ),
          ]),
        ]),
      );
}
