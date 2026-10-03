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
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 112),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Label(greeting, size: 12, weight: bold, color: Tw.fuchsia400),
                    const SizedBox(height: 4),
                    Text(city.currentCity?.name ?? context.t('city.near_you'), style: tw(24, weight: black)),
                  ]),
                ),
                const Padding(padding: EdgeInsets.only(top: 4), child: LanguageSelector()),
              ],
            ),
            const SizedBox(height: 24),
            _RadarCard(onTap: () => openRoute(context, AppRoute.map)),
            if (user != null) ...[
              const SizedBox(height: 24),
              _QuickLinks(),
            ],
            if (venues.isNotEmpty) ...[
              const SizedBox(height: 24),
              Label(context.t('radar.status', fallback: 'Estado del Radar'), size: 14, tracking: 0.05),
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
              Row(children: [
                Expanded(child: Label(context.t('events.title', fallback: 'Eventos y Planes'), size: 14, tracking: 0.05)),
                GestureDetector(
                  onTap: () => openRoute(context, AppRoute.events),
                  child: Label(context.t('city.see_more', fallback: 'Ver más'), color: Tw.fuchsia500),
                ),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                height: 158,
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
                child: Column(children: [
                  const Icon(Icons.explore, size: 48, color: Tw.slate700),
                  const SizedBox(height: 16),
                  Text(context.t('home.empty', fallback: 'Todavia no hay actividad en tu ciudad'),
                      textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
                  if (user != null) ...[
                    const SizedBox(height: 16),
                    Pressable(
                      onTap: () => openRoute(context, AppRoute.venues),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.circular(16)),
                        child: Label(context.t('home.explore', fallback: 'Explorar locales'), size: 12, color: Tw.white),
                      ),
                    ),
                  ],
                ]),
              ),
            if (user == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(children: [
                  Text(context.t('home.register_cta', fallback: 'Regístrate para acceder a todas las funciones'),
                      textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
                  const SizedBox(height: 12),
                  GradientButton(
                    label: context.t('home.register_btn', fallback: 'Crear Cuenta'),
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    onTap: () => openRoute(context, AppRoute.login),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _RadarCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RadarCard({required this.onTap});

  @override
  Widget build(BuildContext context) => GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(24),
        radius: 24,
        borderColor: Tw.fuchsia500.withValues(alpha: 0.3),
        gradient: LinearGradient(colors: [
          Tw.fuchsia600.withValues(alpha: 0.2),
          Tw.indigo600.withValues(alpha: 0.2),
        ]),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Tw.fuchsia500.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.radar, color: Tw.fuchsia400, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('radar.open', fallback: 'Abrir Radar'), style: tw(18, weight: black)),
              const SizedBox(height: 2),
              Label(context.t('radar.view_map', fallback: 'Ver mapa en tiempo real'), weight: bold),
            ]),
          ),
          const Icon(Icons.arrow_forward, color: Tw.slate500),
        ]),
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
            padding: const EdgeInsets.all(16),
            child: Stack(clipBehavior: Clip.none, children: [
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(height: 8),
                  Label(label, size: 9, tracking: 0.05),
                ]),
              ),
              if (badge > 0) Positioned(top: -20, right: -20, child: CountBadge(badge)),
            ]),
          ),
        );
    return Row(children: [
      tile(Icons.chat, Tw.blue400, context.t('nav.chat', fallback: 'Chat'), AppRoute.chat, badge: unread),
      const SizedBox(width: 12),
      tile(Icons.visibility, Tw.purple400, context.t('profile.my_visits', fallback: 'Visitas'), AppRoute.visits),
      const SizedBox(width: 12),
      tile(Icons.confirmation_number, Tw.fuchsia400, context.t('profile.tickets', fallback: 'Entradas'), AppRoute.tickets),
    ]);
  }
}

