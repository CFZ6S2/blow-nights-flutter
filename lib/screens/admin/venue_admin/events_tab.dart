import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../models/firestore_utils.dart';
import '../../../navigation.dart' show webBase;
import '../../../providers/platform_settings.dart' show uuidV4;
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

/// Picks a flyer resized like the web's compressToWebP (max 1200px, quality 0.8) and uploads it to
/// venues/{venueId}/events/{eventId}/flyer.webp; returns the download URL.
Future<String?> pickAndUploadFlyer(String venueId, String eventId, {XFile? file}) async {
  final picked = file ?? await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200, imageQuality: 80);
  if (picked == null) return null;
  final ref = FirebaseStorage.instance.ref('venues/$venueId/events/$eventId/flyer.webp');
  await ref.putData(await picked.readAsBytes(), SettableMetadata(contentType: picked.mimeType ?? 'image/jpeg'));
  return ref.getDownloadURL();
}

/// Port of components/venue-admin/EventsTab.tsx
class VenueEventsTab extends StatefulWidget {
  final Map<String, dynamic> venue;
  const VenueEventsTab({super.key, required this.venue});

  @override
  State<VenueEventsTab> createState() => _VenueEventsTabState();
}

class _Tier {
  final String id;
  final TextEditingController name, price, quota, perks;
  _Tier(this.id, {String name = '', num price = 0, int quota = 0, String perks = ''})
      : name = TextEditingController(text: name),
        price = TextEditingController(text: '$price'),
        quota = TextEditingController(text: '$quota'),
        perks = TextEditingController(text: perks);

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name.text,
        'price': double.tryParse(price.text.replaceAll(',', '.')) ?? 0,
        'quota': int.tryParse(quota.text) ?? 0,
        'sold': 0,
        'perks': perks.text,
      };

  void dispose() {
    for (final c in [name, price, quota, perks]) {
      c.dispose();
    }
  }
}

class _VenueEventsTabState extends State<VenueEventsTab> {
  StreamSubscription? _sub;
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  bool _creating = false;
  bool _connecting = false;

  final _title = TextEditingController();
  DateTime? _start;
  XFile? _flyer;
  List<_Tier> _tiers = [_Tier('tier_general', name: 'Entrada General', price: 0, quota: 100, perks: '1 Copa incluida')];
  bool _saving = false;
  String? _uploadingFor;

