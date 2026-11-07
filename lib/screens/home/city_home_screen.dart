import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/event.dart';
import '../../models/venue.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/city_provider.dart';
import '../../providers/venues_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/poster.dart';
import '../../widgets/language_selector.dart';

/// Port of app/[city]/page.tsx
class CityHomeScreen extends StatelessWidget {
  const CityHomeScreen({super.key});

  static const _busy = 50, _rising = 10, _active = 1;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final city = context.watch<CityProvider>();
    final data = context.watch<VenuesProvider>();
    final user = auth.user;

    final hour = DateTime.now().hour;
    final greeting = hour >= 5 && hour < 14
        ? context.t('home.greeting_morning', fallback: 'Buenos dias')
        : hour < 21
        ? context.t('home.greeting_afternoon', fallback: 'Buenas tardes')
        : context.t('home.greeting_night', fallback: 'Buenas noches');

    if (auth.loading || data.loading || city.loading) return const _HomeSkeleton();

    final events = data.upcomingEvents;
    final commercial = data.all.where((v) => v.meta == null || v.meta!.group == 'commercial').toList();
    // Check-ins are real even without opening hours: people there say more than a schedule.
    int checks(Venue v) => v.openStatus != VenueOpenStatus.closed ? data.liveCountFor(v) : 0;
    bool hasEvent(Venue v) => events.any((e) => e.venueId == v.id);
    // Stable sort, same priority as the web: open > no schedule > closed, then hottest, then has event tonight.
    final indexed = commercial.asMap().entries.toList()
      ..sort((a, b) {
        final av = a.value, bv = b.value;
        final ao = av.openStatus, bo = bv.openStatus;
        if (ao != bo) return ao.index - bo.index;
        final ac = checks(av), bc = checks(bv);
        if (ac != bc) return bc - ac;
        final ae = hasEvent(av), be = hasEvent(bv);
        if (ae != be) return ae ? -1 : 1;
        return a.key - b.key;
      });
    final venues = indexed.map((e) => e.value).take(10).toList();

