import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/city_selector.dart';
import '../../widgets/common.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/radar_map.dart';

/// Port of app/[city]/map/page.tsx (logged-in view).
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    if (auth.user == null || profile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) openRoute(context, AppRoute.login, replace: true);
      });
      return const Scaffold();
    }
    final vip = ['plus', 'black'].contains(profile.membershipTier);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(slivers: [
          SliverPersistentHeader(pinned: true, delegate: _Header(auth)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
            sliver: SliverList.list(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Text(context.t('city.near_you'), style: tw(20, weight: bold))),
                Text(context.t('city.approx_location'), style: tw(12, weight: medium, color: Tw.purple400)),
              ]),
              const SizedBox(height: 16),
              const RadarMap(),
              const SizedBox(height: 32),
              _quickActions(context, vip),
              if (vip) ...[
                const SizedBox(height: 32),
                _VipPanel(uid: auth.user!.uid, data: profile.data),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _quickActions(BuildContext context, bool vip) {
    Widget tile(IconData icon, Color color, String title, String sub, AppRoute route) => Expanded(
          child: GlassCard(
            onTap: () => openRoute(context, route),
            radius: 24,
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 30, color: color, shadows: [Shadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]),
              const SizedBox(height: 12),
              Text(title, style: tw(16, weight: bold)),
              const SizedBox(height: 4),
              Text(sub, style: tw(10, color: Tw.slate400)),
            ]),
          ),
        );
    return Column(children: [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tile(Icons.nightlife, Tw.fuchsia400, context.t('city.where_going'), context.t('city.choose_spot'), AppRoute.venues),
          const SizedBox(width: 16),
          tile(Icons.confirmation_number, const Color(0xFFFACC15), context.t('city.my_wallet'), context.t('city.tickets_passes'), AppRoute.tickets),
        ]),
      ),
      const SizedBox(height: 16),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tile(Icons.event, Tw.emerald400, context.t('city.events', fallback: 'Eventos'), context.t('city.whats_on', fallback: 'Que hay esta noche'),
              AppRoute.events),
          const SizedBox(width: 16),
          tile(Icons.groups, Tw.amber400, context.t('city.plans', fallback: 'Planes'), context.t('city.your_plans', fallback: 'Tus quedadas'),
              AppRoute.myPlans),
        ]),
      ),
      const SizedBox(height: 16),
      GlassCard(
        onTap: () => openRoute(context, AppRoute.entradas),
        radius: 24,
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Icon(Icons.confirmation_number, size: 30, color: const Color(0xFFFACC15),
              shadows: [Shadow(color: const Color(0xFFFACC15).withValues(alpha: 0.5), blurRadius: 8)]),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('city.buy_tickets'), style: tw(16, weight: bold)),
              const SizedBox(height: 4),
              Text(context.t('city.buy_tickets_desc'), style: tw(10, color: Tw.slate400)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFFACC15), borderRadius: BorderRadius.circular(99)),
            child: Label(context.t('city.no_register'), size: 9, color: Tw.black, tracking: -0.05),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      GlassCard(
        onTap: () => openRoute(context, AppRoute.premium),
        radius: 24,
        padding: const EdgeInsets.all(20),
        borderColor: vip ? const Color(0x4DEAB308) : null,
        child: Row(children: [
          Text(vip ? '👑' : '⭐', style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(vip ? context.t('city.vip_account') : context.t('city.go_premium'),
                  style: tw(16, weight: bold, color: vip ? const Color(0xFFFACC15) : Tw.white)),
              const SizedBox(height: 4),
              Text(vip ? context.t('city.enjoy_advantages') : context.t('city.see_plans'), style: tw(10, color: Tw.slate400)),
            ]),
          ),
          if (!vip)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Tw.white,
                borderRadius: BorderRadius.circular(99),
                boxShadow: [BoxShadow(color: Tw.w(0.3), blurRadius: 15)],
              ),
              child: Label(context.t('city.see_more'), size: 9, color: Tw.black, tracking: -0.05),
            ),
        ]),
      ),
    ]);
  }
}

class _Header extends SliverPersistentHeaderDelegate {
  final AuthProvider auth;
  _Header(this.auth);