  String get _venueId => widget.venue['id'] as String;
  I18n get _i18n => context.read<I18n>();

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('venues/$_venueId/events')
        .orderBy('start_date', descending: true)
        .snapshots()
        .listen((s) => setState(() {
              _events = [for (final d in s.docs) {'id': d.id, ...d.data()}];
              _loading = false;
            }), onError: (_) => setState(() => _loading = false));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _title.dispose();
    for (final t in _tiers) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _connectStripe() async {
    setState(() => _connecting = true);
    try {
      final r1 = await callFn('createStripeConnectAccount', {'venueId': _venueId});
      final r2 = await callFn('createStripeAccountLink', {'accountId': r1['accountId'], 'origin': webBase});
      final url = r2['url'];
      if (url is String) {
        await openInApp(url);
      } else if (mounted) {
        showToast(context, 'No se pudo generar el enlace de Stripe.', error: true);
      }
    } catch (e) {
      if (mounted) showToast(context, 'Error al conectar con Stripe: ${errorMessage(e, '')}', error: true);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _deleteEvent(String id, String title) async {
    if (!await confirmDialog(context,
        message: '¿Deseas eliminar el evento "$title"? Los enlaces asociados dejarán de estar disponibles.', danger: true, confirmText: 'Eliminar evento')) {
      return;
    }
    try {
      await FirebaseFirestore.instance.doc('venues/$_venueId/events/$id').delete();
      if (mounted) showToast(context, 'Evento eliminado con éxito');
    } catch (e) {
      if (mounted) showToast(context, 'Error al eliminar el evento: ${errorMessage(e, '')}', error: true);
    }
  }

  Future<void> _changeFlyer(String eventId) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200, imageQuality: 80);
    if (file == null) return;
    setState(() => _uploadingFor = eventId);
    try {
      final url = await pickAndUploadFlyer(_venueId, eventId, file: file);
      await FirebaseFirestore.instance.doc('venues/$_venueId/events/$eventId').update({'banner_url': url});
      if (mounted) showToast(context, _i18n.t('events_tab.flyer_updated', fallback: 'Flyer actualizado con éxito'));
    } catch (e) {
      if (mounted) {
        showToast(context, _i18n.t('events_tab.flyer_update_error', fallback: 'Error al subir el flyer: ${errorMessage(e, 'Permiso denegado')}'), error: true);
      }
    } finally {
      if (mounted) setState(() => _uploadingFor = null);
    }
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: _start ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start ?? DateTime(now.year, now.month, now.day, 23)),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (time == null) return;
    setState(() => _start = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _create() async {
    if (_title.text.isEmpty || _start == null) {
      showToast(context, _i18n.t('events_tab.title_date_required'));
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await callFn('createVenueEvent', {
        'venueId': _venueId,
        'title': _title.text,
        'startDate': DateFormat("yyyy-MM-dd'T'HH:mm").format(_start!),
        'bannerUrl': '',
        'ticketTiers': [for (final t in _tiers) t.toJson()],
      });
      final eventId = res['eventId'] as String;
      if (_flyer != null) {
        try {
          final url = await pickAndUploadFlyer(_venueId, eventId, file: _flyer);
          await FirebaseFirestore.instance.doc('venues/$_venueId/events/$eventId').update({'banner_url': url});
        } catch (_) {
          if (mounted) {
            showToast(
                context,
                _i18n.t('events_tab.flyer_upload_warning',
                    fallback:
                        'Evento creado, pero no se pudo subir el flyer automáticamente. Puedes subirlo pulsando sobre la tarjeta del evento.'));
          }
        }
      }
      for (final t in _tiers) {
        t.dispose();
      }
      _title.clear();
      setState(() {
        _creating = false;
        _start = null;
        _flyer = null;
        _tiers = [_Tier('tier_general', name: 'Entrada General', price: 15, quota: 100, perks: '1 Copa incluida')];
      });
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('events_tab.create_error'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy(String text, String toastKey) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(context, _i18n.t(toastKey));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return AdminEmpty(context.t('events_tab.loading_events'), loading: true);
    final hasStripe = (widget.venue['stripeAccountId'] as String?)?.isNotEmpty == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!hasStripe)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Tw.amber500.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Tw.amber500.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.account_balance, size: 16, color: Tw.amber400),
              const SizedBox(width: 8),
              Expanded(child: Text('Cobros de entradas de pago (Stripe Connect)', style: tw(14, weight: bold, color: Tw.amber400))),
            ]),
            const SizedBox(height: 6),
            Text('Tu local no tiene vinculada una cuenta de Stripe para transferencias bancarias de entradas de pago.',
                style: tw(12, color: Tw.slate300, height: 1.6)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
              child: Text.rich(TextSpan(style: tw(11, color: Tw.slate300), children: [
                TextSpan(text: '💡 Modo pruebas (0 €): ', style: tw(11, weight: bold, color: Tw.emerald400)),
                const TextSpan(text: 'Crea tramos a '),
                TextSpan(text: '0,00 €', style: tw(11, weight: bold)),
                const TextSpan(text: ' para probar la compra y validación de QR sin comisiones ni cuenta bancaria.'),
              ])),
            ),
            const SizedBox(height: 12),
            AdminButton(
              icon: Icons.credit_card,
              label: _connecting ? 'Conectando...' : 'Conectar Stripe',
              color: Tw.amber500,
              textColor: Tw.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              onTap: _connecting ? null : _connectStripe,
            ),
          ]),
        )
      else
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Tw.emerald500.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Tw.emerald500.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.verified, size: 14, color: Tw.emerald400),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Cuenta de Stripe Connect vinculada para recibir transferencias bancarias de entradas de pago.',
                  style: tw(12, weight: semibold, color: Tw.emerald400)),
            ),
          ]),
        ),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: Text(context.t('admin_b2b.event_management'), style: tw(20, weight: black))),
        AdminButton(
          label: _creating ? context.t('admin_b2b.cancel') : '+ ${context.t('admin_b2b.new_event')}',
          onTap: () => setState(() => _creating = !_creating),
        ),
      ]),
      if (_creating) ...[const SizedBox(height: 24), _createForm(context)],
      const SizedBox(height: 24),
      if (_events.isEmpty && !_creating)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Text(context.t('events_tab.no_events'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
        ),
      for (final e in _events) _eventCard(context, e),
    ]);
  }

  Widget _createForm(BuildContext context) {
    Widget label(String t) => Padding(padding: const EdgeInsets.only(bottom: 4, top: 16), child: Text(t, style: tw(12, weight: bold, color: Tw.slate400)));
    InputDecoration underline(String? hint) => InputDecoration(
          hintText: hint,
          hintStyle: tw(14, color: Tw.slate600),
          isDense: true,
          contentPadding: const EdgeInsets.only(bottom: 4),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Tw.w(0.1))),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Tw.fuchsia500)),
        );

    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('admin_b2b.create_new_event'), style: tw(18, weight: bold)),
        label(context.t('admin_b2b.event_title')),
        AdminInput(controller: _title, hint: 'Ej. Sábado Loco - Winter Edition'),
        label(context.t('admin_b2b.start_date_time')),
        GestureDetector(
          onTap: _pickStart,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
            child: Row(children: [
              Expanded(
                child: Text(_start == null ? 'dd/mm/aaaa --:--' : DateFormat('dd/MM/yyyy HH:mm').format(_start!),
                    style: tw(14, color: _start == null ? Tw.slate500 : Tw.white)),
              ),
              const Icon(Icons.calendar_today, size: 16, color: Tw.slate400),
            ]),
          ),
        ),
        label(context.t('events_tab.flyer_label')),
        Row(children: [
          AdminButton(
            label: 'Elegir archivo',
            onTap: () async {
              final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200, imageQuality: 80);
              if (f != null) setState(() => _flyer = f);
            },
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(_flyer?.name ?? '', overflow: TextOverflow.ellipsis, style: tw(12, color: Tw.slate400))),
        ]),
        if (_flyer != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: FutureBuilder(
              future: _flyer!.readAsBytes(),
              builder: (_, s) => s.hasData
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(s.data!, height: 128, fit: BoxFit.cover)),
                    )
                  : const SizedBox(height: 128),
            ),
          ),
        const SizedBox(height: 16),
        Divider(height: 1, color: Tw.w(0.1)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text(context.t('events_tab.ticket_tiers'), style: tw(15, weight: bold, color: Tw.fuchsia400))),
          GestureDetector(
            onTap: () => setState(() => _tiers = [..._tiers, _Tier('tier_${DateTime.now().millisecondsSinceEpoch}')]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: Tw.fuchsia400)),
              child: Text('+ ${context.t('events_tab.add_btn')}', style: tw(12, color: Tw.fuchsia400)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        for (var i = 0; i < _tiers.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
            child: Stack(children: [
              AdminGrid(children: [
                for (final (key, ctrl, kb, hint) in [
                  ('events_tab.tier_name', _tiers[i].name, TextInputType.text, 'Ej. General'),
                  ('events_tab.tier_price', _tiers[i].price, const TextInputType.numberWithOptions(decimal: true), null),
                  ('events_tab.tier_quota', _tiers[i].quota, TextInputType.number, null),
                  ('events_tab.tier_perks', _tiers[i].perks, TextInputType.text, null),
                ])
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Label(context.t(key), color: Tw.slate500, weight: FontWeight.w400),
                    TextField(controller: ctrl, keyboardType: kb, style: tw(14), decoration: underline(hint)),
                  ]),
              ]),
              if (_tiers.length > 1)
                Positioned(
                  top: -8,
                  right: -8,
                  child: IconButton(
                    onPressed: () => setState(() {
                      _tiers[i].dispose();
                      _tiers = [..._tiers]..removeAt(i);
                    }),
                    icon: const Icon(Icons.close, size: 16, color: Tw.red400),
                  ),
                ),
            ]),
          ),
        const SizedBox(height: 12),
        AdminButton(
          label: _saving ? context.t('events_tab.saving') : context.t('admin_b2b.create_event_and_generate_scanner'),
          expand: true,
          padding: const EdgeInsets.symmetric(vertical: 16),
          onTap: _saving ? null : _create,
        ),
      ]),
    );
  }

  Widget _eventCard(BuildContext context, Map<String, dynamic> e) {
    final id = e['id'] as String;
    final title = (e['title'] as String?) ?? '';
    final banner = e['banner_url'] as String?;
    final tiers = (e['ticket_tiers'] as List? ?? const []).whereType<Map>().toList();
    final soldTiers = tiers.fold<num>(0, (a, t) => a + ((t['sold'] as num?) ?? 0));
    final soldStats = ((e['stats'] as Map?)?['total_sold'] as num?) ?? 0;
    final start = e['start_date'];
    final startText = start is String ? start : (parseDate(start) != null ? DateFormat('dd/MM/yyyy HH:mm').format(parseDate(start)!) : context.t('events_tab.no_date'));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          onTap: _uploadingFor == null ? () => _changeFlyer(id) : null,
          child: Container(
            height: 144,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
            child: Stack(fit: StackFit.expand, children: [
              if (banner != null && banner.isNotEmpty)
                NetImage(banner)
              else
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_photo_alternate, size: 30, color: Tw.fuchsia400),
                  const SizedBox(height: 4),
                  Label('Subir flyer', color: Tw.fuchsia300, weight: bold, tracking: 0.05),
                ]),
              if (_uploadingFor == id)
                Container(
                  color: Colors.black.withValues(alpha: 0.8),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)),
                    const SizedBox(height: 4),
                    Text('Subiendo...', style: tw(9, weight: bold, color: Tw.fuchsia400)),
                  ]),
                )
              else if (banner != null && banner.isNotEmpty)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.file_upload, size: 12, color: Tw.fuchsia400),
                      const SizedBox(width: 4),
                      Label('Cambiar flyer', color: Tw.fuchsia300, weight: bold, tracking: 0.05),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: tw(18, weight: black)),
              Text(startText, style: tw(12, color: Tw.slate400)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${(soldStats > soldTiers ? soldStats : soldTiers).toInt()}', style: tw(24, weight: black, color: Tw.fuchsia400)),
            Label(context.t('admin_b2b.sold_tickets'), size: 9, color: Tw.slate500, weight: FontWeight.w400),
          ]),
          IconButton(onPressed: () => _deleteEvent(id, title), icon: const Icon(Icons.delete_outline, color: Tw.slate500)),
        ]),
        if (tiers.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in tiers)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Tw.w(0.1))),
                child: Text.rich(TextSpan(style: tw(12, weight: semibold, color: Tw.slate300), children: [
                  TextSpan(text: '${(t['name'] as String?)?.isNotEmpty == true ? t['name'] : 'Entrada'}: ', style: tw(12, weight: bold)),
                  TextSpan(
                    text: ((t['price'] as num?) ?? 0) == 0 ? 'GRATIS (0 €)' : '${((t['price'] as num?) ?? 0).toStringAsFixed(2)} €',
                    style: tw(12, weight: bold, color: ((t['price'] as num?) ?? 0) == 0 ? Tw.emerald400 : Tw.fuchsia400),
                  ),
                  TextSpan(text: ' (${((t['quota'] as num?) ?? 0) - ((t['sold'] as num?) ?? 0)} disp.)', style: tw(10, color: Tw.slate500)),
                ])),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        Divider(height: 1, color: Tw.w(0.05)),
        const SizedBox(height: 12),
        _MagicLink(venueId: _venueId, eventId: id, onCopy: _copy),
        const SizedBox(height: 8),
        _linkRow(
          context.t('events_tab.buy_link'),
          '/buy?venue=$_venueId&event=$id',
          Tw.green400,
          Tw.green600,
          Icons.share,
          () => _copy('$webBase/buy?venue=$_venueId&event=$id', 'events_tab.buy_link_copied'),
        ),
        _EventPromoters(venueId: _venueId, eventId: id),
      ]),
    );
  }
}

