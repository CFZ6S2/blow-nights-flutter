import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/firestore_utils.dart';
import 'ble_identity.dart';

/// Friend groups for the BLE finder. Stored in `finder_groups/{inviteCode}` (rules in the web repo's firestore.rules):
/// the doc id IS the invite code, so joining is a blind update that only succeeds for whoever knows it.
final _col = FirebaseFirestore.instance.collection('finder_groups');

const finderMaxMembers = 20;
const finderGroupLifetime = Duration(days: 3);

/// No I, L, O, 0 or 1: codes get read aloud and typed in the dark.
const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const _invitePrefix = 'BNG1:';

class FinderMember {
  final String uid;
  final String nick;
  final String fotoUrl;
  /// Secret key the member's phone derives its rotating BLE id from (see ble_identity.dart), and its announced
  /// successor with the moment it takes over.
  final String bleKey;
  final String bleKeyNext;
  final DateTime? bleKeyNextAt;

  /// Static id written by the first APK (before rotation); only read so those phones are still recognised.
  final String legacyBleId;
  final DateTime? joinedAt;
  const FinderMember({
    required this.uid,
    this.nick = '',
    this.fotoUrl = '',
    this.bleKey = '',
    this.bleKeyNext = '',
    this.bleKeyNextAt,
    this.legacyBleId = '',
    this.joinedAt,
  });

  /// Ids this member's phone may be advertising right now.
  Set<String> get advertisedIds => bleKey.isNotEmpty
      ? bleIdsAround([bleKey, if (bleKeyNext.isNotEmpty) bleKeyNext])
      : {if (legacyBleId.isNotEmpty) legacyBleId};

  factory FinderMember.from(String uid, Object? raw) {
    final m = raw is Map ? raw : const {};
    return FinderMember(
      uid: uid,
      nick: safeStr(m['nick']),
      fotoUrl: safeStr(m['fotoUrl']),
      bleKey: safeStr(m['bleKey']),
      bleKeyNext: safeStr(m['bleKeyNext']),
      bleKeyNextAt: parseDate(m['bleKeyNextAt']),
      legacyBleId: safeStr(m['bleId']),
      joinedAt: parseDate(m['joinedAt']),
    );
  }
}

class MeetingPoint {
  final String label;
  final double? lat;
  final double? lng;
  final String setBy;
  final DateTime? setAt;
  const MeetingPoint({required this.label, this.lat, this.lng, this.setBy = '', this.setAt});

  bool get hasCoords => lat != null && lng != null;

  static MeetingPoint? from(Object? raw) {
    if (raw is! Map) return null;
    return MeetingPoint(
      label: safeStr(raw['label']),
      lat: asDouble(raw['lat']),
      lng: asDouble(raw['lng']),
      setBy: safeStr(raw['setBy']),
      setAt: parseDate(raw['setAt']),
    );
  }
}

class FinderGroup {
  final String code;
  final String name;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final List<String> memberIds;
  final Map<String, FinderMember> members;
  final MeetingPoint? meetingPoint;

  /// False while the snapshot includes local writes the server hasn't acknowledged yet.
  final bool confirmed;
  const FinderGroup({
    required this.code,
    required this.name,
    required this.createdBy,
    this.createdAt,
    this.expiresAt,
    this.memberIds = const [],
    this.members = const {},
    this.meetingPoint,
    this.confirmed = true,
  });

  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  String get invitePayload => '$_invitePrefix$code';

  /// Members in join order (memberIds keeps it); entries without data still show up.
  List<FinderMember> get orderedMembers => [for (final id in memberIds) members[id] ?? FinderMember(uid: id)];

