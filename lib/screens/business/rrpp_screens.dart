import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/address_autocomplete.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';

/// Independent RRPP, as the web's features/rrpp: sign-up from the business access, the RRPP panel (QR packs, own
/// events, passes with a link for each guest, door link) and saved door links for scanners.

// Pack sizes createRRPPQRPackageCheckout accepts, at 0,50 € each.
const _packs = [25, 50, 100, 250];
const _otherCity = '__other__';

String rrppDoorUrl(String venueId, String eventId, String token) =>
    '$webBase/door?venue=${Uri.encodeComponent(venueId)}&event=${Uri.encodeComponent(eventId)}&token=${Uri.encodeComponent(token)}';

void _whatsapp(String text) => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, context.read<I18n>().t('rrpp_copied', fallback: 'Copiado'));
}

InputDecoration _field(String hint) => adminInputDecoration(hint, focus: Tw.emerald500).copyWith(fillColor: Colors.black.withValues(alpha: 0.6));

// ─────────────────────────────────────────────────────────────────────────────
/// Sign-up (business login, "Soy RRPP independiente"): granted at once by submitRRPPApplication, then the panel.
class RRPPSignupForm extends StatefulWidget {
  final VoidCallback onBack;
  const RRPPSignupForm({super.key, required this.onBack});

  @override
  State<RRPPSignupForm> createState() => _RRPPSignupFormState();
}

class _RRPPSignupFormState extends State<RRPPSignupForm> {
  final _nick = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _otherCityName = TextEditingController();
  List<(String, String)> _cities = [];
  String _cityId = '';
  bool _accepted = false;
  bool _loading = false;
  String _error = '';

