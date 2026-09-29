import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/city_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/language_selector.dart';

// Illustration only (shown as "Ejemplo"), as app/page.tsx: no invented figures, and generic kinds of venue instead of
// real clubs that aren't on the platform.
class _LVenue {
  final String name;
  final double x;
  final double y;
  const _LVenue(this.name, this.x, this.y);
}

class _LCity {
  final String label;
  final String country;
  final String tag;
  final List<_LVenue> venues;
  const _LCity(this.label, this.country, this.tag, this.venues);
}

const _cities = {
  'madrid': _LCity('Madrid', 'ES', 'Furia & Afters', [
    _LVenue('Techno club', 28, 35),
    _LVenue('Big room club', 62, 48),
    _LVenue('House club', 50, 72),
    _LVenue('Urban & VIP', 74, 28),
    _LVenue('Tech house', 38, 82),
  ]),
  'barcelona': _LCity('Barcelona', 'ES', 'Beach & Raves', [
    _LVenue('Multi-room club', 70, 40),
    _LVenue('Live music', 35, 65),
    _LVenue('Beach club', 80, 70),
    _LVenue('Techno club', 25, 30),
  ]),
  'london': _LCity('London', 'UK', 'Warehouse & Bass', [
    _LVenue('Bass club', 52, 45),
    _LVenue('Warehouse', 75, 25),
    _LVenue('House club', 32, 68),
    _LVenue('Techno club', 42, 82),
  ]),
  'lisboa': _LCity('Lisboa', 'PT', 'Rooftops & Techno', [
    _LVenue('Waterfront club', 60, 55),
    _LVenue('Underground', 45, 38),
    _LVenue('Live music', 30, 70),
  ]),
  'paris': _LCity('Paris', 'FR', 'Electronique & Chic', [
    _LVenue('Electro club', 55, 40),
    _LVenue('Techno bunker', 35, 60),
    _LVenue('Visual club', 72, 75),
  ]),
  'berlin': _LCity('Berlin', 'DE', 'Industrial Techno', [
    _LVenue('Techno club', 48, 48),
    _LVenue('Riverside house', 68, 35),
    _LVenue('Industrial techno', 30, 65),
    _LVenue('Late-night club', 62, 78),
  ]),
};

/// lib/routes.ts CITY_SLUGS order.
const _citySlugs = ['madrid', 'london', 'barcelona', 'lisboa', 'paris', 'berlin'];

String _flag(String country) =>
    const {'ES': '🇪🇸', 'UK': '🇬🇧', 'PT': '🇵🇹', 'FR': '🇫🇷', 'DE': '🇩🇪'}[country] ?? '🌍';

const _bg = Color(0xFF04060E);
const _brandGradient = LinearGradient(colors: [Tw.fuchsia600, Tw.purple600, Tw.indigo600]);

/// Port of app/page.tsx — the guest landing. [onEnter] opens the radar shell.
class LandingScreen extends StatefulWidget {
  final VoidCallback onEnter;
  const LandingScreen({super.key, required this.onEnter});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _scroll = ScrollController();
  final _heroKey = GlobalKey();
  late String _slug;
  int _activeVenue = 0;
  bool _clubsTab = false;