  factory FinderGroup.from(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final raw = d['members'] is Map ? d['members'] as Map : const {};
    return FinderGroup(
      code: doc.id,
      name: safeStr(d['name']),
      createdBy: safeStr(d['createdBy']),
      createdAt: parseDate(d['createdAt']),
      expiresAt: parseDate(d['expiresAt']),
      memberIds: asStringList(d['memberIds']),
      members: {for (final e in raw.entries) e.key.toString(): FinderMember.from(e.key.toString(), e.value)},
      meetingPoint: MeetingPoint.from(d['meetingPoint']),
      confirmed: !doc.metadata.hasPendingWrites,
    );
  }
}

String _random(String alphabet, int length) {
  final r = math.Random.secure();
  return List.generate(length, (_) => alphabet[r.nextInt(alphabet.length)]).join();
}

/// Extracts an invite code from a QR / NFC payload ("BNG1:CODE", possibly inside an NDEF text record) or a typed code.
String? parseInviteCode(String raw) {
  final up = raw.toUpperCase();
  final code = RegExp('${RegExp.escape(_invitePrefix)}([A-Z0-9]{6})').firstMatch(up)?.group(1) ??
      (RegExp(r'^[A-Z0-9]{6}$').hasMatch(up.trim()) ? up.trim() : null);
  if (code == null || code.split('').any((c) => !_codeAlphabet.contains(c))) return null;
  return code;
}

/// BLE fields of a member entry for this install's key schedule (see ble_identity.dart).
Map<String, Object?> _bleFields(List<OwnBleKey> keys) => {
      'bleKey': keys.first.key,
      if (keys.length > 1) ...{
        'bleKeyNext': keys[1].key,
        'bleKeyNextAt': Timestamp.fromMillisecondsSinceEpoch(keys[1].fromMs),
      },
    };

Map<String, dynamic> _memberEntry(String nick, String fotoUrl, List<OwnBleKey> keys) => {
      'nick': nick.length > 40 ? nick.substring(0, 40) : nick,
      'fotoUrl': fotoUrl.length > 1000 ? '' : fotoUrl,
      ..._bleFields(keys),
      'joinedAt': FieldValue.serverTimestamp(),
    };

/// Whether [mine] already carries this install's current key schedule (and not the first APK's static id).
bool bleEntryUpToDate(FinderMember? mine, List<OwnBleKey> keys) {
  if (mine == null || mine.legacyBleId.isNotEmpty || mine.bleKey != keys.first.key) return false;
  if (keys.length == 1) return mine.bleKeyNext.isEmpty;
  return mine.bleKeyNext == keys[1].key && mine.bleKeyNextAt?.millisecondsSinceEpoch == keys[1].fromMs;
}

Stream<List<FinderGroup>> watchMyGroups(String uid) => _col
    .where('memberIds', arrayContains: uid)
    .snapshots()
    .map((s) => s.docs.map(FinderGroup.from).where((g) => !g.expired).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now())));

Stream<FinderGroup?> watchGroup(String code) =>
    _col.doc(code).snapshots().map((s) => s.exists ? FinderGroup.from(s) : null);