  I18n get _i18n => context.read<I18n>();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _email.text = auth.user?.email ?? '';
    _nick.text = (auth.profile?.data['nick'] as String?) ?? auth.user?.displayName ?? '';
    FirebaseFirestore.instance.collection('cities').where('isActive', isEqualTo: true).get().then((s) {
      if (!mounted) return;
      setState(() => _cities = [for (final d in s.docs) (d.id, (d.data()['name'] as String?) ?? d.id)]..sort((a, b) => a.$2.compareTo(b.$2)));
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_nick, _email, _password, _phone, _otherCityName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final city = _cityId == _otherCity ? _otherCityName.text.trim() : _cities.where((c) => c.$1 == _cityId).map((c) => c.$2).firstOrNull ?? '';
    if (city.isEmpty) return setState(() => _error = _i18n.t('rrpp_signup_city_required', fallback: 'Indica tu ciudad.'));
    if (!_accepted) return setState(() => _error = _i18n.t('rrpp_signup_accept_required', fallback: 'Acepta cómo funciona el cobro para continuar.'));
    if (auth.user == null && _password.text.length < 6) {
      return setState(() => _error = _i18n.t('business_login_password_too_short', fallback: 'La contraseña debe tener al menos 6 caracteres'));
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      var user = auth.user;
      if (user == null) {
        try {
          final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
          await cred.user!.updateDisplayName(_nick.text.trim());
          user = cred.user!;
        } on FirebaseAuthException catch (e) {
          if (e.code != 'email-already-in-use') rethrow;
          user = (await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text)).user!;
        }
      }
      await callFn('submitRRPPApplication', {
        'nick': _nick.text.trim(),
        'email': user.email ?? _email.text.trim(),
        'phone': _phone.text.trim(),
        'city': city,
        if (_cityId.isNotEmpty && _cityId != _otherCity) 'cityId': _cityId,
      });
      // The RRPP role is a claim: refresh the token so the panel sees it without signing in again.
      await auth.refreshToken();
      if (mounted) openRoute(context, AppRoute.pr, replace: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is FirebaseAuthException && (e.code == 'wrong-password' || e.code == 'invalid-credential')
              ? _i18n.t('business_login_email_exists_title', fallback: 'Ya existe una cuenta con este email.')
              : errorMessage(e, _i18n.t('business_login_apply_error', fallback: 'Error al procesar el registro. Inténtalo de nuevo.'));
        });
      }
    }
  }

  Widget _input(String label, TextEditingController c, {String? hint, TextInputType? type, bool obscure = false, bool enabled = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(label, size: 10, weight: black, color: Tw.slate500, tracking: 0.2),
          const SizedBox(height: 6),
          TextField(controller: c, enabled: enabled, keyboardType: type, obscureText: obscure, style: tw(14), decoration: adminInputDecoration(hint, focus: Tw.emerald500)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: widget.onBack,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.arrow_back, size: 16, color: Tw.slate500),
              const SizedBox(width: 8),
              Label(context.t('business_login_back', fallback: 'Volver'), size: 12, weight: bold, color: Tw.slate500, tracking: 0.05),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Tw.emerald600.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.emerald500.withValues(alpha: 0.2))),
          child: Row(children: [
            const Icon(Icons.confirmation_number, color: Tw.emerald400),
            const SizedBox(width: 12),
            Expanded(child: Label(context.t('business_login_become_rrpp', fallback: 'Soy RRPP independiente'), size: 13, weight: black, color: const Color(0xFF6EE7B7), tracking: 0.05)),
          ]),
        ),
        const SizedBox(height: 16),
        for (final (k, f) in const [
          ('rrpp_signup_point_packs', 'Compras packs de QR a 0,50 € por pase para tus eventos, estén o no en un local de la app.'),
          ('rrpp_signup_point_outside', 'A tus invitados les cobras tú, por fuera de la app. Desde la app no se cobra nada.'),
          ('rrpp_signup_point_venue', 'Si quieres vender entradas desde la app, da de alta tu local o pide al local que te añada a su equipo de RRPP.'),
          ('rrpp_signup_point_welcome', 'Empiezas con 25 QR de regalo.'),
        ])
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• ${context.t(k, fallback: f)}', style: tw(12, color: Tw.slate300, height: 1.5))),
        const SizedBox(height: 16),
        if (user == null) ...[
          AdminButton(
            label: context.t('business_login_continue_with_google', fallback: 'Continuar con Google'),
            color: Tw.white,
            textColor: Tw.slate900,
            expand: true,
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: _loading ? null : () => context.read<AuthProvider>().loginWithGoogle().catchError((_) {}),
          ),
          const SizedBox(height: 12),
          Center(child: Label(context.t('business_login_or_fill_form', fallback: 'o completa el formulario'), color: Tw.slate600)),
          const SizedBox(height: 12),
        ],
        if (_error.isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error, textAlign: TextAlign.center, style: tw(12, weight: bold, color: Tw.red400))),
        _input(context.t('rrpp_signup_nick', fallback: 'Nombre artístico'), _nick, hint: context.t('rrpp_signup_nick_placeholder', fallback: 'Cómo te conocen en la noche')),
        _input(context.t('business_login_contact_email', fallback: 'Email de Contacto'), _email, hint: 'tu@email.com', type: TextInputType.emailAddress, enabled: user == null),
        if (user == null) _input(context.t('business_login_create_password', fallback: 'Crear Contraseña'), _password, hint: '••••••••', obscure: true),
        _input(context.t('business_login_phone', fallback: 'Teléfono'), _phone, hint: '+34 600 000 000', type: TextInputType.phone),
        Label(context.t('rrpp_signup_city', fallback: 'Tu ciudad'), size: 10, weight: black, color: Tw.slate500, tracking: 0.2),
        const SizedBox(height: 6),
        AdminSelect<String>(
          value: _cityId.isEmpty ? null : _cityId,
          hint: context.t('business_login_select_city', fallback: 'Selecciona una ciudad'),
          items: [..._cities, (_otherCity, context.t('business_login_other_city', fallback: 'Otra ciudad / Aún no listada'))],
          onChanged: (v) => setState(() => _cityId = v ?? ''),
        ),
        if (_cityId == _otherCity) ...[
          const SizedBox(height: 8),
          TextField(controller: _otherCityName, style: tw(14), decoration: adminInputDecoration(context.t('rrpp_signup_city_placeholder', fallback: 'Escribe tu ciudad'), focus: Tw.emerald500)),
        ],
        const SizedBox(height: 14),
        CheckboxListTile(
          value: _accepted,
          onChanged: (v) => setState(() => _accepted = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: Tw.emerald500,
          title: Text(
            context.t('rrpp_signup_accept', fallback: 'Entiendo que desde la app no se cobra: cobro yo a mis invitados, y para vender entradas en la app tengo que dar de alta un local.'),
            style: tw(12, color: Tw.slate300, height: 1.5),
          ),
        ),
        const SizedBox(height: 8),
        AdminButton(
          label: _loading ? context.t('business_login_processing', fallback: 'Procesando...') : context.t('rrpp_signup_submit', fallback: 'Crear mi cuenta de RRPP'),
          color: Tw.emerald500,
          textColor: Tw.slate950,
          expand: true,
          loading: _loading,
          padding: const EdgeInsets.symmetric(vertical: 16),
          onTap: _loading ? null : _submit,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// The RRPP panel: QR balance and packs, its events, passes with a link for each guest and the door link.
/// Nothing is charged through the app.
class RRPPPanel extends StatefulWidget {
  final bool success;
  const RRPPPanel({super.key, this.success = false});

  @override
  State<RRPPPanel> createState() => _RRPPPanelState();
}

class _RRPPPanelState extends State<RRPPPanel> {
  int? _quota;
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _passes = [];
  String _selected = '';
  bool _creating = false;
  String _error = '';
  String _notice = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await callFn('getRRPPWallet');
      if (!mounted) return;
      setState(() {
        _quota = (res['quota'] as num?)?.toInt() ?? 0;
        _events = [for (final e in (res['events'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
        _passes = [for (final t in (res['tickets'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, context.read<I18n>().t('rrpp_panel_load_error', fallback: 'No se pudo cargar tu panel.')));
    }
  }

  Future<void> _buy() async {
    final qty = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Tw.slate900,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t('rrpp_panel_buy_title', fallback: 'Comprar QR'), style: tw(18, weight: black)),
            const SizedBox(height: 4),
            Text(ctx.t('rrpp_panel_buy_desc', fallback: '0,50 € por QR. Cada QR es un pase para un invitado.'), style: tw(12, color: Tw.slate400)),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final q in _packs)
                Pressable(
                  onTap: () => Navigator.of(ctx).pop(q),
                  child: Container(
                    width: 130,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
                    child: Column(children: [
                      Text('$q', style: tw(20, weight: black)),
                      Text('${(q * 0.5).toStringAsFixed(2).replaceAll('.', ',')} €', style: tw(12, weight: bold, color: Tw.emerald400)),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (qty == null) return;
    try {
      final res = await callFn('createRRPPQRPackageCheckout', {'quantity': qty, 'origin': webBase});
      if (res['url'] is String) await openInApp(res['url'] as String);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, context.read<I18n>().t('rrpp_panel_buy_error', fallback: 'No se pudo iniciar el pago.')));
    }
  }

  Widget _box(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
        child: child,
      );

  Widget _banner(String text, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Text(text, style: tw(12, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final event = _events.where((e) => e['eventId'] == _selected).firstOrNull;
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(8, top + 8, 16, 8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), border: Border(bottom: BorderSide(color: Tw.w(0.1)))),
          child: Row(children: [
            IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            const Icon(Icons.confirmation_number, color: Tw.emerald400),
            const SizedBox(width: 8),
            Expanded(child: Text(context.t('rrpp_panel_title', fallback: 'RRPP independiente'), overflow: TextOverflow.ellipsis, style: tw(16, weight: bold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Tw.emerald500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3))),
              child: Text(_quota == null ? '…' : context.t('rrpp_panel_balance', fallback: '{{count}} QR', params: {'count': _quota}), style: tw(13, weight: black, color: Tw.emerald400)),
            ),
            const SizedBox(width: 8),
            AdminButton(
              label: context.t('rrpp_panel_buy', fallback: '+ Comprar QR'),
              color: Tw.emerald500,
              textColor: Tw.slate950,
              fontSize: 11,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              onTap: _buy,
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 80), children: [
              if (widget.success) _banner(context.t('rrpp_panel_paid', fallback: 'Pago completado: tus QR ya están en tu saldo.'), Tw.emerald400),
              if (_error.isNotEmpty) _banner(_error, Tw.red400),
              if (_notice.isNotEmpty) _banner(_notice, Tw.emerald400),
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Tw.amber500.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.amber500.withValues(alpha: 0.2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '${context.t('rrpp_panel_rule_title', fallback: 'Desde la app no se cobra.')} ', style: tw(13, weight: bold, color: Tw.amber400)),
                    TextSpan(text: context.t('rrpp_panel_rule_text', fallback: 'Cada pase gasta 1 QR de tu saldo; a tus invitados les cobras tú, por fuera.'), style: tw(13, color: Tw.slate300)),
                  ])),
                  const SizedBox(height: 8),
                  Text(
                    context.t('rrpp_panel_rule_venue', fallback: '¿Quieres vender entradas desde la app? Da de alta tu local, o pide al local con el que trabajas que te añada a su equipo de RRPP.'),
                    style: tw(12, color: Tw.slate400),
                  ),
                  TextButton(
                    onPressed: () => openRoute(context, AppRoute.business, args: {'type': 'venue'}),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                    child: Text(context.t('rrpp_panel_register_venue', fallback: 'Dar de alta un local'), style: tw(12, weight: bold, color: Tw.emerald400)),
                  ),
                ]),
              ),
              _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(context.t('rrpp_panel_events', fallback: 'Mis eventos'), style: tw(15, weight: bold))),
                  TextButton(
                    onPressed: () => setState(() => _creating = !_creating),
                    child: Text(_creating ? context.t('rrpp_panel_close', fallback: 'Cerrar') : context.t('rrpp_panel_new_event', fallback: '+ Nuevo evento'),
                        style: tw(12, weight: bold, color: Tw.emerald400)),
                  ),
                ]),
                if (_creating)
                  _NewEventForm(
                    onError: (m) => setState(() => _error = m),
                    onCreated: (id, notice) async {
                      setState(() {
                        _creating = false;
                        _notice = notice;
                        _error = '';
                      });
                      await _load();
                      if (mounted) setState(() => _selected = id);
                    },
                  ),
                if (_events.isEmpty && !_creating)
                  Text(context.t('rrpp_panel_no_events', fallback: 'Aún no tienes eventos. Crea uno para emitir pases y conseguir el enlace de puerta.'), style: tw(13, color: Tw.slate500))
                else
                  for (final e in _events)
                    Pressable(
                      onTap: () => setState(() => _selected = e['eventId'] == _selected ? '' : '${e['eventId']}'),
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: e['eventId'] == _selected ? Tw.emerald500.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: e['eventId'] == _selected ? Tw.emerald500.withValues(alpha: 0.5) : Tw.w(0.1)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${e['title'] ?? ''}', style: tw(14, weight: bold)),
                          Text(
                            [
                              '${e['date'] ?? ''}${e['time'] != null ? ' · ${e['time']}' : ''}',
                              '${e['venueName'] ?? ''}',
                              if (e['external'] != true) context.t('rrpp_panel_app_venue', fallback: 'local de la app'),
                            ].join(' · '),
                            style: tw(12, color: Tw.slate400),
                          ),
                        ]),
                      ),
                    ),
              ])),
              if (event != null)
                _EventDetail(
                  event: event,
                  passes: [for (final p in _passes) if ((p['rrppEventId'] ?? p['eventId']) == event['eventId']) p],
                  onIssued: _load,
                  onError: (m) => setState(() => _error = m),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _NewEventForm extends StatefulWidget {
  final void Function(String eventId, String notice) onCreated;
  final ValueChanged<String> onError;
  const _NewEventForm({required this.onCreated, required this.onError});

  @override
  State<_NewEventForm> createState() => _NewEventFormState();
}

class _NewEventFormState extends State<_NewEventForm> {
  final _title = TextEditingController();
  final _search = TextEditingController();
  final _place = TextEditingController();
  final _address = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool _inApp = false;
  List<Map<String, dynamic>> _venues = [];
  String _venueId = '';
  ({double lat, double lng})? _coords;
  bool _saving = false;

  I18n get _i18n => context.read<I18n>();

  @override
  void dispose() {
    for (final c in [_title, _search, _place, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadVenues() async {
    if (_venues.isNotEmpty) return;
    try {
      final s = await FirebaseFirestore.instance.collection('venues').where('isActive', isEqualTo: true).get();
      if (!mounted) return;
      setState(() => _venues = [
            for (final d in s.docs)
              if (d.data()['rrppParty'] != true && d.data()['isClaimed'] != false) {'id': d.id, 'name': (d.data()['name'] as String?) ?? d.id, 'address': d.data()['address']},
          ]);
    } catch (_) {}
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _date == null) return;
    if (_inApp && _venueId.isEmpty) return widget.onError(_i18n.t('rrpp_event_pick_venue', fallback: 'Elige el local de la app.'));
    if (!_inApp && (_coords == null || _place.text.trim().isEmpty)) return widget.onError(_i18n.t('rrpp_event_pick_address', fallback: 'Elige la dirección de la lista.'));
    setState(() => _saving = true);
    try {
      final d = _date!;
      final res = await callFn('createRRPPParty', {
        'eventName': _title.text.trim(),
        'eventDate': '${d.year}-${_two(d.month)}-${_two(d.day)}',
        if (_time != null) 'eventTime': '${_two(_time!.hour)}:${_two(_time!.minute)}',
        if (_inApp) 'venueId': _venueId else ...{'venueName': _place.text.trim(), 'address': _address.text.trim(), 'lat': _coords!.lat, 'lng': _coords!.lng},
      });
      widget.onCreated(
        '${res['eventId']}',
        res['matchedVenue'] == true
            ? _i18n.t('rrpp_event_matched', fallback: 'Esa dirección es de {{venue}}, un local de la app: tus pases valen en su puerta y con tu enlace.', params: {'venue': res['venueName']})
            : '',
      );
    } catch (e) {
      widget.onError(errorMessage(e, _i18n.t('rrpp_event_error', fallback: 'No se pudo crear el evento.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final matches = q.isEmpty ? const <Map<String, dynamic>>[] : _venues.where((v) => '${v['name']}'.toLowerCase().contains(q)).take(8).toList();
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _title, style: tw(14), onChanged: (_) => setState(() {}), decoration: _field(context.t('rrpp_event_title', fallback: 'Nombre del evento'))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: AdminButton(
              label: _date == null ? context.t('rrpp_event_date', fallback: 'Fecha') : '${_date!.day}/${_date!.month}/${_date!.year}',
              color: Tw.w(0.08),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 365)), initialDate: _date ?? now);
                if (d != null) setState(() => _date = d);
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AdminButton(
              label: _time == null ? context.t('rrpp_event_time', fallback: 'Hora') : '${_two(_time!.hour)}:${_two(_time!.minute)}',
              color: Tw.w(0.08),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 23, minute: 0));
                if (t != null) setState(() => _time = t);
              },
            ),
          ),
        ]),
        const SizedBox(height: 10),
        AdminChips<bool>(
          items: [(false, context.t('rrpp_event_outside', fallback: 'Fuera de la app')), (true, context.t('rrpp_event_app_venue', fallback: 'En un local de la app'))],
          selected: _inApp,
          color: Tw.emerald600,
          onSelect: (v) {
            setState(() => _inApp = v);
            if (v) _loadVenues();
          },
        ),
        const SizedBox(height: 10),
        if (_inApp) ...[
          TextField(
            controller: _search,
            style: tw(14),
            onChanged: (_) => setState(() => _venueId = ''),
            decoration: _field(context.t('rrpp_event_search_venue', fallback: 'Buscar local')),
          ),
          for (final v in matches)
            Pressable(
              onTap: () => setState(() {
                _venueId = '${v['id']}';
                _search.text = '${v['name']}';
              }),
              child: Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _venueId == v['id'] ? Tw.emerald500.withValues(alpha: 0.2) : Tw.w(0.05), borderRadius: BorderRadius.circular(8)),
                child: Text('${v['name']}${v['address'] != null ? ' · ${v['address']}' : ''}', style: tw(12, color: Tw.slate300)),
              ),
            ),
        ] else ...[
          TextField(controller: _place, style: tw(14), decoration: _field(context.t('rrpp_event_place', fallback: 'Nombre del sitio'))),
          const SizedBox(height: 10),
          AddressAutocomplete(
            controller: _address,
            placeholder: context.t('rrpp_event_address', fallback: 'Dirección'),
            onSelect: (r) => setState(() => _coords = (lat: r.lat, lng: r.lng)),
          ),
          const SizedBox(height: 6),
          Text(context.t('rrpp_event_radar', fallback: 'Saldrá en el radar como fiesta RRPP hasta el día siguiente, con el aviso de que la entrada se consigue contigo.'),
              style: tw(11, color: Tw.slate500)),
        ],
        const SizedBox(height: 12),
        AdminButton(
          label: _saving ? context.t('business_login_processing', fallback: 'Procesando...') : context.t('rrpp_event_create', fallback: 'Crear evento'),
          color: Tw.emerald500,
          textColor: Tw.slate950,
          expand: true,
          loading: _saving,
          padding: const EdgeInsets.symmetric(vertical: 12),
          onTap: _saving || _title.text.trim().isEmpty || _date == null ? null : _save,
        ),
      ]),
    );
  }
}

