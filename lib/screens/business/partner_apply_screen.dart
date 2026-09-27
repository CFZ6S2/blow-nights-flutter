import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import 'promoter_screens.dart' show openWhatsApp;

/// Port of app/partners/apply/page.tsx (City Manager / partner application form + floating WhatsApp).
class PartnerApplyScreen extends StatefulWidget {
  const PartnerApplyScreen({super.key});

  @override
  State<PartnerApplyScreen> createState() => _PartnerApplyScreenState();
}

class _PartnerApplyScreenState extends State<PartnerApplyScreen> {
  List<Map<String, dynamic>> _cities = [];
  String _city = '';
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _experience = TextEditingController();
  bool _submitting = false;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.collection('cities').where('readyForFranchise', isEqualTo: true).get().then((s) {
      if (mounted) setState(() => _cities = [for (final d in s.docs) {'id': d.id, ...d.data()}]);
    });
    for (final c in [_name, _phone, _experience]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _experience.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = context.read<AuthProvider>().user;
    final i18n = context.read<I18n>();
    if (user == null) {
      showToast(context, i18n.t('partners_apply.login_required'));
      openRoute(context, AppRoute.login, replace: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await FirebaseFirestore.instance.collection('partner_applications').add({
        'userId': user.uid,
        'email': user.email,
        'name': _name.text,
        'phone': _phone.text,
        'cityId': _city,
        'experience': _experience.text,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      setState(() => _success = true);
    } catch (_) {
      if (mounted) showToast(context, i18n.t('partners_apply.error_submitting'), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 4, top: 20), child: Label(t, size: 12, weight: bold, tracking: 0.05));

  InputDecoration _deco(String hint) => adminInputDecoration(hint, focus: Tw.purple500).copyWith(
        fillColor: Tw.slate950,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.slate800)),
      );

  @override
  Widget build(BuildContext context) {
    if (context.watch<AuthProvider>().loading) return const Scaffold(backgroundColor: Tw.slate950);
    final valid = _city.isNotEmpty && _name.text.trim().isNotEmpty && _phone.text.trim().isNotEmpty && _experience.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: Tw.slate950,
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF25D366),
        foregroundColor: Tw.white,
        shape: const CircleBorder(),
        tooltip: context.t('partners_apply.whatsapp_tooltip'),
        onPressed: () => openWhatsApp(context.read<I18n>().t('partners_apply.whatsapp_message')),
        child: const Icon(Icons.chat, size: 28),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 100), children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.arrow_back, size: 16, color: Tw.slate400),
                const SizedBox(width: 8),
                Label(context.t('partners_apply.back'), size: 14, weight: bold, tracking: 0.05),
              ]),
            ),
          ),
          const SizedBox(height: 32),
          if (_success)
            AdminCard(
              color: Tw.slate900,
              borderColor: Tw.green500.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(28),
              child: Column(children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(color: Tw.green500.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle, size: 40, color: Tw.green500),
                ),
                const SizedBox(height: 24),
                Text(context.t('partners_apply.success_title'), textAlign: TextAlign.center, style: tw(28, weight: black)),
                const SizedBox(height: 16),
                Text(context.t('partners_apply.success_desc'), textAlign: TextAlign.center, style: tw(15, color: Tw.slate400)),
                const SizedBox(height: 32),
                AdminButton(
                  label: context.t('partners_apply.back_to_home'),
                  color: Tw.white,
                  textColor: Tw.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                ),
              ]),
            )
          else
            AdminCard(
              color: Tw.slate900,
              borderColor: Tw.slate800,
              padding: const EdgeInsets.all(28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(context.t('partners_apply.form_title'), style: tw(28, weight: black)),
                const SizedBox(height: 8),
                Text(context.t('partners_apply.form_desc'), style: tw(14, color: Tw.slate400)),
                const SizedBox(height: 12),
                _label(context.t('partners_apply.city_label')),
                AdminSelect<String>(
                  value: _city.isEmpty ? null : _city,
                  hint: context.t('partners_apply.city_placeholder'),
                  items: [
                    for (final c in _cities) (c['id'] as String, '${c['name'] ?? c['id']} (${context.t('partners_apply.city_active_opportunity')})'),
                    ('other', context.t('partners_apply.city_other')),
                  ],
                  onChanged: (v) => setState(() => _city = v ?? ''),
                ),
                _label(context.t('partners_apply.name_label')),
                TextField(controller: _name, style: tw(14), decoration: _deco(context.t('partners_apply.name_placeholder'))),
                _label(context.t('partners_apply.phone_label')),
                TextField(controller: _phone, keyboardType: TextInputType.phone, style: tw(14), decoration: _deco(context.t('partners_apply.phone_placeholder'))),
                _label(context.t('partners_apply.experience_label')),
                TextField(controller: _experience, maxLines: 4, style: tw(14), decoration: _deco(context.t('partners_apply.experience_placeholder'))),
                const SizedBox(height: 24),
                GradientButton(
                  label: _submitting ? context.t('partners_apply.submit_loading') : context.t('partners_apply.submit_btn'),
                  icon: _submitting ? null : Icons.send,
                  loading: _submitting,
                  expand: true,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  gradient: const LinearGradient(colors: [Tw.purple600, Tw.indigo600]),
                  onTap: _submitting || !valid ? null : _submit,
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