Widget _linkRow(String label, String path, Color labelColor, Color buttonColor, IconData icon, VoidCallback onTap) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: labelColor.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label(label, color: labelColor, weight: bold),
            const SizedBox(height: 4),
            Text(path, overflow: TextOverflow.ellipsis, style: tw(12, color: Tw.slate400).copyWith(fontFamily: 'monospace')),
          ]),
        ),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: buttonColor, shape: BoxShape.circle),
            child: Icon(icon, color: Tw.white, size: 20),
          ),
        ),
      ]),
    );

class _MagicLink extends StatefulWidget {
  final String venueId, eventId;
  final Future<void> Function(String text, String toastKey) onCopy;
  const _MagicLink({required this.venueId, required this.eventId, required this.onCopy});

  @override
  State<_MagicLink> createState() => _MagicLinkState();
}

class _MagicLinkState extends State<_MagicLink> {
  String? _token;

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.doc('venues/${widget.venueId}/events/${widget.eventId}/private/secrets').get().then((s) {
      if (s.exists && mounted) setState(() => _token = s.data()?['door_access_token'] as String?);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;
    if (token == null) return Text(context.t('events_tab.loading_link'), style: tw(10, color: Tw.slate500));
    return _linkRow(
      context.t('events_tab.door_magic_link'),
      '/door/${widget.venueId}/${widget.eventId}?token=${token.length > 8 ? token.substring(0, 8) : token}...',
      Tw.fuchsia400,
      Tw.fuchsia600,
      Icons.content_copy,
      () => widget.onCopy('$webBase/door?venue=${widget.venueId}&event=${widget.eventId}&token=$token', 'events_tab.link_copied'),
    );
  }
}

class _EventPromoters extends StatefulWidget {
  final String venueId, eventId;
  const _EventPromoters({required this.venueId, required this.eventId});