    return Scaffold(
      body: PartyGlow(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 112),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: tw(14, weight: semibold, color: Tw.sun),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          city.currentCity?.name ?? context.t('city.near_you'),
                          style: tw(30, weight: FontWeight.w800, tracking: -0.025, height: 1.15),
                        ),
                      ],
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(top: 4), child: LanguageSelector()),
                ],
              ),
              const SizedBox(height: 24),
              _RadarCard(onTap: () => openRoute(context, AppRoute.map)),
              if (user != null) ...[const SizedBox(height: 24), _QuickLinks()],
              if (venues.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  context.t('radar.status', fallback: 'Estado del Radar'),
                  style: tw(20, weight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < venues.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FadeIn(
                      delay: Duration(milliseconds: i * 50),
                      child: _VenueStatusCard(
                        venue: venues[i],
                        checks: checks(venues[i]),
                        hasEventToday: hasEvent(venues[i]),
                        loggedIn: user != null,
                      ),
                    ),
                  ),
              ],
              if (events.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.t('events.title', fallback: 'Eventos y Planes'),
                        style: tw(20, weight: FontWeight.w800),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => openRoute(context, AppRoute.events),
                      child: Text(
                        context.t('city.see_more', fallback: 'Ver más'),
                        style: tw(14, weight: bold, color: Tw.sun),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 208,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: events.length > 5 ? 5 : events.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _EventMiniCard(event: events[i]),
                  ),
                ),
              ],
              if (events.isEmpty && venues.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 64),
                  child: Column(
                    children: [
                      Poster(
                        kind: PosterKind.violet,
                        width: 80,
                        height: 80,
                        shade: false,
                        radius: BorderRadius.circular(24),
                        child: const Center(child: Icon(Icons.explore, size: 36, color: Tw.white)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.t('home.empty', fallback: 'Todavia no hay actividad en tu ciudad'),
                        textAlign: TextAlign.center,
                        style: tw(16, color: Tw.inkSoft),
                      ),
                      if (user != null) ...[
                        const SizedBox(height: 16),
                        Pressable(
                          onTap: () => openRoute(context, AppRoute.venues),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: AppTheme.ctaGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              context.t('home.explore', fallback: 'Explorar locales'),
                              style: tw(14, weight: bold),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (user == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(
                        context.t('home.register_cta', fallback: 'Regístrate para acceder a todas las funciones'),
                        textAlign: TextAlign.center,
                        style: tw(14, color: Tw.inkSoft),
                      ),
                      const SizedBox(height: 12),
                      GradientButton(
                        label: context.t('home.register_btn', fallback: 'Crear Cuenta'),
                        fontSize: 12,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        onTap: () => openRoute(context, AppRoute.login),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadarCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RadarCard({required this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Tw.line),
      ),
      child: Poster(
        kind: PosterKind.club,
        height: 160,
        radius: BorderRadius.circular(23),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Tw.night.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Tw.w(0.2)),
                    ),
                    child: const Icon(Icons.radar, color: Tw.sun, size: 24),
                  ),
                  const Spacer(),
                  const LiveBars(),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('radar.open', fallback: 'Abrir Radar'),
                          style: tw(24, weight: FontWeight.w800, height: 1.2),
                        ),
                        Text(
                          context.t('radar.view_map', fallback: 'Ver mapa en tiempo real'),
                          style: tw(14, color: Tw.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const CtaCircle(icon: Icons.arrow_forward),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _QuickLinks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final unread = context.watch<UnreadChats>().count;
    Widget tile(IconData icon, Color color, String label, AppRoute route, {int badge = 0}) => Expanded(
      child: GlassCard(
        onTap: () => openRoute(context, route),
        radius: 16,
        color: Tw.panel,
        padding: const EdgeInsets.all(16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tw(12, weight: semibold, color: Tw.inkSoft),
                  ),
                ],
              ),
            ),
            if (badge > 0) Positioned(top: -20, right: -20, child: CountBadge(badge)),
          ],
        ),
      ),
    );
    return Row(
      children: [
        tile(Icons.chat, Tw.live, context.t('nav.chat', fallback: 'Chat'), AppRoute.chat, badge: unread),
        const SizedBox(width: 12),
        tile(Icons.visibility, Tw.sun, context.t('profile.my_visits', fallback: 'Visitas'), AppRoute.visits),
        const SizedBox(width: 12),
        tile(
          Icons.confirmation_number,
          Tw.sunset,
          context.t('profile.tickets', fallback: 'Entradas'),
          AppRoute.tickets,
        ),
      ],
    );
  }
}

class _VenueStatusCard extends StatelessWidget {
  final Venue venue;
  final int checks;
  final bool hasEventToday;
  final bool loggedIn;
  const _VenueStatusCard({
    required this.venue,
    required this.checks,
    required this.hasEventToday,
    required this.loggedIn,
  });

