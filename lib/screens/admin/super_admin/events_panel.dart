import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

/// Port of features/super-admin/EventsPanel.tsx (mobile card layout) + hooks/useEvents.ts
class EventsPanel extends StatefulWidget {
  final List<Map<String, dynamic>> allUsers;
  const EventsPanel({super.key, required this.allUsers});

  @override
  State<EventsPanel> createState() => _EventsPanelState();
}

class _EventsPanelState extends State<EventsPanel> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final s = await FirebaseFirestore.instance.collection('events').orderBy('created_at', descending: true).limit(50).get();
      if (mounted) setState(() => _events = [for (final d in s.docs) {'id': d.id, ...d.data()}]);
    } catch (e) {
      debugPrint('Error fetching events: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    final i18n = context.read<I18n>();
    if (!await confirmDialog(context, message: i18n.t('admin.events.confirm_delete'), danger: true, confirmText: i18n.t('admin.events.delete_btn'))) {
      return;
    }
    try {
      await callFn('adminDeleteEvent', {'eventId': id});
      setState(() => _events.removeWhere((e) => e['id'] == id));
    } catch (_) {
      if (mounted) showToast(context, i18n.t('admin.events.delete_error'), error: true);
    }
  }

  int _sold(Map<String, dynamic> e) {
    final stats = (e['stats'] as Map?)?['total_sold'] as num? ?? 0;
    final tiers = (e['ticket_tiers'] as List? ?? const []).fold<num>(0, (acc, t) => acc + ((t is Map ? t['sold'] as num? : null) ?? 0));
    return (stats > tiers ? stats : tiers).toInt();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminEmpty('Cargando eventos...', loading: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Eventos Independientes', style: tw(20, weight: bold)),
      const SizedBox(height: 24),
      if (_events.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text('No hay eventos.', textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
        ),
      for (final e in _events) ...[_card(e), const SizedBox(height: 12)],
    ]);
  }

  Widget _card(Map<String, dynamic> e) {
    final owner = widget.allUsers.where((u) => u['id'] == e['organizerId'] || u['uid'] == e['organizerId']).firstOrNull;
    final status = (e['status'] as String?) ?? 'active';
    final start = e['start_date'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.slate800)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text((e['title'] as String?) ?? '', style: tw(14, weight: bold))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: status == 'active' ? Tw.green500.withValues(alpha: 0.1) : Tw.slate800,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(status.toUpperCase(), style: tw(10, weight: bold, color: status == 'active' ? Tw.green400 : Tw.slate400)),
          ),
        ]),
        const SizedBox(height: 8),
        Text((owner?['email'] ?? e['organizerId'] ?? '') as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(12, color: Tw.slate400)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(start is String ? start : shortDate(start), style: tw(12, color: Tw.slate500))),
          Text('${_sold(e)} tickets', style: tw(12, color: Tw.slate400)),
        ]),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _delete(e['id'] as String),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('Borrar', style: tw(12, weight: bold, color: Tw.red400))),
        ),
      ]),
    );
  }
}