  @override
  void initState() {
    super.initState();
    final stored = context.read<CityProvider>().citySlug;
    _slug = _cities.containsKey(stored) ? stored! : 'madrid';
    _scroll.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  _LCity get _city => _cities[_slug] ?? _cities['madrid']!;

  void _selectCity(String slug) {
    setState(() {
      _slug = slug;
      _activeVenue = 0;
    });
    // The showcase is illustrative: picking a city here doesn't change where the radar opens (the user's zone).
  }

  void _openRadar([String? slug]) {
    if (slug != null) _selectCity(slug);
    widget.onEnter();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    // useScroll({ target: hero, offset: ['start start', 'end start'] }): opacity 1→0 over progress 0–0.9, scale 1→0.95 over 0–1.
    // On the web the hero starts at y=0 (its pt-32 sits under the fixed header), so the range includes the list's top padding.
    final heroH = (_heroKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
    final range = top + 64 + heroH;
    final progress = _scroll.hasClients ? (_scroll.offset / range).clamp(0.0, 1.0) : 0.0;
    final heroOpacity = 1 - (progress / 0.9).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        const _Aurora(),
        ListView(
          controller: _scroll,
          padding: EdgeInsets.only(top: top + 64),
          children: [
            Opacity(
              opacity: heroOpacity,
              child: Transform.scale(scale: 1 - 0.05 * progress, child: KeyedSubtree(key: _heroKey, child: _hero(context))),
            ),
            _bento(context),
            _citiesShowcase(context),
            _audience(context),
            _footer(context),
          ],
        ),
        _header(context, top),
      ]),
    );
  }

  // ─── Header ───
  Widget _header(BuildContext context, double top) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: EdgeInsets.fromLTRB(12, top + 12, 12, 12),
              decoration: BoxDecoration(
                color: _bg.withValues(alpha: 0.8),
                border: Border(bottom: BorderSide(color: Tw.w(0.08))),
              ),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Tw.fuchsia600, Tw.indigo600]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.25), blurRadius: 15)],
                  ),
                  child: const Icon(Icons.radar, size: 16, color: Tw.white),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(TextSpan(children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: _GradientText('BLOW', const LinearGradient(colors: [Tw.white, Color(0xFFF1F5F9), Tw.slate400]),
                            style: tw(18, weight: black, tracking: -0.025)),
                      ),
                      TextSpan(text: 'NIGHTS', style: tw(18, weight: black, color: Tw.fuchsia500, tracking: -0.025)),
                    ])),
                  ),
                ),
                const Spacer(),
                _cityDropdown(context),
                const SizedBox(width: 6),
                _headerIcon(Icons.login, () => openRoute(context, AppRoute.login)),
                const SizedBox(width: 6),
                const LanguageSelector(),
                const SizedBox(width: 6),
                Pressable(
                  onTap: () => _openRadar(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: _brandGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.25), blurRadius: 15)],
                    ),
                    child: const Icon(Icons.explore, size: 16, color: Tw.white),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _headerIcon(IconData icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 16, color: Tw.slate300)),
      );

  Widget _cityDropdown(BuildContext context) => Builder(
        builder: (btnCtx) => Pressable(
          onTap: () => _openCityMenu(btnCtx),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_flag(_city.country), style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 12, color: Tw.slate600),
            ]),
          ),
        ),
      );

  void _openCityMenu(BuildContext btnCtx) {
    final box = btnCtx.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.of(btnCtx).size;
    showGeneralDialog(
      context: btnCtx,
      barrierDismissible: true,
      barrierLabel: 'city',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, _, _) => Stack(children: [
        Positioned(
          top: origin.dy + box.size.height + 8,
          right: screen.width - origin.dx - box.size.width,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 192,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Tw.slate900.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Tw.w(0.1)),
                boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 50, offset: Offset(0, 20))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final e in _cities.entries)
                  Pressable(
                    onTap: () {
                      _selectCity(e.key);
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _slug == e.key ? Tw.fuchsia500.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        Text(_flag(e.value.country), style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e.value.label, style: tw(12, weight: bold, color: _slug == e.key ? Tw.fuchsia300 : Tw.slate300))),
                        if (_slug == e.key) const Icon(Icons.check, size: 16, color: Tw.fuchsia400),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ]),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(anim), alignment: Alignment.topRight, child: child),
      ),
    );
  }

  // ─── Hero ───
  Widget _hero(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 64, 20, 80),
        child: Column(children: [
          _FadeIn(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(99), border: Border.all(color: Tw.w(0.1))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const _Pulse(child: SizedBox(width: 8, height: 8, child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.fuchsia500)))),
                const SizedBox(width: 8),
                Flexible(child: Label(context.t('landing_live_badge'), size: 11, weight: bold, color: Tw.slate300, tracking: 0.25)),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          _FadeIn(
            delay: 100,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: context.t('landing_hero_title_1')),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: _GradientText(
                    context.t('landing_hero_title_2'),
                    const LinearGradient(colors: [Tw.fuchsia400, Color(0xFFD8B4FE), Tw.indigo400]),
                    style: tw(36, weight: black, tracking: -0.025, height: 1.02),
                  ),
                ),
              ]),
              textAlign: TextAlign.center,
              style: tw(36, weight: black, tracking: -0.025, height: 1.02),
            ),
          ),
          const SizedBox(height: 24),
          _FadeIn(
            delay: 200,
            child: Text(context.t('landing_hero_description'),
                textAlign: TextAlign.center, style: tw(16, weight: FontWeight.w300, color: Tw.slate300, height: 1.6)),
          ),
          const SizedBox(height: 32),
          _FadeIn(
            delay: 300,
            child: Column(children: [
              Pressable(
                onTap: () => _openRadar(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: _brandGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.3), blurRadius: 50, offset: const Offset(0, 25))],
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.radar, size: 18, color: Tw.white),
                    const SizedBox(width: 8),
                    Flexible(
                        // Name the city only if the user is really in it; the radar opens on their own zone.
                        child: Label(
                            context.watch<CityProvider>().cityId == _slug
                                ? context.t('landing_cta_explore', params: {'city': _city.label})
                                : context.t('landing_cta_explore_near'),
                            size: 14,
                            weight: bold,
                            color: Tw.white,
                            tracking: 0.15)),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Pressable(
                onTap: () => openRoute(context, AppRoute.entradas),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(color: Tw.w(0.06), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.confirmation_number, size: 18, color: Tw.fuchsia400),
                    const SizedBox(width: 8),
                    Flexible(child: Label(context.t('landing_cta_tickets'), size: 14, weight: semibold, color: const Color(0xFFE2E8F0), tracking: 0.15)),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 48),
          _FadeIn(delay: 200, child: _radarWidget(context)),
        ]),
      );

  Widget _radarWidget(BuildContext context) {
    final city = _city;
    final active = city.venues[_activeVenue.clamp(0, city.venues.length - 1)];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF080C1B).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Tw.w(0.15)),
        boxShadow: [
          BoxShadow(color: Tw.fuchsia600.withValues(alpha: 0.15), blurRadius: 40),
          const BoxShadow(color: Color(0xCC000000), blurRadius: 50, offset: Offset(0, 25)),
        ],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.w(0.08)))),
          child: Row(children: [
            const _PingDot(),
            const SizedBox(width: 8),
            Expanded(child: Label(context.t('landing_radar_demo_title'), size: 12, weight: bold, color: const Color(0xFFE2E8F0), tracking: 0.2)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Tw.fuchsia500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.2)),
              ),
              child: Text(context.t('landing_demo_badge'), style: tw(11, color: Tw.fuchsia400).copyWith(fontFamily: 'monospace')),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final slug in _citySlugs)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Pressable(
                  onTap: () => _selectCity(slug),
                  child: AnimatedScale(
                    scale: slug == _slug ? 1.03 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: slug == _slug ? const LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]) : null,
                        color: slug == _slug ? null : Tw.w(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: slug == _slug ? null : Border.all(color: Tw.w(0.05)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_flag(_cities[slug]?.country ?? 'ES')),
                        const SizedBox(width: 6),
                        Text(_cities[slug]?.label ?? slug, style: tw(12, weight: semibold, color: slug == _slug ? Tw.white : Tw.slate400)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 20),
        AspectRatio(
          aspectRatio: 1,
          child: _RadarScreen(
            key: ValueKey(_slug),
            venues: city.venues,
            active: _activeVenue,
            youLabel: context.t('landing_radar_you'),
            onSelect: (i) => setState(() => _activeVenue = i),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Tw.w(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.08))),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Tw.fuchsia600, Tw.indigo600]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.nightlife, size: 18, color: Tw.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(active.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(12, weight: bold)),
                Text(city.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(11, color: Tw.slate400)),
              ]),
            ),
            const SizedBox(width: 12),
            Pressable(
              onTap: () => _openRadar(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.arrow_forward, size: 14, color: Tw.white),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ─── Bento ───
  Widget _sectionHead(BuildContext context, String badge, Color badgeColor, String title, String subtitle, {double titleSize = 30}) => _FadeIn(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: badgeColor.withValues(alpha: 0.2)),
            ),
            child: Label(badge, size: 12, weight: bold, color: badgeColor, tracking: 0.3),
          ),
          const SizedBox(height: 24),
          Text(title, textAlign: TextAlign.center, style: tw(titleSize, weight: black, tracking: -0.025, height: 1.1)),
          const SizedBox(height: 16),
          Text(subtitle, textAlign: TextAlign.center, style: tw(16, weight: FontWeight.w300, color: Tw.slate400, height: 1.6)),
        ]),
      );

  Widget _bentoCard({required Color accent, required IconData icon, required String label, required String title, required String desc, Widget? footer}) =>
      _FadeIn(
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tw.w(0.06), Tw.w(0.02)]),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Tw.w(0.1)),
          ),
          child: Stack(children: [
            Positioned(top: -80, right: -80, child: Orb(color: accent.withValues(alpha: 0.12), size: 280)),
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, size: 24, color: Color.lerp(accent, Tw.white, 0.25)),
                ),
                const SizedBox(height: 24),
                Label(label, size: 12, weight: bold, color: Color.lerp(accent, Tw.white, 0.25)!, tracking: 0.2),
                const SizedBox(height: 8),
                Text(title, style: tw(24, weight: bold, height: 1.2)),
                const SizedBox(height: 12),
                Text(desc, style: tw(14, color: Tw.slate400, height: 1.6)),
                if (footer != null) ...[const SizedBox(height: 24), footer],
              ]),
            ),
          ]),
        ),
      );

  Widget _bento(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 64, 20, 40),
        child: Column(children: [
          _sectionHead(context, context.t('landing_bento_badge'), Tw.fuchsia400, context.t('landing_bento_title'), context.t('landing_bento_subtitle')),
          const SizedBox(height: 48),
          _bentoCard(
            accent: Tw.fuchsia500,
            icon: Icons.radar,
            label: context.t('landing_bento1_label'),
            title: context.t('landing_bento1_title'),
            desc: context.t('landing_bento1_desc'),
          ),
          _bentoCard(
            accent: Tw.indigo500,
            icon: Icons.confirmation_number,
            label: context.t('landing_bento2_label'),
            title: context.t('landing_bento2_title'),
            desc: context.t('landing_bento2_desc'),
            footer: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B4B).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Tw.indigo500.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.qr_code_scanner, size: 24, color: Tw.indigo400),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('landing_bento2_scan'), style: tw(12, weight: bold)),
                    Text(context.t('landing_bento2_scan_desc'), style: tw(11, color: Tw.slate400)),
                  ]),
                ),
              ]),
            ),
          ),
          _bentoCard(
            accent: const Color(0xFF06B6D4),
            icon: Icons.groups,
            label: context.t('landing_bento3_label'),
            title: context.t('landing_bento3_title'),
            desc: context.t('landing_bento3_desc'),
            footer: Wrap(spacing: 8, runSpacing: 8, children: [
              _tag(context.t('landing_bento3_tag1'), const Color(0xFF06B6D4), const Color(0xFF67E8F9)),
              _tag(context.t('landing_bento3_tag2'), Tw.purple500, const Color(0xFFD8B4FE)),
            ]),
          ),
          _bentoCard(
            accent: Tw.purple500,
            icon: Icons.verified,
            label: context.t('landing_bento4_label'),
            title: context.t('landing_bento4_title'),
            desc: context.t('landing_bento4_desc'),
            footer: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 3,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final k in ['landing_bento4_badge1', 'landing_bento4_badge2', 'landing_bento4_badge3', 'landing_bento4_badge4'])
                  Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: Tw.w(0.04), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
                    child: Text(context.t(k), textAlign: TextAlign.center, maxLines: 2, style: tw(12, weight: medium, color: Tw.slate300)),
                  ),
              ],
            ),
          ),
        ]),
      );

  Widget _tag(String text, Color base, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: base.withValues(alpha: 0.2)),
        ),
        child: Text(text, style: tw(12, weight: semibold, color: fg)),
      );

  // ─── Cities ───
  Widget _citiesShowcase(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 96, 20, 96),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.w(0.08)))),
        child: Column(children: [
          _sectionHead(context, context.t('landing_cities_badge'), Tw.indigo400, context.t('landing_cities_title'), context.t('landing_cities_subtitle')),
          const SizedBox(height: 64),
          for (final slug in _citySlugs)
            if (_cities[slug] case final city?)
              _FadeIn(
                child: Pressable(
                  onTap: () => _openRadar(slug),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Tw.w(0.04), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
                    child: Column(children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_flag(city.country), style: const TextStyle(fontSize: 30)),
                            const SizedBox(height: 8),
                            Text(city.label, style: tw(24, weight: black)),
                            const SizedBox(height: 2),
                            Text(city.tag, style: tw(12, color: Tw.slate400)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.only(top: 16),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.w(0.08)))),
                        child: Row(children: [
                          Expanded(child: Label(context.t('landing_cities_open_radar'), size: 12, weight: bold, color: Tw.slate300, tracking: 0.05)),
                          const Icon(Icons.arrow_forward, size: 16, color: Tw.fuchsia400),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
        ]),
      );


  // ─── Clubbers / Clubs ───
  Widget _audience(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 96, 20, 96),
        child: Column(children: [
          _FadeIn(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Tw.w(0.06), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _audienceTab(context.t('landing_tab_clubbers'), !_clubsTab, Tw.fuchsia600, () => setState(() => _clubsTab = false)),
                _audienceTab(context.t('landing_tab_clubs'), _clubsTab, Tw.indigo600, () => setState(() => _clubsTab = true)),
              ]),
            ),
          ),
          const SizedBox(height: 40),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(a), child: c),
            ),
            child: _clubsTab ? _clubsCard(context) : _clubbersCard(context),
          ),
        ]),
      );

  Widget _audienceTab(String label, bool active, Color color, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 15)] : null,
          ),
          child: Label(label, size: 11, weight: bold, color: active ? Tw.white : Tw.slate400, tracking: 0.05),
        ),
      );

  Widget _clubbersCard(BuildContext context) => Container(
        key: const ValueKey('clubbers'),
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF4A044E).withValues(alpha: 0.3), Tw.slate900.withValues(alpha: 0.6), const Color(0xFF1E1B4B).withValues(alpha: 0.3)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(context.t('landing_clubbers_title'), textAlign: TextAlign.center, style: tw(30, weight: black, height: 1.15)),
          const SizedBox(height: 16),
          Text(context.t('landing_clubbers_desc'), textAlign: TextAlign.center, style: tw(16, weight: FontWeight.w300, color: Tw.slate300, height: 1.5)),
          const SizedBox(height: 32),
          Pressable(
            onTap: () => _openRadar(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                gradient: AppTheme.ctaGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.25), blurRadius: 25)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt, size: 18, color: Tw.white),
                const SizedBox(width: 8),
                Flexible(child: Label(context.t('landing_clubbers_cta'), size: 14, weight: bold, color: Tw.white, tracking: 0.1)),
              ]),
            ),
          ),
        ]),
      );

  Widget _clubsCard(BuildContext context) => Container(
        key: const ValueKey('clubs'),
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF1E1B4B).withValues(alpha: 0.4), Tw.slate900.withValues(alpha: 0.6), Tw.slate950],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Tw.indigo500.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Tw.indigo500.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Tw.indigo500.withValues(alpha: 0.2)),
            ),
            child: Label(context.t('landing_clubs_plan'), size: 12, weight: bold, color: Tw.indigo400, tracking: 0.05),
          ),
          const SizedBox(height: 16),
          Text(context.t('landing_clubs_title'), textAlign: TextAlign.center, style: tw(30, weight: black, height: 1.15)),
          const SizedBox(height: 16),
          Text(context.t('landing_clubs_desc'), textAlign: TextAlign.center, style: tw(16, weight: FontWeight.w300, color: Tw.slate300, height: 1.5)),
          const SizedBox(height: 32),
          Pressable(
            onTap: () => openRoute(context, AppRoute.business),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(16)),
              child: Label(context.t('landing_clubs_cta_register'), size: 14, weight: bold, color: Tw.slate950, tracking: 0.1, align: TextAlign.center),
            ),
          ),
          const SizedBox(height: 16),
          Pressable(
            onTap: () => openRoute(context, AppRoute.scanner),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(color: Tw.w(0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
              child: Label(context.t('landing_clubs_cta_scanner'), size: 14, weight: semibold, color: Tw.white, tracking: 0.05, align: TextAlign.center),
            ),
          ),
        ]),
      );

  // ─── Footer ───
  Widget _footer(BuildContext context) {
    Widget link(String key, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Label(context.t(key), size: 12, weight: bold, tracking: 0.15),
        );
    return Container(
      padding: EdgeInsets.fromLTRB(20, 56, 20, 56 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: const Color(0xFF020308), border: Border(top: BorderSide(color: Tw.w(0.08)))),
      child: Column(children: [
        _GradientText('BLOW NIGHTS', const LinearGradient(colors: [Tw.fuchsia500, Tw.indigo500]), style: tw(18, weight: black, tracking: -0.025)),
        const SizedBox(height: 8),
        Text(context.t('landing_footer_tagline'), textAlign: TextAlign.center, style: tw(12, weight: FontWeight.w300, color: Tw.slate500)),
        const SizedBox(height: 32),
        Wrap(alignment: WrapAlignment.center, spacing: 32, runSpacing: 16, children: [
          link('landing_footer_radar', () => _openRadar()),
          link('landing_footer_tickets', () => openRoute(context, AppRoute.entradas)),
          link('landing_footer_venues', () => openRoute(context, AppRoute.business)),
          link('landing_footer_scanner', () => openRoute(context, AppRoute.scanner)),
          link('landing_footer_privacy', () => openRoute(context, AppRoute.privacy)),
          link('landing_footer_terms', () => openRoute(context, AppRoute.terms)),
        ]),
        const SizedBox(height: 32),
        Text('© ${DateTime.now().year} ${context.t('landing_footer_copyright')}',
            style: tw(12, color: Tw.slate600).copyWith(fontFamily: 'monospace')),
      ]),
    );
  }
}