class _EventDetail extends StatefulWidget {
  final Map<String, dynamic> event;
  final List<Map<String, dynamic>> passes;
  final Future<void> Function() onIssued;
  final ValueChanged<String> onError;
  const _EventDetail({required this.event, required this.passes, required this.onIssued, required this.onError});

  @override
  State<_EventDetail> createState() => _EventDetailState();
}

class _EventDetailState extends State<_EventDetail> {
  final _names = TextEditingController();
  bool _issuing = false;
  List<Map<String, dynamic>> _issued = [];

  I18n get _i18n => context.read<I18n>();

  @override
  void dispose() {
    _names.dispose();
    super.dispose();
  }

  String _passText(String name, String url) =>
      _i18n.t('rrpp_pass_message', fallback: 'Hola {{name}}, aquí tienes tu pase para {{event}}: {{url}}', params: {'name': name, 'event': widget.event['title'], 'url': url});

  Future<void> _issue() async {
    final list = _names.text.split('\n').map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
    if (list.isEmpty) return;
    setState(() => _issuing = true);
    try {
      final res = await callFn('issueRRPPTickets', {'eventId': widget.event['eventId'], 'guestNames': list});
      setState(() {
        _issued = [for (final t in (res['tickets'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
        _names.clear();
      });
      await widget.onIssued();
    } catch (e) {
      widget.onError(errorMessage(e, _i18n.t('rrpp_issue_error', fallback: 'No se pudieron emitir los pases.')));
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  Future<void> _resend(Map<String, dynamic> p) async {
    try {
      final res = await callFn('resendRRPPPass', {'ticketId': p['ticketId']});
      _whatsapp(_passText('${p['clientName']}', '$webBase${res['passPath']}'));
    } catch (e) {
      widget.onError(errorMessage(e, _i18n.t('rrpp_issue_error', fallback: 'No se pudieron emitir los pases.')));
    }
  }

  Widget _box(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final door = rrppDoorUrl('${e['venueId']}', '${e['eventId']}', '${e['doorToken']}');
    return Column(children: [
      _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('rrpp_door_title', fallback: 'Enlace de puerta'), style: tw(15, weight: bold)),
        const SizedBox(height: 4),
        Text(context.t('rrpp_door_desc', fallback: 'Pásaselo a quien escanee en la puerta: no necesita cuenta. Si tiene cuenta, puede guardarlo y escanear desde la app.'),
            style: tw(12, color: Tw.slate400)),
        const SizedBox(height: 12),
        Center(
          child: Container(padding: const EdgeInsets.all(10), color: Tw.white, child: QrImageView(data: door, size: 150, backgroundColor: Tw.white)),
        ),
        const SizedBox(height: 10),
        Text(door, style: tw(10, color: Tw.slate500).copyWith(fontFamily: 'monospace')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: AdminButton(label: context.t('rrpp_copy', fallback: 'Copiar'), color: Tw.w(0.1), expand: true, onTap: () => _copy(context, door))),
          const SizedBox(width: 10),
          Expanded(
            child: AdminButton(
              label: 'WhatsApp',
              color: Tw.green600,
              expand: true,
              onTap: () => _whatsapp(_i18n.t('rrpp_door_message', fallback: 'Enlace para escanear los pases de {{event}}: {{url}}', params: {'event': e['title'], 'url': door})),
            ),
          ),
        ]),
      ])),
      _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('rrpp_issue_title', fallback: 'Emitir pases'), style: tw(15, weight: bold)),
        const SizedBox(height: 4),
        Text(context.t('rrpp_issue_desc', fallback: 'Un nombre por línea; cada pase gasta 1 QR. Cada invitado recibe su enlace con el QR, sin necesidad de cuenta.'),
            style: tw(12, color: Tw.slate400)),
        const SizedBox(height: 12),
        TextField(
          controller: _names,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          style: tw(14).copyWith(fontFamily: 'monospace'),
          decoration: _field('Carlos García\nLaura Morales'),
        ),
        const SizedBox(height: 12),
        AdminButton(
          label: _issuing ? context.t('rrpp_issuing', fallback: 'Emitiendo…') : context.t('rrpp_issue_submit', fallback: 'Emitir pases'),
          color: Tw.emerald500,
          textColor: Tw.slate950,
          expand: true,
          loading: _issuing,
          padding: const EdgeInsets.symmetric(vertical: 12),
          onTap: _issuing || _names.text.trim().isEmpty ? null : _issue,
        ),
        for (final p in _issued)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Tw.emerald500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(child: Text('${p['clientName']}', overflow: TextOverflow.ellipsis, style: tw(13, weight: bold))),
              IconButton(icon: const Icon(Icons.copy, size: 16, color: Tw.slate300), onPressed: () => _copy(context, '$webBase${p['passPath']}')),
              IconButton(icon: const Icon(Icons.send, size: 16, color: Tw.green400), onPressed: () => _whatsapp(_passText('${p['clientName']}', '$webBase${p['passPath']}'))),
            ]),
          ),
      ])),
      _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('rrpp_passes_title', fallback: 'Pases de este evento'), style: tw(15, weight: bold)),
        const SizedBox(height: 8),
        if (widget.passes.isEmpty)
          Text(context.t('rrpp_passes_empty', fallback: 'Todavía no has emitido pases para este evento.'), style: tw(13, color: Tw.slate500))
        else
          for (final p in widget.passes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: Text('${p['clientName'] ?? ''}', overflow: TextOverflow.ellipsis, style: tw(13, weight: bold))),
                AdminBadge(
                  p['status'] == 'used' ? context.t('rrpp_pass_used', fallback: 'Ha entrado') : context.t('rrpp_pass_valid', fallback: 'Válido'),
                  color: p['status'] == 'used' ? const Color(0xFFD8B4FE) : const Color(0xFF6EE7B7),
                ),
                if (p['status'] == 'valid')
                  TextButton(onPressed: () => _resend(p), child: Text(context.t('rrpp_pass_resend', fallback: 'Reenviar'), style: tw(11, weight: bold, color: Tw.emerald400))),
              ]),
            ),
      ])),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Footer of the door scanner: keep this door link in the account (saveDoorAccess) to open it later from