  @override
  State<_EventPromoters> createState() => _EventPromotersState();
}

class _EventPromotersState extends State<_EventPromoters> {
  StreamSubscription? _sub;
  List<Map<String, dynamic>> _promoters = [];
  bool _loading = true;
  final _name = TextEditingController();

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('venues/${widget.venueId}/events/${widget.eventId}/promoters');

  @override
  void initState() {
    super.initState();
    _sub = _col.snapshots().listen((s) => setState(() {
          _promoters = [for (final d in s.docs) {'id': d.id, ...d.data()}];
          _loading = false;
        }), onError: (_) => setState(() => _loading = false));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _error() => showToast(context, context.read<I18n>().t('events_tab.action_error'), error: true);

  Future<void> _add() async {
    final name = _name.text;
    if (name.trim().isEmpty) return;
    final token = uuidV4().replaceAll('-', '') + DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    try {
      await _col.doc().set({
        'name': name,
        'code': name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
        'access_token': token,
        'is_closed': false,
        'liquidated_by_venue': false,
        'liquidated_by_rrpp': false,
        'created_at': Timestamp.now(),
      });
      _name.clear();
    } catch (_) {
      _error();
    }
  }

  Future<void> _close(String id) async {
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context, message: i18n.t('events_tab.confirm_close_rrpp'), danger: true, confirmText: i18n.t('events_tab.close_btn'))) return;
    try {
      await _col.doc(id).set({'is_closed': true, 'closed_at': Timestamp.now()}, SetOptions(merge: true));
    } catch (_) {
      _error();
    }
  }

