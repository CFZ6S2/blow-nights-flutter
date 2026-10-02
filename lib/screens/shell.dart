import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../navigation.dart';
import '../providers/auth_provider.dart';
import '../providers/city_provider.dart';
import '../providers/venues_provider.dart';
import '../services/nearby.dart';
import '../services/push_sync.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'events/events_screen.dart';
import 'home/city_home_screen.dart';
import 'landing/landing_screen.dart';
import 'profile/profile_screen.dart';
import 'setup/setup_profile_screen.dart';
import 'staff/staff_screens.dart';
import 'venues/venues_screen.dart';

/// Root: splash while auth resolves, then the tabbed shell.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final shell = context.watch<ShellController>();
    if (auth.loading) return const SplashScreen();
    if (auth.user == null && !shell.landingDismissed) return LandingScreen(onEnter: shell.dismissLanding);
    if (needsProfileSetup(auth)) return const SetupProfileScreen();
    // Venue staff (invite or door account) open the app straight into their scanners.
    if (auth.role == 'door' && auth.claims?['venueId'] is String) return const StaffHomeScreen();
    return const MainShell();
  }
}

/// AuthContext's loading screen: rotated gradient tile + placeholder bar, pulsing.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FadeTransition(
            opacity: Tween(begin: 1.0, end: 0.5).animate(_c),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Transform.rotate(
                angle: 12 * math.pi / 180,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Tw.fuchsia600, Tw.indigo600]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.2), blurRadius: 50, offset: const Offset(0, 25))],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(height: 12, width: 96, decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(4))),
            ]),
          ),
        ),
      );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _pages = [CityHomeScreen(), VenuesScreen(), EventsScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final shell = context.watch<ShellController>();
    final cityId = context.select<CityProvider, String?>((c) => c.cityId);
    final center = context.select<CityProvider, GeoPos?>((c) => c.center);
    final profile = auth.profile;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<VenuesProvider>().setZone(center, cityId);
      // Push token and approximate position for venue promos (services/push_sync.dart), once the profile is known.
      if (auth.user == null || profile != null) {
        PushSync.start(
          auth.user?.uid,
          notificationsOff: profile?.data['notificationsEnabled'] == false,
          savedToken: profile?.data['fcmToken'] as String?,
          staff: auth.role == 'door',
        );
      }
    });

    final showNav = auth.user != null && auth.role != 'venueOwner';
    shell.navVisible = showNav;
    final index = showNav ? shell.index : 0;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: showNav ? _BottomNav(index: index) : null,
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final AppRoute? route;
  final int? tab;
  final int badge;
  final bool dot;
  const _NavItem(this.icon, this.label, {this.route, this.tab, this.badge = 0, this.dot = false});
}

/// Port of components/BottomNav.tsx
class _BottomNav extends StatelessWidget {
  final int index;
  const _BottomNav({required this.index});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final unread = context.watch<UnreadChats>().count;
    final profileIncomplete = auth.profile != null && auth.profile!.incomplete;

    final items = <_NavItem>[
      _NavItem(Icons.radar, context.t('nav.radar', fallback: 'Radar'), tab: 0),
      _NavItem(Icons.nightlife, context.t('nav.venues', fallback: 'Locales'), tab: 1),
      _NavItem(Icons.event, context.t('nav.events', fallback: 'Eventos'), tab: 2),
      _NavItem(Icons.person, context.t('nav.profile', fallback: 'Perfil'), tab: 3, badge: unread, dot: profileIncomplete),
      if (auth.isSuperAdmin)
        const _NavItem(Icons.admin_panel_settings, 'Maestro', route: AppRoute.superAdmin)
      else if (auth.isAdmin)
        _NavItem(Icons.admin_panel_settings, context.t('nav.admin', fallback: 'Admin'), route: AppRoute.admin)
      else if (auth.isCityManager)
        _NavItem(Icons.domain, context.t('nav.city_manager', fallback: 'Manager'), route: AppRoute.cityManager)
      else if (auth.isMasterPartner)
        _NavItem(Icons.handshake, context.t('nav.master_partner', fallback: 'Partner'), route: AppRoute.masterPartner)
      else if (auth.isCityAdmin)
        _NavItem(Icons.domain, context.t('nav.city_manager', fallback: 'Manager'), route: AppRoute.cityManager)
      else if (auth.isVenueManager)
        _NavItem(Icons.storefront, context.t('nav.my_venue'), route: AppRoute.venueAdmin),
    ];

    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.only(bottom: bottom),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            border: Border(top: BorderSide(color: Tw.w(0.1))),
            boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, -10))],
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  for (final item in items) _NavButton(item: item, active: item.tab != null && item.tab == index),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool active;
  const _NavButton({required this.item, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? Tw.fuchsia400 : Tw.slate500;
    return Pressable(
      scale: 0.8,
      onTap: () {
        HapticFeedback.selectionClick();
        if (item.tab != null) {
          context.read<ShellController>().setTab(item.tab!);
        } else if (item.route != null) {
          openRoute(context, item.route!);
        }
      },
      child: SizedBox(
        width: 64,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Icon(item.icon, size: 24, color: color, shadows: active ? [Shadow(color: Tw.fuchsia600.withValues(alpha: 0.5), blurRadius: 8)] : null),
            Positioned(
              top: -16,
              child: AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                  child: Container(
                    width: 24,
                    height: 4,
                    decoration: BoxDecoration(color: Tw.fuchsia400.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(99)),
                  ),
                ),
              ),
            ),
            if (item.badge > 0) Positioned(top: -4, right: -12, child: CountBadge(item.badge)),
            if (item.dot && item.badge == 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Tw.amber400,
                    boxShadow: [BoxShadow(color: Tw.amber400.withValues(alpha: 0.4), blurRadius: 8)],
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: tw(10, weight: black, color: color, tracking: -0.05),
            child: Text(item.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }
}
