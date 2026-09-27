import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../models/firestore_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/address_autocomplete.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';
import '../../../widgets/location_picker.dart';

const _allDays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// Port of components/venue-admin/VenueConfigTab.tsx
class VenueConfigTab extends StatefulWidget {
  final Map<String, dynamic> venue;
  const VenueConfigTab({super.key, required this.venue});

  @override
  State<VenueConfigTab> createState() => _VenueConfigTabState();
}

class _VenueConfigTabState extends State<VenueConfigTab> {
  late final _name = TextEditingController(text: (widget.venue['name'] as String?) ?? '');
  late final _description = TextEditingController(text: (widget.venue['description'] as String?) ?? '');
  late final _address = TextEditingController(text: (widget.venue['address'] as String?) ?? '');
  late final _externalUrl = TextEditingController(text: (widget.venue['externalTicketUrl'] as String?) ?? '');
  late String _type = (widget.venue['type'] as String?) ?? 'bar';
  late bool _isActive = widget.venue['isActive'] != false;
  late ({double latitude, double longitude})? _location = () {
    final loc = parseLocation(widget.venue);
    return loc == null ? null : (latitude: loc.lat, longitude: loc.lng);
  }();
  late List<String> _openingDays = asStringList(widget.venue['openingDays']);
  late final Map<String, ({String open, String close})> _hours = {
    for (final e in (widget.venue['openingHours'] as Map? ?? const {}).entries)
      if (e.value is Map) '${e.key}': (open: '${(e.value as Map)['open'] ?? '22:00'}', close: '${(e.value as Map)['close'] ?? '06:00'}'),
  };
  bool _saving = false;
  Map<String, dynamic>? _owner;
  int _mapKey = 0;

