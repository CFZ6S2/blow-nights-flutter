import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/city_provider.dart';
import '../../services/social.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chill_form.dart';
import '../../widgets/chill_paywall.dart';
import '../../widgets/city_selector.dart';
import '../../widgets/common.dart';

String chillTimeLeft(Object? expiresAt) {
  final d = parseDate(expiresAt);
  if (d == null) return '';
  final ms = d.difference(DateTime.now()).inMilliseconds;
  if (ms <= 0) return 'Expired';
  final h = ms ~/ 3600000, m = (ms % 3600000) ~/ 60000;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// Port of app/[city]/chills/page.tsx
class ChillsScreen extends StatefulWidget {
  const ChillsScreen({super.key});

  @override
  State<ChillsScreen> createState() => _ChillsScreenState();
}

class _ChillsScreenState extends State<ChillsScreen> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _chills = [];
  List<Map<String, dynamic>> _mine = [];
  bool _loading = true;
  String _tab = 'feed';
  final List<StreamSubscription> _subs = [];
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthProvider>().user?.uid;
    final slug = context.watch<CityProvider>().citySlug;
    final key = '$uid|$slug';
    if (key == _key) return;
    _key = key;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    if (uid == null || slug == null) {
      _loading = false;
      return;
    }
    _loading = true;
    _subs.add(_db
        .collection('chills')
        .where('city_slug', isEqualTo: slug)
        .where('status', whereIn: ['active', 'full'])
        .orderBy('created_at', descending: true)
        .snapshots()
        .listen((s) => setState(() {
              _chills = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
              _loading = false;
            }), onError: (_) => setState(() => _loading = false)));
    _subs.add(_db
        .collection('chills')
        .where('host_uid', isEqualTo: uid)
        .where('status', whereIn: ['active', 'full'])
        .snapshots()
        .listen((s) => setState(() => _mine = s.docs.map((d) => {'id': d.id, ...d.data()}).toList()), onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (!context.read<AuthProvider>().hasChillAccess) {
      showChillPaywall(context);
      return;
    }
    final id = await showCreateChillModal(context);
    if (id != null && mounted) openRoute(context, AppRoute.chillDetail, args: {'id': id});
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading || _loading) return const _ChillsSkeleton();
    final lat = auth.profile?.lat, lng = auth.profile?.lng;
    final sorted = [..._chills];
    if (lat != null && lng != null) {
      double d(Map<String, dynamic> c) => calculateDistance(lat, lng, asDouble(c['approx_lat']) ?? 0, asDouble(c['approx_lng']) ?? 0);
      sorted.sort((a, b) => d(a).compareTo(d(b)));
    }
    final list = _tab == 'feed' ? sorted : _mine;
    final cityName = context.watch<CityProvider>().currentCity?.name;

    Widget createBtn() => Pressable(
          onTap: _create,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.circular(12)),
            child: Text(context.t('chills.create_chill'), style: tw(14, weight: black)),
          ),
        );

    return Scaffold(
      backgroundColor: Tw.black,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 112), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Chills', style: tw(24, weight: black)),
                  const SizedBox(width: 8),
                  const Icon(Icons.local_fire_department, color: Tw.fuchsia400, size: 20),
                ]),
                const SizedBox(height: 4),
                const CitySelector(),
              ]),
            ),
            Pressable(
              onTap: _create,
              scale: 0.9,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Tw.fuchsia600,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.2), blurRadius: 15)],
                ),
                child: const Icon(Icons.add, color: Tw.white),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          Row(children: [
            for (final t in ['feed', 'mine']) ...[
              Pressable(
                onTap: () => setState(() => _tab = t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _tab == t ? Tw.fuchsia500 : Tw.w(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _tab == t ? Tw.fuchsia500 : Tw.w(0.05)),
                  ),
                  child: Label(t == 'feed' ? context.t('chills.tab_radar') : context.t('chills.tab_mine'),
                      color: _tab == t ? Tw.white : Tw.slate500),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 24),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Column(children: [
                Icon(_tab == 'feed' ? Icons.nightlife : Icons.home, size: 48, color: Tw.slate700),
                const SizedBox(height: 16),
                Text(
                  _tab == 'feed'
                      ? '${context.t('chills.no_active')}${cityName ?? context.t('chills.your_city')}'
                      : context.t('chills.no_mine'),
                  textAlign: TextAlign.center,
                  style: tw(14, weight: bold, color: Tw.slate500),
                ),
                if (_tab == 'feed') ...[
                  const SizedBox(height: 4),
                  Text(context.t('chills.be_first'), style: tw(12, color: Tw.slate600)),
                ],
                const SizedBox(height: 24),
                createBtn(),
              ]),
            )
          else
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ChillCard(
                  chill: c,
                  userLat: lat,
                  userLng: lng,
                  onTap: () => openRoute(context, AppRoute.chillDetail, args: {'id': c['id'] as String}),
                ),
              ),
        ]),
      ),
    );
  }
}

