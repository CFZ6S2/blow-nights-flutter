import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/admin/admin_screen.dart';
import 'screens/admin/bar_scanner_screen.dart';
import 'screens/admin/city_manager_screen.dart';
import 'screens/admin/master_partner_screen.dart';
import 'screens/admin/scanner_screens.dart';
import 'screens/admin/super_admin_screen.dart';
import 'screens/admin/venue_admin_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/business/business_landing_screen.dart';
import 'screens/business/business_login_screen.dart';
import 'screens/business/business_screens.dart';
import 'screens/business/city_partners_screen.dart';
import 'screens/business/investors_screen.dart';
import 'screens/business/kiosk_screen.dart';
import 'screens/business/partner_apply_screen.dart';
import 'screens/business/partners_landing_screen.dart';
import 'screens/business/promoter_screens.dart';
import 'screens/business/public_pages.dart';
import 'screens/staff/staff_screens.dart';
import 'screens/bar/bar_order_screen.dart';
import 'screens/bar/event_bar_screen.dart';
import 'screens/chat/chat_detail_screen.dart';
import 'screens/chat/chat_list_screen.dart';
import 'screens/chills/chill_detail_screen.dart';
import 'screens/chills/chills_screen.dart';
import 'screens/plans/create_plan_screen.dart';
import 'screens/plans/my_plans_screen.dart';
import 'screens/plans/plan_manage_screen.dart';
import 'screens/tickets/buy_screen.dart';
import 'screens/tickets/entradas_screen.dart';
import 'screens/tickets/pass_screen.dart';
import 'screens/events/event_detail_screen.dart';
import 'screens/events/events_screen.dart';
import 'screens/friends/friend_group_screen.dart';
import 'screens/friends/friend_groups_screen.dart';
import 'screens/legal/legal_screens.dart';
import 'screens/map/map_screen.dart';
import 'screens/premium/premium_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/profile_view_screen.dart';
import 'screens/setup/setup_profile_screen.dart';
import 'screens/tickets/chill_ticket_screen.dart';
import 'screens/tickets/consumption_screen.dart';
import 'screens/tickets/wallet_screen.dart';
import 'screens/venues/venue_claims_screen.dart';
import 'screens/venues/venue_detail_screen.dart';
import 'screens/visits/visits_screen.dart';
import 'screens/venues/venues_screen.dart';
import 'theme/app_theme.dart';
import 'i18n/i18n.dart';
import 'providers/platform_settings.dart';
import 'widgets/common.dart';

const webBase = 'https://blownights.com';

enum AppRoute {
  home,
  venues,
  events,
  profile,
  map,
  login,
  chat,
  chatDetail,
  profileView,
  chillDetail,
  chills,
  entradas,
  myPlans,
  createPlan,
  planManage,
  pass,
  chillTicket,
  barGift,
  barOrder,
  buy,
  consumption,
  visits,
  tickets,
  eventDetail,
  venueDetail,
  venueClaims,
  setupProfile,
  premium,
  terms,
  privacy,
  rules,
  superAdmin,
  admin,
  cityManager,
  masterPartner,
  venueAdmin,
  scanner,
  door,
  barScanner,
  staffJoin,
  staffHome,
  kiosk,
  partnersApply,
  investors,
  businessClaim,
  businessStripe,
  setupStripe,
  pr,
  prJoin,
  partners,
  cityPartners,
  discover,
  localEntradas,
  venueMenu,
  business,
  businessLanding,
  friendGroups,
  friendGroup,
}

const tabRoutes = [AppRoute.home, AppRoute.venues, AppRoute.events, AppRoute.profile];

