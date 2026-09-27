import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../models/firestore_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';
import '../../../widgets/territory_map_picker.dart';

/// Port of features/super-admin/PartnersPanel.tsx (Master Partners / City Managers provisioning).
class PartnersPanel extends StatefulWidget {
  const PartnersPanel({super.key});

  @override
  State<PartnersPanel> createState() => _PartnersPanelState();
}

class _PartnersPanelState extends State<PartnersPanel> {
  List<Map<String, dynamic>> _partners = [];
  bool _loading = true;
  bool _showCreate = false;

  final _userId = TextEditingController();
  final _displayName = TextEditingController();
  final _cityIds = TextEditingController();
  final _splitPct = TextEditingController(text: '50');
  final _notes = TextEditingController();
  final _matchRegions = TextEditingController();
  final _matchCountries = TextEditingController(text: 'España');
  String _type = 'masterPartner';
  bool _creating = false;

  bool _showPreview = false;
  final _testAddress = TextEditingController();
  Map<String, dynamic>? _testResult;
  bool _testing = false;
  List<({double lat, double lng, String name})> _venueMarkers = [];

  String? _retrying;
  bool _batchSyncing = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    for (final c in [_userId, _displayName, _cityIds]) {
      c.addListener(() => setState(() {}));
    }
    _testAddress.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_userId, _displayName, _cityIds, _splitPct, _notes, _matchRegions, _matchCountries, _testAddress]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (mounted) showToast(context, msg, error: error);
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await callFn('listMasterPartners', {});
      final list = res['partners'];
      if (list is List) setState(() => _partners = [for (final p in list) Map<String, dynamic>.from(p as Map)]);
    } catch (e) {
      _toast(errorMessage(e, 'Error loading partners'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _cityIdsArray => _cityIds.text.split(',').map((c) => c.trim().toLowerCase()).where((c) => c.isNotEmpty).toList();
  List<String> _lines(String s, String sep) => s.split(sep).map((r) => r.trim()).where((r) => r.isNotEmpty).toList();

  Future<void> _create() async {
    if (_userId.text.trim().isEmpty || _displayName.text.trim().isEmpty || _cityIds.text.trim().isEmpty) return;
    final cityIds = _cityIdsArray;
    if (_type == 'cityManager' && cityIds.length > 1) {
      _toast('Un City Manager solo puede gestionar una ciudad.', error: true);
      return;
    }
    setState(() => _creating = true);
    try {
      final res = await callFn('createMasterPartner', {
        'userId': _userId.text.trim(),
        'displayName': _displayName.text.trim(),
        'cityIds': cityIds,
        'splitPct': num.tryParse(_splitPct.text) ?? 0,
        'notes': _notes.text.trim(),
        'type': _type,
        'matchRegions': _lines(_matchRegions.text, '\n'),
        'matchCountries': _lines(_matchCountries.text, ','),
      });
      if (res['warning'] is String) {
        _toast(res['warning'] as String);
      } else {
        _toast("${_type == 'cityManager' ? 'City Manager' : 'Master Partner'} '${_displayName.text}' creado.");
      }
      for (final c in [_userId, _displayName, _cityIds, _notes, _matchRegions]) {
        c.clear();
      }
      _splitPct.text = '50';
      _matchCountries.text = 'España';
      setState(() {
        _type = 'masterPartner';
        _showCreate = false;
      });
      _fetch();
    } catch (e) {
      _toast(errorMessage(e, 'Error creating MP'), error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _suspend(String mpId) async {
    final i18n = context.read<I18n>();
    final reason = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => _SuspendDialog(
        title: i18n.t('super_admin.suspend_mp_title', fallback: 'Suspender Master Partner'),
        desc: i18n.t('super_admin.suspend_mp_desc',
            fallback: 'Esto revocará el rol masterPartner del usuario y bloqueará su acceso al panel. Los venues y subagentes se mantienen.'),
        placeholder: i18n.t('super_admin.suspend_reason_placeholder', fallback: 'Razón de la suspensión (obligatoria)...'),
        cancel: i18n.t('super_admin.cancel', fallback: 'Cancelar'),
        confirm: i18n.t('super_admin.confirm_suspend', fallback: 'Confirmar Suspensión'),
        onConfirm: (r) => callFn('suspendMasterPartner', {'masterPartnerId': mpId, 'reason': r}),
      ),
    );
    if (reason == null) return;
    _toast('Master Partner suspendido.');
    _fetch();
  }

  Future<void> _reactivate(String mpId) async {
    try {
      await callFn('updateMasterPartner', {'masterPartnerId': mpId, 'status': 'active'});
      _toast('Master Partner reactivado.');
      _fetch();
    } catch (e) {
      _toast(errorMessage(e, 'Error reactivating MP'), error: true);
    }
  }

  Future<void> _retrySync(String mpId) async {
    setState(() => _retrying = mpId);
    try {
      await callFn('retryClaimSync', {'masterPartnerId': mpId});
      _toast('Claims sincronizados correctamente.');
      _fetch();
    } catch (e) {
      _toast(errorMessage(e, 'Error syncing claims'), error: true);
    } finally {
      if (mounted) setState(() => _retrying = null);
    }
  }

  Future<void> _batchSync() async {
    setState(() => _batchSyncing = true);
    try {
      final d = await callFn('retryClaimSync', {});
      final processed = (d['processed'] as num?)?.toInt() ?? 0;
      if (processed == 0) {
        _toast('No hay MPs con sync pendiente.');
      } else {
        final failed = (d['failed'] as num?)?.toInt() ?? 0;
        _toast('Batch sync: ${d['synced']} OK, $failed fallidos de $processed.', error: failed > 0);
      }
      _fetch();
    } catch (e) {
      _toast(errorMessage(e, 'Error batch syncing'), error: true);
    } finally {
      if (mounted) setState(() => _batchSyncing = false);
    }
  }

  Future<void> _testResolution() async {
    if (_testAddress.text.trim().length < 5) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final res = await callFn('testTerritoryResolution', {
        'address': _testAddress.text.trim(),
        'testRegions': _lines(_matchRegions.text, '\n'),
        'testCountries': _lines(_matchCountries.text, ','),
      });
      setState(() => _testResult = res);
    } catch (e) {
      setState(() => _testResult = {'success': false, 'error': errorMessage(e, 'Error')});
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _loadVenueMarkers() async {
    final ids = _cityIdsArray;
    if (!_showPreview || ids.isEmpty) {
      setState(() => _venueMarkers = []);
      return;
    }
    try {
      final all = <({double lat, double lng, String name})>[];
      for (var i = 0; i < ids.length; i += 10) {
        final chunk = ids.sublist(i, (i + 10).clamp(0, ids.length));
        final s = await FirebaseFirestore.instance.collection('venues').where('cityId', whereIn: chunk).get();
        for (final d in s.docs) {
          final loc = d.data()['location'];
          if (loc is GeoPoint) all.add((lat: loc.latitude, lng: loc.longitude, name: (d.data()['name'] as String?) ?? d.id));
        }
      }
      if (mounted) setState(() => _venueMarkers = all);
    } catch (_) {
      if (mounted) setState(() => _venueMarkers = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.t('super_admin.partners_title', fallback: 'Master Partners'), style: tw(20, weight: black)),
      Text(context.t('super_admin.partners_subtitle', fallback: 'Provisioning y gestión de responsables territoriales'),
          style: tw(14, color: Tw.slate400)),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (_partners.any((mp) => mp['claimSyncStatus'] != 'synced'))
          AdminButton(
            icon: _batchSyncing ? Icons.hourglass_top : Icons.sync,
            label: _batchSyncing ? context.t('super_admin.syncing', fallback: 'Sincronizando...') : context.t('super_admin.batch_sync', fallback: 'Sync Pendientes'),
            color: Tw.amber400,
            outlined: true,
            onTap: _batchSyncing ? null : _batchSync,
          ),
        AdminButton(
          icon: Icons.person_add,
          label: context.t('super_admin.create_mp', fallback: 'Crear MP'),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          onTap: () => setState(() => _showCreate = !_showCreate),
        ),
      ]),
      if (_showCreate) ...[const SizedBox(height: 24), _createForm(context)],
      const SizedBox(height: 32),
      if (_loading)
        const AdminEmpty('', loading: true)
      else if (_partners.isEmpty)
        AdminCard(
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
          borderColor: Tw.w(0.05),
          child: Column(children: [
            const Icon(Icons.handshake, size: 40, color: Tw.slate600),
            const SizedBox(height: 12),
            Text(context.t('super_admin.no_partners', fallback: 'Sin Master Partners'), style: tw(18, weight: bold)),
            const SizedBox(height: 8),
            Text(context.t('super_admin.no_partners_desc', fallback: 'Crea el primer responsable territorial para comenzar la expansión comercial.'),
                textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
          ]),
        )
      else
        for (final mp in _partners) _partnerCard(mp),
    ]);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 12),
        child: Label(text, weight: bold),
      );

  Widget _createForm(BuildContext context) {
    final isCm = _type == 'cityManager';
    final canCreate = _userId.text.trim().isNotEmpty && _displayName.text.trim().isNotEmpty && _cityIds.text.trim().isNotEmpty;
    final r = _testResult;
    final geo = r?['geocoded'] is Map ? Map<String, dynamic>.from(r!['geocoded'] as Map) : null;
    final resolved = r?['resolvedCityId'] as String?;

    return AdminCard(
      radius: 16,
      borderColor: Tw.fuchsia500.withValues(alpha: 0.2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Label(isCm ? context.t('super_admin.new_cm_form', fallback: 'Nuevo City Manager') : context.t('super_admin.new_mp_form', fallback: 'Nuevo Master Partner'),
            size: 13, color: Tw.fuchsia400),
        const SizedBox(height: 12),
        Row(children: [
          _typeButton('masterPartner', 'Master Partner', Tw.fuchsia600),
          const SizedBox(width: 8),
          _typeButton('cityManager', 'City Manager', const Color(0xFF0891B2)),
        ]),
        _label('Firebase UID'),
        TextField(controller: _userId, style: tw(14).copyWith(fontFamily: 'monospace'), decoration: adminInputDecoration('abc123...')),
        _label(context.t('super_admin.mp_name', fallback: 'Nombre')),
        AdminInput(controller: _displayName, hint: 'Aurora BCN'),
        _label(isCm ? context.t('super_admin.cm_city', fallback: 'Ciudad') : context.t('super_admin.mp_cities', fallback: 'Ciudades (comma-sep)')),
        AdminInput(controller: _cityIds, hint: isCm ? 'barcelona' : 'barcelona, madrid'),
        _label('Split % (MP)'),
        TextField(
          controller: _splitPct,
          keyboardType: TextInputType.number,
          style: tw(14).copyWith(fontFamily: 'monospace'),
          decoration: adminInputDecoration(null),
        ),
        _label(context.t('super_admin.mp_notes', fallback: 'Notas')),
        AdminInput(controller: _notes, hint: 'Notas internas...'),
        const SizedBox(height: 16),
        Divider(height: 1, color: Tw.w(0.1)),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Label('Configuración Territorial', color: Tw.cyan400)),
          GestureDetector(
            onTap: () {
              setState(() => _showPreview = !_showPreview);
              _loadVenueMarkers();
            },
            child: Row(children: [
              const Icon(Icons.map, size: 14, color: Tw.fuchsia400),
              const SizedBox(width: 4),
              Text(_showPreview ? 'Ocultar mapa' : 'Ver en mapa', style: tw(10, color: Tw.fuchsia400)),
            ]),
          ),
        ]),
        _label('Match Regions (una por línea)'),
        TextField(
          controller: _matchRegions,
          maxLines: 3,
          style: tw(14).copyWith(fontFamily: 'monospace'),
          decoration: adminInputDecoration('Extremadura\nCáceres\nBadajoz', focus: Tw.cyan400),
        ),
        const SizedBox(height: 4),
        Text(
          'Nombres de región/provincia/localidad que Google Geocoding devuelve. El venue se asigna a este territorio si coincide alguno.',
          style: tw(10, color: Tw.slate600),
        ),
        _label('Match Countries (comma-sep)'),
        AdminInput(controller: _matchCountries, hint: 'España', focus: Tw.cyan400),
        const SizedBox(height: 4),
        Text('Filtro de país para evitar colisiones internacionales (ej: Valencia España vs Venezuela).', style: tw(10, color: Tw.slate600)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.science, size: 14, color: Tw.amber400),
              SizedBox(width: 6),
              Label('Test de Resolución Territorial', color: Tw.amber400, weight: bold),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: AdminInput(
                  controller: _testAddress,
                  hint: 'Calle Mayor 5, Mérida, España',
                  focus: Tw.amber500,
                  onSubmitted: (_) => _testResolution(),
                ),
              ),
              const SizedBox(width: 8),
              AdminButton(
                label: _testing ? 'Probando...' : 'Probar',
                color: const Color(0xFFD97706),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                onTap: _testing || _testAddress.text.trim().length < 5 ? null : _testResolution,
              ),
            ]),
            if (r != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (resolved != null ? Tw.green500 : Tw.red500).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (resolved != null ? Tw.green500 : Tw.red500).withValues(alpha: 0.2)),
                ),
                child: r['success'] == true
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(resolved != null ? Icons.check_circle : Icons.error, size: 14, color: resolved != null ? Tw.green400 : Tw.red400),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              resolved == 'TEST_MATCH'
                                  ? 'Territorio: CONFIGURACIÓN ACTUAL (Simulado)'
                                  : resolved != null
                                      ? 'Territorio: ${resolved.toUpperCase()}'
                                      : 'Sin territorio asignado',
                              style: tw(14, weight: bold, color: resolved != null ? Tw.green400 : Tw.red400),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        for (final (k, label) in const [
                          ('formattedAddress', 'Dirección'),
                          ('country', 'País'),
                          ('region', 'Región'),
                          ('province', 'Provincia'),
                          ('locality', 'Localidad'),
                        ])
                          Text.rich(TextSpan(style: tw(12, color: Tw.slate400).copyWith(fontFamily: 'monospace'), children: [
                            TextSpan(text: '$label: '),
                            TextSpan(text: '${geo?[k] ?? ''}', style: tw(12).copyWith(fontFamily: 'monospace')),
                          ])),
                      ])
                    : Text('${r['error'] ?? ''}', style: tw(12, color: Tw.red400).copyWith(fontFamily: 'monospace')),
              ),
            ],
          ]),
        ),
        if (_showPreview) ...[
          const SizedBox(height: 12),
          Text(
            '${_venueMarkers.length} venues ${_cityIdsArray.isNotEmpty ? 'en ${_cityIdsArray.join(', ').toUpperCase()}' : ''}'
            '${r?['success'] == true && geo != null ? ' · Pin amarillo = dirección de test' : ''}',
            style: tw(10, color: Tw.slate500),
          ),
          const SizedBox(height: 8),
          TerritoryPreviewMap(
            venues: _venueMarkers,
            testPoint: r?['success'] == true && geo != null && geo['latitude'] is num
                ? (
                    lat: (geo['latitude'] as num).toDouble(),
                    lng: (geo['longitude'] as num).toDouble(),
                    label: (geo['formattedAddress'] as String?) ?? '',
                  )
                : null,
          ),
        ],
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => setState(() => _showCreate = false),
            child: Text(context.t('super_admin.cancel', fallback: 'Cancelar'), style: tw(14, color: Tw.slate400)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: AdminButton(
              label: _creating
                  ? context.t('super_admin.creating', fallback: 'Creando...')
                  : isCm
                      ? context.t('super_admin.create_cm_btn', fallback: 'Crear City Manager')
                      : context.t('super_admin.create_mp_btn', fallback: 'Crear Master Partner'),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              onTap: _creating || !canCreate ? null : _create,
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _typeButton(String value, String label, Color color) {
    final active = _type == value;
    return Pressable(
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color : Tw.w(0.1)),
        ),
        child: Text(label, style: tw(12, weight: bold, color: active ? Tw.white : Tw.slate400)),
      ),
    );
  }

  Widget _partnerCard(Map<String, dynamic> mp) {
    final id = mp['id'] as String;
    final active = mp['status'] == 'active';
    final isCm = mp['type'] == 'cityManager';
    final sync = (mp['claimSyncStatus'] as String?) ?? 'unknown';
    final syncColor = switch (sync) {
      'synced' => Tw.green400,
      'pending' => Tw.amber400,
      'failed' => Tw.red400,
      _ => Tw.slate500,
    };
    final uid = (mp['userId'] as String?) ?? '';
    final cities = asStringList(mp['cityIds']).map((c) => c.toUpperCase()).join(', ');
    final created = mp['createdAt'] is String ? DateTime.tryParse(mp['createdAt'] as String) : null;

    return Opacity(
      opacity: active ? 1 : 0.7,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Tw.w(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? Tw.w(0.1) : Tw.red500.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text((mp['displayName'] as String?) ?? '', style: tw(16, weight: black)),
            _pill(isCm ? 'CM' : 'MP', isCm ? Tw.cyan400 : Tw.fuchsia400),
            _pill((mp['status'] as String?) ?? '', active ? Tw.green400 : mp['status'] == 'suspended' ? Tw.red400 : Tw.slate400),
            Text(sync == 'synced' ? '● sync' : sync == 'failed' ? '● fail' : '● $sync', style: tw(10, color: syncColor).copyWith(fontFamily: 'monospace')),
            if (sync != 'synced')
              GestureDetector(
                onTap: _retrying == id ? null : () => _retrySync(id),
                child: Text(_retrying == id ? '...' : 'retry', style: tw(10, color: Tw.amber400, decoration: TextDecoration.underline)),
              ),
          ]),
          const SizedBox(height: 6),
          Text.rich(TextSpan(style: tw(12, color: Tw.slate500), children: [
            const TextSpan(text: 'UID: '),
            TextSpan(text: '${uid.length > 12 ? uid.substring(0, 12) : uid}...', style: tw(12, color: Tw.slate300).copyWith(fontFamily: 'monospace')),
            TextSpan(text: ' · $cities · Split: '),
            TextSpan(text: '${mp['splitPct']}%', style: tw(12, color: Tw.fuchsia300).copyWith(fontFamily: 'monospace')),
            if (created != null) TextSpan(text: ' · ${created.day}/${created.month}/${created.year}'),
          ])),
          if ((mp['notes'] as String?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(mp['notes'] as String, style: tw(12, color: Tw.slate600, style: FontStyle.italic)),
            ),
          const SizedBox(height: 12),
          active
              ? AdminButton(label: context.t('super_admin.suspend', fallback: 'Suspender'), color: Tw.red400, outlined: true, onTap: () => _suspend(id))
              : AdminButton(label: context.t('super_admin.reactivate', fallback: 'Reactivar'), color: Tw.green400, outlined: true, onTap: () => _reactivate(id)),
        ]),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Label(text, color: color, weight: bold),
      );
}