class ChillCard extends StatelessWidget {
  final Map<String, dynamic> chill;
  final double? userLat;
  final double? userLng;
  final VoidCallback onTap;
  const ChillCard({super.key, required this.chill, this.userLat, this.userLng, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = chill;
    final dist = userLat != null && userLng != null
        ? calculateDistance(userLat!, userLng!, asDouble(c['approx_lat']) ?? 0, asDouble(c['approx_lng']) ?? 0)
        : null;
    final accepted = c['accepted_users'] is List ? (c['accepted_users'] as List).length : 0;
    final max = asInt(c['max_capacity']);
    final spots = max - accepted;
    final full = c['status'] == 'full' || spots <= 0;
    final tags = asStringList(c['tags']);
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Tw.slate900.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Tw.w(0.05)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.4), width: 2)),
              child: ClipOval(
                child: NetImage(
                  c['host_foto'] as String?,
                  placeholder: Container(color: const Color(0x66701A75), child: const Icon(Icons.person, size: 18, color: Tw.fuchsia400)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(safeStr(c['title']), style: tw(14, weight: black, height: 1.2)),
                const SizedBox(height: 2),
                Text('${safeStr(c['host_nick'])}${dist != null && dist > 0 ? '  $dist km' : ''}', style: tw(10, weight: bold, color: Tw.slate500)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (full ? Tw.red500 : Tw.green500).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(full ? 'LLENO' : '$spots plazas', style: tw(10, weight: black, color: full ? Tw.red400 : Tw.green400)),
              ),
              const SizedBox(height: 4),
              Text(chillTimeLeft(c['expires_at']), style: tw(10, color: Tw.slate600).copyWith(fontFamily: 'monospace')),
            ]),
          ]),
          if (safeStr(c['description']).isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(safeStr(c['description']), maxLines: 2, overflow: TextOverflow.ellipsis, style: tw(12, color: Tw.slate400)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final t in tags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(99)),
                    child: Text(t, style: tw(10, weight: bold, color: Tw.slate400)),
                  ),
              ]),
            ),
            Icon(Icons.group, size: 12, color: Tw.fuchsia500.withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Text('$accepted/$max', style: tw(10, weight: bold, color: Tw.slate500)),
          ]),
        ]),
      ),
    );
  }
}

class _ChillsSkeleton extends StatelessWidget {
  const _ChillsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w, double r = 8, Color? c}) =>
        Container(height: h, width: w, decoration: BoxDecoration(color: c ?? Tw.w(0.05), borderRadius: BorderRadius.circular(r)));
    return Scaffold(
      backgroundColor: Tw.black,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 24), children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [box(28, w: 96), const SizedBox(height: 8), box(16, w: 128)])),
            box(48, w: 48, r: 16, c: Tw.fuchsia500.withValues(alpha: 0.1)),
          ]),
          const SizedBox(height: 24),
          Row(children: [box(36, w: 96, r: 12, c: Tw.fuchsia500.withValues(alpha: 0.1)), const SizedBox(width: 8), box(36, w: 80, r: 12)]),
          const SizedBox(height: 24),
          for (var i = 0; i < 4; i++)
            Container(
              height: 132,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.05))),
            ),
        ]),
      ),
    );
  }
}
