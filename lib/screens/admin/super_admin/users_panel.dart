import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../navigation.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/social.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

enum UsersPanelMode { users, roles }

class _RoleOption {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final String redirect;
  const _RoleOption(this.value, this.label, this.icon, this.color, this.redirect);
}

const _roleOptions = [
  _RoleOption('venueOwner', 'Venue Manager', Icons.storefront, Tw.blue400, '/venue-admin'),
  _RoleOption('cityAdmin', 'City Manager', Icons.location_city, Tw.green400, '/city-manager'),
  _RoleOption('admin', 'Admin', Icons.admin_panel_settings, Tw.purple400, '/admin'),
  _RoleOption('superadmin', 'Super Admin', Icons.local_police, Tw.red400, '/super-admin'),
  _RoleOption('rrpp', 'RRPP', Icons.badge, Tw.fuchsia400, '/'),
  _RoleOption('door', 'Puerta', Icons.meeting_room, Tw.orange400, '/door'),
];

/// Port of features/super-admin/UsersPanel.tsx + hooks/useUsers.ts ("usuarios" and "roles" tabs).
class UsersPanel extends StatefulWidget {
  final UsersPanelMode mode;
  final List<Map<String, dynamic>> cities;
  final List<Map<String, dynamic>> venues;
  const UsersPanel({super.key, required this.mode, required this.cities, required this.venues});

  @override
  State<UsersPanel> createState() => _UsersPanelState();
}