/// Suspend modal: reason (min 5 chars) → suspendMasterPartner; pops with the reason on success.
class _SuspendDialog extends StatefulWidget {
  final String title, desc, placeholder, cancel, confirm;
  final Future<void> Function(String reason) onConfirm;
  const _SuspendDialog({
    required this.title,
    required this.desc,
    required this.placeholder,
    required this.cancel,
    required this.confirm,
    required this.onConfirm,
  });

  @override
  State<_SuspendDialog> createState() => _SuspendDialogState();
}

class _SuspendDialogState extends State<_SuspendDialog> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Tw.slate900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Tw.red500.withValues(alpha: 0.3))),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.title, style: tw(18, weight: black, color: Tw.red400)),
            const SizedBox(height: 12),
            Text(widget.desc, style: tw(14, color: Tw.slate400)),
            const SizedBox(height: 16),
            TextField(controller: _reason, maxLines: 4, style: tw(14), decoration: adminInputDecoration(widget.placeholder, focus: Tw.red500)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.cancel, style: tw(14, color: Tw.slate400))),
              const SizedBox(width: 8),
              Flexible(
                child: AdminButton(
                  label: widget.confirm,
                  color: Tw.red600,
                  loading: _busy,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  onTap: _busy || _reason.text.trim().length < 5
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await widget.onConfirm(_reason.text.trim());
                            if (context.mounted) Navigator.of(context).pop(_reason.text.trim());
                          } catch (e) {
                            if (context.mounted) showToast(context, errorMessage(e, 'Error suspending MP'), error: true);
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                ),
              ),
            ]),
          ]),
        ),
      );
}