/// Background glows + dot grid (fixed behind the scroll).
class _Aurora extends StatelessWidget {
  const _Aurora();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      child: Stack(children: [
        Positioned(
          top: -size.height * 0.1,
          left: size.width / 2 - 350,
          child: Container(
            width: 700,
            height: 450,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [Tw.fuchsia600.withValues(alpha: 0.18), Tw.indigo600.withValues(alpha: 0.08), Colors.transparent]),
            ),
          ),
        ),
        Positioned(top: size.height * 0.35, left: -size.width * 0.1 - 150, child: Orb(color: Tw.purple600.withValues(alpha: 0.1), size: 500)),
        Positioned(top: size.height * 0.6, right: -size.width * 0.1 - 150, child: Orb(color: const Color(0xFF0891B2).withValues(alpha: 0.1), size: 550)),
        Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
      ]),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Tw.white.withValues(alpha: 0.4 * 0.04);
    for (var y = 1.0; y < size.height; y += 32) {
      for (var x = 1.0; x < size.width; x += 32) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The circular radar simulation: rings, crosshair, rotating conic sweep, pulsing hotspots.
class _RadarScreen extends StatefulWidget {
  final List<_LVenue> venues;
  final int active;
  final String youLabel;
  final ValueChanged<int> onSelect;
  const _RadarScreen({super.key, required this.venues, required this.active, required this.youLabel, required this.onSelect});

  @override
  State<_RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<_RadarScreen> with TickerProviderStateMixin {
  late final _sweep = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  late final _appear = AnimationController(vsync: this, duration: Duration(milliseconds: 400 + widget.venues.length * 80))..forward();

  @override
  void dispose() {
    _sweep.dispose();
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF050713),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Tw.w(0.08)),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          Widget ring(double f, Color color) => Center(
                child: Container(
                  width: w * f,
                  height: h * f,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color)),
                ),
              );
          return Stack(clipBehavior: Clip.none, children: [
            ring(0.8, Tw.fuchsia500.withValues(alpha: 0.15)),
            ring(0.55, Tw.indigo500.withValues(alpha: 0.2)),
            ring(0.3, Tw.w(0.1)),
            Positioned(left: 0, right: 0, top: h / 2, child: Container(height: 1, color: Tw.w(0.06))),
            Positioned(top: 0, bottom: 0, left: w / 2, child: Container(width: 1, color: Tw.w(0.06))),
            Positioned.fill(
              child: IgnorePointer(
                child: RotationTransition(
                  turns: _sweep,
                  child: Transform.scale(
                    scale: 1.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: SweepGradient(
                          startAngle: -math.pi / 2,
                          endAngle: 3 * math.pi / 2,
                          colors: [Tw.fuchsia500.withValues(alpha: 0.25), Colors.transparent],
                          stops: const [0, 65 / 360],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                _Ping(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Tw.white,
                      boxShadow: [BoxShadow(color: Tw.white, blurRadius: 15)],
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  child: Text(widget.youLabel, style: tw(9, color: Tw.slate400, tracking: 0.1).copyWith(fontFamily: 'monospace')),
                ),
              ]),
            ),
            for (final (i, v) in widget.venues.indexed) _hotspot(i, v, w, h),
          ]);
        }),
      );

  Widget _hotspot(int i, _LVenue v, double w, double h) {
    final isActive = i == widget.active;
    final start = (i * 80) / _appear.duration!.inMilliseconds;
    final anim = CurvedAnimation(parent: _appear, curve: Interval(start.clamp(0.0, 1.0), 1));
    return Positioned(
      left: w * v.x / 100 - 60,
      top: h * v.y / 100 - 60,
      width: 120,
      height: 120,
      child: ScaleTransition(
        scale: anim,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          if (isActive)
            IgnorePointer(
              child: _Ping(child: Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.fuchsia500.withValues(alpha: 0.3)))),
            ),
          GestureDetector(
            onTap: () => widget.onSelect(i),
            child: AnimatedScale(
              scale: isActive ? 1.25 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? Tw.fuchsia500 : Tw.indigo600.withValues(alpha: 0.8),
                  boxShadow: isActive ? [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.8), blurRadius: 15)] : null,
                ),
                child: const Icon(Icons.nightlife, size: 12, color: Tw.white),
              ),
            ),
          ),
          Positioned(
            bottom: 60 + 12 + 6,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: isActive ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Tw.slate900.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Tw.w(0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(v.name, softWrap: false, style: tw(11, weight: bold, height: 1.2)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// `animate-ping`: a copy scales to 2x while fading out, looping every second.
class _Ping extends StatefulWidget {
  final Widget child;
  const _Ping({required this.child});

  @override
  State<_Ping> createState() => _PingState();
}

class _PingState extends State<_Ping> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = Curves.easeOut.transform(_c.value);
          return Transform.scale(scale: 1 + t, child: Opacity(opacity: 1 - t, child: child));
        },
        child: widget.child,
      );
}