/// Every page of the web has a native screen here; nothing opens blownights.com.
final Map<AppRoute, Widget Function(Map<String, String> args)> screenRegistry = {
  AppRoute.login: (_) => const LoginScreen(),
  AppRoute.map: (_) => const MapScreen(),
  AppRoute.venues: (_) => const VenuesScreen(),
  AppRoute.events: (_) => const EventsScreen(),
  AppRoute.profile: (_) => const ProfileScreen(),
  AppRoute.setupProfile: (_) => const SetupProfileScreen(editing: true),
  AppRoute.tickets: (a) => WalletScreen(claimTicketId: a['claimTicketId']),
  AppRoute.venueDetail: (a) => VenueDetailScreen(venueId: a['venueId'] ?? '', type: a['type']),
  AppRoute.venueClaims: (_) => const VenueClaimsScreen(),
  AppRoute.chat: (_) => const ChatListScreen(),
  AppRoute.chatDetail: (a) => ChatDetailScreen(chatId: a['id'] ?? ''),
  AppRoute.visits: (_) => const VisitsScreen(),
  AppRoute.premium: (_) => const PremiumScreen(),
  AppRoute.terms: (_) => const TermsScreen(),
  AppRoute.privacy: (_) => const PrivacyScreen(),
  AppRoute.rules: (_) => const RulesScreen(),
  AppRoute.eventDetail: (a) => EventDetailScreen(eventId: a['eventId'] ?? ''),
  AppRoute.myPlans: (_) => const MyPlansScreen(),
  AppRoute.createPlan: (_) => const CreatePlanScreen(),
  AppRoute.planManage: (a) => PlanManageScreen(planId: a['id'] ?? ''),
  AppRoute.chills: (_) => const ChillsScreen(),
  AppRoute.chillDetail: (a) => ChillDetailScreen(chillId: a['id'] ?? ''),
  AppRoute.entradas: (a) => EntradasScreen(refCode: a['ref'] ?? ''),
  AppRoute.buy: (a) => BuyScreen(venueId: a['venue'], eventId: a['event'], rrppId: a['rrpp'], refCode: a['ref'] ?? ''),
  AppRoute.pass: (a) => PassScreen(id: a['id'], accessToken: a['access']),
  AppRoute.chillTicket: (a) => ChillTicketScreen(id: a['id'] ?? ''),
  AppRoute.profileView: (a) => ProfileViewScreen(userId: a['id'] ?? '', pingVenueId: a['pingVenueId']),
  AppRoute.consumption: (a) => ConsumptionScreen(success: a['success'] == 'true'),
  AppRoute.barOrder: (a) => BarOrderScreen(venueId: a['venueId']),
  AppRoute.barGift: (a) => EventBarScreen(giftNick: a['giftNick'] ?? ''),
  AppRoute.superAdmin: (_) => const SuperAdminScreen(),
  AppRoute.admin: (_) => const AdminScreen(),
  AppRoute.cityManager: (_) => const CityManagerScreen(),
  AppRoute.masterPartner: (_) => const MasterPartnerScreen(),
  AppRoute.venueAdmin: (_) => const VenueAdminScreen(),
  AppRoute.scanner: (a) => ScannerScreen(mode: a['mode'], deviceId: a['device']),
  AppRoute.business: (a) => BusinessLoginScreen(refCode: a['ref'], initialType: a['type']),
  AppRoute.businessClaim: (a) => ClaimVenueScreen(venue: a['venue']),
  AppRoute.businessStripe: (a) => BusinessStripeScreen(refresh: a['refresh'] != null, returned: a['return'] != null),
  AppRoute.setupStripe: (_) => const SetupStripeScreen(),
  AppRoute.pr: (a) => PromoterScreen(token: a['token'], eventId: a['event'], venueId: a['venue'], success: a['success'] != null),
  AppRoute.prJoin: (_) => const PrJoinScreen(),
  AppRoute.kiosk: (_) => const KioskScreen(),
  AppRoute.partnersApply: (_) => const PartnerApplyScreen(),
  AppRoute.discover: (_) => const DiscoverScreen(),
  AppRoute.businessLanding: (_) => const BusinessLandingScreen(),
  AppRoute.partners: (_) => const PartnersLandingScreen(),
  AppRoute.cityPartners: (a) => CityPartnersScreen(citySlug: a['city'] ?? 'madrid'),
  AppRoute.investors: (_) => const InvestorsScreen(),
  AppRoute.localEntradas: (a) => LocalEntradasScreen(slug: a['slug'] ?? '', giftUserId: a['gift'], refCode: a['ref'] ?? ''),
  AppRoute.venueMenu: (a) => VenueMenuScreen(venueId: a['venueId'] ?? 'default'),
  AppRoute.barScanner: (a) => BarScannerScreen(venueId: a['venue'] ?? ''),
  AppRoute.staffJoin: (a) => StaffJoinScreen(invite: a['i'] ?? ''),
  AppRoute.staffHome: (_) => const StaffHomeScreen(),
  AppRoute.door: (a) => DoorScreen(venueId: a['venue'] ?? '', eventId: a['event'] ?? '', token: a['token'] ?? ''),
  // App-only (no web page): BLE friend finder.
  AppRoute.friendGroups: (a) => FriendGroupsScreen(joinCode: a['join']),
  AppRoute.friendGroup: (a) => FriendGroupScreen(code: a['code'] ?? ''),
};