  Future<void> _liquidate(String id, bool current) async {
    try {
      await _col.doc(id).set({'liquidated_by_venue': !current, 'liquidated_at': Timestamp.now()}, SetOptions(merge: true));
    } catch (_) {
      _error();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _promoters.where((p) => !(p['liquidated_by_rrpp'] == true && p['liquidated_by_venue'] == true)).toList();
    Widget status(bool done, String label, String doneText, String pendingText) => Row(children: [
          Icon(done ? Icons.check_circle : Icons.pending, size: 10, color: done ? Tw.green400 : Tw.slate500),
          const SizedBox(width: 4),
          Text('$label: ${done ? doneText : pendingText}', style: tw(10, color: done ? Tw.green400 : Tw.slate500)),
        ]);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Divider(height: 1, color: Tw.w(0.05)),
        const SizedBox(height: 16),
        Text(context.t('events_tab.rrpp_team'), style: tw(14, weight: bold, color: Tw.fuchsia400)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _name,
              style: tw(14),
              decoration: adminInputDecoration(context.t('events_tab.new_rrpp_placeholder')).copyWith(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                fillColor: Colors.black.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AdminButton(label: context.t('events_tab.add_btn'), onTap: _add),
        ]),
        const SizedBox(height: 12),
        if (_loading)
          Text(context.t('events_tab.loading'), style: tw(12, color: Tw.slate500))
        else if (_promoters.isEmpty)
          Text(context.t('events_tab.no_rrpp'), style: tw(12, color: Tw.slate500))
        else
          for (final p in visible)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: p['is_closed'] == true ? 0.4 : 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p['is_closed'] == true ? Tw.yellow500.withValues(alpha: 0.2) : Tw.w(0.1)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text((p['name'] as String?) ?? '', style: tw(14, weight: bold))),
                      if (p['is_closed'] == true) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Tw.yellow500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                          child: Text(context.t('events_tab.closed'), style: tw(10, color: Tw.yellow400)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    if (p['is_closed'] != true)
                      GestureDetector(
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(
                              text: '$webBase/pr?token=${p['access_token']}&event=${widget.eventId}&venue=${widget.venueId}'));
                          if (context.mounted) showToast(context, context.read<I18n>().t('events_tab.rrpp_link_copied'));
                        },
                        child: Row(children: [
                          const Icon(Icons.link, size: 12, color: Tw.fuchsia400),
                          const SizedBox(width: 4),
                          Text(context.t('events_tab.copy_link'), style: tw(10, color: Tw.fuchsia400)),
                        ]),
                      )
                    else ...[
                      status(p['liquidated_by_venue'] == true, context.t('events_tab.venue_settled'), context.t('events_tab.settled'), context.t('events_tab.pending')),
                      status(p['liquidated_by_rrpp'] == true, context.t('events_tab.rrpp_confirmed'), context.t('events_tab.confirmed'), context.t('events_tab.pending')),
                    ],
                  ]),
                ),
                if (p['is_closed'] != true)
                  AdminButton(
                    label: context.t('events_tab.close_list'),
                    color: Tw.yellow500,
                    outlined: true,
                    fontSize: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    onTap: () => _close(p['id'] as String),
                  )
                else
                  AdminButton(
                    label: p['liquidated_by_venue'] == true ? context.t('events_tab.cancel_payment') : context.t('events_tab.mark_paid'),
                    color: p['liquidated_by_venue'] == true ? Tw.red400 : Tw.green400,
                    outlined: true,
                    fontSize: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    onTap: () => _liquidate(p['id'] as String, p['liquidated_by_venue'] == true),
                  ),
              ]),
            ),
      ]),
    );
  }
}
