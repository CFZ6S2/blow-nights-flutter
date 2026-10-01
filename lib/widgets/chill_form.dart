import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../providers/auth_provider.dart';
import '../providers/city_provider.dart';
import '../services/chills.dart';
import '../theme/app_theme.dart';
import 'common.dart';

const chillTagOptions = ['Previa', 'After', 'Piscina', 'Terraza', 'Fiesta', 'Cena', 'Chill', 'Juegos'];

/// Form shared by app/create-plan/page.tsx ([page] = true) and components/CreateChillModal.tsx.
class ChillForm extends StatefulWidget {
  final bool page;
  final void Function(String chillId) onCreated;
  const ChillForm({super.key, required this.page, required this.onCreated});

  @override
  State<ChillForm> createState() => _ChillFormState();
}

class _ChillFormState extends State<ChillForm> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _address = TextEditingController();
  String _capacity = '10';
  final List<String> _tags = [];
  bool _submitting = false;
  String _error = '';
  ({double lat, double lng})? _gps;
  bool _gpsLoading = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _desc, _address]) {
      c.addListener(() => setState(() {}));
    }
    final p = context.read<AuthProvider>().profile;
    if (p?.lat != null && p?.lng != null) _gps = (lat: p!.lat!, lng: p.lng!);
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _requestGps() async {
    setState(() => _gpsLoading = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
        );
        _gps = (lat: pos.latitude, lng: pos.longitude);
      }
    } catch (_) {}
    if (mounted) setState(() => _gpsLoading = false);
  }

  Future<void> _submit() async {
    final i18n = context.read<I18n>();
    final citySlug = context.read<CityProvider>().citySlug;
    final p = context.read<AuthProvider>().profile;
    final coords = widget.page ? _gps : (p?.lat != null && p?.lng != null ? (lat: p!.lat!, lng: p.lng!) : null);
    String? err;
    if (_title.text.trim().isEmpty) {
      err = i18n.t('chill_modal.err_no_name', fallback: 'Ponle un nombre a tu plan');
    } else if (_address.text.trim().isEmpty) {
      err = i18n.t('chill_modal.err_no_address', fallback: 'Indica la direccion');
    } else if (coords == null) {
      err = widget.page
          ? i18n.t('create_plan.err_no_gps', fallback: 'Necesitamos tu ubicacion para crear el plan')
          : i18n.t('chill_modal.err_no_location');
    }
    if (err != null) {
      setState(() => _error = err!);
      return;
    }
    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      final id = await createChill(
        title: _title.text.trim(),
        description: _desc.text.trim(),
        exactAddress: _address.text.trim(),
        approxLat: coords!.lat,
        approxLng: coords.lng,
        maxCapacity: int.tryParse(_capacity) ?? 10,
        citySlug: citySlug,
        tags: _tags,
      );
      widget.onCreated(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = fnMessage(e, i18n.t('chill_modal.err_create', fallback: 'Error al crear el plan'));
          _submitting = false;
        });
      }
    }
  }

  Widget _label(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Label(text),
          if (trailing != null) ...[const SizedBox(width: 4), trailing],
        ]),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        counterText: '',
        fillColor: Tw.black,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Tw.w(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.fuchsia500)),
      );

  Widget _counter(int n, int max) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('$n/$max', textAlign: TextAlign.right, style: tw(10, color: Tw.slate600)),
      );

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final canSubmit = !_submitting && (!page || _title.text.trim().isNotEmpty);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label(context.t('chill_modal.plan_name', fallback: 'Nombre del plan')),
      TextField(controller: _title, maxLength: 60, style: tw(16), decoration: _dec(context.t('chill_modal.ph_plan_name', fallback: 'Ej: Previa en mi terraza'))),
      if (page) _counter(_title.text.length, 60),
      const SizedBox(height: 20),
      _label(context.t('chill_modal.desc_label', fallback: 'Descripcion')),
      TextField(
        controller: _desc,
        maxLength: 300,
        maxLines: 3,
        style: tw(16),
        decoration: _dec(context.t('chill_modal.ph_desc', fallback: 'Cuenta de que va el plan...')),
      ),
      if (page) _counter(_desc.text.length, 300),
      const SizedBox(height: 20),
      _label(
        context.t('chill_modal.address_label', fallback: 'Direccion'),
        trailing: Text(context.t('chill_modal.address_private', fallback: '(privada)'), style: tw(10, weight: black, color: Tw.fuchsia400)),
      ),
      TextField(controller: _address, style: tw(16), decoration: _dec(context.t('chill_modal.ph_address', fallback: 'Calle, numero, piso...'))),
      const SizedBox(height: 6),
      Row(children: [
        const Icon(Icons.lock, size: 12, color: Tw.slate600),
        const SizedBox(width: 4),
        Expanded(child: Text(context.t('chill_modal.address_hint', fallback: 'Solo visible para aceptados'), style: tw(10, color: Tw.slate600))),
      ]),
      if (page) ...[
        const SizedBox(height: 20),
        _label(context.t('create_plan.location', fallback: 'Ubicacion')),
        _gps != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Tw.emerald500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tw.emerald500.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle, size: 14, color: Tw.emerald400),
                  const SizedBox(width: 8),
                  Text(context.t('create_plan.gps_ok', fallback: 'Ubicacion obtenida'), style: tw(12, weight: bold, color: Tw.emerald400)),
                ]),
              )
            : Pressable(
                onTap: _gpsLoading ? () {} : _requestGps,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(_gpsLoading ? Icons.hourglass_empty : Icons.my_location, size: 16, color: Tw.slate300),
                    const SizedBox(width: 8),
                    Text(
                      _gpsLoading
                          ? context.t('create_plan.getting_gps', fallback: 'Obteniendo...')
                          : context.t('create_plan.get_gps', fallback: 'Obtener ubicacion'),
                      style: tw(14, color: Tw.slate300),
                    ),
                  ]),
                ),
              ),
      ],
      const SizedBox(height: 20),
      _label(context.t('chill_modal.max_capacity', fallback: 'Capacidad maxima')),
      Row(children: [
        for (final n in ['5', '10', '15', '20']) ...[
          Expanded(
            child: Pressable(
              onTap: () => setState(() => _capacity = n),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _capacity == n ? Tw.fuchsia500 : Tw.w(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _capacity == n ? Tw.fuchsia500 : Tw.w(0.05)),
                ),
                child: Text(n, textAlign: TextAlign.center, style: tw(14, weight: black, color: _capacity == n ? Tw.white : Tw.slate400)),
              ),
            ),
          ),
          if (n != '20') const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 20),
      _label(
        context.t('chill_modal.tags_label', fallback: 'Etiquetas'),
        trailing: page ? Text('(max 3)', style: tw(10, weight: black, color: Tw.slate600)) : null,
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final tag in chillTagOptions)
          Pressable(
            onTap: () => setState(() {
              if (_tags.contains(tag)) {
                _tags.remove(tag);
              } else if (_tags.length < 3) {
                _tags.add(tag);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _tags.contains(tag) ? Tw.fuchsia500 : Tw.w(0.05),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: _tags.contains(tag) ? Tw.fuchsia500 : Tw.w(0.05)),
              ),
              child: Text(context.t('tags.${tag.toLowerCase()}', fallback: tag),
                  style: tw(12, weight: bold, color: _tags.contains(tag) ? Tw.white : Tw.slate400)),
            ),
          ),
      ]),
      if (_error.isNotEmpty) ...[
        const SizedBox(height: 20),
        page
            ? Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Tw.red500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.error, size: 14, color: Tw.red400),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error, style: tw(12, color: Tw.red400))),
                ]),
              )
            : Text(_error, textAlign: TextAlign.center, style: tw(12, color: Tw.red400)),
      ],
      const SizedBox(height: 20),
      Pressable(
        onTap: canSubmit ? _submit : () {},
        scale: 0.95,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: canSubmit ? Tw.fuchsia600 : Tw.slate800,
            borderRadius: BorderRadius.circular(16),
            boxShadow: canSubmit ? [BoxShadow(color: Tw.fuchsia600.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: -10)] : null,
          ),
          child: Text(
            _submitting ? context.t('chill_modal.creating', fallback: 'Creando...') : context.t('chill_modal.btn_create', fallback: 'Crear plan'),
            textAlign: TextAlign.center,
            style: tw(18, weight: black, color: canSubmit ? Tw.white : Tw.slate600),
          ),
        ),
      ),
    ]);
  }
}

/// Port of components/CreateChillModal.tsx
Future<String?> showCreateChillModal(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
          decoration: BoxDecoration(
            color: Tw.slate900,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Tw.w(0.1)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SafeArea(
              top: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(ctx.t('chill_modal.title'), style: tw(20, weight: black))),
                  GestureDetector(onTap: () => Navigator.of(ctx).pop(), child: const Icon(Icons.close, color: Tw.slate500)),
                ]),
                const SizedBox(height: 24),
                ChillForm(page: false, onCreated: (id) => Navigator.of(ctx).pop(id)),
              ]),
            ),
          ),
        ),
      ),
    );