/// Returns the new invite code. A collision with an existing code is denied by the rules, so retry with a new one.
Future<String> createGroup({required String uid, required String name, required String nick, required String fotoUrl}) async {
  final keys = await ensureBleKeys();
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    final code = _random(_codeAlphabet, 6);
    try {
      await _col.doc(code).set({
        'name': name.trim().length > 40 ? name.trim().substring(0, 40) : name.trim(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(finderGroupLifetime)),
        'memberIds': [uid],
        'members': {uid: _memberEntry(nick, fotoUrl, keys)},
        'meetingPoint': null,
      });
      return code;
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError ?? StateError('createGroup');
}

enum JoinResult { joined, alreadyMember, invalid }

/// Blind join: the update succeeds only if the code exists, hasn't expired and has room (see firestore.rules).
Future<JoinResult> joinGroup({required String code, required String uid, required String nick, required String fotoUrl}) async {
  final ref = _col.doc(code);
  // Already a member → readable, and re-joining would be denied (the join branch requires not being in memberIds).
  try {
    final snap = await ref.get();
    if (snap.exists) {
      await refreshMyEntry(code, uid: uid, nick: nick, fotoUrl: fotoUrl);
      return JoinResult.alreadyMember;
    }
  } catch (_) {}
  try {
    await ref.update({
      'memberIds': FieldValue.arrayUnion([uid]),
      'members.$uid': _memberEntry(nick, fotoUrl, await ensureBleKeys()),
    });
    return JoinResult.joined;
  } catch (_) {
    return JoinResult.invalid;
  }
}

/// Writes this install's BLE key schedule (and the profile, when given) into my entry, dropping the first APK's static
/// id. True once the server has it; false on error or after [timeout] (offline: the write stays queued).
Future<bool> refreshMyEntry(String code,
    {required String uid,
    String? nick,
    String? fotoUrl,
    List<OwnBleKey>? keys,
    Duration timeout = const Duration(seconds: 15)}) async {
  final entry = _memberEntry(nick ?? '', fotoUrl ?? '', keys ?? await ensureBleKeys())..remove('joinedAt');
  if (nick == null) entry.remove('nick');
  if (fotoUrl == null) entry.remove('fotoUrl');
  try {
    await _col.doc(code).update({
      for (final e in entry.entries) 'members.$uid.${e.key}': e.value,
      if (!entry.containsKey('bleKeyNext')) 'members.$uid.bleKeyNext': FieldValue.delete(),
      if (!entry.containsKey('bleKeyNext')) 'members.$uid.bleKeyNextAt': FieldValue.delete(),
      'members.$uid.bleId': FieldValue.delete(),
    }).timeout(timeout);
    return true;
  } catch (_) {
    return false;
  }
}

/// Renews this install's BLE key when due and publishes the schedule to every group the user is in. The successor key
/// is marked published (so the phone may start advertising with it) only once all groups have it server-side.
/// Returns the schedule; safe to call often (overlapping calls share one run). Without [nick]/[fotoUrl] (background
/// renewal) only BLE fields are written.
Future<List<OwnBleKey>> syncMyBleKeys({required String uid, String? nick, String? fotoUrl}) =>
    _syncing ??= _syncMyBleKeys(uid, nick, fotoUrl).whenComplete(() => _syncing = null);

Future<List<OwnBleKey>>? _syncing;

Future<List<OwnBleKey>> _syncMyBleKeys(String uid, String? nick, String? fotoUrl) async {
  final keys = await ensureBleKeys();
  List<FinderGroup> groups;
  try {
    final snap = await _col.where('memberIds', arrayContains: uid).get().timeout(const Duration(seconds: 15));
    if (snap.metadata.isFromCache) return keys;
    groups = snap.docs.map(FinderGroup.from).where((g) => !g.expired).toList();
  } catch (_) {
    return keys;
  }
  var allHaveIt = true;
  for (final g in groups) {
    if (g.confirmed && bleEntryUpToDate(g.members[uid], keys)) continue;
    if (!await refreshMyEntry(g.code, uid: uid, nick: nick, fotoUrl: fotoUrl, keys: keys)) allHaveIt = false;
  }
  if (keys.length > 1 && !keys[1].published && allHaveIt) {
    await markBleKeyPublished(keys[1].key);
    return ensureBleKeys();
  }
  return keys;
}

Future<void> leaveGroup(String code, String uid) => _col.doc(code).update({
      'memberIds': FieldValue.arrayRemove([uid]),
      'members.$uid': FieldValue.delete(),
    });

Future<void> deleteGroup(String code) => _col.doc(code).delete();

Future<void> setMeetingPoint(String code, String uid, {String? label, double? lat, double? lng}) =>
    _col.doc(code).update({
      'meetingPoint': label == null
          ? null
          : {
              'label': label.length > 60 ? label.substring(0, 60) : label,
              'lat': ?lat,
              'lng': ?lng,
              'setBy': uid,
              'setAt': FieldValue.serverTimestamp(),
            },
    });