/// "Mis puertas". Without an account, a quick sign-up (name, email, password or Google), no full profile.
class SaveDoorBar extends StatefulWidget {
  final String eventId, venueId, token;
  const SaveDoorBar({super.key, required this.eventId, required this.venueId, required this.token});

  @override
  State<SaveDoorBar> createState() => _SaveDoorBarState();
}

class _SaveDoorBarState extends State<SaveDoorBar> {
  bool _saved = false;
  bool _busy = false;
  String _error = '';

  Future<void> _save() => callFn('saveDoorAccess', {'eventId': widget.eventId, 'venueId': widget.venueId, 'token': widget.token});

  Future<void> _saveNow() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await _save();
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, context.read<I18n>().t('door_save_error', fallback: 'No se pudo guardar la puerta.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signUpSheet() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    var busy = false;
    var error = '';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11131F),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t('door_save_title', fallback: 'Guardar esta puerta'), style: tw(16, weight: bold)),
            const SizedBox(height: 12),
            AdminButton(
              label: ctx.t('business_login_continue_with_google', fallback: 'Continuar con Google'),
              color: Tw.white,
              textColor: Tw.slate900,
              expand: true,
              onTap: busy
                  ? null
                  : () async {
                      try {
                        await ctx.read<AuthProvider>().loginWithGoogle();
                        await _save();
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } catch (e) {
                        setLocal(() => error = errorMessage(e, ''));
                      }
                    },
            ),
            const SizedBox(height: 10),
            TextField(controller: name, style: tw(14), decoration: adminInputDecoration(ctx.t('door_save_name', fallback: 'Tu nombre'))),
            const SizedBox(height: 8),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, style: tw(14), decoration: adminInputDecoration('Email')),
            const SizedBox(height: 8),
            TextField(controller: password, obscureText: true, style: tw(14), decoration: adminInputDecoration(ctx.t('door_save_password', fallback: 'Contraseña'))),
            if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error, style: tw(12, color: Tw.red400))),
            const SizedBox(height: 12),
            AdminButton(
              label: busy ? '…' : ctx.t('door_save_submit', fallback: 'Crear cuenta y guardar'),
              expand: true,
              loading: busy,
              padding: const EdgeInsets.symmetric(vertical: 12),
              onTap: busy
                  ? null
                  : () async {
                      setLocal(() {
                        busy = true;
                        error = '';
                      });
                      try {
                        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.text.trim(), password: password.text);
                        await cred.user!.updateDisplayName(name.text.trim());
                        await _save();
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } on FirebaseAuthException catch (e) {
                        setLocal(() {
                          busy = false;
                          error = e.code == 'email-already-in-use'
                              ? ctx.read<I18n>().t('door_account_exists', fallback: 'Ya hay una cuenta con ese email: entra con ella y pulsa guardar.')
                              : errorMessage(e, ctx.read<I18n>().t('door_save_error', fallback: 'No se pudo guardar la puerta.'));
                        });
                      } catch (e) {
                        setLocal(() {
                          busy = false;
                          error = errorMessage(e, ctx.read<I18n>().t('door_save_error', fallback: 'No se pudo guardar la puerta.'));
                        });
                      }
                    },
            ),
          ]),
        ),
      ),
    );
    name.dispose();
    email.dispose();
    password.dispose();
    if (saved == true && mounted) setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_saved) return Text(context.t('door_saved', fallback: 'Puerta guardada: la tienes en «Mis puertas».'), textAlign: TextAlign.center, style: tw(11, color: Tw.emerald400));
    final user = context.watch<AuthProvider>().user;
    return TextButton(
      onPressed: _busy ? null : (user != null ? _saveNow : _signUpSheet),
      child: Text(
        _error.isNotEmpty
            ? _error
            : user != null
                ? context.t('door_save_btn', fallback: 'Guardar esta puerta en mi cuenta')
                : context.t('door_save_prompt', fallback: 'Sin login. ¿Escaneas a menudo? Guarda esta puerta en una cuenta y ábrela desde la app.'),
        textAlign: TextAlign.center,
        style: tw(11, color: Tw.slate500),
      ),
    );
  }
}

