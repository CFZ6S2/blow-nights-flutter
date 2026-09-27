import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../models/firestore_utils.dart';
import '../../../navigation.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

const _panel = Color(0xFF11131F);
const _panelBorder = Color(0xFF23273F);
const _row = Color(0xFF1C1F38);
const _rowBorder = Color(0xFF3B3F68);
const _formBg = Color(0xFF07080D);
const _formBorder = Color(0xFF2B2F52);

InputDecoration _fieldDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: tw(14, color: Tw.slate500),
      isDense: true,
      filled: true,
      fillColor: _row,
      contentPadding: const EdgeInsets.all(10),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.transparent)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.fuchsia500)),
    );

/// Port of components/venue-admin/DoorTab.tsx: per-event scanner magic links + named door accounts.
class DoorTab extends StatefulWidget {
  final String venueId;
  const DoorTab({super.key, required this.venueId});

  @override
  State<DoorTab> createState() => _DoorTabState();
}

class _DoorTabState extends State<DoorTab> {
  final _db = FirebaseFirestore.instance;
  List<({String id, String title, String date, String? token, bool loading})> _links = [];
  bool _eventsLoading = true;
  String? _regenerating;
  List<Map<String, dynamic>> _employees = [];
  bool _loading = true;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  I18n get _i18n => context.read<I18n>();

