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
import '../../widgets/basemap.dart';
import '../../widgets/venue_reviews.dart';
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
  int _checkins = 0;
  String? _purchasing;
  bool _claiming = false;
  int _gallery = 0;
  final _pager = PageController();
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
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _pager.dispose();
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

  Future<void> _claim() async {
    final i18n = context.read<I18n>();
    if (context.read<AuthProvider>().user == null) {
      showToast(context, i18n.t('venueDetail.loginToClaim'));
      openRoute(context, AppRoute.login);
      return;
    }
    setState(() => _claiming = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('claimCommunityVenue').call({'venueId': widget.venueId});
      if (!mounted) return;
      openRoute(context, AppRoute.venueAdmin);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) showToast(context, e.message ?? i18n.t('venueDetail.errorClaiming'), error: true);
    }
    if (mounted) setState(() => _claiming = false);
  }

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
    final d = v.data;
    final title = safeStr(d['title'] ?? d['name']);
    final pricing = d['ticketPricing'] is Map ? Map<String, dynamic>.from(d['ticketPricing']) : <String, dynamic>{};
    final tiers = d['ticket_tiers'] is List ? (d['ticket_tiers'] as List).whereType<Map>().toList() : <Map>[];
    final community = d['ownerId'] == 'community';
    final isOpen = v.hasSchedule ? isVenueOpenNow(v.openingDays, v.openingHours).isOpen : true;
    final sched = formatScheduleToday(v.openingDays, v.openingHours);
    final photos = [if (v.bannerUrl != null && v.bannerUrl!.isNotEmpty) v.bannerUrl!, ...asStringList(d['photoUrls'])];
    final loc = v.location;
    final iconData = v.type == 'chill' ? Icons.local_fire_department : v.type == 'cruising' ? Icons.park : Icons.nightlife;
    final iconColor = v.type == 'chill' ? Tw.red500 : v.type == 'cruising' ? Tw.green500 : Tw.fuchsia400;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(children: [
        Positioned(top: -size.height * 0.1, left: -size.width * 0.2, child: Orb(color: Tw.fuchsia600.withValues(alpha: 0.1), size: size.width * 0.8)),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 128), children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.arrow_back, size: 14, color: Tw.slate500),
                  const SizedBox(width: 8),
                  Text(context.t('venueDetail.back'), style: tw(12, weight: bold, color: Tw.slate500)),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Tw.w(0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: community ? (v.type == 'chill' ? Tw.red500 : Tw.green500) : Colors.transparent, width: 2),
                ),
                child: Icon(iconData, size: 30, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: tw(24, weight: black, tracking: -0.025)),
                  if (v.address.isNotEmpty) Text(v.address, style: tw(12, color: Tw.slate500)),
                  if (v.openingDays.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Label(isVenueOpenNow(v.openingDays, v.openingHours).isOpen
                              ? context.t('venuesPage.open_now', fallback: 'Abierto')
                              : _nextOpeningLabel(context, v),
                          color: isVenueOpenNow(v.openingDays, v.openingHours).isOpen ? Tw.green400 : Tw.slate500, tracking: 0.05),
                      if (sched != null) ...[const SizedBox(width: 8), Text(sched, style: tw(10, color: Tw.slate500))],
                    ]),
                  ],
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, children: [
              isOpen
                  ? _chip('$_checkins ${context.t('venueDetail.peopleGo', count: _checkins)}', Tw.fuchsia500.withValues(alpha: 0.1),
                      Tw.fuchsia500.withValues(alpha: 0.2), Tw.fuchsia400)
                  : _chip(_nextOpeningLabel(context, v), Tw.slate800.withValues(alpha: 0.6), Tw.w(0.1), Tw.slate400),
              if (v.capacity != null)
                _chip('${context.t('venueDetail.capacity')} ${v.capacity}', Tw.w(0.05), Tw.w(0.1), Tw.slate500),
            ]),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 24),
              SizedBox(
                height: 224,
                child: Stack(children: [
                  PageView.builder(
                    controller: _pager,
                    itemCount: photos.length,
                    onPageChanged: (i) => setState(() => _gallery = i),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ClipRRect(borderRadius: BorderRadius.circular(24), child: NetImage(photos[i])),
                    ),
                  ),
                  if (photos.length > 1) ...[
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (var i = 0; i < photos.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _gallery ? 16 : 6,
                            height: 6,
                            decoration: BoxDecoration(color: i == _gallery ? Tw.white : Tw.w(0.4), borderRadius: BorderRadius.circular(99)),
                          ),
                      ]),
                    ),
                    if (_gallery > 0) _galleryArrow(Icons.chevron_left, Alignment.centerLeft, -1),
                    if (_gallery < photos.length - 1) _galleryArrow(Icons.chevron_right, Alignment.centerRight, 1),
                  ],
                ]),
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
                    final slug = context.read<CityProvider>().citySlug ?? 'madrid';
                    SharePlus.instance.share(ShareParams(
                      title: title,
                      uri: Uri.parse('$webBase/$slug/venues/detail?id=${widget.venueId}${widget.type != null ? '&type=${widget.type}' : ''}'),
                    ));
                  }),
                ),
              ]),
            ],
            if (v.description.isNotEmpty) ...[
              const SizedBox(height: 24),
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Text(v.description, style: tw(14, color: Tw.slate300, height: 1.6)),
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
                  const Icon(Icons.location_on, size: 12, color: Tw.slate500),
                  const SizedBox(width: 6),
                  Expanded(child: Text(v.address, style: tw(11, color: Tw.slate500))),
                ]),
              ],
            ],
            const SizedBox(height: 24),
            if (community)
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
                      gradient: const LinearGradient(colors: [Color(0xFFE11D48), Tw.orange500]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: const Color(0xFFE11D48).withValues(alpha: 0.3), blurRadius: 30, offset: const Offset(0, 10))],
                    ),
                    child: Label(context.t('venueDetail.buyOfficialTicket'), size: 14, color: Tw.white, align: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 16),
                Text(context.t('venueDetail.redirectTaquilla'), textAlign: TextAlign.center, style: tw(10, color: Tw.slate500)),
              ])
            else if (!ticketingOn)
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  const Icon(Icons.confirmation_number, size: 30, color: Tw.slate500),
                  const SizedBox(height: 8),
                  Label(context.t('venue_detail_online_unavailable', fallback: 'Venta online no disponible'), size: 14, color: Tw.slate300, tracking: 0.05),
                  const SizedBox(height: 8),
                  Text(
                    context.t('venue_detail_online_paused',
                        fallback: 'La venta anticipada de entradas para este local está temporalmente pausada o solo disponible en taquilla física.'),
                    textAlign: TextAlign.center,
                    style: tw(12, color: Tw.slate400),
                  ),
                ]),
              )
            else if (_events.isNotEmpty || pricing.isNotEmpty || tiers.isNotEmpty)
              _ticketsSection(context, pricing, tiers, currency)
            else
              GlassCard(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  const Icon(Icons.local_activity, size: 36, color: Tw.slate700),
                  const SizedBox(height: 12),
                  Text(context.t('venueDetail.noTickets'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
                  const SizedBox(height: 8),
                  Text(context.t('venueDetail.checkInFromVenues'), textAlign: TextAlign.center, style: tw(10, color: Tw.slate600)),
                ]),
              ),
            const SizedBox(height: 24),
            VenueReviews(venueId: widget.venueId, venueName: title),
          ]),
        ),
      ]),
    );
  }

  Widget _galleryArrow(IconData icon, Alignment align, int delta) => Align(
        alignment: align,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GestureDetector(
            onTap: () => _pager.animateToPage(_gallery + delta, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.6)),
              child: Icon(icon, color: Tw.white, size: 18),
            ),
          ),
        ),
      );

  Widget _chip(String text, Color bg, Color border, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
        child: Label(text, color: fg),
      );

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) => GlassCard(
        onTap: onTap,
        radius: 16,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: Tw.fuchsia400),
          const SizedBox(width: 8),
          Text(label, style: tw(12, weight: bold, color: Tw.slate300)),
        ]),
      );

  Widget _scheduleCard(BuildContext context, Venue v) => GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.schedule, size: 14, color: Tw.slate400),
            const SizedBox(width: 8),
            Label(context.t('venueDetail.schedule', fallback: 'Horario'), size: 12),
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
                      color: v.openingDays.contains(day) ? Tw.w(0.05) : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Expanded(child: Text(context.t('venue_config.day_$day'), overflow: TextOverflow.ellipsis, style: tw(11, weight: bold, color: Tw.slate300))),
                      Text(
                        v.openingDays.contains(day) && v.openingHours[day] != null
                            ? '${v.openingHours[day]!.open} – ${v.openingHours[day]!.close}'
                            : '—',
                        style: tw(11, color: Tw.slate400),
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
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
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
                    decoration: BoxDecoration(color: Tw.fuchsia500, borderRadius: BorderRadius.circular(99)),
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(9, weight: black)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Tw.fuchsia500,
                      border: Border.all(color: Tw.white, width: 2),
                      boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.6), blurRadius: 12)],
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
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        const Icon(Icons.forum, size: 36, color: Tw.slate700),
        const SizedBox(height: 12),
        Text(context.t('venueDetail.communitySpot'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
        const SizedBox(height: 8),
        Text(context.t('venueDetail.joinChat'), textAlign: TextAlign.center, style: tw(10, color: Tw.slate500)),
        if (['club', 'bar', 'sauna', 'chiringuito'].contains(v.type) && auth.user != null) ...[
          const SizedBox(height: 32),
          Divider(color: Tw.w(0.1)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x993B0764), Tw.slate900, Color(0x991E1B4B)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.purple500.withValues(alpha: 0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Tw.purple600.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Tw.purple500.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.storefront, size: 20, color: Tw.purple400),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('venueDetail.areYouOwner'), style: tw(14, weight: bold)),
                    Text(context.t('venueDetail.claimDescription'), style: tw(12, color: Tw.slate300, height: 1.5)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Pressable(
                onTap: () => _showClaimModal(context, v),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Tw.purple600, Tw.indigo600]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.auto_awesome, size: 16, color: Tw.white),
                    const SizedBox(width: 8),
                    Label(context.t('venueDetail.claimButton'), size: 12, color: Tw.white, weight: FontWeight.w800, tracking: 0.05),
                  ]),
                ),
              ),
            ]),
          ),
        ],
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

  void _showClaimModal(BuildContext context, Venue v) => showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.8),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => Dialog(
            backgroundColor: Tw.slate900,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Tw.purple500.withValues(alpha: 0.4))),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Tw.purple600.withValues(alpha: 0.2),
                      border: Border.all(color: Tw.purple500.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.verified_user, color: Tw.purple400),
                  ),
                ),
                const SizedBox(height: 8),
                Text('${ctx.t('venueDetail.takeControl')} ${v.name}', textAlign: TextAlign.center, style: tw(16, weight: bold)),
                const SizedBox(height: 4),
                Text(ctx.t('venueDetail.adminAccessInfo'), textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Tw.slate950.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Tw.slate800),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final k in ['venueDetail.scanner', 'venueDetail.rrppPanel', 'venueDetail.promotions'])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Text('✓', style: tw(12, color: Tw.emerald400)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(ctx.t(k), style: tw(12, color: Tw.slate300))),
                        ]),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: Pressable(
                      onTap: _claiming ? () {} : () => Navigator.of(ctx).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(12)),
                        child: Text(ctx.t('venueDetail.cancel'), textAlign: TextAlign.center, style: tw(12, weight: semibold, color: Tw.slate300)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Opacity(
                      opacity: _claiming ? 0.5 : 1,
                      child: Pressable(
                        onTap: _claiming
                            ? () {}
                            : () async {
                                setLocal(() {});
                                Navigator.of(ctx).pop();
                                await _claim();
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(color: Tw.purple600, borderRadius: BorderRadius.circular(12)),
                          child: Text(_claiming ? ctx.t('venueDetail.assigning') : ctx.t('venueDetail.confirmAndEnter'),
                              textAlign: TextAlign.center, style: tw(12, weight: bold)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      );

  Widget _ticketsSection(BuildContext context, Map<String, dynamic> pricing, List<Map> tiers, String currency) {
    Widget buyButton(String id, {String? label, VoidCallback? onTap}) => Opacity(
          opacity: _purchasing != null && _purchasing != id ? 0.5 : 1,
          child: Pressable(
            onTap: onTap ?? () => _purchase(id),
            scale: 0.95,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(gradient: AppTheme.ctaGradient, borderRadius: BorderRadius.circular(16)),
              child: _purchasing == id
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.white))
                  : Label(label ?? context.t('venueDetail.buy'), color: Tw.white),
            ),
          ),
        );

    Widget tierCard(String id, String name, String? sub, String price, Object? quota) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GlassCard(
            padding: const EdgeInsets.all(24),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: tw(14, weight: black)),
                  if (sub != null && sub.isNotEmpty) ...[const SizedBox(height: 4), Text(sub, style: tw(10, color: Tw.slate500))],
                  const SizedBox(height: 8),
                  Text(price, style: tw(18, weight: black, color: Tw.fuchsia400)),
                  if (quota != null) ...[
                    const SizedBox(height: 4),
                    Text('${context.t('venueDetail.limitedSpots')} $quota', style: tw(9, color: Tw.slate600)),
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
          const Icon(Icons.event, size: 16, color: Tw.fuchsia400),
          const SizedBox(width: 8),
          Expanded(child: Label(context.t('venueDetail.events', fallback: 'Próximos Eventos & Fiestas'), size: 14, color: Tw.fuchsia400, tracking: 0.2)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(99), border: Border.all(color: Tw.w(0.1))),
            child: Text('${_events.length} ${_events.length == 1 ? 'evento' : 'eventos'}', style: tw(10, weight: bold, color: Tw.slate500)),
          ),
        ]),
        const SizedBox(height: 16),
        for (final evt in _events) ...[
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: NetImage(
                    evt['banner_url'] as String?,
                    width: 80,
                    height: 80,
                    placeholder: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Tw.fuchsia600.withValues(alpha: 0.2),
                        border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.event, size: 30, color: Tw.fuchsia400),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Tw.emerald500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                      child: Label(context.t('events.source_venue', fallback: 'Local'), size: 8, color: Tw.emerald400, tracking: 0.05),
                    ),
                    const SizedBox(height: 4),
                    Text(safeStr(evt['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(16, weight: black)),
                    if (parseDate(evt['start_date'] ?? evt['date']) != null)
                      Text(
                        '${DateFormat('EEE, d MMM', 'es').format(parseDate(evt['start_date'] ?? evt['date'])!)} · ${DateFormat('HH:mm').format(parseDate(evt['start_date'] ?? evt['date'])!)}',
                        style: tw(12, color: Tw.slate400),
                      ),
                  ]),
                ),
              ]),
              if (evt['ticket_tiers'] is List && (evt['ticket_tiers'] as List).isNotEmpty) ...[
                const SizedBox(height: 16),
                Divider(color: Tw.w(0.05), height: 1),
                const SizedBox(height: 12),
                Label('Entradas disponibles'),
                const SizedBox(height: 8),
                for (final tier in (evt['ticket_tiers'] as List).whereType<Map>())
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Tw.w(0.05)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(safeStr(tier['name']), style: tw(12, weight: black)),
                          if (safeStr(tier['perks']).isNotEmpty) Text(safeStr(tier['perks']), style: tw(10, color: Tw.slate400)),
                          const SizedBox(height: 4),
                          Text(
                            (asDouble(tier['price']) ?? 0) == 0
                                ? context.t('events.free_label', fallback: 'Gratis')
                                : formatPrice(asDouble(tier['price']) ?? 0, currency),
                            style: tw(14, weight: black, color: Tw.fuchsia400),
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
                            Label(
                              (asDouble(tier['price']) ?? 0) == 0
                                  ? context.t('events.claim_free', fallback: 'Obtener')
                                  : context.t('venueDetail.buy', fallback: 'Comprar'),
                              color: Tw.white,
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
        Label(context.t('venueDetail.availableTickets'), size: 14, color: Tw.slate500, tracking: 0.2),
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
        Container(height: h, width: w, decoration: BoxDecoration(color: c ?? Tw.w(0.05), borderRadius: BorderRadius.circular(r)));
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
                decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(24)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  box(28, w: 192),
                  const SizedBox(height: 12),
                  box(16, w: 128, c: Tw.fuchsia500.withValues(alpha: 0.1)),
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
