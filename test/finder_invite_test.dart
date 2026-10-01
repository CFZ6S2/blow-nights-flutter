import 'dart:convert';

import 'package:blow_nights/services/finder_groups.dart';
import 'package:flutter_test/flutter_test.dart';

// What FinderNative.readInvites hands to the join sheet, which parses it with parseInviteCode.
void main() {
  test("the phone's answer (HCE) is the invite payload", () {
    expect(parseInviteCode('BNG1:KX7PQ4'), 'KX7PQ4');
  });

  test('a sticker read page by page (NDEF text record in Type 2 memory) still gives the code', () {
    // TLV 03 + short text record "en" + "BNG1:KX7PQ4", terminator FE, rest of the page zeroed.
    final record = [0xD1, 0x01, 0x0E, 0x54, 0x02, 0x65, 0x6E, ...ascii.encode('BNG1:kx7pq4')];
    final memory = [0x03, record.length, ...record, 0xFE, 0x00, 0x00];
    expect(parseInviteCode(latin1.decode(memory)), 'KX7PQ4');
  });

  test('a tag without an invite gives nothing', () {
    expect(parseInviteCode(latin1.decode([0x03, 0x00, 0xFE, 0x00])), isNull);
  });
}