/// "Mis puertas": the door links saved in the account; each one opens the door scanner.
class MyDoorsScreen extends StatelessWidget {
  const MyDoorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      backgroundColor: const Color(0xFF07080D),
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(context.t('door_my_doors', fallback: 'Mis puertas'), style: tw(18, weight: black))),
      body: user == null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${context.t('door_my_doors_login', fallback: 'Abre el enlace de puerta que te ha pasado el RRPP o el local. Si guardaste puertas en tu cuenta,')} '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () => openRoute(context, AppRoute.login),
                    child: Text(context.t('door_my_doors_login_link', fallback: 'inicia sesión'), style: tw(14, weight: bold, color: Tw.fuchsia400)),
                  ),
                ),
                const TextSpan(text: '.'),
              ]), style: tw(14, color: Tw.slate400)),
            )
          : FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('doors').orderBy('savedAt', descending: true).get(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500));
                final doors = snap.data!.docs.map((d) => d.data()).toList();
                if (doors.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(context.t('door_my_doors_empty', fallback: 'Aún no tienes puertas guardadas. Abre un enlace de puerta y pulsa «Guardar esta puerta».'),
                        style: tw(14, color: Tw.slate400)),
                  );
                }
                return ListView(padding: const EdgeInsets.all(16), children: [
                  for (final d in doors)
                    Pressable(
                      onTap: () => openRoute(context, AppRoute.door, args: {'venue': '${d['venueId'] ?? ''}', 'event': '${d['eventId']}', 'token': '${d['token']}'}),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xFF11131F), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF23273F))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${d['title'] ?? ''}', style: tw(15, weight: bold)),
                          Text([d['venueName'], d['date']].where((v) => v != null && '$v'.isNotEmpty).join(' · '), style: tw(12, color: Tw.slate400)),
                        ]),
                      ),
                    ),
                ]);
              },
            ),
    );
  }
}