  @override
  double get minExtent => auth.isAdmin ? 104 : 72;
  @override
  double get maxExtent => minExtent;

  @override
  bool shouldRebuild(covariant _Header old) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    Widget pill(IconData icon, String label, Color color, AppRoute route) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Pressable(
            onTap: () => openRoute(context, route),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 12, color: color == Tw.fuchsia600 ? Tw.fuchsia400 : Tw.purple400),
                const SizedBox(width: 4),
                Label(label, size: 9, color: color == Tw.fuchsia600 ? Tw.fuchsia400 : Tw.purple400, tracking: 0),
              ]),
            ),
          ),
        );
    final actions = <Widget>[
      if (auth.isSuperAdmin) pill(Icons.admin_panel_settings, 'Maestro', Tw.fuchsia600, AppRoute.superAdmin),
      if (auth.isAdmin) pill(Icons.tune, 'Admin', Tw.purple600, AppRoute.admin),
      const LanguageSelector(),
      const SizedBox(width: 6),
      Pressable(
        onTap: () async {
          await context.read<AuthProvider>().logout();
          if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        },
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Tw.w(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Tw.w(0.05)),
          ),
          child: const Icon(Icons.logout, size: 12, color: Tw.slate400),
        ),
      ),
    ];
    final wrap = auth.isAdmin;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Tw.slate900.withValues(alpha: 0.9),
        border: Border(bottom: BorderSide(color: Tw.w(0.05))),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
        IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, color: Tw.slate400, size: 20),
        ),
        const CitySelector(),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [Tw.pink500, Color(0xFF8B5CF6)]).createShader(r),
              child: Text('BLOW NIGHTS', style: tw(16, weight: black, tracking: -0.05)),
            ),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${context.t('city.hello')}, ${auth.profile?.nick.isNotEmpty == true ? auth.profile!.nick : 'Usuario'}! '),
                if (auth.isAdmin) TextSpan(text: '[ADMIN]', style: tw(10, weight: black, color: Tw.purple400)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tw(10, weight: medium, color: Tw.slate400),
            ),
          ]),
        ),
        if (!wrap) ...actions,
        ]),
        if (wrap) ...[
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
        ],
      ]),
    );
  }
}

class _VipPanel extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  const _VipPanel({required this.uid, required this.data});

  @override
  Widget build(BuildContext context) {
    final incognito = data['incognito'] == true;
    final lastBoost = parseDate(data['lastBoost']);
    final cooldown = lastBoost != null && lastBoost.isAfter(DateTime.now().subtract(const Duration(hours: 24)));
    final users = FirebaseFirestore.instance.collection('users').doc(uid);
    Widget row(String title, String sub, Widget trailing) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Tw.w(0.05)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: tw(14, weight: bold)),
                Text(sub, style: tw(10, color: Tw.slate500)),
              ]),
            ),
            trailing,
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFFEAB308).withValues(alpha: 0.1), Colors.transparent],
        ),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFEAB308)),
          const SizedBox(width: 8),
          Label(context.t('city.vip_active_features'), size: 12, color: const Color(0xFFEAB308), tracking: 0.2),
        ]),
        const SizedBox(height: 24),
        row(
          context.t('city.incognito_mode'),
          context.t('city.navigate_hidden'),
          GestureDetector(
            onTap: () => users.set({'incognito': !incognito}, SetOptions(merge: true)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 24,
              decoration: BoxDecoration(
                color: incognito ? const Color(0xFFEAB308) : Tw.slate700,
                borderRadius: BorderRadius.circular(99),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: incognito ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Tw.white),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        row(
          context.t('city.daily_boost'),
          context.t('city.more_visibility'),
          Pressable(
            onTap: cooldown
                ? () {}
                : () => users.set({
                      'boostedUntil': DateTime.now().add(const Duration(hours: 1)),
                      'lastBoost': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: cooldown ? Tw.slate800 : Tw.white, borderRadius: BorderRadius.circular(12)),
              child: Label(cooldown ? context.t('city.used') : context.t('city.activate_boost'), size: 9,
                  color: cooldown ? Tw.slate500 : Tw.black, tracking: -0.05),
            ),
          ),
        ),
      ]),
    );
  }
}
