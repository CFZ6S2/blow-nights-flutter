import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/platform_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';

/// react-i18next `<Trans>`: `<1>text</1>` (or `<strong>`) segments rendered bold.
TextSpan transSpan(String s, TextStyle base, TextStyle strong) {
  final spans = <TextSpan>[];
  final re = RegExp(r'<(\w+)>(.*?)</\1>');
  var last = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start), style: base));
    spans.add(TextSpan(text: m.group(2), style: strong));
    last = m.end;
  }
  if (last < s.length) spans.add(TextSpan(text: s.substring(last), style: base));
  return TextSpan(children: spans);
}

/// Port of app/business/claim/page.tsx (claim-your-venue pitch; the form only confirms, like the web).
class ClaimVenueScreen extends StatefulWidget {
  final String? venue;
  const ClaimVenueScreen({super.key, this.venue});

  @override
  State<ClaimVenueScreen> createState() => _ClaimVenueScreenState();
}

class _ClaimVenueScreenState extends State<ClaimVenueScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _claim() {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) return;
    final i18n = context.read<I18n>();
    if (context.read<PlatformSettings>().flags['moduleVenueRegistration'] == false) {
      showToast(context, 'El registro y reclamación de locales está actualmente gestionado directamente por administración.');
      return;
    }
    showToast(context, i18n.t('business.claim.alert_success'));
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final venue = widget.venue?.isNotEmpty == true ? widget.venue! : context.t('business.claim.default_venue');
    InputDecoration deco(String hint) => adminInputDecoration(hint, focus: Tw.amber500).copyWith(fillColor: Tw.black);
    Widget benefit(String key) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('✓ ', style: tw(14, color: Tw.amber500)),
            Expanded(child: Text(context.t(key), style: tw(14, color: Tw.slate300))),
          ]),
        );
    return Scaffold(
      backgroundColor: const Color(0xFF07080D),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(height: 4, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Tw.amber400, Color(0xFFCA8A04)]))),
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('🏪', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 24),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${context.t('business.claim.title')} ', style: tw(24, weight: black, height: 1.2)),
                      TextSpan(text: venue, style: tw(24, weight: black, color: const Color(0xFFFCD34D), height: 1.2)),
                    ])),
                    const SizedBox(height: 16),
                    Text.rich(transSpan(context.t('business.claim.description'), tw(14, color: Tw.slate400, height: 1.6), tw(14, weight: bold, color: Tw.white, height: 1.6))),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF78350F).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Tw.amber500.withValues(alpha: 0.2)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Label(context.t('business.claim.benefits_title'), size: 12, weight: bold, color: Tw.amber500),
                        const SizedBox(height: 8),
                        benefit('business.claim.benefits_1'),
                        benefit('business.claim.benefits_2'),
                        benefit('business.claim.benefits_3'),
                      ]),
                    ),
                    const SizedBox(height: 32),
                    Label(context.t('business.claim.form.name_label'), weight: bold),
                    const SizedBox(height: 4),
                    TextField(controller: _name, style: tw(14), decoration: deco(context.t('business.claim.form.name_placeholder'))),
                    const SizedBox(height: 16),
                    Label(context.t('business.claim.form.phone_label'), weight: bold),
                    const SizedBox(height: 4),
                    TextField(controller: _phone, keyboardType: TextInputType.phone, style: tw(14), decoration: deco('+34 600 000 000')),
                    const SizedBox(height: 20),
                    GradientButton(
                      label: context.t('business.claim.form.submit'),
                      expand: true,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      gradient: const LinearGradient(colors: [Tw.amber500, Color(0xFFCA8A04)]),
                      onTap: _claim,
                    ),
                    const SizedBox(height: 24),
                    Text(context.t('business.claim.footer_note'), textAlign: TextAlign.center, style: tw(10, color: Tw.slate500)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Port of app/business/stripe/page.tsx (venue Stripe Connect onboarding).
class BusinessStripeScreen extends StatefulWidget {
  final bool refresh;
  final bool returned;
  const BusinessStripeScreen({super.key, this.refresh = false, this.returned = false});

  @override
  State<BusinessStripeScreen> createState() => _BusinessStripeScreenState();
}

class _BusinessStripeScreenState extends State<BusinessStripeScreen> {
  Map<String, dynamic>? _venue;
  bool _loading = true;
  bool _linking = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final i18n = context.read<I18n>();
    if (auth.user == null) {
      openRoute(context, AppRoute.business, replace: true);
      return;
    }
    try {
      final venueId = auth.profile?.data['venueId'] as String?;
      if (venueId == null || venueId.isEmpty) {
        setState(() => _error = i18n.t('business.stripe.error.no_venue'));
      } else {
        final s = await FirebaseFirestore.instance.collection('venues').doc(venueId).get();
        if (s.exists) {
          setState(() => _venue = {'id': s.id, ...?s.data()});
        } else {
          setState(() => _error = i18n.t('business.stripe.error.venue_not_found'));
        }
      }
    } catch (e) {
      setState(() => _error = errorMessage(e, ''));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _connect() async {
    final i18n = context.read<I18n>();
    setState(() {
      _linking = true;
      _error = '';
    });
    try {
      final r1 = await callFn('createStripeConnectAccount', {'venueId': _venue!['id']});
      final r2 = await callFn('createStripeAccountLink', {'accountId': r1['accountId'], 'origin': webBase});
      if (r2['url'] is String) {
        await openInApp(r2['url'] as String);
      } else {
        setState(() => _error = i18n.t('business.stripe.error.no_link'));
      }
    } catch (e) {
      setState(() => _error = i18n.t('business.stripe.error.connect_error') + errorMessage(e, ''));
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(backgroundColor: const Color(0xFF0B0C10), body: Center(child: Text(context.t('common.loading'), style: tw(14))));
    }
    final v = _venue;
    Widget notice(String text, Color c) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.5))),
          child: Text(text, style: tw(14, color: c)),
        );
    Widget step(String n, String key) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Tw.fuchsia500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
              child: Text(n, style: tw(14, color: Tw.fuchsia400)),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(context.t(key), style: tw(14, color: Tw.slate300))),
          ]),
        );
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Align(alignment: Alignment.centerLeft, child: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400))),
          const SizedBox(height: 16),
          Text(context.t('business.stripe.title').toUpperCase(), textAlign: TextAlign.center, style: tw(28, weight: black, color: Tw.fuchsia400, tracking: 0.1)),
          const SizedBox(height: 8),
          Text(context.t('business.stripe.subtitle'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
          const SizedBox(height: 40),
          if (_error.isNotEmpty) notice(_error, Tw.red400),
          if (widget.refresh) notice(context.t('business.stripe.message.cancelled'), Tw.yellow400),
          if (widget.returned) notice(context.t('business.stripe.message.success'), Tw.green400),
          if (v != null)
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: const Color(0xFF11131F), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF23273F))),
              child: Stack(children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text((v['name'] as String?) ?? '', style: tw(20, weight: bold)),
                    const SizedBox(height: 16),
                    if ((v['stripeAccountId'] as String?)?.isNotEmpty == true) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Tw.green400.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Tw.green400.withValues(alpha: 0.2)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle, color: Tw.green400),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(context.t('business.stripe.account_linked'), style: tw(14, weight: bold, color: Tw.green400)),
                              Text('ID: ${v['stripeAccountId']}', style: tw(12, color: Tw.green400.withValues(alpha: 0.7))),
                            ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      Text(context.t('business.stripe.description_linked'), style: tw(14, color: Tw.slate400)),
                      const SizedBox(height: 16),
                      AdminButton(
                        icon: Icons.open_in_new,
                        label: 'Ver Dashboard de Cobros en Stripe',
                        color: const Color(0xFF635BFF),
                        expand: true,
                        fontSize: 13,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onTap: () => openInApp('https://dashboard.stripe.com'),
                      ),
                      const SizedBox(height: 12),
                      AdminButton(
                        label: _linking ? context.t('common.loading') : context.t('business.stripe.update_bank_details'),
                        color: const Color(0xFF1C1F38),
                        textColor: Tw.slate300,
                        expand: true,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onTap: _linking ? null : _connect,
                      ),
                    ] else ...[
                      step('1', 'business.stripe.step_1'),
                      step('2', 'business.stripe.step_2'),
                      step('3', 'business.stripe.step_3'),
                      const SizedBox(height: 8),
                      AdminButton(
                        icon: _linking ? null : Icons.account_balance,
                        label: _linking ? context.t('business.stripe.connecting') : context.t('business.stripe.setup_bank_account'),
                        color: const Color(0xFF635BFF),
                        expand: true,
                        fontSize: 13,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        onTap: _linking ? null : _connect,
                      ),
                      const SizedBox(height: 8),
                      Text(context.t('business.stripe.footer_note'), textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
                    ],
                  ]),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: const BoxDecoration(color: Tw.blue600, borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16))),
                    child: Label('Powered by Stripe Connect', color: Tw.white, tracking: 0),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Port of app/setup-stripe/page.tsx (superadmin one-off: create Stripe products + TEST100 promo code).
