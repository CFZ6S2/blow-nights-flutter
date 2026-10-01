import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Port of app/premium/page.tsx
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _submitting = false;
  String _error = '';
  String _period = 'yearly';
  String? _timeLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final auth = context.read<AuthProvider>();
    final fromProfile = auth.profile?.blackBoostExpires?.millisecondsSinceEpoch;
    final fromClaims = auth.claims?['blackBoostExpires'];
    final expires = fromProfile ?? (fromClaims is num ? fromClaims.toInt() : null);
    String? left;
    if (expires != null) {
      final diff = expires - DateTime.now().millisecondsSinceEpoch;
      if (diff > 0) {
        final h = diff ~/ 3600000, m = (diff % 3600000) ~/ 60000, s = (diff % 60000) ~/ 1000;
        left = '${h}h ${m}m ${s}s';
      }
    }
    if (left != _timeLeft) setState(() => _timeLeft = left);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _callCheckout(String fn, Map<String, dynamic> data) async {
    // No city needed: the membership callables accept a user without one (no City Manager attribution then).
    final i18n = context.read<I18n>();
    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      final res = await FirebaseFunctions.instance.httpsCallable(fn).call<Map<String, dynamic>>(data);
      final url = res.data['url'] as String?;
      if (url != null) {
        await openInApp(url);
      } else if (fn != 'createStripePortalSession') {
        setState(() => _error = i18n.t('premium.error_session'));
      }
    } on FirebaseFunctionsException catch (e) {
      if (fn == 'createStripePortalSession') {
        if (mounted) showToast(context, i18n.t('premium.error_portal'), error: true);
      } else {
        setState(() => _error = e.message ?? i18n.t('premium.error_payment'));
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final p = auth.profile;
    if (auth.loading || auth.user == null) return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final tier = p?.membershipTier ?? 'free';
    final isPlus = auth.isPlus, isBlack = auth.isBlack, promo = auth.isPromoLifetime;
    final cur = p?.cityId == 'albuquerque' ? r'$' : '€';
    final monthly = _period == 'monthly';
    final perLabel = monthly ? context.t('premium_per_month', fallback: 'mes') : context.t('premium_per_year', fallback: 'año');
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(children: [
        Positioned(top: -size.height * 0.1, left: -size.width * 0.1, child: Orb(color: Tw.fuchsia600.withValues(alpha: 0.2), size: 384)),
        Positioned(bottom: -size.height * 0.1, right: -size.width * 0.1, child: Orb(color: Tw.indigo600.withValues(alpha: 0.2), size: 384)),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 96), children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.chevron_left, size: 28)),
              const SizedBox(width: 8),
              Expanded(child: Text(context.t('premium.title', fallback: 'Planes de Membresía'), style: tw(24, weight: bold))),
            ]),
            const SizedBox(height: 32),
            Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(99), border: Border.all(color: Tw.w(0.2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Pressable(
                    onTap: () => setState(() => _period = 'monthly'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      decoration: BoxDecoration(color: monthly ? Tw.white : null, borderRadius: BorderRadius.circular(99)),
                      child: Text(context.t('premium.monthly'), style: tw(14, weight: bold, color: monthly ? Tw.black : Tw.w(0.7))),
                    ),
                  ),
                  Pressable(
                    onTap: () => setState(() => _period = 'yearly'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: !monthly ? const LinearGradient(colors: [Tw.fuchsia500, Tw.indigo500]) : null,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(children: [
                        Text(context.t('premium.yearly'), style: tw(14, weight: bold, color: !monthly ? Tw.white : Tw.w(0.7))),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Tw.w(0.2), borderRadius: BorderRadius.circular(99)),
                          child: Text('-25%', style: tw(12)),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 32),
            if (_error.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Tw.red500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Tw.red500.withValues(alpha: 0.5)),
                ),
                child: Text(_error, textAlign: TextAlign.center, style: tw(14, color: Tw.red500)),
              ),
              const SizedBox(height: 32),
            ],
            if (promo) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [const Color(0xFFEAB308).withValues(alpha: 0.2), Tw.orange500.withValues(alpha: 0.2)]),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.3)),
                ),
                child: Column(children: [
                  const Text('👑', style: TextStyle(fontSize: 36)),
                  const SizedBox(height: 8),
                  Text(context.t('premium.founder_title'), textAlign: TextAlign.center, style: tw(20, weight: black, color: const Color(0xFFEAB308))),
                  const SizedBox(height: 8),
                  Text(context.t('premium.founder_desc'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate300)),
                ]),
              ),
              const SizedBox(height: 32),
            ],
            if ((isPlus || isBlack) && !promo) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.2))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Label(context.t('premium.current_plan'), size: 12, weight: bold),
                      isBlack
                          ? ShaderMask(
                              shaderCallback: (r) => const LinearGradient(colors: [Tw.slate300, Tw.white]).createShader(r),
                              child: Text('BLACK', style: tw(24, weight: black)),
                            )
                          : Text('PLUS', style: tw(24, weight: black, color: Tw.fuchsia400)),
                    ]),
                  ),
                  Pressable(
                    onTap: _submitting ? () {} : () => _callCheckout('createStripePortalSession', {}),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
                      child: Text(context.t('premium.manage'), style: tw(14, weight: bold)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 32),
            ],
            // FREE
            _tierCard(
              border: tier == 'free' && !promo ? Tw.w(0.4) : Tw.w(0.1),
              glow: tier == 'free' && !promo ? Tw.w(0.1) : null,
              opacity: tier == 'free' && !promo ? 1 : 0.7,
              title: Label(context.t('premium_plan_free', fallback: 'Free'), size: 20, color: Tw.slate300),
              price: '0$cur',
              per: null,
              features: [
                (Icons.check_circle, Tw.w(0.5), context.t('premium.feat_map'), false),
                (Icons.check_circle, Tw.w(0.5), context.t('premium.feat_chat'), false),
                (Icons.check_circle, Tw.w(0.5), context.t('premium.feat_pings_3'), false),
                (Icons.check_circle, Tw.w(0.5), context.t('premium.feat_venues'), false),
              ],
              featureColor: Tw.slate400,
              footer: tier == 'free' && !promo
                  ? Column(children: [
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Tw.indigo500.withValues(alpha: 0.3)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(context.t('premium_black_8h_title', fallback: 'Black 8h Pass'), style: tw(14, weight: black, color: Tw.indigo400)),
                          const SizedBox(height: 4),
                          Text(context.t('premium.black8h_desc'), style: tw(10, color: Tw.slate400, height: 1.5)),
                          const SizedBox(height: 12),
                          if (_timeLeft != null)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: Tw.indigo500.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Tw.indigo500.withValues(alpha: 0.3)),
                              ),
                              child: Text('${context.t('premium.active')}: $_timeLeft',
                                  textAlign: TextAlign.center,
                                  style: tw(12, weight: bold, color: const Color(0xFFA5B4FC)).copyWith(fontFamily: 'monospace')),
                            )
                          else
                            Pressable(
                              onTap: _submitting ? () {} : () => _callCheckout('createBlack8hCheckout', {'origin': webBase}),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: Tw.indigo600,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [BoxShadow(color: Tw.indigo500.withValues(alpha: 0.2), blurRadius: 15)],
                                ),
                                child: Text(context.t('premium.buy_for', params: {'price': '5$cur'}),
                                    textAlign: TextAlign.center, style: tw(12, weight: bold)),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      Label(context.t('premium.current_plan'), weight: bold, color: Tw.slate500, tracking: 0),
                    ])
                  : null,
            ),
            const SizedBox(height: 24),
            // PLUS
            _tierCard(
              border: isPlus ? Tw.fuchsia500 : Tw.w(0.1),
              glow: isPlus ? Tw.fuchsia500.withValues(alpha: 0.2) : null,
              title: Label(context.t('premium_plan_plus', fallback: 'Plus'), size: 20, color: Tw.fuchsia400),
              price: monthly ? '10$cur' : '90$cur',
              per: perLabel,
              features: [
                (Icons.add_circle, Tw.fuchsia500, context.t('premium.all_free'), true),
                (Icons.visibility, Tw.fuchsia500, context.t('premium.feat_visitors'), false),
                (Icons.visibility_off, Tw.fuchsia500, context.t('premium.feat_ghost'), false),
                (Icons.bolt, Tw.fuchsia500, context.t('premium.feat_pings_10'), false),
                (Icons.rocket_launch, Tw.fuchsia500, context.t('premium.feat_boost'), false),
                (Icons.tune, Tw.fuchsia500, context.t('premium.feat_filters'), false),
                (Icons.favorite, Tw.fuchsia500, context.t('premium.feat_see_likes'), false),
              ],
              footer: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: !isPlus && !isBlack && !promo
                    ? Pressable(
                        onTap: _submitting ? () {} : () => _callCheckout('createUserMembershipCheckout', {'tier': 'plus', 'period': _period, 'origin': webBase}),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(16)),
                          child: Label(context.t('premium.upgrade_plus'), color: Tw.black, align: TextAlign.center),
                        ),
                      )
                    : isPlus
                        ? Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: Tw.fuchsia500.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
                            ),
                            child: Label(context.t('premium.current_plan'), weight: bold, color: Tw.fuchsia400, tracking: 0, align: TextAlign.center),
                          )
                        : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 24),
            // BLACK
            _tierCard(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.slate900, Tw.black]),
              border: isBlack || promo ? Tw.slate400 : Tw.slate700,
              glow: isBlack || promo ? Tw.w(0.15) : null,
              vipRibbon: true,
              title: ShaderMask(
                shaderCallback: (r) => const LinearGradient(colors: [Tw.slate300, Tw.white]).createShader(r),
                child: Label(context.t('premium_plan_black', fallback: 'Black'), size: 20, color: Tw.white),
              ),
              price: monthly ? '20$cur' : '180$cur',
              per: perLabel,
              features: [
                (Icons.add_circle, const Color(0xFFF1F5F9), context.t('premium.all_plus'), true),
                (Icons.bolt, const Color(0xFFF1F5F9), context.t('premium.feat_pings_unlimited'), false),
                (Icons.rocket_launch, const Color(0xFFF1F5F9), context.t('premium.feat_boosts_unlimited'), false),
                (Icons.shield, const Color(0xFFF1F5F9), context.t('premium.feat_incognito'), false),
                (Icons.stars, const Color(0xFFF1F5F9), context.t('premium.feat_vip'), false),
                (Icons.nightlife, Tw.white, context.t('premium.feat_chills'), true),
                (Icons.block, const Color(0xFFF1F5F9), context.t('premium.feat_no_ads'), false),
              ],
              highlightIndex: 5,
              footer: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: !isBlack && !promo
                    ? Pressable(
                        onTap: _submitting ? () {} : () => _callCheckout('createUserMembershipCheckout', {'tier': 'black', 'period': _period, 'origin': webBase}),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFE2E8F0), Tw.white]),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Tw.w(0.3), blurRadius: 20)],
                          ),
                          child: Label(context.t('premium.upgrade_black'), color: Tw.black, align: TextAlign.center),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.3))),
                        child: Label(context.t('premium.current_plan'), color: Tw.white, align: TextAlign.center),
                      ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _tierCard({
    required Color border,
    Color? glow,
    double opacity = 1,
    Gradient? gradient,
    bool vipRibbon = false,
    required Widget title,
    required String price,
    required String? per,
    required List<(IconData, Color, String, bool)> features,
    Color featureColor = Tw.slate300,
    int? highlightIndex,
    Widget? footer,
  }) =>
      Opacity(
        opacity: opacity,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: gradient == null ? Tw.w(0.05) : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: border),
            boxShadow: glow != null ? [BoxShadow(color: glow, blurRadius: 30)] : null,
          ),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                title,
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(price, style: tw(34, weight: black)),
                  if (per != null) ...[const SizedBox(width: 4), Text('/$per', style: tw(12, weight: black, color: Tw.slate500))],
                ]),
                const SizedBox(height: 32),
                for (var i = 0; i < features.length; i++) ...[
                  Container(
                    padding: i == highlightIndex ? const EdgeInsets.all(8) : EdgeInsets.zero,
                    decoration: i == highlightIndex
                        ? BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.2)))
                        : null,
                    child: Row(children: [
                      Icon(features[i].$1, size: 14, color: features[i].$2),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(features[i].$3,
                            style: tw(12, weight: i == highlightIndex ? black : bold, color: features[i].$4 ? Tw.white : featureColor)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],
                ?footer,
              ]),
            ),
            if (vipRibbon)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Tw.slate400, Tw.white]),
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                  ),
                  child: Label('VIP', color: Tw.black),
                ),
              ),
          ]),
        ),
      );
}
