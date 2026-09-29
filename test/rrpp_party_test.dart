import 'package:blow_nights/models/rrpp_party.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Same cases as the web (frontend/src/__tests__/rrppParty.test.ts).
void main() {
  final now = DateTime.utc(2026, 10, 10, 12);
  Timestamp ts(String iso) => Timestamp.fromDate(DateTime.parse(iso));

  test('other venues are always shown', () {
    expect(rrppPartyVisible({'isActive': true}, now), isTrue);
    expect(rrppPartyVisible(null, now), isTrue);
    expect(isRRPPParty({'isActive': true}), isFalse);
  });

  test('a party shows until visibleUntil, and not once archived or inactive', () {
    expect(rrppPartyVisible({'rrppParty': true, 'visibleUntil': ts('2026-10-11T00:00:00Z')}, now), isTrue);
    expect(rrppPartyVisible({'rrppParty': true, 'visibleUntil': ts('2026-10-10T00:00:00Z')}, now), isFalse);
    expect(rrppPartyVisible({'rrppParty': true, 'visibleUntil': {'seconds': DateTime.parse('2026-10-12T00:00:00Z').millisecondsSinceEpoch ~/ 1000}}, now), isTrue);
    expect(rrppPartyVisible({'rrppParty': true, 'archived': true, 'visibleUntil': ts('2026-10-11T00:00:00Z')}, now), isFalse);
    expect(rrppPartyVisible({'rrppParty': true, 'isActive': false, 'visibleUntil': ts('2026-10-11T00:00:00Z')}, now), isFalse);
    expect(rrppPartyVisible({'rrppParty': true}, now), isFalse);
  });
}
