import 'package:blow_nights/services/ble_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vectors produced with javax.crypto exactly as BleIdRotation.kt does (and checked with Python's hmac):
// the phone advertising and the friends recognising it must derive the same ids.
void main() {
  const key = 'q3Jb9xZ0Lw7mT2vK5sHc1A';

  group('rotating ids', () {
    test('ids match the Android implementation', () {
      expect(bleIdFor(key, 1989455), '7AEDZU1W');
      expect(bleIdFor(key, 1989456), 'T1TNW0Z4');
      expect(bleIdFor(key, 0), 'UDVS8TW4');
    });

    test('period rolls over every 15 minutes, UTC-aligned', () {
      expect(blePeriod(DateTime.utc(2026, 9, 27, 11, 59, 59)), 1989455);
      expect(blePeriod(DateTime.utc(2026, 9, 27, 12)), 1989456);
      expect(blePeriod(DateTime.utc(2026, 9, 27, 12, 14, 59)), 1989456);
      expect(blePeriod(DateTime.utc(2026, 9, 27, 12, 15)), 1989457);
      expect(blePeriod(DateTime.utc(2026, 9, 27, 12, 5).toLocal()), 1989456);
    });

    test('friends accept ±2 periods (±30 min)', () {
      final ids = bleIdsAround([key], DateTime.utc(2026, 9, 27, 12, 5));
      expect(ids, {'V6HR568T', '7AEDZU1W', 'T1TNW0Z4', 'WEINUPAY', 'IT1J4E35'});
    });

    test('with a renewed key announced, ids of both keys are accepted', () {
      const next = 'Zx9Ab8Cd7Ef6Gh5Ij4Kl3M';
      final t = DateTime.utc(2026, 9, 27, 12, 5);
      final ids = bleIdsAround([key, next], t);
      expect(ids.length, 10);
      expect(ids.containsAll(bleIdsAround([key], t)), isTrue);
      expect(ids.containsAll(bleIdsAround([next], t)), isTrue);
    });

    test('ids are 8 chars from the advertised alphabet and differ per key', () {
      final id = bleIdFor(key, 1989456);
      expect(RegExp(r'^[A-Z0-9]{8}$').hasMatch(id), isTrue);
      expect(bleIdFor('another-key-0123456789', 1989456), isNot(id));
    });

    test('key format', () {
      expect(isValidBleKey(key), isTrue);
      expect(isValidBleKey('short'), isFalse);
      expect(isValidBleKey('q3Jb9xZ0Lw7mT2vK5sHc1A=='), isFalse);
    });
  });

  group('key renewal', () {
    final t0 = DateTime.utc(2026, 9, 27, 12, 7);
    int ms(DateTime t) => t.millisecondsSinceEpoch;
    DateTime at(Duration d) => t0.add(d);

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('first key is created in force from the current period, nothing announced', () async {
      final keys = await ensureBleKeys(t0);
      expect(keys, hasLength(1));
      expect(keys.first.published, isTrue);
      expect(keys.first.fromMs, ms(DateTime.utc(2026, 9, 27, 12)));
      expect(isValidBleKey(keys.first.key), isTrue);
      expect(advertisingSchedule(keys), [(key: keys.first.key, fromMs: keys.first.fromMs)]);
    });

    test('successor is announced 12 h before the key turns 24 h old, and not advertised until published', () async {
      final first = (await ensureBleKeys(t0)).first;
      expect(await ensureBleKeys(at(const Duration(hours: 11))), hasLength(1));

      final keys = await ensureBleKeys(at(const Duration(hours: 12)));
      expect(keys, hasLength(2));
      expect(keys.first.key, first.key);
      expect(keys[1].published, isFalse);
      // Switch time = 12 h after the announcement, rounded up to a period boundary.
      expect(keys[1].fromMs, ms(DateTime.utc(2026, 9, 28, 12, 15)));
      expect(keys[1].fromMs % bleRotationPeriod.inMilliseconds, 0);
      expect(advertisingSchedule(keys).map((k) => k.key), [first.key]);

      // Calling again doesn't announce another one.
      expect((await ensureBleKeys(at(const Duration(hours: 13))))[1].key, keys[1].key);
    });

    test('once published the successor is advertised from its switch time and then replaces the old key', () async {
      final first = (await ensureBleKeys(t0)).first;
      final announced = (await ensureBleKeys(at(const Duration(hours: 12))))[1];
      await markBleKeyPublished(announced.key);

      final before = await ensureBleKeys(at(const Duration(hours: 13)));
      expect(advertisingSchedule(before), [
        (key: first.key, fromMs: first.fromMs),
        (key: announced.key, fromMs: announced.fromMs),
      ]);

      final after = await ensureBleKeys(DateTime.fromMillisecondsSinceEpoch(announced.fromMs, isUtc: true));
      expect(after, hasLength(1));
      expect(after.first.key, announced.key);
      expect(after.first.published, isTrue);
    });

    test('a successor never published (offline) postpones the switch instead of going dark', () async {
      final first = (await ensureBleKeys(t0)).first;
      final announced = (await ensureBleKeys(at(const Duration(hours: 12))))[1];

      final late = DateTime.fromMillisecondsSinceEpoch(announced.fromMs + 3600000, isUtc: true);
      final keys = await ensureBleKeys(late);
      expect(keys.first.key, first.key, reason: 'old key stays in force');
      expect(keys[1].key, announced.key, reason: 'same successor, still to be published');
      expect(keys[1].fromMs, greaterThanOrEqualTo(ms(late) + bleKeyLead.inMilliseconds));
      expect(advertisingSchedule(keys).map((k) => k.key), [first.key]);
    });

    test('overlapping renewals (screen + radar service) announce a single successor', () async {
      await ensureBleKeys(t0);
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) ensureBleKeys(at(const Duration(hours: 12))),
      ]);
      expect(results.map((r) => r[1].key).toSet(), hasLength(1));
    });

    test('an install from before renewal keeps its key and starts renewing', () async {
      SharedPreferences.setMockInitialValues({'finder_ble_key': key});
      final keys = await ensureBleKeys(t0);
      expect(keys.first.key, key);
      expect(keys.first.published, isTrue);
      expect(keys, hasLength(2), reason: 'the old key is overdue, so a successor is announced right away');
    });

    test('a corrupt schedule starts over with a fresh key', () async {
      SharedPreferences.setMockInitialValues({'finder_ble_keys': '{not json'});
      final keys = await ensureBleKeys(t0);
      expect(keys, hasLength(1));
      expect(isValidBleKey(keys.first.key), isTrue);
    });
  });
}
