import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../i18n/i18n.dart';
import '../../models/firestore_utils.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/social.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Port of app/[city]/chat/detail/page.tsx (+ hooks/useChat.ts, useMedia.ts)
class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  const ChatDetailScreen({super.key, required this.chatId});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _db = FirebaseFirestore.instance;
  late final DocumentReference<Map<String, dynamic>> _chatRef = _db.collection('chats').doc(widget.chatId);
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _otherTyping = false;
  List<String> _activeUsers = [];
  Map<String, dynamic>? _other;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _nearBottom = true;
  bool _localTyping = false;
  bool _uploading = false;
  double _progress = 0;
  final _recorder = AudioRecorder();
  bool _recording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  final List<StreamSubscription> _subs = [];
  late final String _uid = context.read<AuthProvider>().user!.uid;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final near = _scroll.position.maxScrollExtent - _scroll.offset < 100;
      if (near != _nearBottom) setState(() => _nearBottom = near);
    });
    _chatRef.update({'activeUsers': FieldValue.arrayUnion([_uid])}).catchError((_) {});
    _subs.add(_chatRef.collection('messages').orderBy('timestamp').limitToLast(100).snapshots().listen((s) {
      setState(() {
        _messages = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _loading = false;
      });
      _markAsRead();
      if (_nearBottom) _scrollToBottom();
    }, onError: (_) => setState(() => _loading = false)));
    _subs.add(_chatRef.snapshots().listen((s) {
      final d = s.data();
      if (d == null) return;
      final users = (d['users'] as List?)?.whereType<String>() ?? const <String>[];
      final otherId = users.firstWhere((u) => u != _uid, orElse: () => '');
      final typing = d['typing'] is Map ? d['typing'] as Map : const {};
      setState(() {
        _otherTyping = typing[otherId] == true;
        _activeUsers = (d['activeUsers'] as List?)?.whereType<String>().toList() ?? [];
      });
      if (_nearBottom) _scrollToBottom();
    }, onError: (_) {}));
    _loadOther();
  }

  Future<void> _loadOther() async {
    final auth = context.read<AuthProvider>();
    final chat = await _chatRef.get();
    if (!chat.exists || !mounted) return;
    final users = (chat.data()?['users'] as List?)?.whereType<String>() ?? const <String>[];
    final otherId = users.firstWhere((u) => u != _uid, orElse: () => '');
    if (otherId.isEmpty) return;
    if (!['plus', 'black'].contains(auth.profile?.membershipTier)) {
      final m = await _db.collection('matches').where('users', arrayContains: _uid).get();
      final hasMatch = m.docs.any((d) => (d.data()['users'] as List?)?.contains(otherId) == true);
      if (!hasMatch) {
        if (mounted) openRoute(context, AppRoute.premium, replace: true);
        return;
      }
    }
    final u = await _db.collection('users').doc(otherId).get();
    if (mounted && u.exists) setState(() => _other = {'id': u.id, ...?u.data()});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _chatRef.update({'activeUsers': FieldValue.arrayRemove([_uid])}).catchError((_) {});
    _recordTimer?.cancel();
    _recorder.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _markAsRead() async {
    final unread = _messages.where((m) => m['senderId'] != _uid && m['read'] == false);
    await Future.wait(unread.map((m) => _chatRef.collection('messages').doc(m['id'] as String).update({
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        }).catchError((_) {})));
  }

  Future<void> _setTyping(bool typing) async {
    if (typing == _localTyping) return;
    _localTyping = typing;
    await _chatRef.update({'typing.$_uid': typing}).catchError((_) {});
  }

  Future<void> _sendMessage(String content, {String type = 'text', String? url}) async {
    if (content.trim().isEmpty && url == null) return;
    await _chatRef.collection('messages').add({
      'content': content.trim(),
      'type': type,
      'url': url,
      'senderId': _uid,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });
    await _chatRef.update({
      'lastMessage': type == 'text' ? content.trim() : 'Sent an $type',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'typing.$_uid': false,
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    try {
      HapticFeedback.selectionClick();
      await _sendMessage(text);
      _input.clear();
      _localTyping = false;
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('chat.detail.send_error', fallback: 'Error al enviar el mensaje.'), error: true);
    }
  }

  Future<String> _upload(File file, String path, String contentType) async {
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      final task = FirebaseStorage.instance.ref(path).putFile(file, SettableMetadata(contentType: contentType));
      task.snapshotEvents.listen((s) {
        if (mounted && s.totalBytes > 0) setState(() => _progress = s.bytesTransferred / s.totalBytes);
      });
      await task;
      return await task.snapshot.ref.getDownloadURL();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickImage() async {
    final i18n = context.read<I18n>();
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (x == null) return;
    try {
      HapticFeedback.mediumImpact();
      final name = x.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final url = await _upload(File(x.path), 'chatMedia/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_$name', 'image/jpeg');
      await _sendMessage('', type: 'image', url: url);
    } catch (_) {
      if (mounted) showToast(context, i18n.t('chat.detail.upload_error'), error: true);
    }
  }

  Future<void> _startRecording() async {
    final i18n = context.read<I18n>();
    try {
      if (!await _recorder.hasPermission()) throw Exception('mic');
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      HapticFeedback.heavyImpact();
      setState(() {
        _recording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _recordSeconds++));
    } catch (_) {
      if (mounted) showToast(context, i18n.t('chat.detail.mic_error'), error: true);
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _recording = false;
      _recordSeconds = 0;
    });
    if (path == null) return;
    try {
      final url = await _upload(File(path), 'chatMedia/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_voice.m4a', 'audio/mp4');
      await _sendMessage('', type: 'audio', url: url);
    } catch (_) {
      if (mounted) showToast(context, context.read<I18n>().t('chat.detail.upload_error'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = _other;
    if (_loading || other == null) {
      return const Scaffold(body: Center(child: SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    final me = context.watch<AuthProvider>().profile;
    final i18n = context.watch<I18n>();
    final otherLat = asDouble(other['lat']), otherLng = asDouble(other['lng']);
    final distance = me?.lat != null && me?.lng != null && otherLat != null && otherLng != null
        ? calculateDistance(me!.lat!, me.lng!, otherLat, otherLng).toString()
        : '0.5';
    final inChat = _activeUsers.contains(other['id']);

    return Scaffold(
      body: Column(children: [
        _header(context, other, inChat, distance),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tw.slate950, Tw.slate950, Tw.slate900]),
            ),
            child: Stack(children: [
              ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(24),
                itemCount: _messages.length + (_otherTyping ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _messages.length) return const _TypingDots();
                  return _messageRow(context, i, i18n);
                },
              ),
              if (!_nearBottom)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _scrollToBottom,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Tw.fuchsia600,
                          boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.3), blurRadius: 15)],
                        ),
                        child: const Icon(Icons.keyboard_arrow_down, color: Tw.white),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        _footer(context),
      ]),
    );
  }

  Widget _header(BuildContext context, Map<String, dynamic> other, bool inChat, String distance) {
    final online = other['online'] == true;
    final i18n = context.read<I18n>();
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 16, 24, 16),
          decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.4), border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
          child: Row(children: [
            _squareBtn(const Icon(Icons.chevron_left, color: Tw.white), () => Navigator.of(context).maybePop()),
            const SizedBox(width: 16),
            Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Tw.w(0.1)),
                  boxShadow: inChat ? [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.6), blurRadius: 20)] : null,
                ),
                child: ClipRRect(borderRadius: BorderRadius.circular(15), child: NetImage(other['fotoUrl'] as String?)),
              ),
              if (online)
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Tw.green500,
                      border: Border.all(color: Tw.slate900, width: 4),
                      boxShadow: const [BoxShadow(color: Tw.green500, blurRadius: 10)],
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(safeStr(other['nick']), maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(18, weight: black, tracking: -0.025, height: 1.2)),
                Row(children: [
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _otherTyping
                          ? Label(i18n.t('chat.typing'), key: const ValueKey('t'), size: 9, color: Tw.fuchsia400, maxLines: 1)
                          : inChat
                              ? Row(key: const ValueKey('a'), mainAxisSize: MainAxisSize.min, children: [
                                  Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Tw.fuchsia500)),
                                  const SizedBox(width: 4),
                                  Label(i18n.t('chat.in_chat'), size: 9, color: Tw.fuchsia500),
                                ])
                              : Label(
                                  online
                                      ? i18n.t('chat.online')
                                      : other['lastSeen'] != null
                                          ? i18n.t('chat.active', params: {'time': formatLastSeen(other['lastSeen'])})
                                          : i18n.t('chat.offline'),
                                  key: const ValueKey('s'),
                                  size: 9,
                                  color: online ? Tw.green500.withValues(alpha: 0.6) : Tw.slate500,
                                  maxLines: 1,
                                ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.w(0.1))),
                  const SizedBox(width: 8),
                  Label('$distance km', size: 9, color: Tw.slate500),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Pressable(
              onTap: () => openRoute(context, AppRoute.barGift, args: {'giftNick': safeStr(other['nick'])}),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.amber500]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tw.w(0.1)),
                  boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.3), blurRadius: 15)],
                ),
                child: const Text('🍹', style: TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 8),
            Builder(builder: (btn) => _squareBtn(const Icon(Icons.more_vert, color: Tw.slate400, size: 18), () => _showOptions(btn, other))),
          ]),
        ),
      ),
    );
  }

  Widget _squareBtn(Widget icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
          child: icon,
        ),
      );

  void _showOptions(BuildContext btn, Map<String, dynamic> other) {
    final i18n = context.read<I18n>();
    final otherId = other['id'] as String;
    final nick = safeStr(other['nick']);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'opts',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      pageBuilder: (ctx, _, _) {
        Widget item(IconData icon, String label, Color color, Future<void> Function() onTap) => InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(icon, color: color == const Color(0xFFE2E8F0) ? Tw.slate400 : color),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, style: tw(14, weight: bold, color: color))),
                ]),
              ),
            );
        return Stack(children: [
          Positioned(
            top: MediaQuery.of(ctx).padding.top + 96,
            right: 24,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 224,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Tw.slate900.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Tw.w(0.1)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  item(Icons.person, i18n.t('chat.view_profile'), const Color(0xFFE2E8F0), () async {
                    Navigator.of(ctx).pop();
                    openRoute(context, AppRoute.profileView, args: {'id': otherId});
                  }),
                  item(Icons.lock_open, i18n.t('chat.grant_access'), const Color(0xFFEAB308), () async {
                    Navigator.of(ctx).pop();
                    if (await confirmDialog(context, message: i18n.t('chat.detail.confirm_access', params: {'name': nick}))) {
                      await _db.collection('users').doc(_uid).update({'permittedUsers': FieldValue.arrayUnion([otherId])});
                      await _sendMessage('¡He desbloqueado mis fotos privadas para ti! 🔥');
                    }
                  }),
                  Divider(color: Tw.w(0.05), height: 1, indent: 8, endIndent: 8),
                  item(Icons.flag, i18n.t('chat.report'), Tw.orange500, () async {
                    Navigator.of(ctx).pop();
                    if (await confirmDialog(context, message: i18n.t('chat.detail.confirm_report'), confirmText: i18n.t('chat.report'), danger: true)) {
                      await reportUser(_uid, otherId, 'Desde chat');
                      if (mounted) showToast(context, i18n.t('chat.detail.report_sent'));
                    }
                  }),
                  item(Icons.block, i18n.t('chat.block'), Tw.red500, () async {
                    Navigator.of(ctx).pop();
                    if (await confirmDialog(context, message: i18n.t('chat.detail.confirm_block'), confirmText: i18n.t('chat.block'), danger: true)) {
                      await blockUser(_uid, otherId);
                      if (mounted) Navigator.of(context).pop();
                    }
                  }),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _messageRow(BuildContext context, int index, I18n i18n) {
    final msg = _messages[index];
    final isMe = msg['senderId'] == _uid;
    final date = parseDate(msg['timestamp']);
    final prev = index > 0 ? parseDate(_messages[index - 1]['timestamp']) : null;
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final showSep = date != null && (prev == null || !sameDay(date, prev));
    String sepLabel = '';
    if (showSep) {
      final now = DateTime.now();
      final diff = DateTime(now.year, now.month, now.day).difference(DateTime(date.year, date.month, date.day)).inDays;
      sepLabel = diff == 0
          ? i18n.t('events.today', fallback: 'Hoy')
          : diff == 1
              ? i18n.t('visits.yesterday', fallback: 'Ayer')
              : DateFormat('EEEE, d MMM', 'es').format(date);
    }
    final type = msg['type'] as String? ?? 'text';
    final url = msg['url'] as String?;
    final content = safeStr(msg['content']);

    return Column(children: [
      if (showSep)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Tw.slate900.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Tw.w(0.05)),
            ),
            child: Label(sepLabel, size: 9, color: Tw.slate500),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8 - 48),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: isMe ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.fuchsia600, Tw.purple600]) : null,
                color: isMe ? null : Tw.slate800.withValues(alpha: 0.8),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isMe ? 24 : 0),
                  topRight: Radius.circular(isMe ? 0 : 24),
                  bottomLeft: const Radius.circular(24),
                  bottomRight: const Radius.circular(24),
                ),
                border: isMe ? null : Border.all(color: Tw.w(0.05)),
                boxShadow: [
                  BoxShadow(
                    color: isMe ? Tw.fuchsia500.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                if (type == 'image' && url != null)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    GestureDetector(
                      onTap: () => _showImage(url),
                      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: NetImage(url, width: 288, fit: BoxFit.cover)),
                    ),
                    if (content.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text(content, style: tw(14, weight: medium))),
                  ])
                else if (type == 'audio' && url != null)
                  _AudioBubble(url: url)
                else
                  Align(alignment: Alignment.centerLeft, widthFactor: 1, child: Text(content, style: tw(14, weight: medium, height: 1.5, color: isMe ? Tw.white : const Color(0xFFF1F5F9)))),
                const SizedBox(height: 8),
                Opacity(
                  opacity: 0.6,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Label(date != null ? DateFormat('HH:mm').format(date) : '', size: 9, color: Tw.white, tracking: 0.05),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Icon(msg['read'] == true ? Icons.done_all : Icons.done, size: 14, color: msg['read'] == true ? Tw.blue400 : Tw.w(0.4)),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  void _showImage(String url) => showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'img',
        barrierColor: Tw.slate950.withValues(alpha: 0.9),
        pageBuilder: (ctx, _, _) => GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Center(child: Padding(padding: const EdgeInsets.all(16), child: ClipRRect(borderRadius: BorderRadius.circular(24), child: NetImage(url, fit: BoxFit.contain)))),
        ),
      );

  Widget _footer(BuildContext context) {
    final hasText = _input.text.trim().isNotEmpty;
    final i18n = context.read<I18n>();
    return Stack(children: [
      ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).padding.bottom + MediaQuery.of(context).viewInsets.bottom * 0),
            decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.8), border: Border(top: BorderSide(color: Tw.w(0.05)))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Pressable(
                onTap: _pickImage,
                scale: 0.9,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
                  child: const Icon(Icons.add_a_photo, color: Tw.slate400),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(32), border: Border.all(color: Tw.w(0.05))),
                  child: _recording
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          color: Tw.red500.withValues(alpha: 0.1),
                          child: Row(children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Tw.red500)),
                            const SizedBox(width: 12),
                            Label('${i18n.t('chat.recording')} ${_recordSeconds ~/ 60}:${(_recordSeconds % 60).toString().padLeft(2, '0')}',
                                size: 12, color: Tw.red400),
                          ]),
                        )
                      : TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 5,
                          style: tw(14),
                          onChanged: (v) => _setTyping(v.isNotEmpty),
                          decoration: InputDecoration(
                            hintText: i18n.t('chat.write_something'),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
                child: Pressable(
                  key: ValueKey(_recording ? 'stop' : hasText ? 'send' : 'mic'),
                  onTap: _recording ? _stopRecording : hasText ? _send : _startRecording,
                  scale: 0.9,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _recording ? Tw.red500 : hasText ? Tw.fuchsia600 : Tw.w(0.05),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: hasText && !_recording ? [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.2), blurRadius: 15)] : null,
                    ),
                    child: Icon(_recording ? Icons.stop : hasText ? Icons.send : Icons.mic, color: _recording || hasText ? Tw.white : Tw.slate400),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
      if (_uploading)
        Positioned(
          top: 0,
          left: 0,
          child: Container(
            height: 4,
            width: MediaQuery.of(context).size.width * _progress,
            decoration: const BoxDecoration(color: Tw.fuchsia500, boxShadow: [BoxShadow(color: Tw.fuchsia500, blurRadius: 15)]),
          ),
        ),
    ]);
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Tw.slate800.withValues(alpha: 0.4),
            borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Transform.translate(
                  offset: Offset(0, -5 * (1 - ((((_c.value - i * 0.16) % 1) * 2 - 1).abs()))),
                  child: Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Tw.fuchsia500),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// Port of components/ChatAudioPlayer.tsx
class _AudioBubble extends StatefulWidget {
  final String url;
  const _AudioBubble({required this.url});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final _player = AudioPlayer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.url).then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((_) => null);
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = _player.playing;
    return SizedBox(
      width: 220,
      child: Row(children: [
        Pressable(
          onTap: () => !_ready ? null : (playing ? _player.pause() : _player.play()),
          scale: 0.9,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.w(0.1)),
            child: Icon(playing ? Icons.pause : Icons.play_arrow, color: Tw.white, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (_, snap) {
              final total = _player.duration?.inMilliseconds ?? 0;
              final p = total == 0 ? 0.0 : ((snap.data?.inMilliseconds ?? 0) / total).clamp(0.0, 1.0);
              return Container(
                height: 6,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(99)),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: p,
                    child: Container(decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(99), boxShadow: const [BoxShadow(color: Tw.white, blurRadius: 10)])),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Opacity(opacity: 0.4, child: Label(playing ? 'Reproduciendo' : 'Nota voz', color: Tw.white)),
      ]),
    );
  }
}
