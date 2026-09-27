import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/address_autocomplete.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';
import '../../../widgets/location_picker.dart';

/// Email → exact match; otherwise nick prefix search (hooks/useVenues.ts searchUserByTerm).
Future<List<Map<String, dynamic>>> searchUserByTerm(String term) async {
  final t = term.trim();
  if (t.isEmpty) return [];
  final users = FirebaseFirestore.instance.collection('users');
  final QuerySnapshot<Map<String, dynamic>> snap;
  if (t.contains('@')) {
    snap = await users.where('email', isEqualTo: t.toLowerCase()).get();
  } else {
    final end = t.substring(0, t.length - 1) + String.fromCharCode(t.codeUnitAt(t.length - 1) + 1);
    snap = await users.where('nick', isGreaterThanOrEqualTo: t).where('nick', isLessThan: end).get();
  }
  return [for (final d in snap.docs) {'id': d.id, ...d.data()}];
}

/// Port of features/super-admin/VenuesPanel.tsx + hooks/useVenues.ts
class VenuesPanel extends StatefulWidget {
  const VenuesPanel({super.key});

  @override
  State<VenuesPanel> createState() => _VenuesPanelState();
}

class _VenuesPanelState extends State<VenuesPanel> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _venues = [];
  Map<String, Map<String, dynamic>> _owners = {};
  bool _loading = true;
  bool _saving = false;

  final _name = TextEditingController();
  final _address = TextEditingController();
  final _desc = TextEditingController();
  String _type = 'club';
  String _city = 'madrid';
  double? _lat;
  double? _lng;
  final _picker = LocationPickerController();
  int _pickerKey = 0;

  Map<String, dynamic>? _selectedOwner;
  final _ownerSearch = TextEditingController();
  List<Map<String, dynamic>> _ownerResults = [];
  bool _searchingOwner = false;

  String? _assigningVenueId;
  final _assignSearch = TextEditingController();
  List<Map<String, dynamic>> _assignResults = [];
  bool _searchingAssign = false;

  I18n get _i18n => context.read<I18n>();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _desc, _ownerSearch, _assignSearch]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final snap = await _db.collection('venues').limit(100).get();
      final venues = [for (final d in snap.docs) <String, dynamic>{'id': d.id, ...d.data()}];
      final ownerIds = {for (final v in venues) if (v['ownerId'] is String && (v['ownerId'] as String).isNotEmpty) v['ownerId'] as String}.toList();
      final owners = <String, Map<String, dynamic>>{};
      for (var i = 0; i < ownerIds.length; i += 30) {
        final chunk = ownerIds.sublist(i, (i + 30).clamp(0, ownerIds.length));
        final s = await _db.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
        for (final d in s.docs) {
          owners[d.id] = d.data();
        }
      }
      if (!mounted) return;
      setState(() {
        _venues = venues;
        _owners = owners;
      });
    } catch (e) {
      debugPrint('Error fetching venues: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_name.text.isEmpty || _lat == null || _lng == null) {
      showToast(context, _i18n.t('admin.venues.required_fields'), error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await callFn('adminCreateVenue', {
        'name': _name.text,
        'type': _type,
        'description': _desc.text,
        'address': _address.text,
        'cityId': _city,
        'latitude': _lat,
        'longitude': _lng,
        if (_selectedOwner != null) 'ownerId': _selectedOwner!['id'],
      });
      await _fetch();
      _name.clear();
      _address.clear();
      _desc.clear();
      _ownerSearch.clear();
      setState(() {
        _lat = null;
        _lng = null;
        _selectedOwner = null;
        _ownerResults = [];
        _pickerKey++;
      });
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('admin.venues.error'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id, String name) async {
    if (!await confirmDialog(context,
        message: _i18n.t('admin.venues.confirm_delete', params: {'name': name}), danger: true, confirmText: _i18n.t('admin.venues.delete_btn'))) {
      return;
    }
    try {
      await callFn('deleteVenue', {'venueId': id});
      await _fetch();
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('admin.venues.error'), error: true);
    }
  }

  Future<void> _assign(String venueId, Map<String, dynamic> user) async {
    if (!await confirmDialog(context,
        message: _i18n.t('admin.venues.confirm_assign_owner', params: {'user': user['nick'] ?? user['email']}),
        confirmText: _i18n.t('admin.venues.assign_btn'))) {
      return;
    }
    try {
      await callFn('assignRole', {'uid': user['id'], 'role': 'venueOwner'});
      await _db.collection('venues').doc(venueId).update({'ownerId': user['id']});
      await _db.collection('users').doc(user['id'] as String).update({'role': 'venueOwner', 'venueId': venueId});
      await _fetch();
      if (mounted) showToast(context, _i18n.t('admin.venues.assign_success'));
      setState(() {
        _assigningVenueId = null;
        _assignSearch.clear();
        _assignResults = [];
      });
    } catch (_) {
      if (mounted) showToast(context, _i18n.t('admin.venues.error'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return AdminEmpty(context.t('super_admin.venues_loading'), loading: true);
    const types = ['club', 'bar', 'sauna', 'cruising', 'restaurant', 'hotel', 'shop', 'other'];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle(context.t('super_admin.create_venue_title')),
          const SizedBox(height: 16),
          AdminInput(controller: _name, hint: context.t('super_admin.venue_name_placeholder')),
          const SizedBox(height: 12),
          AddressAutocomplete(
            controller: _address,
            placeholder: context.t('super_admin.venue_address_placeholder'),
            onSelect: (r) {
              setState(() {
                _lat = r.lat;
                _lng = r.lng;
              });
              _picker.flyTo(r.lat, r.lng);
            },
          ),
          const SizedBox(height: 12),
          AdminInput(controller: _desc, hint: context.t('super_admin.venue_desc_placeholder')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: AdminSelect<String>(
                value: _type,
                items: [for (final t in types) (t, context.t('super_admin.venue_type_$t'))],
                onChanged: (v) => setState(() => _type = v ?? 'club'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AdminSelect<String>(
                value: _city,
                items: const [('madrid', 'Madrid'), ('barcelona', 'Barcelona'), ('london', 'London')],
                onChanged: (v) => setState(() => _city = v ?? 'madrid'),
              ),
            ),
          ]),
          FieldLabel(context.t('super_admin.venue_location_label')),
          VenueLocationPicker(
            key: ValueKey(_pickerKey),
            controller: _picker,
            onLocationChange: (lat, lng) {
              _lat = lat;
              _lng = lng;
            },
          ),
          FieldLabel(context.t('super_admin.venue_owner_label', fallback: 'Asignar dueño (opcional)')),
          if (_selectedOwner != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Tw.green500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.green500.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${_selectedOwner!['nick'] ?? _selectedOwner!['email']} ', style: tw(14, weight: bold, color: Tw.green400)),
                    TextSpan(text: (_selectedOwner!['email'] as String?) ?? '', style: tw(12, color: Tw.slate500)),
                  ])),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedOwner = null;
                    _ownerResults = [];
                    _ownerSearch.clear();
                  }),
                  child: Text('✕', style: tw(12, weight: bold, color: Tw.red400)),
                ),
              ]),
            )
          else ...[
            _searchRow(_ownerSearch, _searchingOwner, () async {
              if (_ownerSearch.text.trim().isEmpty) return;
              setState(() => _searchingOwner = true);
              try {
                final r = await searchUserByTerm(_ownerSearch.text);
                setState(() => _ownerResults = r);
              } catch (_) {
              } finally {
                if (mounted) setState(() => _searchingOwner = false);
              }
            }),
            for (final u in _ownerResults)
              _userChoice(u, () => setState(() {
                    _selectedOwner = u;
                    _ownerResults = [];
                    _ownerSearch.clear();
                  })),
          ],
          const SizedBox(height: 16),
          AdminButton(
            label: _saving ? context.t('super_admin.creating_venue') : context.t('super_admin.create_venue_btn'),
            expand: true,
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: _saving ? null : _create,
          ),
        ]),
      ),
      const SizedBox(height: 32),
      AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle(context.t('super_admin.venues_directory')),
          const SizedBox(height: 16),
          for (final v in _venues) _venueCard(v),
        ]),
      ),
    ]);
  }

  Widget _searchRow(TextEditingController ctrl, bool busy, VoidCallback onSearch) => Row(children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            style: tw(12),
            onSubmitted: (_) => onSearch(),
            decoration: adminInputDecoration(context.t('super_admin.search_nick_email')).copyWith(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        AdminButton(
          label: context.t('super_admin.search_btn_short'),
          color: Tw.blue600,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: busy ? null : onSearch,
        ),
      ]);

  Widget _userChoice(Map<String, dynamic> u, VoidCallback onChoose) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${u['nick'] ?? ''} ', style: tw(12, weight: bold)),
              TextSpan(text: (u['email'] ?? u['id']) as String, style: tw(12, color: Tw.slate500)),
            ])),
          ),
          AdminButton(
            label: context.t('super_admin.choose_btn'),
            color: Tw.green600,
            fontSize: 10,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            onTap: onChoose,
          ),
        ]),
      );

  Widget _venueCard(Map<String, dynamic> v) {
    final id = v['id'] as String;
    final ownerId = v['ownerId'] as String?;
    final owner = ownerId == null ? null : _owners[ownerId];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((v['name'] as String?) ?? id, style: tw(15, weight: bold)),
              Label('${v['type'] ?? ''} | ${context.t('super_admin.city_label_short')} ${v['cityId'] ?? ''}', color: Tw.slate400, weight: FontWeight.w400),
              if ((v['address'] as String?)?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('📍 ${v['address']}', style: tw(12, color: Tw.slate300)),
                ),
              const SizedBox(height: 6),
              if (ownerId != null && ownerId.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(8)),
                  child: owner != null
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('👤 ${owner['nick'] ?? owner['displayName'] ?? '—'}', style: tw(12, weight: bold)),
                          Text('✉ ${owner['email'] ?? ''}', style: tw(10, color: Tw.slate400)),
                          if ((owner['phone'] as String?)?.isNotEmpty == true) Text('📞 ${owner['phone']}', style: tw(10, color: Tw.slate400)),
                        ])
                      : Text('${context.t('super_admin.owner_label')} $ownerId', style: tw(10, color: Tw.slate500).copyWith(fontFamily: 'monospace')),
                )
              else
                Text(context.t('super_admin.no_owner', fallback: 'Sin dueño asignado'),
                    style: tw(10, weight: bold, color: Tw.orange400.withValues(alpha: 0.7))),
            ]),
          ),
          const SizedBox(width: 8),
          Column(children: [
            AdminButton(
              label: context.t('super_admin.assign_btn'),
              color: Tw.w(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              onTap: () => setState(() => _assigningVenueId = _assigningVenueId == id ? null : id),
            ),
            const SizedBox(height: 6),
            AdminButton(
              label: context.t('super_admin.delete_btn'),
              color: Tw.red900.withValues(alpha: 0.5),
              textColor: Tw.red400,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              onTap: () => _delete(id, (v['name'] as String?) ?? id),
            ),
          ]),
        ]),
        if (_assigningVenueId == id) ...[
          const SizedBox(height: 16),
          Divider(height: 1, color: Tw.w(0.1)),
          const SizedBox(height: 16),
          _searchRow(_assignSearch, _searchingAssign, () async {
            if (_assignSearch.text.trim().isEmpty) return;
            setState(() => _searchingAssign = true);
            try {
              final r = await searchUserByTerm(_assignSearch.text);
              setState(() => _assignResults = r);
            } catch (_) {
              if (mounted) showToast(context, _i18n.t('admin.venues.search_error'), error: true);
            } finally {
              if (mounted) setState(() => _searchingAssign = false);
            }
          }),
          const SizedBox(height: 8),
          for (final u in _assignResults) _userChoice(u, () => _assign(id, u)),
        ],
      ]),
    );
  }
}
