import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';
import '../../../widgets/territory_map_picker.dart';

/// Port of features/super-admin/CitiesPanel.tsx + hooks/useCities.ts
class CitiesPanel extends StatefulWidget {
  const CitiesPanel({super.key});

  @override
  State<CitiesPanel> createState() => _CitiesPanelState();
}

class _CitiesPanelState extends State<CitiesPanel> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _cities = [];
  bool _loading = true;
  bool _saving = false;

  String? _editingStripeCity;
  final _stripeEditCtrl = TextEditingController();

  final _slug = TextEditingController();
  final _name = TextEditingController();
  final _partnerName = TextEditingController();
  final _partnerEmail = TextEditingController();
  final _stripeId = TextEditingController();
  final _annualFee = TextEditingController(text: '5000');
  final _managerEmail = TextEditingController();
  List<List<double>>? _polygon;
  int _pickerKey = 0;

  I18n get _i18n => context.read<I18n>();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    for (final c in [_stripeEditCtrl, _slug, _name, _partnerName, _partnerEmail, _stripeId, _annualFee, _managerEmail]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final snap = await _db.collection('cities').limit(100).get();
      final withCounts = await Future.wait(snap.docs.map((d) async {
        var count = 0;
        try {
          final c = await _db.collection('venues').where('cityId', isEqualTo: d.id).count().get();
          count = c.count ?? 0;
        } catch (_) {}
        return <String, dynamic>{'id': d.id, ...d.data(), 'activeVenuesCount': count};
      }));
      if (mounted) setState(() => _cities = withCounts);
    } catch (e) {
      debugPrint('Error fetching cities: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    try {
      final slug = _slug.text.toLowerCase();
      if (slug.isEmpty || _name.text.isEmpty || _annualFee.text.isEmpty) throw Exception(_i18n.t('admin.cities.error_required'));

      Map<String, dynamic>? manager;
      final managerEmail = _managerEmail.text;
      if (managerEmail.isNotEmpty) {
        final s = await _db.collection('users').where('email', isEqualTo: managerEmail.toLowerCase().trim()).get();
        if (s.docs.isEmpty) throw Exception(_i18n.t('admin.cities.error_manager_not_found', params: {'email': managerEmail}));
        manager = {'id': s.docs.first.id, ...s.docs.first.data()};
      }

      List<List<double>>? closed;
      final poly = _polygon;
      if (poly != null && poly.length >= 3) {
        closed = [...poly, poly.first];
        final v = validatePolygon(closed);
        if (!v.valid) throw Exception(_i18n.t('admin.cities.error_invalid_polygon', params: {'error': v.error}));
      }

      final now = DateTime.now();
      final nextYear = DateTime(now.year + 1, now.month, now.day, now.hour, now.minute, now.second);
      await _db.collection('cities').doc(slug).set({
        'city_slug': slug,
        'name': _name.text,
        'isActive': true,
        'partner_name': manager != null ? (manager['nick'] ?? manager['name'] ?? 'Sin nombre') : _partnerName.text,
        'partner_email': manager != null ? manager['email'] : _partnerEmail.text,
        'partnerId': manager?['id'],
        'partner_stripe_account_id': _stripeId.text,
        // Same shape as the web: Firestore rejects nested arrays, so the ring is stored as {lng, lat} maps.
        if (closed != null) 'territory': {'type': 'Polygon', 'points': [for (final p in closed) {'lng': p[0], 'lat': p[1]}]},
        'license': {
          'annual_fee': int.tryParse(_annualFee.text) ?? 0,
          'status': 'active',
          'valid_from': now.toUtc().toIso8601String(),
          'expires_at': nextYear.toUtc().toIso8601String(),
          'auto_renew': true,
        },
      });
      if (manager != null) await callFn('assignRole', {'uid': manager['id'], 'role': 'cityAdmin', 'cityId': slug});
      if (closed != null) {
        try {
          await callFn('updateCityTerritory', {'cityId': slug, 'polygon': closed});
        } catch (e) {
          debugPrint('updateCityTerritory: $e');
        }
      }
      await _fetch();
      for (final c in [_slug, _name, _partnerName, _partnerEmail, _stripeId, _managerEmail]) {
        c.clear();
      }
      _annualFee.text = '5000';
      setState(() {
        _polygon = null;
        _pickerKey++;
      });
      if (mounted) showToast(context, _i18n.t('super_admin.city_created_success'));
    } catch (e) {
      if (mounted) showToast(context, _i18n.t('admin.cities.error'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateStripe(String cityId, String acct) async {
    if (!await confirmDialog(context,
        message: _i18n.t('admin.cities.confirm_stripe', params: {'city': cityId, 'stripe': acct}), confirmText: _i18n.t('admin.cities.save_btn'))) {
      return;
    }
    try {
      await _db.collection('cities').doc(cityId).set({'partner_stripe_account_id': acct.isEmpty ? null : acct}, SetOptions(merge: true));
      if (mounted) showToast(context, _i18n.t('admin.cities.stripe_updated'));
      await _fetch();
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('admin.cities.error'), error: true);
    }
  }

  Future<void> _delete(String cityId) async {
    if (cityId == 'madrid') {
      showToast(context, _i18n.t('super_admin.cannot_delete_parent'), error: true);
      return;
    }
    if (!await confirmDialog(context,
        message: '¿Eliminar la ciudad "$cityId" y su licencia? Esta acción no se puede deshacer.',
        danger: true,
        confirmText: _i18n.t('super_admin.delete_btn'))) {
      return;
    }
    try {
      await _db.collection('cities').doc(cityId).delete();
      if (mounted) showToast(context, _i18n.t('super_admin.city_deleted'));
      await _fetch();
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('admin.cities.error'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return AdminEmpty(context.t('super_admin.cities_loading'), loading: true);
    final hot = _cities.where((c) => c['readyForFranchise'] == true).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hot.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Tw.red600, Tw.orange500]),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Tw.red400.withValues(alpha: 0.5), width: 2),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🚨', style: TextStyle(fontSize: 36)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('super_admin.territories_ready_title'), style: tw(20, weight: black, height: 1)),
                const SizedBox(height: 4),
                Text(context.t('super_admin.territories_ready_desc'), style: tw(14, weight: medium, color: const Color(0xE6FEE2E2))),
                const SizedBox(height: 16),
                for (final c in hot)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(child: Text(_capitalize((c['slug'] ?? c['id']) as String), style: tw(14, weight: bold))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(8)),
                        child: Text(context.t('super_admin.venues_count', count: asIntOr0(c['activeVenuesCount'])),
                            style: tw(12, weight: black, color: Tw.red600)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 32),
      ],
      AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle(context.t('super_admin.activate_license')),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: AdminInput(controller: _slug, hint: context.t('super_admin.city_slug_placeholder'))),
            const SizedBox(width: 12),
            Expanded(child: AdminInput(controller: _name, hint: context.t('super_admin.city_name_placeholder'))),
          ]),
          const SizedBox(height: 12),
          AdminInput(controller: _managerEmail, hint: context.t('super_admin.cm_email_placeholder'), keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          AdminInput(controller: _partnerName, hint: context.t('super_admin.partner_name_placeholder')),
          const SizedBox(height: 12),
          AdminInput(controller: _partnerEmail, hint: context.t('super_admin.partner_email_placeholder'), keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          AdminInput(controller: _stripeId, hint: context.t('super_admin.stripe_id_placeholder'), focus: Tw.blue500),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
            child: Row(children: [
              Text(context.t('super_admin.annual_fee_label'), style: tw(14, color: Tw.slate400)),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _annualFee,
                  keyboardType: TextInputType.number,
                  style: tw(14, weight: bold, color: Tw.green400).copyWith(fontFamily: 'monospace'),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                ),
              ),
            ]),
          ),
          FieldLabel(context.t('super_admin.territory_label')),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Tw.orange500.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Tw.orange500.withValues(alpha: 0.2)),
            ),
            child: Text.rich(TextSpan(style: tw(10, color: const Color(0xFFFED7AA)), children: [
              TextSpan(text: 'Importante: ', style: tw(10, weight: bold, color: const Color(0xFFFED7AA))),
              const TextSpan(
                  text: 'El polígono se guarda para uso visual en la app. La jurisdicción real se asigna por texto (Match Regions) en el panel de Partners.'),
            ])),
          ),
          const SizedBox(height: 8),
          Text(context.t('super_admin.territory_hint'), style: tw(10, color: Tw.slate500)),
          const SizedBox(height: 8),
          TerritoryMapPicker(key: ValueKey(_pickerKey), onPolygonChange: (p) => _polygon = p),
          const SizedBox(height: 16),
          AdminButton(
            label: context.t('super_admin.create_franchise_btn'),
            expand: true,
            loading: _saving,
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: _saving ? null : _create,
          ),
        ]),
      ),
      const SizedBox(height: 32),
      AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle(context.t('super_admin.operating_cities')),
          const SizedBox(height: 16),
          for (final c in _cities) _cityCard(c),
        ]),
      ),
    ]);
  }

  Widget _cityCard(Map<String, dynamic> c) {
    final id = c['id'] as String;
    final isMadrid = id == 'madrid';
    final license = c['license'] is Map ? Map<String, dynamic>.from(c['license'] as Map) : null;
    final isActive = license?['status'] == 'active';
    final territory = c['territory'] is Map ? c['territory'] as Map : null;
    final points = territory?['points'];
    final vertexCount = points is List && points.isNotEmpty ? points.length - 1 : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isMadrid ? Tw.fuchsia500.withValues(alpha: 0.5) : Tw.w(0.05)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text((c['name'] ?? id) as String, style: tw(18, weight: bold)),
              if (isMadrid)
                AdminBadge(context.t('super_admin.direct_parent'), color: Tw.fuchsia400)
              else
                AdminBadge((license?['status'] as String?) ?? context.t('super_admin.no_license'), color: isActive ? Tw.green400 : Tw.red400),
            ]),
          ),
          if (!isMadrid)
            GestureDetector(
              onTap: () => _delete(id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Tw.red500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
                ),
                child: Text(context.t('super_admin.delete_city_btn'), style: tw(9, color: Tw.red400)),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Text.rich(TextSpan(style: tw(11, color: Tw.slate400), children: [
          const TextSpan(text: 'Partner: '),
          TextSpan(text: (c['partner_name'] as String?) ?? context.t('super_admin.nobody'), style: tw(11)),
          TextSpan(text: ' (${(c['partner_email'] as String?) ?? context.t('super_admin.no_email')})'),
        ])),
        const SizedBox(height: 4),
        if (_editingStripeCity == id)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _stripeEditCtrl,
                style: tw(12),
                decoration: adminInputDecoration('acct_...', focus: Tw.blue500),
              ),
            ),
            const SizedBox(width: 6),
            AdminButton(
              label: 'OK',
              color: Tw.blue600,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onTap: () async {
                await _updateStripe(id, _stripeEditCtrl.text);
                if (mounted) setState(() => _editingStripeCity = null);
              },
            ),
            const SizedBox(width: 4),
            AdminButton(
              label: 'X',
              color: Tw.w(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onTap: () => setState(() => _editingStripeCity = null),
            ),
          ])
        else
          Row(children: [
            Flexible(
              child: Text('Stripe: ${(c['partner_stripe_account_id'] as String?)?.isNotEmpty == true ? c['partner_stripe_account_id'] : context.t('super_admin.not_linked')}',
                  style: tw(10, color: const Color(0xFF93C5FD)).copyWith(fontFamily: 'monospace')),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() {
                _editingStripeCity = id;
                _stripeEditCtrl.text = (c['partner_stripe_account_id'] as String?) ?? '';
              }),
              child: Text(context.t('super_admin.edit_btn'), style: tw(10, color: Tw.blue400)),
            ),
          ]),
        if (!isMadrid && license != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(style: tw(10, color: Tw.slate400), children: [
                TextSpan(text: '${context.t('super_admin.fee_label')} '),
                TextSpan(text: '${license['annual_fee']}€', style: tw(10, weight: bold, color: Tw.green400).copyWith(fontFamily: 'monospace')),
              ])),
              Text(
                '${context.t('super_admin.expires_label')} ${license['expires_at'] != null ? shortDate(license['expires_at']) : context.t('super_admin.no_date')}',
                style: tw(10, color: Tw.slate400),
              ),
            ]),
          ),
        if (territory != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.pentagon, size: 12, color: Tw.fuchsia400),
              const SizedBox(width: 4),
              Text(context.t('super_admin.territory_defined', count: vertexCount), style: tw(10, weight: bold, color: Tw.fuchsia400)),
            ]),
          ),
        if (!isMadrid)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4), border: Border.all(color: Tw.w(0.05))),
            child: Text(context.t('super_admin.assign_partner_hint'), style: tw(9, color: Tw.slate500)),
          ),
      ]),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

int asIntOr0(Object? v) => v is num ? v.toInt() : 0;