/// Solid dot with an `animate-ping` halo behind it.
class _PingDot extends StatelessWidget {
  const _PingDot();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 12,
        height: 12,
        child: Stack(children: [
          _Ping(child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.fuchsia400.withValues(alpha: 0.75)))),
          Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Tw.fuchsia500)),
        ]),
      );
}

/// `animate-pulse`: opacity 1 → .5 → 1 every 2s.
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: Tween(begin: 1.0, end: 0.5).animate(_c), child: widget.child);
}

/// FadeInSection: fades up 35px when first built (list items build as they scroll into view).
class _FadeIn extends StatelessWidget {
  final Widget child;
  final int delay;
  const _FadeIn({required this.child, this.delay = 0});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 700 + delay),
        curve: Interval(delay / (700 + delay), 1, curve: const Cubic(0.22, 1, 0.36, 1)),
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 35 * (1 - v)), child: c)),
        child: child,
      );
}

/// `bg-clip-text text-transparent bg-gradient-to-r`
class _GradientText extends StatelessWidget {
  final String text;
  final Gradient gradient;
  final TextStyle style;
  const _GradientText(this.text, this.gradient, {required this.style});

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (b) => gradient.createShader(Offset.zero & b.size),
        child: Text(text, style: style.copyWith(color: Tw.white)),
      );
}
