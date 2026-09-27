import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/profile_overlay.dart';

/// Port of app/[city]/visits/page.tsx
class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key});

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  List<Map<String, dynamic>> _visits = [];
  bool _loading = true;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;
    _sub = FirebaseFirestore.instance
        .collection('visits')
        .where('visitedId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen((s) => setState(() {
              _visits = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
              _loading = false;
            }), onError: (_) => setState(() => _loading = false));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _when(BuildContext context, DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    final min = now.difference(d).inMinutes;
    if (min < 1) return context.t('visits.just_now', fallback: 'Justo ahora');
    if (min < 60) return '${context.t('visits.ago', fallback: 'Hace')} ${min}min';
    final h = min ~/ 60;
    if (h < 24) return '${context.t('visits.ago', fallback: 'Hace')} ${h}h';
    final y = now.subtract(const Duration(days: 1));
    if (y.year == d.year && y.month == d.month && y.day == d.day) return context.t('visits.yesterday', fallback: 'Ayer');
    return DateFormat('d MMM', 'es').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading || _loading) {
      return Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(32), children: [
            Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16))),
              const SizedBox(width: 24),
              Container(width: 160, height: 32, decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12))),
            ]),
            const SizedBox(height: 32),
            for (var i = 0; i < 5; i++)
              Container(height: 88, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24))),
          ]),
        ),
      );
    }
    final premium = ['plus', 'black'].contains(auth.profile?.membershipTier);

    return Scaffold(
      body: Column(children: [
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: EdgeInsets.fromLTRB(32, MediaQuery.of(context).padding.top + 24, 32, 24),
              decoration: BoxDecoration(color: Tw.slate950.withValues(alpha: 0.6), border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
              child: Row(children: [
                Pressable(
                  onTap: () => Navigator.of(context).maybePop(),
                  scale: 0.9,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
                    child: const Icon(Icons.chevron_left, color: Tw.white),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('visits.title'), style: tw(30, weight: black, tracking: -0.05, height: 1)),
                    const SizedBox(height: 4),
                    Label(context.t('visits.subtitle'), color: Tw.slate500, tracking: 0.3, maxLines: 1),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Tw.fuchsia500.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    Text('${_visits.length}', style: tw(12, weight: black, color: Tw.fuchsia400)),
                    const SizedBox(width: 8),
                    const Icon(Icons.visibility, size: 14, color: Tw.fuchsia500),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 128), children: [
            if (_visits.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 128),
                child: Column(children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.w(0.05)),
                    child: const Icon(Icons.visibility_off, size: 48, color: Tw.slate700),
                  ),
                  const SizedBox(height: 32),
                  Text(context.t('visits.empty_title'), style: tw(20, weight: black, color: Tw.slate400)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 200,
                    child: Text(context.t('visits.empty_subtitle'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate600)),
                  ),
                ]),
              )
            else
              for (var i = 0; i < _visits.length; i++) _visitCard(context, _visits[i], i, premium),
            if (!premium && _visits.isNotEmpty) ...[
              const SizedBox(height: 48),
              _upsell(context),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _visitCard(BuildContext context, Map<String, dynamic> v, int idx, bool premium) {
    final locked = !premium && idx > 2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        onTap: () {
          if (premium) {
            HapticFeedback.selectionClick();
            showProfileOverlay(context, v['visitorId'] as String);
          } else {
            HapticFeedback.heavyImpact();
            openRoute(context, AppRoute.premium);
          }
        },
        scale: premium ? 0.98 : 1,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(40), border: Border.all(color: Tw.w(0.05))),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(29),
                    border: Border.all(color: premium ? Tw.fuchsia500.withValues(alpha: 0.3) : Tw.slate800, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(27),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: locked ? 20 : 0, sigmaY: locked ? 20 : 0),
                      child: NetImage(v['visitorFoto'] as String?, placeholder: Container(color: Tw.slate800)),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: locked ? 4 : 0, sigmaY: locked ? 4 : 0),
                      child: Text(safeStr(v['visitorNick']), maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(18, weight: black)),
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.schedule, size: 10, color: Tw.slate500),
                      const SizedBox(width: 8),
                      Label(_when(context, parseDate(v['timestamp'])), weight: bold, color: Tw.slate500),
                    ]),
                  ]),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12)),
                  child: Icon(premium ? Icons.chevron_right : Icons.star, size: 14, color: Tw.slate600),
                ),
              ]),
            ),
            if (locked)
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      color: Tw.slate950.withValues(alpha: 0.4),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAB308).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.lock, size: 12, color: Color(0xFFEAB308)),
                          const SizedBox(width: 8),
                          Label(context.t('visits.vip_only'), size: 8, color: const Color(0xFFEAB308)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _upsell(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.slate900, Tw.slate950]),
          borderRadius: BorderRadius.circular(48),
          border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Container(height: 4, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFACC15), Color(0xFFCA8A04), Color(0xFFFACC15)]))),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAB308).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.2)),
                ),
                child: const Icon(Icons.workspace_premium, size: 36, color: Color(0xFFEAB308)),
              ),
              const SizedBox(height: 24),
              Text(context.t('visits.fans_title'), textAlign: TextAlign.center, style: tw(24, weight: black, tracking: -0.025)),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${context.t('visits.there_are')} '),
                  TextSpan(
                    text: '${_visits.length} ${context.t('visits.people', count: _visits.length)}',
                    style: tw(14, weight: bold, color: Tw.white),
                  ),
                  TextSpan(text: ' ${context.t('visits.fans_promo_text')}'),
                ]),
                textAlign: TextAlign.center,
                style: tw(14, color: Tw.slate400, height: 1.6),
              ),
              const SizedBox(height: 32),
              Pressable(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  openRoute(context, AppRoute.premium);
                },
                scale: 0.95,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFACC15), Color(0xFFEAB308), Color(0xFFCA8A04)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: const Color(0xFFEAB308).withValues(alpha: 0.3), blurRadius: 40, offset: const Offset(0, 15))],
                  ),
                  child: Label(context.t('visits.unlock_now'), size: 12, color: Tw.black, tracking: 0.3, align: TextAlign.center),
                ),
              ),
            ]),
          ),
        ]),
      );
}