  @override
  void initState() {
    super.initState();
    _fetchLinks();
    _fetchEmployees();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _fetchLinks() async {
    setState(() => _eventsLoading = true);
    try {
      final snap = await _db.collection('venues/${widget.venueId}/events').get();
      String date(Map<String, dynamic> d) {
        if (d['start_date'] != null) {
          final dt = parseDate(d['start_date']);
          if (dt != null) return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        }
        if (d['date'] is String) return d['date'] as String;
        final dt = parseDate(d['date']);
        return dt == null ? '' : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }

      setState(() => _links = [
            for (final d in snap.docs) (id: d.id, title: (d.data()['title'] as String?) ?? 'Evento', date: date(d.data()), token: null, loading: true),
          ]);
      await Future.wait(_links.map((ev) async {
        String? token;
        try {
          final s = await _db.doc('venues/${widget.venueId}/events/${ev.id}/private/secrets').get();
          if (s.exists) token = (s.data()?['door_access_token'] ?? s.data()?['scanner_token']) as String?;
        } catch (_) {}
        if (mounted) {
          setState(() => _links = [for (final l in _links) l.id == ev.id ? (id: l.id, title: l.title, date: l.date, token: token, loading: false) : l]);
        }
      }));
    } catch (e) {
      debugPrint('Error fetching event links: $e');
    } finally {
      if (mounted) setState(() => _eventsLoading = false);
    }
  }

  Future<void> _fetchEmployees() async {
    setState(() => _loading = true);
    try {
      final s = await _db.collection('venues/${widget.venueId}/employees').get();
      if (mounted) setState(() => _employees = [for (final d in s.docs) {'id': d.id, ...d.data()}]);
    } catch (e) {
      debugPrint('$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _regenerate(String eventId) async {
    if (!await confirmDialog(context,
        message: _i18n.t('door_tab.regen_confirm',
            fallback:
                '¿Seguro que quieres invalidar el enlace actual y generar un nuevo token de puerta? El enlace anterior dejará de funcionar inmediatamente.'),
        danger: true,
        confirmText: _i18n.t('door_tab.regen_token', fallback: 'Regenerar Token'))) {
      return;
    }
    setState(() => _regenerating = eventId);
    try {
      final res = await callFn('regenerateEventDoorToken', {'venueId': widget.venueId, 'eventId': eventId});
      final token = res['token'] as String?;
      if (token != null) {
        setState(() => _links = [for (final l in _links) l.id == eventId ? (id: l.id, title: l.title, date: l.date, token: token, loading: false) : l]);
        if (mounted) showToast(context, _i18n.t('door_tab.token_regenerated', fallback: 'Token de puerta regenerado con éxito.'));
      }
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('door_tab.error_regen', fallback: 'Error al regenerar token de puerta.'), error: true);
    } finally {
      if (mounted) setState(() => _regenerating = null);
    }
  }

  Future<void> _add() async {
    if (_name.text.isEmpty || !_email.text.contains('@') || _password.text.length < 6) return;
    try {
      await callFn('createDoorEmployee', {'venueId': widget.venueId, 'email': _email.text, 'password': _password.text, 'name': _name.text});
      _name.clear();
      _email.clear();
      _password.clear();
      _fetchEmployees();
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('door_tab.error_add'), error: true);
    }
  }

  Future<void> _toggle(String uid, bool active) async {
    try {
      await callFn(active ? 'revokeDoorEmployee' : 'reactivateDoorEmployee', {'venueId': widget.venueId, 'uid': uid});
      _fetchEmployees();
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('door_tab.error_toggle'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AdminCard(
          radius: 16,
          color: _panel,
          borderColor: _panelBorder,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Tw.fuchsia600.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.qr_code_scanner, color: Tw.fuchsia400),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('door_tab.scanner_links_title', fallback: 'Enlaces de Escáner por Evento'), style: tw(20, weight: bold)),
                  Text(
                    context.t('door_tab.scanner_links_desc',
                        fallback: 'Comparte este enlace con tu personal de puerta. No requiere usuario ni contraseña, solo el enlace seguro con su token.'),
                    style: tw(12, color: Tw.slate400),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            if (_eventsLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(context.t('door_tab.loading', fallback: 'Cargando...'), textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
              )
            else if (_links.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(context.t('door_tab.no_events', fallback: 'No hay eventos creados.'), textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
              )
            else
              for (final ev in _links) _linkCard(context, ev),
          ]),
        ),
        const SizedBox(height: 32),
        AdminCard(
          radius: 16,
          color: _panel,
          borderColor: _panelBorder,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.t('door_tab.employees_section_title', fallback: 'Cuentas Nominales de Puerta'), style: tw(20, weight: bold)),
            Text(
              context.t('door_tab.employees_section_desc',
                  fallback: 'Opcional: Crea cuentas con email y contraseña para tus empleados si prefieres auditoría nominal de accesos.'),
              style: tw(12, color: Tw.slate400),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _formBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _formBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: _name, style: tw(14), decoration: _fieldDeco(context.t('door_tab.name_placeholder'))),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  style: tw(14),
                  decoration: _fieldDeco(context.t('door_tab.email_placeholder')),
                ),
                const SizedBox(height: 8),
                TextField(controller: _password, obscureText: true, style: tw(14), decoration: _fieldDeco(context.t('door_tab.password_placeholder'))),
                const SizedBox(height: 8),
                AdminButton(label: context.t('door_tab.add'), expand: true, padding: const EdgeInsets.symmetric(vertical: 12), onTap: _add),
              ]),
            ),
            const SizedBox(height: 24),
            if (_loading)
              Text(context.t('door_tab.loading'), style: tw(12, color: Tw.slate500))
            else ...[
              for (final emp in _employees)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: _row, borderRadius: BorderRadius.circular(12), border: Border.all(color: _rowBorder)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text.rich(TextSpan(children: [
                          TextSpan(text: '${emp['name'] ?? ''} ', style: tw(14, weight: bold)),
                          TextSpan(text: '(${emp['email'] ?? ''})', style: tw(12, color: Tw.slate400)),
                        ])),
                        const SizedBox(height: 2),
                        Label(emp['active'] == true ? context.t('door_tab.active_status') : context.t('door_tab.revoked_status'),
                            color: emp['active'] == true ? Tw.emerald400 : Tw.red400, tracking: 0),
                      ]),
                    ),
                    AdminButton(
                      label: emp['active'] == true ? context.t('door_tab.revoke_access') : context.t('door_tab.reactivate'),
                      color: emp['active'] == true ? Tw.red400 : Tw.emerald400,
                      outlined: true,
                      onTap: () => _toggle(emp['id'] as String, emp['active'] == true),
                    ),
                  ]),
                ),
              if (_employees.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(context.t('door_tab.empty', fallback: 'No hay empleados registrados.'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
                ),
            ],
          ]),
        ),
      ]);

  Widget _linkCard(BuildContext context, ({String id, String title, String date, String? token, bool loading}) ev) {
    final token = ev.token;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _row.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12), border: Border.all(color: _rowBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(ev.title, style: tw(16, weight: black)),
          if (ev.date.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(99)),
              child: Text(ev.date, style: tw(10, color: Tw.slate300)),
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          ev.loading
              ? '...'
              : token != null
                  ? '/door?venue=${widget.venueId}&event=${ev.id}&token=${token.length > 10 ? token.substring(0, 10) : token}...'
                  : 'Sin token configurado',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tw(12, color: Tw.slate400).copyWith(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          if (token != null) ...[
            AdminButton(
              icon: Icons.content_copy,
              label: context.t('door_tab.copy_link', fallback: 'Copiar Enlace'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: '$webBase/door?venue=${widget.venueId}&event=${ev.id}&token=$token'));
                if (context.mounted) showToast(context, context.read<I18n>().t('events_tab.link_copied', fallback: 'Enlace copiado al portapapeles'));
              },
            ),
            AdminButton(
              icon: Icons.open_in_new,
              label: context.t('door_tab.open_scanner', fallback: 'Abrir Escáner'),
              color: Tw.w(0.1),
              onTap: () => openRoute(context, AppRoute.door, args: {'venue': widget.venueId, 'event': ev.id, 'token': token}),
            ),
          ],
          AdminButton(
            icon: Icons.sync,
            label: _regenerating == ev.id ? '...' : context.t('door_tab.regen_token', fallback: 'Regenerar'),
            color: Tw.red400,
            outlined: true,
            onTap: _regenerating == ev.id ? null : () => _regenerate(ev.id),
          ),
        ]),
      ]),
    );
  }
}