class _UsersPanelState extends State<UsersPanel> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _assignments = [];
  bool _loadingUsers = false;

  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  Map<String, dynamic>? _selected;
  bool _actionLoading = false;

  Map<String, dynamic>? _roleResult;
  bool _roleSearching = false;
  bool _assigning = false;

  final _searchCtrl = TextEditingController();
  final _roleEmailCtrl = TextEditingController();
  String _filterCity = 'all';
  String _selectedRole = '';
  String _roleCityId = '';
  String _roleVenueId = '';
  String? _ownerVenueId;

  I18n get _i18n => context.read<I18n>();

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _roleEmailCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(QuerySnapshot<Map<String, dynamic>> s) => [for (final d in s.docs) {'id': d.id, ...d.data()}];

  Future<void> _fetchUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final roles = await _db
          .collection('users')
          .where('role', whereIn: ['venueOwner', 'cityAdmin', 'admin', 'superadmin', 'rrpp', 'door'])
          .limit(100)
          .get();
      final all = await _db.collection('users').orderBy('createdAt', descending: true).limit(150).get();
      if (!mounted) return;
      setState(() {
        _assignments = _rows(roles);
        _allUsers = _rows(all);
      });
    } catch (e) {
      debugPrint('Error fetching users: $e');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  void _toast(String key, {bool error = false, Map<String, Object?>? params}) {
    if (mounted) showToast(context, _i18n.t(key, params: params), error: error);
  }

  Future<void> _search() async {
    final q = _searchCtrl.text;
    if (q.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _selected = null;
    });
    try {
      var results = _rows(await _db.collection('users').where('email', isEqualTo: q.toLowerCase().trim()).get());
      if (results.isEmpty) {
        // Prefix search on nick: [q, q with last char + 1).
        final end = q.substring(0, q.length - 1) + String.fromCharCode(q.codeUnitAt(q.length - 1) + 1);
        results = _rows(await _db.collection('users').where('nick', isGreaterThanOrEqualTo: q).where('nick', isLessThan: end).get());
      }
      setState(() => _searchResults = results);
      if (results.isEmpty) _toast('admin.users.search_not_found');
    } catch (_) {
      _toast('admin.users.search_error', error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _roleSearch() async {
    final email = _roleEmailCtrl.text;
    if (email.trim().isEmpty) return;
    setState(() {
      _roleSearching = true;
      _roleResult = null;
    });
    try {
      final snap = await _db.collection('users').where('email', isEqualTo: email.toLowerCase().trim()).get();
      if (snap.docs.isEmpty) {
        _toast('admin.users.role_search_empty');
      } else {
        setState(() => _roleResult = {'id': snap.docs.first.id, ...snap.docs.first.data()});
      }
    } catch (_) {
      _toast('admin.users.search_error', error: true);
    } finally {
      if (mounted) setState(() => _roleSearching = false);
    }
  }

  Future<void> _assignRole() async {
    final u = _roleResult;
    if (u == null || _selectedRole.isEmpty) return;
    setState(() => _assigning = true);
    try {
      final params = <String, Object?>{'uid': u['id'], 'role': _selectedRole};
      if (_selectedRole == 'cityAdmin' && _roleCityId.isNotEmpty) {
        params['cityId'] = _roleCityId;
        await _db.collection('cities').doc(_roleCityId).update({
          'partnerId': u['id'],
          'partner_email': u['email'],
          'partner_name': u['nick'] ?? u['name'] ?? 'Sin nombre',
        });
      }
      if (_selectedRole == 'venueOwner' && _roleVenueId.isNotEmpty) {
        await _db.collection('venues').doc(_roleVenueId).update({'ownerId': u['id']});
      }
      await callFn('assignRole', params);
      _toast('admin.users.role_assigned', params: {'role': _selectedRole, 'email': u['email']});
      setState(() => _roleResult = {...u, 'role': _selectedRole});
      await _fetchUsers();
    } catch (_) {
      _toast('admin.users.error', error: true);
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _revokeRole(String uid, String email) async {
    if (!await confirmDialog(context,
        message: _i18n.t('admin.users.confirm_revoke', params: {'email': email}), danger: true, confirmText: _i18n.t('admin.users.revoke_btn'))) {
      return;
    }
    try {
      await callFn('assignRole', {'uid': uid, 'role': 'user'});
      _toast('admin.users.role_revoked');
      await _fetchUsers();
    } catch (_) {
      _toast('admin.users.error', error: true);
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _actionLoading = true);
    try {
      await action();
    } catch (_) {
      _toast('admin.users.error', error: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _deleteUser(String uid) async {
    if (!await confirmDialog(context,
        message: _i18n.t('admin.users.confirm_delete'), danger: true, confirmText: _i18n.t('admin.users.delete_btn'))) {
      return;
    }
    await _runAction(() async {
      await callFn('adminDeleteUser', {'uid': uid});
      _toast('admin.users.delete_success');
      setState(() {
        _selected = null;
        _searchResults.removeWhere((u) => u['id'] == uid);
        _allUsers.removeWhere((u) => u['id'] == uid);
      });
    });
  }

  Future<void> _fastTrackRrpp(String uid) async {
    if (!await confirmDialog(context,
        message: _i18n.t('admin.users.confirm_fasttrack_rrpp'), confirmText: _i18n.t('admin.users.confirm_btn'))) {
      return;
    }
    await _runAction(() async {
      try {
        await callFn('approveRRPP', {'applicationId': uid, 'action': 'approve'});
      } catch (_) {
        await callFn('assignRole', {'uid': uid, 'role': 'rrpp'});
      }
      _toast('admin.users.fasttrack_rrpp_success');
      setState(() {
        _selected = {...?_selected, 'role': 'rrpp'};
        _allUsers = [for (final u in _allUsers) u['id'] == uid ? {...u, 'role': 'rrpp'} : u];
      });
    });
  }

  Future<void> _banUser(String uid) async {
    final reason = await promptInput(context,
        message: _i18n.t('admin.users.ban_reason_prompt'),
        placeholder: _i18n.t('admin.users.ban_reason_placeholder'),
        confirmText: _i18n.t('admin.users.ban_btn'));
    if (reason == null) return;
    await _runAction(() async {
      await callFn('banUser', {'uid': uid, 'reason': reason});
      _toast('admin.users.ban_success');
      setState(() => _selected = _selected == null ? null : {..._selected!, 'banned': true, 'bannedReason': reason});
    });
  }

  Future<void> _updateCity(String uid, String cityId) async {
    if (!await confirmDialog(context,
        message: _i18n.t('admin.users.confirm_update_city', params: {'city': cityId.isEmpty ? _i18n.t('admin.users.none') : cityId}),
        confirmText: _i18n.t('admin.users.assign_btn'))) {
      return;
    }
    await _runAction(() async {
      await _db.collection('users').doc(uid).update({'city': cityId, 'cityId': cityId});
      _toast('admin.users.update_city_success');
      setState(() {
        _selected = _selected == null ? null : {..._selected!, 'city': cityId, 'cityId': cityId};
        _allUsers = [for (final u in _allUsers) u['id'] == uid ? {...u, 'city': cityId, 'cityId': cityId} : u];
      });
    });
  }

  Future<void> _assignVenueOwner() async {
    final venueId = _ownerVenueId;
    if (venueId == null || venueId.isEmpty) {
      _toast('super_admin.select_venue_prompt');
      return;
    }
    final u = _selected!;
    final venueName = widget.venues.where((v) => v['id'] == venueId).firstOrNull?['name'] ?? venueId;
    if (!await confirmDialog(context,
        message: _i18n.t('admin.users.confirm_assign_owner', params: {'user': u['nick'] ?? u['email'], 'venue': venueName}),
        confirmText: _i18n.t('admin.users.assign_btn'))) {
      return;
    }
    await _runAction(() async {
      await callFn('assignRole', {'uid': u['id'], 'role': 'venueOwner'});
      await _db.collection('venues').doc(venueId).update({'ownerId': u['id']});
      await _db.collection('users').doc(u['id'] as String).update({'role': 'venueOwner', 'venueId': venueId});
      _toast('admin.users.assign_owner_success');
      setState(() => _selected = {...u, 'role': 'venueOwner', 'venueId': venueId});
    });
  }

  Future<void> _sendDm() async {
    final me = context.read<AuthProvider>().user;
    final u = _selected;
    if (me == null || u == null) return;
    final chatId = await getOrCreateChat(me.uid, u['id'] as String);
    if (mounted) openRoute(context, AppRoute.chatDetail, args: {'id': chatId});
  }

  @override
  Widget build(BuildContext context) => widget.mode == UsersPanelMode.users ? _usersTab(context) : _rolesTab(context);

  // ─── Usuarios ───
  Widget _usersTab(BuildContext context) {
    final filtered = _allUsers.where((u) => _filterCity == 'all' || (u['city'] ?? u['cityId']) == _filterCity).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle(context.t('super_admin.search_users')),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: AdminInput(controller: _searchCtrl, hint: context.t('super_admin.email_nick_placeholder'), onSubmitted: (_) => _search())),
            const SizedBox(width: 8),
            AdminButton(
              label: _searching ? context.t('super_admin.searching') : context.t('super_admin.search_btn'),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              onTap: _searching ? null : _search,
            ),
          ]),
          const SizedBox(height: 24),
          if (_searchResults.isNotEmpty) ...[
            Label('${context.t('super_admin.search_results')} (${_searchResults.length})', size: 12, weight: bold, color: Tw.fuchsia400),
            const SizedBox(height: 8),
            for (final u in _searchResults) _userRow(u, showCity: false),
          ] else ...[
            Row(children: [
              Expanded(child: Label(context.t('super_admin.latest_registrations'), size: 12, weight: bold)),
              AdminSelect<String>(
                dense: true,
                value: _filterCity,
                items: [('all', context.t('super_admin.all_cities')), for (final c in widget.cities) (c['id'] as String, (c['name'] ?? c['id']) as String)],
                onChanged: (v) => setState(() => _filterCity = v ?? 'all'),
              ),
            ]),
            const SizedBox(height: 16),
            Divider(height: 1, color: Tw.w(0.1)),
            const SizedBox(height: 16),
            if (_loadingUsers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(context.t('super_admin.loading_users'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
              )
            else
              for (final u in filtered) _userRow(u, showCity: true),
          ],
        ]),
      ),
      const SizedBox(height: 32),
      _detail(context),
    ]);
  }

  Widget _userRow(Map<String, dynamic> u, {required bool showCity}) {
    final active = _selected?['id'] == u['id'];
    final city = (u['city'] ?? u['cityId']) as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        onTap: () => setState(() {
          _selected = u;
          _ownerVenueId = null;
        }),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: active ? Tw.fuchsia500.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? Tw.fuchsia500.withValues(alpha: 0.5) : Tw.w(0.05)),
          ),
          child: Row(children: [
            ClipOval(child: NetImage(avatarUrl(u), width: 40, height: 40)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text((u['nick'] as String?) ?? context.t('super_admin.no_nick'),
                        overflow: TextOverflow.ellipsis, style: tw(14, weight: bold)),
                  ),
                  if (u['banned'] == true) ...[
                    const SizedBox(width: 8),
                    AdminBadge(context.t('super_admin.banned'), color: Tw.red400, background: Tw.red900.withValues(alpha: 0.3)),
                  ],
                ]),
                Text((u['email'] as String?) ?? '', overflow: TextOverflow.ellipsis, style: tw(10, color: Tw.slate400)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              AdminBadge((u['role'] as String?) ?? 'user', color: Tw.slate500, background: Tw.w(0.05)),
              if (showCity && city != null && city.isNotEmpty) ...[
                const SizedBox(height: 4),
                AdminBadge(city, color: Tw.blue400, background: Tw.blue900.withValues(alpha: 0.2)),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context) {
    final u = _selected;
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AdminSectionTitle(context.t('super_admin.user_detail')),
        const SizedBox(height: 24),
        if (u == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(context.t('super_admin.select_user_prompt'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
          )
        else ...[
          Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(16), child: NetImage(avatarUrl(u), width: 96, height: 96)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((u['nick'] as String?) ?? context.t('super_admin.no_nick'), style: tw(24, weight: black)),
                Text((u['email'] as String?) ?? '', style: tw(14, color: Tw.slate400)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  AdminBadge((u['role'] as String?) ?? 'user', color: Tw.white, background: Tw.w(0.1)),
                  if (u['premium'] == true) AdminBadge('Premium', color: Tw.yellow500),
                  if (u['banned'] == true) AdminBadge(context.t('super_admin.banned'), color: Tw.red400, background: Tw.red900.withValues(alpha: 0.3)),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
          AdminGrid(children: [
            _infoBox('ID (UID)', Text(u['id'] as String, style: tw(12, color: Tw.slate300).copyWith(fontFamily: 'monospace'))),
            _infoBox(
              context.t('super_admin.created_date'),
              Text(u['createdAt'] != null ? shortDate(u['createdAt']) : context.t('super_admin.unknown'), style: tw(12, color: Tw.slate300)),
            ),
            _infoBox(context.t('super_admin.phone'),
                Text((u['phone'] as String?) ?? context.t('super_admin.not_registered'), style: tw(12, color: Tw.slate300))),
            _infoBox(
              context.t('super_admin.rrpp_city'),
              AdminSelect<String>(
                dense: true,
                value: (u['city'] ?? u['cityId'] ?? '') as String,
                items: [('', context.t('super_admin.no_city')), for (final c in widget.cities) (c['id'] as String, (c['name'] ?? c['id']) as String)],
                onChanged: _actionLoading ? null : (v) => _updateCity(u['id'] as String, v ?? ''),
              ),
            ),
          ]),
          const SizedBox(height: 32),
          Label(context.t('super_admin.moderation_actions'), size: 12, weight: bold, color: Tw.slate500),
          const SizedBox(height: 8),
          Divider(height: 1, color: Tw.w(0.1)),
          const SizedBox(height: 12),
          _action(Icons.chat, context.t('super_admin.send_dm'), Tw.white, Tw.w(0.05), Tw.w(0.1), _sendDm),
          _action(
            Icons.assignment_ind,
            u['role'] == 'rrpp' ? context.t('super_admin.already_rrpp') : context.t('super_admin.convert_to_rrpp'),
            Tw.fuchsia400,
            Tw.fuchsia900.withValues(alpha: 0.2),
            Tw.fuchsia500.withValues(alpha: 0.2),
            _actionLoading || u['role'] == 'rrpp' ? null : () => _fastTrackRrpp(u['id'] as String),
          ),
          AdminSelect<String>(
            value: _ownerVenueId,
            hint: context.t('super_admin.select_venue_prompt'),
            items: [for (final v in widget.venues) (v['id'] as String, '${v['name'] ?? v['id']} (${v['cityId'] ?? 'sin ciudad'})')],
            onChanged: (v) => setState(() => _ownerVenueId = v),
          ),
          const SizedBox(height: 8),
          _action(
            Icons.storefront,
            u['role'] == 'venueOwner' ? context.t('super_admin.already_venue_owner') : context.t('super_admin.convert_to_venue_owner'),
            Tw.blue400,
            Tw.blue900.withValues(alpha: 0.2),
            Tw.blue500.withValues(alpha: 0.2),
            _actionLoading || u['role'] == 'venueOwner' ? null : _assignVenueOwner,
          ),
          _action(
            Icons.block,
            u['banned'] == true ? context.t('super_admin.user_already_banned') : context.t('super_admin.ban_user'),
            Tw.orange400,
            Tw.orange900.withValues(alpha: 0.2),
            Tw.orange500.withValues(alpha: 0.2),
            _actionLoading || u['banned'] == true ? null : () => _banUser(u['id'] as String),
          ),
          _action(
            Icons.delete_forever,
            context.t('super_admin.delete_account_permanently'),
            Tw.red400,
            Tw.red900.withValues(alpha: 0.2),
            Tw.red500.withValues(alpha: 0.3),
            _actionLoading ? null : () => _deleteUser(u['id'] as String),
          ),
        ],
      ]),
    );
  }

  Widget _infoBox(String label, Widget value) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(label, color: Tw.slate500, weight: bold),
          const SizedBox(height: 4),
          value,
        ]),
      );

  Widget _action(IconData icon, String label, Color fg, Color bg, Color border, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Pressable(
            onTap: onTap ?? () {},
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 8),
                Flexible(child: Text(label, textAlign: TextAlign.center, style: tw(14, weight: bold, color: fg))),
              ]),
            ),
          ),
        ),
      );

  // ─── Roles ───
  Widget _rolesTab(BuildContext context) {
    final r = _roleResult;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle(context.t('super_admin.assign_role_by_email')),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: AdminInput(
                controller: _roleEmailCtrl,
                hint: context.t('super_admin.email_user_placeholder'),
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => _roleSearch(),
              ),
            ),
            const SizedBox(width: 8),
            AdminButton(
              label: _roleSearching ? context.t('super_admin.searching') : context.t('super_admin.search_btn'),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              onTap: _roleSearching ? null : _roleSearch,
            ),
          ]),
          if (r != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: Tw.fuchsia500.withValues(alpha: 0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.person, color: Tw.fuchsia400),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((r['nick'] as String?) ?? context.t('super_admin.no_nick'), style: tw(18, weight: bold)),
                      Text((r['email'] as String?) ?? '', style: tw(12, color: Tw.slate400)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Text(context.t('super_admin.current_role'), style: tw(12, color: Tw.slate500)),
                  const SizedBox(width: 8),
                  AdminBadge(
                    (r['role'] as String?) ?? 'user',
                    color: r['role'] != null && r['role'] != 'user' ? Tw.fuchsia400 : Tw.slate500,
                    background: r['role'] != null && r['role'] != 'user' ? Tw.fuchsia500.withValues(alpha: 0.2) : Tw.w(0.05),
                  ),
                ]),
              ]),
            ),
            FieldLabel(context.t('super_admin.new_role')),
            for (final opt in _roleOptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Pressable(
                  onTap: () => setState(() => _selectedRole = opt.value),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _selectedRole == opt.value ? Tw.fuchsia500.withValues(alpha: 0.1) : Tw.w(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _selectedRole == opt.value ? Tw.fuchsia500.withValues(alpha: 0.5) : Tw.w(0.05)),
                    ),
                    child: Row(children: [
                      Icon(opt.icon, color: opt.color),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(opt.label, style: tw(14, weight: bold)),
                        Text('${context.t('super_admin.redirects_to')} ${opt.redirect}', style: tw(10, color: Tw.slate500)),
                      ]),
                    ]),
                  ),
                ),
              ),
            if (_selectedRole == 'cityAdmin') ...[
              FieldLabel(context.t('super_admin.assigned_city')),
              AdminSelect<String>(
                value: _roleCityId,
                items: [('', context.t('super_admin.select_city_prompt')), for (final c in widget.cities) (c['id'] as String, '${c['name']} (${c['id']})')],
                onChanged: (v) => setState(() => _roleCityId = v ?? ''),
              ),
            ],
            if (_selectedRole == 'venueOwner') ...[
              FieldLabel(context.t('super_admin.assigned_venue')),
              AdminSelect<String>(
                value: _roleVenueId,
                items: [('', context.t('super_admin.select_venue_prompt')), for (final v in widget.venues) (v['id'] as String, (v['name'] ?? v['id']) as String)],
                onChanged: (v) => setState(() => _roleVenueId = v ?? ''),
              ),
            ],
            const SizedBox(height: 16),
            AdminButton(
              label: _assigning ? context.t('super_admin.assigning') : context.t('super_admin.assign_role_btn', params: {'role': _selectedRole}),
              color: Tw.white,
              textColor: Tw.black,
              expand: true,
              padding: const EdgeInsets.symmetric(vertical: 14),
              loading: _assigning,
              onTap: _selectedRole.isEmpty ? null : _assignRole,
            ),
          ],
        ]),
      ),
      const SizedBox(height: 32),
      AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle('${context.t('super_admin.users_with_role')} (${_assignments.length})'),
          const SizedBox(height: 16),
          if (_assignments.isEmpty) Text(context.t('super_admin.no_special_roles'), style: tw(14, color: Tw.slate500)),
          for (final u in _assignments) _assignmentRow(u),
        ]),
      ),
    ]);
  }

  Widget _assignmentRow(Map<String, dynamic> u) {
    final info = _roleOptions.where((r) => r.value == u['role']).firstOrNull;
    final color = info?.color ?? Tw.slate400;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(info?.icon ?? Icons.person, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((u['nick'] as String?) ?? context.t('super_admin.no_nick'), overflow: TextOverflow.ellipsis, style: tw(14, weight: bold)),
              Text((u['email'] as String?) ?? '', overflow: TextOverflow.ellipsis, style: tw(10, color: Tw.slate400)),
            ]),
          ),
          AdminBadge(info?.label ?? (u['role'] as String? ?? ''), color: color, background: Tw.w(0.05)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _revokeRole(u['id'] as String, (u['email'] ?? u['nick'] ?? '') as String),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Tw.red900.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
              child: Text(context.t('super_admin.revoke_role'), style: tw(10, weight: bold, color: Tw.red400)),
            ),
          ),
        ]),
        if (u['cityId'] != null)
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 4),
            child: Text('${context.t('super_admin.city_label')} ${u['cityId']}', style: tw(10, color: Tw.green400)),
          ),
      ]),
    );
  }
}