  @override
  void initState() {
    super.initState();
    final ownerId = widget.venue['ownerId'];
    if (ownerId is String && ownerId.isNotEmpty) {
      FirebaseFirestore.instance.collection('users').doc(ownerId).get().then((s) {
        if (s.exists && mounted) setState(() => _owner = s.data());
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _address, _externalUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleDay(String day) => setState(() {
        if (_openingDays.contains(day)) {
          _openingDays = _openingDays.where((d) => d != day).toList();
          _hours.remove(day);
        } else {
          _hours[day] = _hours[day] ?? (open: '22:00', close: '06:00');
          _openingDays = [..._openingDays, day];
        }
      });

  Future<void> _pickTime(String day, bool open) async {
    final current = open ? _hours[day]!.open : _hours[day]!.close;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 22, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return;
    final v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => _hours[day] = open ? (open: v, close: _hours[day]!.close) : (open: _hours[day]!.open, close: v));
  }

  Future<void> _save() async {
    final i18n = context.read<I18n>();
    setState(() => _saving = true);
    try {
      await callFn('updateVenueConfig', {
        'venueId': widget.venue['id'],
        'fields': {
          'name': _name.text,
          'description': _description.text,
          'address': _address.text,
          'type': _type,
          'externalTicketUrl': _externalUrl.text,
          'isActive': _isActive,
          'openingDays': _openingDays,
          'openingHours': {for (final e in _hours.entries) e.key: {'open': e.value.open, 'close': e.value.close}},
          if (_location != null) 'location': {'latitude': _location!.latitude, 'longitude': _location!.longitude},
        },
      });
      if (mounted) showToast(context, i18n.t('venue_config.save_success'));
    } catch (_) {
      if (mounted) showToast(context, i18n.t('venue_config.save_error'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context, message: i18n.t('venue_config.delete_confirm'), danger: true, confirmText: i18n.t('venue_config.delete_btn'))) return;
    try {
      await callFn('deleteVenue', {'venueId': widget.venue['id']});
      if (mounted) showToast(context, i18n.t('venue_config.delete_success'));
    } catch (_) {
      if (mounted) showToast(context, i18n.t('venue_config.delete_error'), error: true);
    }
  }

  Widget _label(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Label(text, tracking: 0.2, color: Tw.slate500));

  InputDecoration _deco({IconData? icon, String? hint}) => adminInputDecoration(hint).copyWith(
        fillColor: Colors.black.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        prefixIcon: icon == null ? null : Icon(icon, size: 16, color: Tw.slate500),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tw.w(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Tw.fuchsia500)),
      );

  Widget _warn(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Icon(icon, size: 12, color: Tw.amber400),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: tw(10, color: Tw.amber400))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      radius: 32,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Tw.fuchsia500.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.tune, color: Tw.fuchsia400),
          ),
          const SizedBox(width: 12),
          Expanded(child: Label(context.t('admin_b2b.venue_profile'), size: 16, color: Tw.white)),
        ]),
        const SizedBox(height: 16),
        Divider(height: 1, color: Tw.w(0.1)),
        const SizedBox(height: 20),
        _label(context.t('admin_b2b.official_name')),
        TextField(controller: _name, style: tw(14), decoration: _deco(icon: Icons.storefront)),
        const SizedBox(height: 20),
        _label(context.t('admin_b2b.description_bio')),
        TextField(controller: _description, maxLines: 4, style: tw(14), decoration: _deco()),
        const SizedBox(height: 20),
        _label(context.t('admin_b2b.physical_address')),
        AddressAutocomplete(
          controller: _address,
          placeholder: context.t('setup_wizard.venue_address_placeholder', fallback: 'Buscar dirección...'),
          onSelect: (r) => setState(() {
            _address.text = r.address;
            if (r.lat != 0 && r.lng != 0) {
              _location = (latitude: r.lat, longitude: r.lng);
              _mapKey++;
            }
          }),
        ),
        const SizedBox(height: 20),
        _label(context.t('venue_config.map_location', fallback: 'Ubicación en el mapa')),
        Text(
          context.t('venue_config.map_location_hint',
              fallback: 'Haz clic en el mapa para marcar la ubicación de tu local. Sin ubicación, tu local no aparecerá en el radar.'),
          style: tw(10, color: Tw.slate500),
        ),
        const SizedBox(height: 12),
        StorefrontLocationPicker(key: ValueKey(_mapKey), location: _location, onChange: (l) => setState(() => _location = l)),
        if (_location == null)
          _warn(Icons.warning, context.t('venue_config.no_location_warning', fallback: 'Tu local no aparece en el mapa porque no tiene ubicación configurada.')),
        const SizedBox(height: 20),
        _label(context.t('venue_config.opening_schedule', fallback: 'Horario de apertura')),
        Text(
          context.t('venue_config.opening_schedule_hint', fallback: 'Marca los días que abre tu local y configura la hora de apertura y cierre.'),
          style: tw(10, color: Tw.slate500),
        ),
        const SizedBox(height: 12),
        for (final day in _allDays) _dayRow(context, day),
        if (_openingDays.isEmpty)
          _warn(Icons.info, context.t('venue_config.no_schedule_warning', fallback: 'Sin horario configurado. Los usuarios no podrán ver si estás abierto.')),
        const SizedBox(height: 20),
        _label(context.t('venue_config.external_ticket_url')),
        TextField(
          controller: _externalUrl,
          keyboardType: TextInputType.url,
          style: tw(14),
          decoration: _deco(icon: Icons.link, hint: 'https://fourvenues.com/...'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Text(context.t('venue_config.external_ticket_hint'), style: tw(10, color: Tw.slate500)),
        ),
        const SizedBox(height: 20),
        _label(context.t('admin_b2b.venue_type')),
        AdminSelect<String>(
          value: _type,
          items: [for (final t in const ['bar', 'club', 'sauna', 'cruising']) (t, context.t('venue_config.type_$t'))],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(context.t('admin_b2b.visibility')),
            Row(children: [
              Switch(value: _isActive, activeThumbColor: Tw.white, activeTrackColor: Tw.fuchsia600, onChanged: (v) => setState(() => _isActive = v)),
              const SizedBox(width: 8),
              Text(_isActive ? context.t('venue_config.active_on_map') : context.t('venue_config.hidden'),
                  style: tw(14, weight: bold, color: _isActive ? Tw.fuchsia400 : Tw.slate500)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
        GradientButton(
          label: _saving ? context.t('venue_config.saving') : context.t('admin_b2b.save_configuration'),
          icon: _saving ? Icons.sync : Icons.save,
          loading: _saving,
          expand: true,
          padding: const EdgeInsets.symmetric(vertical: 20),
          gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]),
          onTap: _saving ? null : _save,
        ),
        if (_owner != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Tw.indigo500.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.indigo500.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.person, size: 14, color: Tw.indigo400),
                const SizedBox(width: 8),
                Label(context.t('venue_config.owner_data', fallback: 'Datos del Titular'), color: Tw.indigo400, tracking: 0.2),
              ]),
              const SizedBox(height: 12),
              for (final (label, value) in [
                (context.t('venue_config.owner_name', fallback: 'Nombre'), _owner!['nick'] ?? _owner!['displayName']),
                (context.t('venue_config.owner_email', fallback: 'Email'), _owner!['email']),
                (context.t('venue_config.owner_phone', fallback: 'Teléfono'), _owner!['phone']),
              ])
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Label(label, color: Tw.slate500, weight: bold),
                    const SizedBox(height: 4),
                    Text(value is String && value.isNotEmpty ? value : '—', style: tw(14, weight: bold)),
                  ]),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF450A0A).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Tw.red500.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.t('venue_config.danger_title'), style: tw(14, weight: bold, color: Tw.red400)),
            Text(context.t('venue_config.danger_desc'), style: tw(12, color: Tw.slate400)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: AdminButton(label: '🗑️ ${context.t('admin_b2b.delete_point')}', color: Tw.red600, onTap: _delete),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _dayRow(BuildContext context, String day) {
    final active = _openingDays.contains(day);
    final h = _hours[day];
    Widget timeBox(String v, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8), border: Border.all(color: Tw.w(0.1))),
            child: Text(v, style: tw(12)),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? Tw.fuchsia500.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? Tw.fuchsia500.withValues(alpha: 0.2) : Tw.w(0.05)),
      ),
      child: Row(children: [
        Transform.scale(
          scale: 0.8,
          child: Switch(value: active, activeThumbColor: Tw.white, activeTrackColor: Tw.fuchsia600, onChanged: (_) => _toggleDay(day)),
        ),
        SizedBox(
          width: 56,
          child: Label(context.t('venue_config.day_$day', fallback: day[0].toUpperCase() + day.substring(1)),
              size: 12, color: active ? Tw.white : Tw.slate500, tracking: 0.05),
        ),
        const Spacer(),
        if (active && h != null) ...[
          timeBox(h.open, () => _pickTime(day, true)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('—', style: tw(12, color: Tw.slate500))),
          timeBox(h.close, () => _pickTime(day, false)),
        ],
      ]),
    );
  }
}