class _VenueStatusCard extends StatelessWidget {
  final Venue venue;
  final int checks;
  final bool hasEventToday;
  final bool loggedIn;
  const _VenueStatusCard({required this.venue, required this.checks, required this.hasEventToday, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    final status = venue.openStatus;
    var icon = '🟢';
    var label = context.t('radar.status_quiet', fallback: 'Abierto • Ambiente tranquilo');
    var color = Tw.emerald400;
    if (status == VenueOpenStatus.closed) {
      icon = '🌙';
      label = context.t('venuesPage.closed_now', fallback: 'Cerrado');
      color = Tw.slate500;
    } else if (checks >= CityHomeScreen._busy) {
      icon = '🔥';
      label = context.t('radar.status_busy', fallback: 'Mucho ambiente');
      color = Tw.red500;
    } else if (checks >= CityHomeScreen._rising) {
      icon = '📈';
      label = context.t('radar.status_rising', fallback: 'Subiendo');
      color = Tw.amber400;
    } else if (checks >= CityHomeScreen._active) {
      label = '$checks ${checks == 1 ? 'persona en directo' : 'personas en directo'}';
      color = Tw.fuchsia400;
    } else if (hasEventToday) {
      icon = '📅';
      label = context.t('radar.status_event', fallback: 'Evento esta noche');
      color = Tw.blue400;
    } else if (status == VenueOpenStatus.unknown) {
      icon = '🕓';
      label = context.t('radar.status_no_hours', fallback: 'Horario no disponible');
      color = Tw.slate400;
    }

    return GlassCard(
      onTap: loggedIn ? () => openRoute(context, AppRoute.venues, args: {'highlight': venue.id}) : null,
      radius: 24,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Label(label, size: 14, color: color, tracking: 0.05, maxLines: 1)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                Text(venue.name, style: tw(16, weight: bold)),
                if (checks > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Tw.fuchsia500.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('$checks ${checks == 1 ? 'persona' : 'personas'}',
                        style: tw(10, weight: black, color: Tw.fuchsia400)),
                  ),
              ]),
              if (venue.address.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('📍 ${venue.address}', style: tw(12, color: Tw.slate500)),
              ],
              if (checks > 0 || status == VenueOpenStatus.open) ...[
                const SizedBox(height: 2),
                Text(
                  checks > 0
                      ? '$checks ${checks == 1 ? 'persona ahora' : 'personas ahora'}'
                      : context.t('radar.no_queue', fallback: 'Sin cola'),
                  style: tw(12, color: Tw.slate500),
                ),
              ],
            ]),
          ),
          if (loggedIn) const Icon(Icons.chevron_right, color: Tw.slate600),
        ]),
      ]),
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
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Tw.w(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Tw.w(0.1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NetImage(
            event.bannerUrl,
            width: 200,
            height: 96,
            placeholder: Container(
              width: 200,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Tw.fuchsia600.withValues(alpha: 0.2), Tw.indigo600.withValues(alpha: 0.2)],
                ),
              ),
              child: const Icon(Icons.event, size: 30, color: Tw.slate600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(12, weight: black)),
              const SizedBox(height: 4),
              Text('$timeLabel${timeStr.isNotEmpty ? ' · $timeStr' : ''}', style: tw(10, color: Tw.slate500)),
            ]),
          ),
        ]),
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
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: c)),
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
          decoration: BoxDecoration(color: c ?? Tw.w(0.05), borderRadius: BorderRadius.circular(r)),
        );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            box(12, w: 96, r: 4, c: Tw.fuchsia500.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            box(28, w: 160, r: 12),
            const SizedBox(height: 24),
            box(80),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: box(80, r: 16)),
              const SizedBox(width: 12),
              Expanded(child: box(80, r: 16)),
              const SizedBox(width: 12),
              Expanded(child: box(80, r: 16)),
            ]),
            const SizedBox(height: 24),
            box(16, w: 128, r: 4),
            const SizedBox(height: 12),
            box(112),
            const SizedBox(height: 12),
            box(112),
          ]),
        ),
      ),
    );
  }
}
