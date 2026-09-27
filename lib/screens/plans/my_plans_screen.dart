import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Port of app/my-plans/page.tsx (+ useMyChills)
class MyPlansScreen extends StatefulWidget {
  const MyPlansScreen({super.key});

  @override
  State<MyPlansScreen> createState() => _MyPlansScreenState();
}

class _MyPlansScreenState extends State<MyPlansScreen> {
  List<Map<String, dynamic>> _chills = [];
  bool _loading = true;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) {
      _loading = false;
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('chills')
        .where('host_uid', isEqualTo: uid)
        .where('status', whereIn: ['active', 'full'])
        .snapshots()
        .listen((s) => setState(() {
              _chills = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
              _loading = false;
            }), onError: (_) => setState(() => _loading = false));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2))));
    Widget addBtn() => Pressable(
          onTap: () => openRoute(context, AppRoute.createPlan),
          scale: 0.95,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Tw.fuchsia600,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Tw.fuchsia600.withValues(alpha: 0.3), blurRadius: 20)],
            ),
            child: const Icon(Icons.add, color: Tw.white),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 128), children: [
          Row(children: [
            IconButton(padding: EdgeInsets.zero, onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('my_plans.title', fallback: 'Mis planes'), style: tw(24, weight: black)),
                Text(context.t('my_plans.subtitle', fallback: 'Planes que has creado'), style: tw(12, color: Tw.slate500)),
              ]),
            ),
            addBtn(),
          ]),
          const SizedBox(height: 24),
          if (_chills.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Column(children: [
                const Icon(Icons.event_note, size: 48, color: Tw.slate700),
                const SizedBox(height: 16),
                Text(context.t('my_plans.empty', fallback: 'No tienes planes activos'), style: tw(16, color: Tw.slate500)),
                const SizedBox(height: 16),
                Pressable(
                  onTap: () => openRoute(context, AppRoute.createPlan),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(color: Tw.fuchsia600, borderRadius: BorderRadius.circular(16)),
                    child: Label(context.t('my_plans.create_first', fallback: 'Crear tu primer plan'), size: 12, color: Tw.white),
                  ),
                ),
              ]),
            )
          else
            for (final c in _chills) _card(context, c),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> c) {
    final status = c['status'] as String? ?? '';
    final (label, color) = switch (status) {
      'full' => (context.t('my_plans.full', fallback: 'Lleno'), Tw.red400),
      'active' => (context.t('my_plans.active', fallback: 'Activo'), Tw.emerald400),
      _ => (status, Tw.slate400),
    };
    final accepted = c['accepted_users'] is List ? (c['accepted_users'] as List).length : 0;
    final pending = c['pending_users'] is List ? (c['pending_users'] as List).length : 0;
    final created = parseDate(c['created_at']);
    final tags = asStringList(c['tags']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        onTap: () => openRoute(context, AppRoute.planManage, args: {'id': c['id'] as String}),
        radius: 16,
        padding: const EdgeInsets.all(20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(safeStr(c['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(14, weight: black))),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Label(label, size: 9, weight: bold, color: color, tracking: 0),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 16, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.group, size: 12, color: Tw.slate500),
                  const SizedBox(width: 4),
                  Text('$accepted/${asInt(c['max_capacity'])}', style: tw(10, color: Tw.slate500)),
                ]),
                if (pending > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.notifications, size: 12, color: Tw.amber400),
                    const SizedBox(width: 4),
                    Text('$pending ${context.t('my_plans.pending', fallback: 'pendientes')}', style: tw(10, color: Tw.amber400)),
                  ]),
                if (created != null) Text(DateFormat('d MMM', 'es').format(created), style: tw(10, color: Tw.slate500)),
              ]),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: [
                  for (final t in tags)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(4)),
                      child: Text(t, style: tw(9, color: Tw.slate500)),
                    ),
                ]),
              ],
            ]),
          ),
          const Icon(Icons.chevron_right, color: Tw.slate600),
        ]),
      ),
    );
  }
}
