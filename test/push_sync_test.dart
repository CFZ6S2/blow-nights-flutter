import 'package:blow_nights/services/push_sync.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushSync position for promos', () {
    test('rounds to 2 decimals (about 1 km)', () {
      expect(PushSync.round2(40.43217), 40.43);
      expect(PushSync.round2(-3.70951), -3.71);
      expect(PushSync.round2(2.1749), 2.17);
    });

    test('writes when there is nothing saved, another account, a new spot, or 6 h later', () {
      const now = 1_000_000_000_000;
      const sixHours = 6 * 3600 * 1000;
      expect(PushSync.shouldWrite(null, 'u1', 40.43, -3.71, now), isTrue);
      expect(PushSync.shouldWrite('u2,40.43,-3.71,$now', 'u1', 40.43, -3.71, now), isTrue);
      expect(PushSync.shouldWrite('u1,40.44,-3.71,$now', 'u1', 40.43, -3.71, now), isTrue);
      expect(PushSync.shouldWrite('u1,40.43,-3.71,${now - sixHours}', 'u1', 40.43, -3.71, now), isTrue);
      expect(PushSync.shouldWrite('u1,40.43,-3.71,${now - sixHours + 1}', 'u1', 40.43, -3.71, now), isFalse);
      expect(PushSync.shouldWrite('garbage', 'u1', 40.43, -3.71, now), isTrue);
    });

    test('notifications count as allowed when authorized or provisional', () {
      expect(PushSync.allowed(AuthorizationStatus.authorized), isTrue);
      expect(PushSync.allowed(AuthorizationStatus.provisional), isTrue);
      expect(PushSync.allowed(AuthorizationStatus.denied), isFalse);
      expect(PushSync.allowed(AuthorizationStatus.notDetermined), isFalse);
    });
  });
}