class SetupStripeScreen extends StatefulWidget {
  const SetupStripeScreen({super.key});

  @override
  State<SetupStripeScreen> createState() => _SetupStripeScreenState();
}

class _SetupStripeScreenState extends State<SetupStripeScreen> {
  Map<String, dynamic>? _result;
  bool _loading = false;
  String _error = '';
  bool _promoCreated = false;
  bool _promoLoading = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    Widget center(String t) => Scaffold(backgroundColor: Tw.black, body: Center(child: Text(t, style: tw(15))));
    if (auth.user == null) return center(context.t('setup_stripe_login_required', fallback: 'Login required'));
    if (auth.role != 'superadmin') return center(context.t('setup_stripe_access_denied', fallback: 'Acceso denegado'));
    final r = _result;
    final envText = r == null ? '' : r.entries.map((e) => '${e.key}=${e.value}').join('\n');
    return Scaffold(
      backgroundColor: Tw.black,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(32), children: [
          Align(alignment: Alignment.centerLeft, child: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400))),
          Text(context.t('setup_stripe_title', fallback: 'Setup Stripe Products'), style: tw(24, weight: bold)),
          const SizedBox(height: 16),
          Text(context.t('setup_stripe_description', fallback: 'Crea los productos y precios en Stripe. Solo ejecutar una vez.'), style: tw(15, color: Tw.slate400)),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: AdminButton(
              label: _loading ? context.t('setup_stripe_creating', fallback: 'Creando productos...') : context.t('setup_stripe_create_button', fallback: 'Crear Productos en Stripe'),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onTap: _loading
                  ? null
                  : () async {
                      setState(() {
                        _loading = true;
                        _error = '';
                      });
                      try {
                        final res = await callFn('setupStripeProducts', {});
                        setState(() => _result = res);
                      } catch (e) {
                        setState(() => _error = errorMessage(e, ''));
                      } finally {
                        if (mounted) setState(() => _loading = false);
                      }
                    },
            ),
          ),
          if (_error.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Tw.red500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.red500)),
              child: Text(_error, style: tw(14, color: Tw.red400)),
            ),
          const SizedBox(height: 32),
          Divider(color: Tw.w(0.1)),
          const SizedBox(height: 32),
          Text(context.t('setup_stripe_promo_title', fallback: 'Promo Code de Test'), style: tw(20, weight: bold)),
          const SizedBox(height: 8),
          Text(context.t('setup_stripe_promo_desc', fallback: 'Crea un código TEST100 con 100% descuento para testing.'), style: tw(15, color: Tw.slate400)),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: AdminButton(
              label: _promoLoading ? context.t('setup_stripe_promo_creating', fallback: 'Creando...') : context.t('setup_stripe_promo_button', fallback: 'Crear Promo Code TEST100'),
              color: Tw.green600,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onTap: _promoLoading
                  ? null
                  : () async {
                      setState(() => _promoLoading = true);
                      try {
                        await callFn('createTestPromoCode', {});
                        setState(() => _promoCreated = true);
                      } catch (e) {
                        setState(() => _error = errorMessage(e, ''));
                      } finally {
                        if (mounted) setState(() => _promoLoading = false);
                      }
                    },
            ),
          ),
          if (_promoCreated)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Tw.green500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.green500)),
              child: Text.rich(TextSpan(style: tw(14, color: Tw.green400), children: [
                TextSpan(text: '${context.t('setup_stripe_promo_created', fallback: 'Código creado:')} '),
                TextSpan(text: 'TEST100', style: tw(14, weight: bold).copyWith(fontFamily: 'monospace')),
                TextSpan(text: ' ${context.t('setup_stripe_promo_details', fallback: '(100% off, max 50 usos)')}'),
              ])),
            ),
          if (r != null) ...[
            const SizedBox(height: 24),
            Text(context.t('setup_stripe_result_title', fallback: 'Products created. Copy this for functions/.env:'), style: tw(18, weight: bold, color: Tw.green400)),
            const SizedBox(height: 8),
            GestureDetector(
              onLongPress: () => Clipboard.setData(ClipboardData(text: envText)),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(12)),
                child: SelectableText(envText, style: tw(14).copyWith(fontFamily: 'monospace')),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
