import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../providers/auth_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/address_autocomplete.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

/// Port of app/venue-admin/SetupWizard.tsx (owner without venues: self-register or ask for delegated management).
class SetupWizard extends StatefulWidget {
  /// Replaces the web's `window.location.reload()` after finishing.
  final VoidCallback onReload;
  const SetupWizard({super.key, required this.onReload});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  String _step = 'choice';
  bool _loading = false;
  final _name = TextEditingController();
  final _address = TextEditingController();
  String _type = 'club';
  String _cityId = '';
  List<Map<String, dynamic>> _cities = [];

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = FirebaseFirestore.instance;
    final uid = context.read<AuthProvider>().user?.uid;
    try {
      final s = await db.collection('cities').where('readyForFranchise', isEqualTo: true).get();
      if (mounted) setState(() => _cities = [for (final d in s.docs) {'id': d.id, ...d.data()}]);
    } catch (e) {
      debugPrint('Error fetching cities: $e');
    }
    try {
      if (uid == null) return;
      final s = await db.collection('partner_applications').where('userId', isEqualTo: uid).limit(1).get();
      if (s.docs.isEmpty || !mounted) return;
      final d = s.docs.first.data();
      setState(() {
        final n = d['venueName'] ?? d['name'];
        if (n is String) _name.text = n;
        if (d['venueAddress'] is String) _address.text = d['venueAddress'] as String;
        if (d['cityId'] is String) _cityId = d['cityId'] as String;
      });
    } catch (_) {}
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _cityId.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final p = auth.profile?.data ?? const {};
    setState(() => _loading = true);
    try {
      await callFn('selfRegisterVenue', {
        'venueName': _name.text,
        'venueAddress': _address.text,
        'venueType': _type,
        // Empty: selfRegisterVenue works the city out from the address. Never Madrid by default.
        if (_cityId.isNotEmpty) 'cityId': _cityId,
        'email': auth.user?.email ?? p['email'] ?? '',
        'name': p['name'] ?? p['nick'] ?? '',
        'phone': p['phone'] ?? '',
      });
      setState(() => _step = 'done');
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('setup_wizard.error_create'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delegate() async {
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(context.read<AuthProvider>().user!.uid).update({'delegatedManagement': true});
      setState(() => _step = 'delegated');
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('setup_wizard.error_delegate'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tw.slate950,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.slate800)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.fuchsia600, Tw.indigo600]),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.2), blurRadius: 16)],
                      ),
                      child: const Icon(Icons.business, size: 32, color: Tw.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(context.t('setup_wizard.welcome'), textAlign: TextAlign.center, style: tw(28, weight: black)),
                  const SizedBox(height: 8),
                  Text(context.t('setup_wizard.welcome_desc'), textAlign: TextAlign.center, style: tw(15, color: Tw.slate400)),
                  const SizedBox(height: 32),
                  switch (_step) {
                    'form' => _form(context),
                    'delegated' => _result(context, Icons.check_circle, Tw.indigo500, 'setup_wizard.delegated_title', 'setup_wizard.delegated_desc',
                        'setup_wizard.reload_panel', Tw.slate800),
                    'done' => _result(context, Icons.check_circle, Tw.green500, 'setup_wizard.done_title', 'setup_wizard.done_desc', 'setup_wizard.enter_panel',
                        Tw.fuchsia600),
                    _ => _choice(context),
                  },
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _option(IconData icon, Color hover, String title, String desc, String cta, VoidCallback? onTap) => Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Pressable(
          onTap: onTap ?? () {},
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Tw.slate950, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.slate800)),
            child: Column(children: [
              Icon(icon, size: 40, color: Tw.slate500),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: tw(18, weight: bold)),
              const SizedBox(height: 8),
              Text(desc, textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Label(cta, size: 12, weight: bold, color: hover, tracking: 0.05),
                Icon(Icons.chevron_right, size: 16, color: hover),
              ]),
            ]),
          ),
        ),
      );

  Widget _choice(BuildContext context) => Column(children: [
        _option(Icons.business, Tw.fuchsia500, context.t('setup_wizard.option_setup'), context.t('setup_wizard.option_setup_desc'),
            context.t('setup_wizard.start'), () => setState(() => _step = 'form')),
        const SizedBox(height: 16),
        _option(Icons.handshake, Tw.indigo500, context.t('setup_wizard.option_delegate'), context.t('setup_wizard.option_delegate_desc'),
            _loading ? context.t('setup_wizard.processing') : context.t('setup_wizard.request'), _loading ? null : _delegate),
      ]);

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 4, top: 12), child: Label(t, size: 12, weight: bold, tracking: 0.05));

  Widget _form(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label(context.t('setup_wizard.venue_name')),
        AdminInput(controller: _name, hint: context.t('setup_wizard.venue_name_placeholder')),
        _label(context.t('setup_wizard.venue_address')),
        AddressAutocomplete(controller: _address, placeholder: context.t('setup_wizard.venue_address_placeholder')),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label(context.t('setup_wizard.type')),
              AdminSelect<String>(
                value: _type,
                items: [for (final t in const ['club', 'bar', 'sauna', 'chiringuito']) (t, context.t('setup_wizard.type_$t'))],
                onChanged: (v) => setState(() => _type = v ?? 'club'),
              ),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label(context.t('setup_wizard.city')),
              AdminSelect<String>(
                value: _cityId.isEmpty ? null : _cityId,
                hint: context.t('setup_wizard.city_select'),
                items: [
                  for (final c in _cities) (c['id'] as String, (c['name'] ?? c['id']) as String),
                  ('other', context.t('setup_wizard.city_other')),
                ],
                onChanged: (v) => setState(() => _cityId = v ?? ''),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          AdminButton(
            label: context.t('setup_wizard.back'),
            color: Tw.slate800,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            onTap: () => setState(() => _step = 'choice'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AdminButton(
              label: _loading ? context.t('setup_wizard.creating') : context.t('setup_wizard.create_venue'),
              expand: true,
              padding: const EdgeInsets.symmetric(vertical: 14),
              onTap: _loading || _name.text.trim().isEmpty || _cityId.isEmpty ? null : _create,
            ),
          ),
        ]),
      ]);

  Widget _result(BuildContext context, IconData icon, Color color, String title, String desc, String cta, Color ctaColor) => Column(children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 40, color: color),
        ),
        const SizedBox(height: 24),
        Text(context.t(title), textAlign: TextAlign.center, style: tw(24, weight: black)),
        const SizedBox(height: 8),
        Text(context.t(desc), textAlign: TextAlign.center, style: tw(15, color: Tw.slate400)),
        const SizedBox(height: 32),
        AdminButton(label: context.t(cta), color: ctaColor, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14), onTap: widget.onReload),
      ]);
}