  @override
  Widget build(BuildContext context) {
    final status = venue.openStatus;
    var icon = '🟢';
    var label = context.t('radar.status_quiet', fallback: 'Abierto • Ambiente tranquilo');
    var color = Tw.live;
    if (status == VenueOpenStatus.closed) {
      icon = '🌙';
      label = context.t('venuesPage.closed_now', fallback: 'Cerrado');
      color = Tw.inkDim;
    } else if (checks >= CityHomeScreen._busy) {
      icon = '🔥';
      label = context.t('radar.status_busy', fallback: 'Mucho ambiente');
      color = Tw.red500;
    } else if (checks >= CityHomeScreen._rising) {
      icon = '📈';
      label = context.t('radar.status_rising', fallback: 'Subiendo');
      color = Tw.sun;
    } else if (checks >= CityHomeScreen._active) {
      label = '$checks ${checks == 1 ? 'persona en directo' : 'personas en directo'}';
      color = Tw.sun;
    } else if (hasEventToday) {
      icon = '📅';
      label = context.t('radar.status_event', fallback: 'Evento esta noche');
      color = Tw.blue400;
    } else if (status == VenueOpenStatus.unknown) {
      icon = '🕓';
      label = context.t('radar.status_no_hours', fallback: 'Horario no disponible');
      color = Tw.inkSoft;
    }

    return GlassCard(
      onTap: loggedIn ? () => openRoute(context, AppRoute.venues, args: {'highlight': venue.id}) : null,
      radius: 24,
      color: Tw.panel,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Poster(type: venue.type, imageUrl: venue.bannerUrl, width: 64, height: 64, radius: BorderRadius.circular(16)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tw(12, weight: bold, color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        venue.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tw(16, weight: FontWeight.w800, party: true),
                      ),
                    ),
                    if (checks > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Tw.party.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text('$checks ${checks == 1 ? 'persona' : 'personas'}', style: tw(12, weight: bold)),
                      ),
                    ],
                  ],
                ),
                if (venue.address.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '📍 ${venue.address}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tw(12, color: Tw.inkDim),
                  ),
                ],
                if (checks > 0 || status == VenueOpenStatus.open) ...[
                  const SizedBox(height: 2),
                  Text(
                    checks > 0
                        ? '$checks ${checks == 1 ? 'persona ahora' : 'personas ahora'}'
                        : context.t('radar.no_queue', fallback: 'Sin cola'),
                    style: tw(12, color: Tw.inkDim),
                  ),
                ],
              ],
            ),
          ),
          if (loggedIn) const Icon(Icons.chevron_right, color: Tw.inkDim),
        ],
      ),
    );
  }
}

class _EventMiniCard extends StatelessWidget {
  final Event event;
  const _EventMiniCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final d = event.start;
    final now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final today = d != null && sameDay(d, now);
    final tomorrow = d != null && sameDay(d, now.add(const Duration(days: 1)));
    final timeLabel = today
        ? context.t('events.today', fallback: 'Hoy')
        : tomorrow
        ? context.t('events.tomorrow', fallback: 'Mañana')
        : d != null
        ? DateFormat('EEE d', 'es').format(d)
        : '';
    final timeStr = d != null ? DateFormat('HH:mm').format(d) : '';

    return Pressable(
      onTap: () => openRoute(context, AppRoute.eventDetail, args: {'eventId': event.id}),
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Tw.line),
        ),
        child: Poster(
          type: 'event',
          imageUrl: event.bannerUrl,
          radius: BorderRadius.circular(23),
          child: Stack(
            children: [
              if (timeLabel.isNotEmpty)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Tw.sun, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      timeLabel,
                      style: tw(12, weight: bold, color: Tw.night),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tw(16, weight: FontWeight.w800, height: 1.2, party: true),
                    ),
                    if (timeStr.isNotEmpty) Text(timeStr, style: tw(12, color: Tw.inkSoft)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FadeIn extends StatelessWidget {
  final Widget child;
  final Duration delay;
  const _FadeIn({required this.child, required this.delay});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 300) + delay,
    curve: Interval(delay.inMilliseconds / (300 + delay.inMilliseconds), 1, curve: Curves.easeOut),
    builder: (_, v, c) => Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: c),
    ),
    child: child,
  );
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w, double r = 24, Color? c}) => Container(
      height: h,
      width: w,
      decoration: BoxDecoration(color: c ?? Tw.panelSoft, borderRadius: BorderRadius.circular(r)),
    );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              box(12, w: 96, r: 4, c: Tw.party.withValues(alpha: 0.2)),
              const SizedBox(height: 8),
              box(28, w: 160, r: 12),
              const SizedBox(height: 24),
              box(80),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: box(80, r: 16)),
                  const SizedBox(width: 12),
                  Expanded(child: box(80, r: 16)),
                  const SizedBox(width: 12),
                  Expanded(child: box(80, r: 16)),
                ],
              ),
              const SizedBox(height: 24),
              box(16, w: 128, r: 4),
              const SizedBox(height: 12),
              box(112),
              const SizedBox(height: 12),
              box(112),
            ],
          ),
        ),
      ),
    );
  }
}
