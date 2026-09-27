import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rotating BLE identity for the friend finder.
///
/// Each install holds a secret key, shared only with the members of its groups (member entry `bleKey`). What goes over
/// the air is `HMAC-SHA256(key, "bn-finder-v1:<period>")` cut to 8 chars, so a passive scanner sees an unrelated id
/// every 15 minutes (UTC epoch-aligned), while friends compute the expected ids from the key and recognise the phone.
///
/// The key itself is renewed every [bleKeyLifetime], so someone who leaves a group (and stops receiving the group
/// document) can only recognise the phone until the keys they already hold stop being used. The next key is published
/// [bleKeyLead] before it takes over (`bleKeyNext` / `bleKeyNextAt`), because friends' phones may be offline at the
/// festival when the switch happens; a key that couldn't be published in time pushes the switch back instead.
///
/// Ids must stay identical to android/.../finder/BleIdRotation.kt; FinderBle.keyFor picks the key in force for each
/// period from [advertisingSchedule].
const bleRotationPeriod = Duration(minutes: 15);
const bleKeyLifetime = Duration(hours: 24);
const bleKeyLead = Duration(hours: 12);

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const _prefsSchedule = 'finder_ble_keys';
const _prefsLegacyKey = 'finder_ble_key';

/// One key and the first instant (a period boundary, ms since epoch) it is used from.
typedef BleKeyUse = ({String key, int fromMs});

int get _periodMs => bleRotationPeriod.inMilliseconds;

int blePeriod(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ _periodMs;

int _floorToPeriod(int ms) => ms ~/ _periodMs * _periodMs;
int _ceilToPeriod(int ms) => (ms + _periodMs - 1) ~/ _periodMs * _periodMs;

String bleIdFor(String key, int period) {
  final mac = Hmac(sha256, utf8.encode(key)).convert(utf8.encode('bn-finder-v1:$period')).bytes;
  return String.fromCharCodes([for (final b in mac.take(8)) _alphabet.codeUnitAt(b % _alphabet.length)]);
}

final _cache = <String, Set<String>>{};

/// Ids a friend holding [keys] may be advertising now: ±2 periods (±30 min) absorbs clock skew between phones and a
/// rotation that runs late while the phone sleeps. Every known key is accepted for every period, so recognition never
/// depends on the exact moment the friend's phone switches keys (it postpones the switch while offline).
Set<String> bleIdsAround(Iterable<String> keys, [DateTime? now]) {
  final p = blePeriod(now ?? DateTime.now());
  final cacheKey = '${keys.join(',')}:$p';
  final hit = _cache[cacheKey];
  if (hit != null) return hit;
  if (_cache.length > 200) _cache.clear();
  return _cache[cacheKey] = {
    for (final k in keys)
      for (var d = -2; d <= 2; d++) bleIdFor(k, p + d),
  };
}

bool isValidBleKey(String key) => RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(key);

String _newKey() {
  final r = math.Random.secure();
  return base64Url.encode(List.generate(16, (_) => r.nextInt(256))).replaceAll('=', '');
}

/// A key in this install's schedule. [published] is set once every group the user is in has the key server-side;
/// only then may the phone start advertising with it.
class OwnBleKey {
  final String key;
  final int fromMs;
  final bool published;
  const OwnBleKey(this.key, this.fromMs, {this.published = false});

  Map<String, Object> toJson() => {'k': key, 'from': fromMs, 'pub': published};
  static OwnBleKey? fromJson(Object? j) {
    if (j is! Map || j['k'] is! String || j['from'] is! int || !isValidBleKey(j['k'] as String)) return null;
    return OwnBleKey(j['k'] as String, j['from'] as int, published: j['pub'] == true);
  }
}

Future<List<OwnBleKey>> _load(SharedPreferences prefs) async {
  try {
    // Each isolate caches prefs; the headless renewal engine (finder_background.dart) may have written since.
    await prefs.reload();
    final raw = prefs.getString(_prefsSchedule);
    if (raw != null) {
      final keys = (jsonDecode(raw) as List).map(OwnBleKey.fromJson).whereType<OwnBleKey>().toList()
        ..sort((a, b) => a.fromMs.compareTo(b.fromMs));
      if (keys.isNotEmpty) return keys;
    }
  } catch (_) {}
  // Installs from before renewal had a single key: keep using it (friends already know it) and renew from there.
  final legacy = prefs.getString(_prefsLegacyKey);
  if (legacy != null && isValidBleKey(legacy)) return [OwnBleKey(legacy, 0, published: true)];
  return [];
}

Future<void> _save(SharedPreferences prefs, List<OwnBleKey> keys) =>
    prefs.setString(_prefsSchedule, jsonEncode([for (final k in keys) k.toJson()]));

/// Schedule reads-modify-writes run one at a time: the screens and the radar service's renewal request may overlap,
/// and two concurrent renewals would each announce a different successor.
Future<void> _queue = Future.value();

Future<T> _serialized<T>(Future<T> Function() task) {
  final run = _queue.then((_) => task());
  _queue = run.then((_) {}, onError: (_) {});
  return run;
}

/// This install's key schedule — the key in force first, then at most one announced successor — after renewing it if
/// due. [now] is only for tests.
Future<List<OwnBleKey>> ensureBleKeys([DateTime? now]) => _serialized(() => _ensureBleKeys(now));

Future<List<OwnBleKey>> _ensureBleKeys(DateTime? now) async {
  final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final prefs = await SharedPreferences.getInstance();
  var keys = await _load(prefs);
  if (keys.isEmpty) keys = [OwnBleKey(_newKey(), _floorToPeriod(t), published: true)];

  // Drop keys superseded by one already in force. The successor only takes over once published (see below).
  final active = keys.lastIndexWhere((k) => k.fromMs <= t && k.published);
  if (active > 0) keys = keys.sublist(active);

  final current = keys.first;
  if (keys.length == 1) {
    if (t >= current.fromMs + bleKeyLifetime.inMilliseconds - bleKeyLead.inMilliseconds) {
      keys = [current, OwnBleKey(_newKey(), _ceilToPeriod(t + bleKeyLead.inMilliseconds))];
    }
  } else if (!keys[1].published && keys[1].fromMs < t + bleKeyLead.inMilliseconds) {
    // Not published yet (offline): push the switch back so friends still get the full lead time to sync it.
    keys = [current, OwnBleKey(keys[1].key, _ceilToPeriod(t + bleKeyLead.inMilliseconds))];
  }
  await _save(prefs, keys);
  return keys;
}

/// Called once every group has [key] server-side.
Future<void> markBleKeyPublished(String key) => _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final keys = await _load(prefs);
      await _save(prefs, [for (final k in keys) k.key == key ? OwnBleKey(k.key, k.fromMs, published: true) : k]);
    });

/// What this phone advertises from: the current key, plus the successor once it's published.
List<BleKeyUse> advertisingSchedule(List<OwnBleKey> keys) =>
    [for (final k in keys) if (k.published || identical(k, keys.first)) (key: k.key, fromMs: k.fromMs)];
