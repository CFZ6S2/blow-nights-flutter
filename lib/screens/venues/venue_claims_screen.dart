import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../models/venue_claim.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Port of app/reclamaciones/page.tsx: the claimant's claims of reference venues and where each one is (web
/// docs/REFERENCE_VENUES.md §3): in review, approved (with the way into their panel), rejected (with the reason),
/// withdrawn or superseded.
class VenueClaimsScreen extends StatefulWidget {
  const VenueClaimsScreen({super.key});

  @override
  State<VenueClaimsScreen> createState() => _VenueClaimsScreenState();
}

class _VenueClaimsScreenState extends State<VenueClaimsScreen> {
  List<Map<String, dynamic>>? _claims;
  String? _busy;
  StreamSubscription? _sub;

  static const _statusColors = <String, (Color, Color)>{
    'pending': (Color(0x33F59E0B), Color(0xFFFCD34D)),
    'approved': (Color(0x3310B981), Color(0xFF6EE7B7)),
    'rejected': (Color(0x33F43F5E), Color(0xFFFDA4AF)),
    'withdrawn': (Color(0x99334155), Tw.slate300),
    'superseded': (Color(0x99334155), Tw.slate300),
  };

  @override
  void initState() {
    super.initState();
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) {
      _claims = [];
      return;
    }
    _sub = FirebaseFirestore.instance.collection('venue_claims').where('claimantUid', isEqualTo: uid).snapshots().listen((s) {
      final list = s.docs.map((d) => {'id': d.id, ...d.data()}).toList()
        ..sort((a, b) => (parseDate(b['createdAt'])?.millisecondsSinceEpoch ?? 0).compareTo(parseDate(a['createdAt'])?.millisecondsSinceEpoch ?? 0));
      setState(() => _claims = list);
    }, onError: (_) => setState(() => _claims = []));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _withdraw(String claimId) async {
    final i18n = context.read<I18n>();
    setState(() => _busy = claimId);
    try {
      await FirebaseFunctions.instance.httpsCallable('withdrawVenueClaim').call({'claimId': claimId});
    } on FirebaseFunctionsException catch (e) {
      if (mounted) showToast(context, e.message ?? i18n.t('venue_claim.error'), error: true);
    } catch (_) {
      if (mounted) showToast(context, i18n.t('venue_claim.error'), error: true);
    }
    if (mounted) setState(() => _busy = null);
  }

  // The venueOwner role arrives in a new ID token: refresh it before entering the panel.
  Future<void> _openPanel() async {
    await context.read<AuthProvider>().refreshToken();
    if (mounted) openRoute(context, AppRoute.venueAdmin);
  }

  @override
  Widget build(BuildContext context) {
    final claims = _claims;
    return Scaffold(
      body: SafeArea(
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
          Label(context.t('venue_claim.my_claims'), size: 18, tracking: 0.1),
          const SizedBox(height: 16),
          if (claims == null)
            Text(context.t('venue_claim.loading'), style: tw(14, color: Tw.slate500))
          else if (claims.isEmpty)
            Text(context.t('venue_claim.none'), style: tw(14, color: Tw.slate500))
          else
            for (final c in claims) ...[_claimCard(context, c), const SizedBox(height: 12)],
        ]),
      ),
    );
  }

  Widget _claimCard(BuildContext context, Map<String, dynamic> c) {
    final status = claimStatuses.contains(c['status']) ? c['status'] as String : 'pending';
    final (bg, fg) = _statusColors[status]!;
    final trial = c['trial'];
    final ends = parseDate(trial is Map ? trial['endsAt'] : null);
    final reason = safeStr(c['rejectionReason']);
    final name = safeStr(c['venueName']).isNotEmpty ? safeStr(c['venueName']) : safeStr(c['venueId']);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(15, weight: bold))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
            child: Label(context.t('venue_claim.status_$status'), size: 10, color: fg, tracking: 0.1),
          ),
        ]),
        const SizedBox(height: 8),
        Text(context.t('venue_claim.explain_$status'), style: tw(12, color: Tw.slate400)),
        if (status == 'rejected' && reason.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(context.t('venue_claim.reason', params: {'reason': reason}), style: tw(12, color: const Color(0xFFFDA4AF))),
        ],
        if (status == 'approved') ...[
          if (ends != null) ...[
            const SizedBox(height: 6),
            Text(context.t('venue_claim.trial_until', params: {'date': DateFormat.yMd(context.read<I18n>().language).format(ends)}),
                style: tw(12, color: const Color(0xFF6EE7B7))),
          ],
          const SizedBox(height: 12),
          GradientButton(
            label: context.t('venue_claim.open_panel'),
            onTap: _openPanel,
            expand: true,
            radius: 12,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            gradient: const LinearGradient(colors: [Tw.emerald600, Tw.emerald500]),
          ),
        ],
        if (status == 'pending') ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Opacity(
              opacity: _busy == c['id'] ? 0.5 : 1,
              child: GestureDetector(
                onTap: _busy == c['id'] ? null : () => _withdraw(c['id'] as String),
                child: Text(context.t('venue_claim.withdraw'),
                    style: tw(12, color: Tw.slate400).copyWith(decoration: TextDecoration.underline, decorationColor: Tw.slate400)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
