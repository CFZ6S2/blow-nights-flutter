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

String timeAgo(DateTime date, I18n i18n) {
  final diffMin = DateTime.now().difference(date).inMinutes;
  if (diffMin < 1) return i18n.t('chat.just_now', fallback: 'ahora');
  if (diffMin < 60) return '${diffMin}min';
  final h = diffMin ~/ 60;
  if (h < 24) return '${h}h';
  final d = h ~/ 24;
  if (d < 7) return '${d}d';
  return DateFormat('d MMM', i18n.dateLocale).format(date);
}

/// Port of app/[city]/chat/page.tsx
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;
    _sub = _db
        .collection('chats')
        .where('users', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .listen((snap) => _build(uid, snap), onError: (_) => setState(() => _loading = false));
  }

  Future<void> _build(String uid, QuerySnapshot<Map<String, dynamic>> snap) async {
    final blocks = await _db.collection('users').doc(uid).collection('blocks').get();
    final blocked = blocks.docs.map((d) => d.data()['blockedId']).toSet();
    final out = <Map<String, dynamic>>[];
    for (final d in snap.docs) {
      final data = d.data();
      final users = (data['users'] as List?)?.whereType<String>().toList() ?? const [];
      final otherId = users.firstWhere((u) => u != uid, orElse: () => '');
      if (otherId.isEmpty || blocked.contains(otherId)) continue;
      final other = await _db.collection('users').doc(otherId).get();
      var unread = 0;
      try {
        final c = await d.reference
            .collection('messages')
            .where('read', isEqualTo: false)
            .where('senderId', isNotEqualTo: uid)
            .count()
            .get();
        unread = c.count ?? 0;
      } catch (_) {}
      out.add({'id': d.id, ...data, 'otherUser': other.data(), 'unreadCount': unread});
    }
    if (mounted) {
      setState(() {
        _chats = out;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final i18n = context.watch<I18n>();
    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(children: [
        IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.chevron_left, size: 28)),
        Expanded(child: Text(context.t('chat.title'), textAlign: TextAlign.center, style: tw(24, weight: bold))),
        if (auth.isSuperAdmin)
          IconButton(onPressed: () => openRoute(context, AppRoute.profile), icon: const Icon(Icons.person, color: Tw.slate400))
        else
          const SizedBox(width: 48),
      ]),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Opacity(opacity: _loading ? 0.4 : 1, child: header),
          Expanded(
            child: _loading
                ? ListView(padding: const EdgeInsets.all(16), children: [for (var i = 0; i < 5; i++) const _ChatSkeleton()])
                : _chats.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: Column(children: [
                          const Text('💬', style: TextStyle(fontSize: 60)),
                          const SizedBox(height: 16),
                          Text(context.t('chat.empty_messages'), style: tw(16, color: Tw.slate500)),
                        ]),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount: _chats.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final c = _chats[i];
                          final other = c['otherUser'] is Map ? Map<String, dynamic>.from(c['otherUser']) : const <String, dynamic>{};
                          final unread = asInt(c['unreadCount']);
                          final has = unread > 0;
                          final last = parseDate(c['lastMessageAt']);
                          return GlassCard(
                            onTap: () => openRoute(context, AppRoute.chatDetail, args: {'id': c['id'] as String}),
                            radius: 24,
                            color: has ? Tw.fuchsia500.withValues(alpha: 0.05) : Tw.w(0.05),
                            borderColor: has ? Tw.fuchsia500.withValues(alpha: 0.2) : Tw.w(0.05),
                            child: Row(children: [
                              Stack(children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: has ? Tw.fuchsia500.withValues(alpha: 0.5) : Tw.purple500.withValues(alpha: 0.3)),
                                  ),
                                  child: ClipOval(child: NetImage(other['fotoUrl'] as String?, placeholder: Container(color: Tw.slate800))),
                                ),
                                if (other['online'] == true)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Tw.green500,
                                        border: Border.all(color: Tw.slate950, width: 2),
                                      ),
                                    ),
                                  ),
                              ]),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(safeStr(other['nick']),
                                          overflow: TextOverflow.ellipsis, style: tw(16, weight: bold, color: has ? Tw.white : Tw.slate300)),
                                    ),
                                    Text(last != null ? timeAgo(last, i18n) : '',
                                        style: tw(10, weight: has ? bold : FontWeight.w400, color: has ? Tw.fuchsia400 : Tw.slate500)),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(
                                    safeStr(c['lastMessage']).isNotEmpty ? safeStr(c['lastMessage']) : context.t('chat.say_hi'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tw(14, weight: has ? semibold : FontWeight.w400, color: has ? Tw.white : Tw.slate400),
                                  ),
                                ]),
                              ),
                              const SizedBox(width: 8),
                              has
                                  ? Container(
                                      constraints: const BoxConstraints(minWidth: 22),
                                      height: 22,
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Tw.fuchsia500,
                                        borderRadius: BorderRadius.circular(99),
                                        boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.4), blurRadius: 10)],
                                      ),
                                      child: Text(unread > 99 ? '99+' : '$unread', style: tw(10, weight: black)),
                                    )
                                  : const Icon(Icons.chevron_right, color: Tw.slate600, size: 18),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24)),
        child: Row(children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.w(0.05))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 14, width: 120, color: Tw.w(0.05)),
              const SizedBox(height: 8),
              Container(height: 12, width: 200, color: Tw.w(0.05)),
            ]),
          ),
        ]),
      );
}