/// Port of components/venue-admin/PromotersTab.tsx
class PromotersTab extends StatefulWidget {
  final String venueId;
  const PromotersTab({super.key, required this.venueId});

  @override
  State<PromotersTab> createState() => _PromotersTabState();
}

class _PromotersTabState extends State<PromotersTab> {
  List<Map<String, dynamic>> _promoters = [];
  bool _loading = true;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _commission = TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _commission.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final s = await FirebaseFirestore.instance.collection('venues/${widget.venueId}/promoters').get();
      if (mounted) setState(() => _promoters = [for (final d in s.docs) {'id': d.id, ...d.data()}]);
    } catch (e) {
      debugPrint('$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final commission = num.tryParse(_commission.text);
    if (_name.text.isEmpty || !_email.text.contains('@') || commission == null || commission < 0 || commission > 100) return;
    try {
      await callFn('createVenuePromoter', {'venueId': widget.venueId, 'email': _email.text, 'name': _name.text, 'commission': commission});
      _name.clear();
      _email.clear();
      _commission.text = '10';
      _fetch();
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('promoters_tab.error_add'), error: true);
    }
  }

  Future<void> _toggle(String uid, bool active) async {
    try {
      await callFn('toggleVenuePromoter', {'venueId': widget.venueId, 'uid': uid, 'active': !active});
      _fetch();
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('promoters_tab.error_toggle'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AdminCard(
        radius: 16,
        color: _panel,
        borderColor: _panelBorder,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(context.t('promoters_tab.title'), style: tw(20, weight: bold)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _formBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _formBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: _name, style: tw(14), decoration: _fieldDeco(context.t('promoters_tab.name_placeholder'))),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: tw(14),
                decoration: _fieldDeco(context.t('promoters_tab.email_placeholder')),
              ),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(
                  width: 128,
                  child: TextField(
                    controller: _commission,
                    keyboardType: TextInputType.number,
                    style: tw(14),
                    decoration: _fieldDeco(context.t('promoters_tab.commission_placeholder')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AdminButton(
                    label: context.t('promoters_tab.invite'),
                    color: Tw.purple500,
                    expand: true,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onTap: _add,
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 24),
          if (_loading)
            Text(context.t('promoters_tab.loading'), style: tw(14))
          else ...[
            for (final p in _promoters)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _row, borderRadius: BorderRadius.circular(8), border: Border.all(color: _rowBorder)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(text: '${p['name'] ?? ''} ', style: tw(15, weight: bold)),
                        TextSpan(text: '(${p['email'] ?? ''})', style: tw(12, color: Tw.slate400)),
                      ])),
                      const SizedBox(height: 4),
                      Wrap(spacing: 16, children: [
                        Text('${context.t('promoters_tab.commission')}: ${p['commission']}%', style: tw(12, weight: black, color: Tw.emerald400)),
                        Text('${context.t('promoters_tab.sales')}: ${(p['stats'] as Map?)?['sales'] ?? 0}', style: tw(12, color: Tw.slate400)),
                        Text('${context.t('promoters_tab.code')}: ${p['code'] ?? ''}', style: tw(12, weight: black, color: Tw.fuchsia400)),
                      ]),
                    ]),
                  ),
                  TextButton(
                    onPressed: () => _toggle(p['id'] as String, p['active'] == true),
                    child: Text(p['active'] == true ? context.t('promoters_tab.deactivate') : context.t('promoters_tab.activate'),
                        style: tw(12, weight: bold)),
                  ),
                ]),
              ),
            if (_promoters.isEmpty) Text(context.t('promoters_tab.empty'), style: tw(14, color: Tw.slate500)),
          ],
        ]),
      );
}
