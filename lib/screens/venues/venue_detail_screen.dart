import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../models/venue.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/city_provider.dart';
import '../../providers/platform_settings.dart';
import '../../services/venue_hours.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/poster.dart';
import '../../widgets/basemap.dart';
import '../../widgets/reference_venue.dart';
import '../../widgets/venue_reviews.dart';
import 'claim_venue_sheet.dart';
import 'venues_screen.dart' show formatPrice;

/// Port of app/[city]/venues/detail/page.tsx
class VenueDetailScreen extends StatefulWidget {
  final String venueId;
  final String? type;
  const VenueDetailScreen({super.key, required this.venueId, this.type});

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  final _db = FirebaseFirestore.instance;
  Venue? _venue;
  List<Map<String, dynamic>> _events = [];
  // The venue's active drinks (Cashless), cheapest first: bought at /bar/order, redeemed at the bar by QR.
  List<({String id, String name, double price})> _drinks = [];
  int _checkins = 0;
  String? _purchasing;
  final List<StreamSubscription> _subs = [];

  bool get _isEvent => widget.type == 'event';

  @override
  void initState() {
    super.initState();
    _subs.add(_db.collection(_isEvent ? 'events' : 'venues').doc(widget.venueId).snapshots().listen((s) {
      if (s.exists) setState(() => _venue = Venue.fromDoc(s));
    }, onError: (_) {}));
    _subs.add(_db.collection('live_sense').doc(widget.venueId).snapshots().listen((s) {
      setState(() => _checkins = s.exists ? asInt(s.data()?['current_count']) : 0);
    }, onError: (_) {}));
    if (!_isEvent) {
      _subs.add(_db
          .collection('venues')
          .doc(widget.venueId)
          .collection('events')
          .orderBy('start_date', descending: true)
          .limit(10)
          .snapshots()
          .listen((s) => setState(() => _events = s.docs.map((d) => {'id': d.id, ...d.data()}).toList()), onError: (_) {}));
      _subs.add(_db
          .collection('products')
          .where('venueId', isEqualTo: widget.venueId)
          .where('active', isEqualTo: true)
          .snapshots()
          .listen((s) {
        final drinks = s.docs
            .map((d) => (id: d.id, name: safeStr(d.data()['name']), price: asDouble(d.data()['price']) ?? 0))
            .where((d) => d.name.isNotEmpty && d.price > 0)
            .toList()
          ..sort((a, b) => a.price.compareTo(b.price));
        setState(() => _drinks = drinks);
      }, onError: (_) {}));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _purchase(String ticketType) async {
    if (context.read<AuthProvider>().user == null || _purchasing != null) return;
    final i18n = context.read<I18n>();
    setState(() => _purchasing = ticketType);
    try {
      final fn = FirebaseFunctions.instance.httpsCallable(_isEvent ? 'purchaseIndependentEventTicket' : 'purchaseVenueTicket');
      final res = await fn.call<Map<String, dynamic>>({
        if (_isEvent) 'eventId': widget.venueId else 'venueId': widget.venueId,
        'ticketType': ticketType,
        'origin': webBase,
        'idempotencyKey': uuidV4(),
      });
      final url = res.data['url'] as String?;
      if (url != null) await openInApp(url);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) showToast(context, e.message ?? i18n.t('venueDetail.errorBuying'), error: true);
    } catch (_) {
      if (mounted) showToast(context, i18n.t('venueDetail.errorBuying'), error: true);
    }
    if (mounted) setState(() => _purchasing = null);
  }

  // A reference venue goes to review (submitVenueClaim); the claimant follows it in "Mis reclamaciones".
  Future<void> _claimReference(String title) async {
    final res = await showClaimVenueSheet(context, venueId: widget.venueId, venueName: title);
    if (!mounted || res == null) return;
    openRoute(context, res == ClaimSheetResult.sent ? AppRoute.venueClaims : AppRoute.login);
  }

  static bool _barTakesOrders(Map<String, dynamic> d) {
    final cashless = d['cashless'] is Map ? d['cashless'] as Map : const {};
    return d['isActive'] != false && cashless['enabled'] != false && cashless['kioskOpen'] != false;
  }

  /// Port of the web venue page's "Copas" section.
  Widget _drinksSection(BuildContext context, String currency) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Label(context.t('venueDetail.drinks_title', fallback: 'Copas'), size: 14, color: Tw.inkDim, tracking: 0.2),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final drink in _drinks.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(child: Text(drink.name, overflow: TextOverflow.ellipsis, style: tw(14, weight: bold))),
                  const SizedBox(width: 12),
                  Text(formatPrice(drink.price, currency), style: tw(14, weight: black, color: Tw.sun)),
                ]),
              ),
            if (_drinks.length > 4)
              Text(context.t('venueDetail.drinks_more', fallback: 'Y {{count}} más en la carta', params: {'count': _drinks.length - 4}),
                  style: tw(10, color: Tw.inkDim)),
            const SizedBox(height: 8),
            Text(context.t('venueDetail.drinks_desc', fallback: 'Pídelas desde el móvil cuando estés en el local y canjéalas en la barra con tu QR.'),
                style: tw(12, color: Tw.inkSoft)),
            const SizedBox(height: 16),
            GradientButton(
              label: context.t('venueDetail.buy_drinks', fallback: 'Comprar copas'),
              icon: Icons.local_bar,
              expand: true,
              onTap: () => openRoute(context, AppRoute.barOrder, args: {'venueId': widget.venueId}),
            ),
          ]),
        ),
      ]);

  String _nextOpeningLabel(BuildContext context, Venue v) {
    final next = getNextOpening(v.openingDays, v.openingHours);
    if (next?.isToday == true) return context.t('venuesPage.opens_today_at', params: {'time': next!.open}, fallback: 'Abre a las ${next.open}');
    if (next != null) {
      final day = context.t('venue_config.day_${next.dayKey}');
      return context.t('venuesPage.opens_on', params: {'day': day, 'time': next.open}, fallback: 'Abre $day ${next.open}');
    }
    return context.t('venuesPage.closed_now', fallback: 'Cerrado');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final v = _venue;
    if (auth.loading || (auth.user != null && auth.profile == null) || v == null) return const _DetailSkeleton();
    final currency = context.watch<CityProvider>().currency;
    final ticketingOn = context.watch<PlatformSettings>().flags['moduleTicketing'] != false;
    final cashlessOn = context.watch<PlatformSettings>().flags['moduleCashless'] == true;
    final d = v.data;
    final title = safeStr(d['title'] ?? d['name']);
    final pricing = d['ticketPricing'] is Map ? Map<String, dynamic>.from(d['ticketPricing']) : <String, dynamic>{};
    final tiers = d['ticket_tiers'] is List ? (d['ticket_tiers'] as List).whereType<Map>().toList() : <Map>[];
    final community = d['ownerId'] == 'community';
    final reference = v.isUnclaimedReference;
    final isOpen = v.hasSchedule ? isVenueOpenNow(v.openingDays, v.openingHours).isOpen : true;
    final sched = formatScheduleToday(v.openingDays, v.openingHours);
    final photos = [if (v.bannerUrl != null && v.bannerUrl!.isNotEmpty) v.bannerUrl!, ...asStringList(d['photoUrls'])];
    final loc = v.location;
    final iconData = v.type == 'chill' ? Icons.local_fire_department : v.type == 'cruising' ? Icons.park : Icons.nightlife;
    final iconColor = v.type == 'chill' ? Tw.red500 : v.type == 'cruising' ? Tw.live : Tw.sun;
    final size = MediaQuery.of(context).size;

    final openNow = v.openingDays.isNotEmpty && isVenueOpenNow(v.openingDays, v.openingHours).isOpen;
    // The first photo goes on the poster; the rest stay in the gallery below (web: Poster + photo strip).
    final gallery = photos.length > 1 ? photos.sublist(1) : const <String>[];

    return Scaffold(
      body: Stack(children: [
        Positioned(top: -size.height * 0.1, left: -size.width * 0.2, child: Orb(color: Tw.party.withValues(alpha: 0.12), size: size.width * 0.8)),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 128), children: [
            // Hero poster (web: Poster h-72 rounded-[28px]) with the back button and the open / boosted pills.
            Poster(
              type: v.type,
              imageUrl: photos.isNotEmpty ? photos.first : null,
              height: 288,
              radius: BorderRadius.circular(28),
              child: Stack(children: [
                Positioned(
                  top: 16,
                  left: 16,
                  child: Pressable(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.nightDeep.withValues(alpha: 0.5)),
                      child: Semantics(
                        label: context.t('venueDetail.back'),
                        child: const Icon(Icons.arrow_back, size: 20, color: Tw.white),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    if (v.openingDays.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Tw.nightDeep.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(99)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: openNow ? Tw.live : Tw.inkDim),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            openNow ? context.t('venuesPage.open_now', fallback: 'Abierto') : _nextOpeningLabel(context, v),
                            style: tw(12, weight: bold),
                          ),
                          if (openNow && sched != null) Text(' · $sched', style: tw(12, weight: medium, color: Tw.inkSoft)),
                        ]),
                      ),
                    if (v.boosted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Tw.party, borderRadius: BorderRadius.circular(99)),
                        child: const Icon(Icons.local_fire_department, size: 14, color: Tw.white),
                      ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            // Header: ring avatar (.bn-ring) + name in the party font.
            Row(children: [
              Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(colors: [Tw.sunset, Tw.sun, Tw.party, Tw.sunset]),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Tw.panel,
                    border: Border.all(color: community ? (v.type == 'chill' ? Tw.red500 : Tw.live) : Tw.night, width: 4),
                  ),
                  child: Icon(iconData, size: 30, color: iconColor),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: tw(32, weight: FontWeight.w800, tracking: -0.025, height: 0.95)),
                  if (v.address.isNotEmpty) ...[const SizedBox(height: 4), Text(v.address, style: tw(14, color: Tw.inkDim))],
                  if (reference) ...[const SizedBox(height: 4), const ReferenceBadge()],
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            // Live card: bouncing bars + people going (web: CARD p-4 with .bn-eq).
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Tw.panel.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Tw.line),
              ),
              child: Row(children: [
                const LiveBars(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      isOpen ? '$_checkins ${context.t('venueDetail.peopleGo', count: _checkins)}' : _nextOpeningLabel(context, v),
                      style: tw(16, weight: bold),
                    ),
                    if (v.capacity != null)
                      Text('${context.t('venueDetail.capacity')} ${v.capacity}', style: tw(12, color: Tw.inkDim)),
                  ]),
                ),
              ]),
            ),
            if (gallery.isNotEmpty) ...[
              const SizedBox(height: 20),
              SizedBox(
                height: 128,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: gallery.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Container(
                    width: 192,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.line)),
                    child: NetImage(gallery[i]),
                  ),
                ),
              ),
            ],
            if (v.address.isNotEmpty || loc != null) ...[
              const SizedBox(height: 24),
              Row(children: [
                if (loc != null) ...[
                  Expanded(
                    child: _actionBtn(Icons.navigation, context.t('venueDetail.directions', fallback: 'Cómo llegar'), () {
                      launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${loc.lat},${loc.lng}'),
                          mode: LaunchMode.externalApplication);
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _actionBtn(Icons.share, context.t('venueDetail.share', fallback: 'Compartir'), () {
                    final slug = context.read<CityProvider>().citySlug ?? nearbySlug;
                    SharePlus.instance.share(ShareParams(
                      title: title,
                      uri: Uri.parse('$webBase/$slug/venues/detail?id=${widget.venueId}${widget.type != null ? '&type=${widget.type}' : ''}'),
                    ));
                  }),
                ),
              ]),
            ],
            if (v.description.isNotEmpty) ...[
              const SizedBox(height: 20),
              GlassCard(
                color: Tw.panel.withValues(alpha: 0.8),
                padding: const EdgeInsets.all(20),
                child: Text(v.description, style: tw(15, color: Tw.inkSoft, height: 1.6)),
              ),
            ],
            if (v.openingDays.isNotEmpty && v.openingHours.isNotEmpty) ...[
              const SizedBox(height: 24),
              _scheduleCard(context, v),
            ],
            if (loc != null) ...[
              const SizedBox(height: 24),
              _miniMap(loc.lat, loc.lng, title),
              if (v.address.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 4),
                  const Icon(Icons.location_on, size: 12, color: Tw.inkDim),
                  const SizedBox(width: 6),
                  Expanded(child: Text(v.address, style: tw(11, color: Tw.inkDim))),
                ]),
              ],
            ],
            const SizedBox(height: 24),
            if (reference)
              ReferenceVenueNotice(onClaim: () => _claimReference(title))
            else if (community)
              _communitySection(context, v)
            else if (v.externalTicketUrl != null && v.externalTicketUrl!.isNotEmpty)
              Column(children: [
                Pressable(
                  onTap: () => openInApp(v.externalTicketUrl!),
                  scale: 0.95,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: AppTheme.ctaGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Color(0xB3E8318A), blurRadius: 30, spreadRadius: -12, offset: Offset(0, 12))],
                    ),
                    child: Text(context.t('venueDetail.buyOfficialTicket'), textAlign: TextAlign.center, style: tw(16, weight: bold)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(context.t('venueDetail.redirectTaquilla'), textAlign: TextAlign.center, style: tw(12, color: Tw.inkDim)),
              ])
            else if (!ticketingOn)
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  const Icon(Icons.confirmation_number, size: 30, color: Tw.inkDim),
                  const SizedBox(height: 8),
                  Text(context.t('venue_detail_online_unavailable', fallback: 'Venta online no disponible'),
                      textAlign: TextAlign.center, style: tw(18, weight: bold, party: true)),
                  const SizedBox(height: 8),
                  Text(
                    context.t('venue_detail_online_paused',
                        fallback: 'La venta anticipada de entradas para este local está temporalmente pausada o solo disponible en taquilla física.'),
                    textAlign: TextAlign.center,
                    style: tw(14, color: Tw.inkDim),
                  ),
                ]),
              )
            else if (_events.isNotEmpty || pricing.isNotEmpty || tiers.isNotEmpty)
              _ticketsSection(context, pricing, tiers, currency)
            else
              GlassCard(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  const Icon(Icons.local_activity, size: 36, color: Tw.line),
                  const SizedBox(height: 12),
                  Text(context.t('venueDetail.noTickets'), textAlign: TextAlign.center, style: tw(14, color: Tw.inkDim)),
                  const SizedBox(height: 8),
                  Text(context.t('venueDetail.checkInFromVenues'), textAlign: TextAlign.center, style: tw(10, color: Tw.inkDim)),
                ]),
              ),
            // Copas: the bar must be taking orders (same checks as the bar order screen) and have something on the menu.
            if (!community && !reference && cashlessOn && _drinks.isNotEmpty && _barTakesOrders(d)) ...[
              const SizedBox(height: 24),
              _drinksSection(context, currency),
            ],
            const SizedBox(height: 24),
            VenueReviews(venueId: widget.venueId, venueName: title),
          ]),
        ),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) => GlassCard(
        onTap: onTap,
        radius: 16,
        color: Tw.panel.withValues(alpha: 0.8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: Tw.sun),
          const SizedBox(width: 8),
          Text(label, style: tw(14, weight: bold, color: Tw.inkSoft)),
        ]),
      );

  Widget _scheduleCard(BuildContext context, Venue v) => GlassCard(
        color: Tw.panel.withValues(alpha: 0.8),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.schedule, size: 18, color: Tw.sun),
            const SizedBox(width: 8),
            Text(context.t('venueDetail.schedule', fallback: 'Horario'), style: tw(18, weight: bold, party: true)),
          ]),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 4,
            padding: EdgeInsets.zero,
            children: [
              for (final day in const ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
                Opacity(
                  opacity: v.openingDays.contains(day) ? 1 : 0.4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: v.openingDays.contains(day) ? Tw.nightDeep.withValues(alpha: 0.6) : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Expanded(child: Text(context.t('venue_config.day_$day'), overflow: TextOverflow.ellipsis, style: tw(11, weight: bold, color: Tw.inkSoft))),
                      Text(
                        v.openingDays.contains(day) && v.openingHours[day] != null
                            ? '${v.openingHours[day]!.open} – ${v.openingHours[day]!.close}'
                            : '—',
                        style: tw(11, color: Tw.inkDim),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ]),
      );

  Widget _miniMap(double lat, double lng, String name) => Container(
        height: 192,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.line)),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(lat, lng),
            initialZoom: 15,
            backgroundColor: Basemap.background,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            const Basemap(),
            MarkerLayer(markers: [
              Marker(
                point: LatLng(lat, lng),
                width: 140,
                height: 56,
                alignment: Alignment.topCenter,
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Tw.party, borderRadius: BorderRadius.circular(99)),
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(9, weight: black)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Tw.party,
                      border: Border.all(color: Tw.white, width: 2),
                      boxShadow: [BoxShadow(color: Tw.party.withValues(alpha: 0.6), blurRadius: 12)],
                    ),
                    child: Center(child: Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Tw.white))),
                  ),
                ]),
              ),
            ]),
          ],
        ),
      );

  Widget _communitySection(BuildContext context, Venue v) {
    final auth = context.watch<AuthProvider>();
    return GlassCard(
      color: Tw.panel.withValues(alpha: 0.8),
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        const Icon(Icons.forum, size: 36, color: Tw.inkDim),
        const SizedBox(height: 12),
        Text(context.t('venueDetail.communitySpot'), textAlign: TextAlign.center, style: tw(14, color: Tw.inkSoft)),
        const SizedBox(height: 8),
        Text(context.t('venueDetail.joinChat'), textAlign: TextAlign.center, style: tw(12, color: Tw.inkDim)),
        if (v.data['createdBy'] == auth.user?.uid && auth.user != null) ...[
          const SizedBox(height: 24),
          Pressable(
            onTap: () async {
              final i18n = context.read<I18n>();
              if (await confirmDialog(context,
                  message: i18n.t('venueDetail.confirmDelete'), confirmText: i18n.t('venueDetail.deleteCommunitySpot'), danger: true)) {
                try {
                  await _db.collection('venues').doc(v.id).delete();
                  if (context.mounted) Navigator.of(context).pop();
                } catch (_) {
                  if (context.mounted) showToast(context, i18n.t('venueDetail.errorDeleting'), error: true);
                }
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Tw.red500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
              ),
              child: Text(context.t('venueDetail.deleteCommunitySpot'), textAlign: TextAlign.center, style: tw(12, weight: bold, color: Tw.red500)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _ticketsSection(BuildContext context, Map<String, dynamic> pricing, List<Map> tiers, String currency) {
    Widget buyButton(String id, {String? label, VoidCallback? onTap}) => Opacity(
          opacity: _purchasing != null && _purchasing != id ? 0.5 : 1,
          child: Pressable(
            onTap: onTap ?? () => _purchase(id),
            scale: 0.95,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(gradient: AppTheme.ctaGradient, borderRadius: BorderRadius.circular(12)),
              child: _purchasing == id
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.white))
                  : Text(label ?? context.t('venueDetail.buy'), style: tw(14, weight: bold)),
            ),
          ),
        );

    Widget tierCard(String id, String name, String? sub, String price, Object? quota) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GlassCard(
            color: Tw.panel.withValues(alpha: 0.8),
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: tw(18, weight: bold, party: true)),
                  if (sub != null && sub.isNotEmpty) ...[const SizedBox(height: 4), Text(sub, style: tw(12, color: Tw.inkDim))],
                  const SizedBox(height: 8),
                  Text(price, style: tw(20, weight: FontWeight.w800, color: Tw.sun)),
                  if (quota != null) ...[
                    const SizedBox(height: 4),
                    Text('${context.t('venueDetail.limitedSpots')} $quota', style: tw(12, color: Tw.inkDim)),
                  ],
                ]),
              ),
              buyButton(id),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_events.isNotEmpty) ...[
        Row(children: [
          Expanded(
            child: Text(context.t('venueDetail.events', fallback: 'Próximos Eventos & Fiestas'),
                style: tw(24, weight: FontWeight.w800, tracking: -0.025)),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Tw.panel, borderRadius: BorderRadius.circular(99), border: Border.all(color: Tw.line)),
            child: Text('${_events.length} ${_events.length == 1 ? 'evento' : 'eventos'}', style: tw(12, weight: bold, color: Tw.inkSoft)),
          ),
        ]),
        const SizedBox(height: 16),
        for (final evt in _events) ...[
          GlassCard(
            color: Tw.panel.withValues(alpha: 0.8),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Poster(
                  type: widget.type ?? 'event',
                  imageUrl: evt['banner_url'] as String?,
                  width: 80,
                  height: 80,
                  shade: false,
                  radius: BorderRadius.circular(16),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Tw.live.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                      child: Text(context.t('events.source_venue', fallback: 'Local'), style: tw(12, weight: semibold, color: Tw.live)),
                    ),
                    const SizedBox(height: 4),
                    Text(safeStr(evt['title']),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(18, weight: bold, party: true)),
                    if (parseDate(evt['start_date'] ?? evt['date']) != null)
                      Text(
                        '${DateFormat('EEE, d MMM', 'es').format(parseDate(evt['start_date'] ?? evt['date'])!)} · ${DateFormat('HH:mm').format(parseDate(evt['start_date'] ?? evt['date'])!)}',
                        style: tw(14, weight: semibold, color: Tw.sun),
                      ),
                  ]),
                ),
              ]),
              if (evt['ticket_tiers'] is List && (evt['ticket_tiers'] as List).isNotEmpty) ...[
                const SizedBox(height: 16),
                Divider(color: Tw.lineSoft, height: 1),
                const SizedBox(height: 12),
                Text('Entradas disponibles', style: tw(12, weight: semibold, color: Tw.inkSoft)),
                const SizedBox(height: 8),
                for (final tier in (evt['ticket_tiers'] as List).whereType<Map>())
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Tw.nightDeep.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Tw.line),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(safeStr(tier['name']), style: tw(14, weight: bold)),
                          if (safeStr(tier['perks']).isNotEmpty) Text(safeStr(tier['perks']), style: tw(12, color: Tw.inkSoft)),
                          const SizedBox(height: 4),
                          Text(
                            (asDouble(tier['price']) ?? 0) == 0
                                ? context.t('events.free_label', fallback: 'Gratis')
                                : formatPrice(asDouble(tier['price']) ?? 0, currency),
                            style: tw(14, weight: black, color: Tw.sun),
                          ),
                        ]),
                      ),
                      Pressable(
                        onTap: () => openRoute(context, AppRoute.buy, args: {'venue': widget.venueId, 'event': evt['id'] as String}),
                        scale: 0.95,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(gradient: AppTheme.ctaGradient, borderRadius: BorderRadius.circular(12)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.confirmation_number, size: 12, color: Tw.white),
                            const SizedBox(width: 6),
                            Text(
                              (asDouble(tier['price']) ?? 0) == 0
                                  ? context.t('events.claim_free', fallback: 'Obtener')
                                  : context.t('venueDetail.buy', fallback: 'Comprar'),
                              style: tw(14, weight: bold),
                            ),
                          ]),
                        ),
                      ),
                    ]),
                  ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
        ],
      ],
      if (pricing.isNotEmpty || tiers.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(context.t('venueDetail.availableTickets'), style: tw(24, weight: FontWeight.w800, tracking: -0.025)),
        const SizedBox(height: 16),
        for (final e in pricing.entries)
          tierCard(
            e.key,
            safeStr(e.value is Map ? e.value['name'] : null).isNotEmpty ? safeStr(e.value['name']) : e.key.replaceAll('_', ' '),
            e.value is Map ? safeStr(e.value['description']) : null,
            formatPrice((asDouble(e.value is Map ? e.value['amount'] : 0) ?? 0) / 100, currency),
            e.value is Map ? e.value['quota'] : null,
          ),
        for (final t in tiers)
          tierCard(safeStr(t['id']), safeStr(t['name']), safeStr(t['perks']), formatPrice(asDouble(t['price']) ?? 0, currency), t['quota']),
      ],
    ]);
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w, double r = 12, Color? c}) =>
        Container(height: h, width: w, decoration: BoxDecoration(color: c ?? Tw.panelSoft, borderRadius: BorderRadius.circular(r)));
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        box(256, r: 0),
        Transform.translate(
          offset: const Offset(0, -32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Tw.panel.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(24)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  box(28, w: 192),
                  const SizedBox(height: 12),
                  box(16, w: 128, c: Tw.party.withValues(alpha: 0.1)),
                  const SizedBox(height: 12),
                  box(12),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [Expanded(child: box(48, r: 16)), const SizedBox(width: 8), Expanded(child: box(48, r: 16))]),
              const SizedBox(height: 16),
              box(96, r: 16),
            ]),
          ),
        ),
      ]),
    );
  }
}