class ShellController extends ChangeNotifier {
  int index = 0;
  bool navVisible = false;

  /// Guests start on the landing (web `/`) until they open the radar.
  bool landingDismissed = false;
  void dismissLanding() {
    landingDismissed = true;
    notifyListeners();
  }

  void setTab(int i) {
    if (i == index) return;
    index = i;
    notifyListeners();
  }
}

/// [replace] swaps the current screen, like router.push after finishing a flow (create plan → manage, buy → pass).
Future<void> openRoute(BuildContext context, AppRoute route, {Map<String, String> args = const {}, bool replace = false}) async {
  // "Amigos cerca" stays closed until super-admin turns moduleFriendFinder on.
  if ((route == AppRoute.friendGroups || route == AppRoute.friendGroup) &&
      !context.read<PlatformSettings>().flag('moduleFriendFinder')) {
    showToast(context, context.read<I18n>().t('finder.unavailable'));
    return;
  }
  // Premium isn't sold in the app until super-admin turns moduleAppPremium on (Google Play payments policy). From a
  // paywall that replaced its screen (a chat without a match), that screen closes too.
  if (route == AppRoute.premium && !context.read<PlatformSettings>().flag('moduleAppPremium')) {
    showToast(context, context.read<I18n>().t('premium.unavailable_app'));
    if (replace) Navigator.of(context).maybePop();
    return;
  }
  final shell = context.read<ShellController>();
  final tab = tabRoutes.indexOf(route);
  if (tab >= 0 && shell.navVisible && args.isEmpty) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    shell.setTab(tab);
    return;
  }
  final builder = screenRegistry[route];
  if (builder != null) {
    final page = MaterialPageRoute(builder: (_) => builder(args));
    final nav = Navigator.of(context);
    await (replace ? nav.pushReplacement(page) : nav.push(page));
    return;
  }
  // Tab routes without their own page (home): back to the shell on that tab. Never leaves the app.
  Navigator.of(context).popUntil((r) => r.isFirst);
  if (tab >= 0) shell.setTab(tab);
}

/// Port of hooks/useUnreadChats.ts
class UnreadChats extends ChangeNotifier {
  int count = 0;
  StreamSubscription? _authSub;
  StreamSubscription? _chatsSub;

  UnreadChats() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _chatsSub?.cancel();
      if (u == null) {
        count = 0;
        notifyListeners();
        return;
      }
      _chatsSub = FirebaseFirestore.instance
          .collection('chats')
          .where('users', arrayContains: u.uid)
          .limit(100)
          .snapshots()
          .listen((snap) => _recount(u.uid, snap.docs.map((d) => d.id).toList()), onError: (_) {});
    });
  }

  Future<void> _recount(String uid, List<String> ids) async {
    var total = 0;
    await Future.wait(ids.map((id) async {
      try {
        final s = await FirebaseFirestore.instance
            .collection('chats')
            .doc(id)
            .collection('messages')
            .where('read', isEqualTo: false)
            .where('senderId', isNotEqualTo: uid)
            .count()
            .get();
        total += s.count ?? 0;
      } catch (_) {}
    }));
    count = total;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _chatsSub?.cancel();
    super.dispose();
  }
}

/// `min-w-[18px] h-[18px] bg-fuchsia-500 text-[9px] font-black rounded-full animate-pulse`
class CountBadge extends StatefulWidget {
  final int count;
  const CountBadge(this.count, {super.key});

  @override
  State<CountBadge> createState() => _CountBadgeState();
}

class _CountBadgeState extends State<CountBadge> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = _c.value;
          final o = t < 0.5 ? 1 - t : t; // opacity 1 → .5 → 1
          return Opacity(opacity: o, child: child);
        },
        child: Container(
          constraints: const BoxConstraints(minWidth: 18),
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Tw.fuchsia500,
            borderRadius: BorderRadius.circular(99),
            boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.4), blurRadius: 10)],
          ),
          child: Text(widget.count > 99 ? '99+' : '${widget.count}', style: tw(9, weight: black)),
        ),
      );
}
