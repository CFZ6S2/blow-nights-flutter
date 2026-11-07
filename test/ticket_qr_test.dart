import 'dart:io';

import 'package:blow_nights/services/ticket_qr.dart';
import 'package:flutter_test/flutter_test.dart';

/// TCS Gate tickets in the app (same as frontend/src/lib/ticketQr.ts): their QR is drawn with TCS's id and key, so
/// TCS's door accepts it; resale and buyback aren't offered for them.
void main() {
  test('a Blow Nights ticket uses its own id and secretKey', () {
    final qr = ticketQrSource({'id': 't1'}, {'secretKey': 'k1', 'gateSecretKey': 'g1'});
    expect(qr.id, 't1');
    expect(qr.secretKey, 'k1');
  });

  test("a TCS Gate ticket uses TCS's id and gateSecretKey", () {
    final qr = ticketQrSource({'id': 'tcs_cs_1', 'accessProvider': 'tcs_gate', 'gateTicketId': 'tk_9'}, {'gateSecretKey': 'g1', 'secretKey': 'k1'});
    expect(qr.id, 'tk_9');
    expect(qr.secretKey, 'g1');
  });

  test("a TCS Gate ticket without TCS's id draws no QR", () {
    final qr = ticketQrSource({'id': 'tcs_cs_1', 'accessProvider': 'tcs_gate'}, {'gateSecretKey': 'g1'});
    expect(qr.secretKey, isNull);
  });

  test('without secrets there is no key', () {
    expect(ticketQrSource({'id': 't1'}, null).secretKey, isNull);
    expect(ticketQrSource({'id': 't1', 'accessProvider': 'tcs_gate', 'gateTicketId': 'tk_9'}, null).secretKey, isNull);
  });

  test('wallet and pass draw the QR through ticketQrSource / qrTicketId, and hide resale and buyback for TCS tickets', () {
    final wallet = File('lib/screens/tickets/wallet_screen.dart').readAsStringSync();
    final pass = File('lib/screens/tickets/pass_screen.dart').readAsStringSync();
    expect(wallet, contains('ticketQrSource(t, _secrets)'));
    expect(wallet, isNot(contains("secretKey: _secrets!['secretKey']")));
    expect(wallet, contains('if (isTcsTicket(t))'));
    expect(wallet, contains('&& !isTcsTicket(t)'));
    expect(pass, contains('ticketQrSource(t,'));
    expect(pass, contains("t['qrTicketId']"));
  });
}
