import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/firestore_utils.dart';

final _db = FirebaseFirestore.instance;
final _fn = FirebaseFunctions.instance;

/// Port of hooks/useLikes.ts → sendLike callable.
Future<({bool isMatch, Map<String, dynamic>? matchData, Object? error})> sendLike(String targetUserId,
    {bool isSuper = false}) async {
  try {
    final res = await _fn.httpsCallable('sendLike').call<Map<String, dynamic>>({
      'targetUserId': targetUserId,
      'isSuper': isSuper,
    });
    final data = Map<String, dynamic>.from(res.data);
    final md = data['matchData'];
    return (
      isMatch: data['isMatch'] == true,
      matchData: md is Map ? Map<String, dynamic>.from(md) : null,
      error: null,
    );
  } catch (e) {
    return (isMatch: false, matchData: null, error: e);
  }
}

/// Port of getOrCreateChat in hooks/useChat.ts
Future<String> getOrCreateChat(String a, String b) async {
  final ids = [a, b]..sort();
  final chatId = ids.join('_');
  final ref = _db.collection('chats').doc(chatId);
  final snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      'users': [a, b],
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'typing': {a: false, b: false},
    });
  }
  return chatId;
}

/// Port of hooks/useSafeActions.ts
Future<void> blockUser(String uid, String blockedId) => _db
    .collection('users')
    .doc(uid)
    .collection('blocks')
    .doc(blockedId)
    .set({'blockedId': blockedId, 'timestamp': FieldValue.serverTimestamp()});

Future<void> reportUser(String uid, String reportedId, String reason, [String details = '']) {
  String sanitize(String s) {
    final c = s.replaceAll(RegExp('[<>]'), '').trim();
    return c.length > 1000 ? c.substring(0, 1000) : c;
  }

  return _db.collection('reports').add({
    'reporterId': uid,
    'reportedId': reportedId,
    'reason': sanitize(reason),
    'details': sanitize(details),
    'timestamp': FieldValue.serverTimestamp(),
    'status': 'pending',
  });
}

/// Port of lib/timeUtils.js formatLastSeen (Spanish strings are hardcoded on the web too).
String formatLastSeen(Object? ts) {
  final date = parseDate(ts);
  if (date == null) return 'hace mucho';
  final diff = DateTime.now().difference(date).inSeconds;
  if (diff < 60) return 'ahora mismo';
  final m = diff ~/ 60;
  if (m < 60) return 'hace $m min';
  final h = m ~/ 60;
  if (h < 24) return 'hace $h h';
  final d = h ~/ 24;
  if (d == 1) return 'ayer';
  if (d < 7) return 'hace $d d';
  return '${date.day}/${date.month}/${date.year}';
}

/// Port of lib/geo.ts calculateDistance (km, 1 decimal).
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return (r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)) * 10).round() / 10;
}

/// Port of ROLE_LABELS / getRoleLabel in lib/platform.ts
class RoleOption {
  final String value;
  final String emoji;
  final String labelKey;
  final String fallbackLabel;
  final String descKey;
  final String fallbackDesc;
  const RoleOption(this.value, this.emoji, this.labelKey, this.fallbackLabel, this.descKey, this.fallbackDesc);
}

const _roleLabels = {
  'party_only': ('profile.role_party_only', 'Solo Fiesta'),
  'fiesta': ('roles.party', 'Fiesta'),
  'chill': ('roles.chill', 'Chill'),
  'afterwork': ('roles.afterwork', 'Afterwork'),
  'social': ('roles.social', 'Social'),
};

String roleLabel(String? rol, String Function(String key, String fallback) t) {
  if (rol == null || rol.isEmpty) return '';
  final e = _roleLabels[rol];
  return e == null ? rol : t(e.$1, e.$2);
}

const platformRoles = [
  RoleOption('fiesta', '🎉', 'roles.party', 'Fiesta', 'roles.party_desc', 'Eventos, clubs y marcha nocturna'),
  RoleOption('chill', '🍹', 'roles.chill', 'Chill', 'roles.chill_desc', 'Copas, terrazas y planes tranquilos'),
  RoleOption('afterwork', '💼', 'roles.afterwork', 'Afterwork', 'roles.afterwork_desc', 'Desconectar y conocer gente'),
  RoleOption('social', '💬', 'roles.social', 'Social', 'roles.social_desc', 'Conectar, hacer amigos y más'),
];
