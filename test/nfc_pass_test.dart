import 'dart:convert';

import 'package:blow_nights/i18n/i18n.dart';
import 'package:blow_nights/services/nfc_pass.dart';
import 'package:blow_nights/widgets/dynamic_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('blownights/nfc_pass');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  // What the card emulation (PassHceService.payload) was last told to answer.
  String? native;
  var pushes = 0;

  setUp(() {
    NfcPass.debugAvailable = true;
    native = 'unset';
    pushes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setPayload') {
        native = (call.arguments as Map)['payload'] as String?;
        pushes++;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    NfcPass.debugAvailable = null;
  });

  group('scanner side', () {
    test('SELECT by name of the BNPASS AID', () {
      expect(NfcPass.selectApdu, [0x00, 0xA4, 0x04, 0x00, 7, 0xF0, 0x42, 0x4E, 0x50, 0x41, 0x53, 0x53, 0x00]);
      expect(ascii.decode(NfcPass.aid.sublist(1)), 'BNPASS');
    });

    test('a phone showing a code answers it followed by 90 00', () {
      const code = 'ent:v2:abc123:1700000000000:nonce:sig';
      expect(NfcPass.codeFromSelectResponse(Uint8List.fromList([...utf8.encode(code), 0x90, 0x00])), code);
    });

    test('"not found", a bare 90 00 or garbage give no code', () {
      expect(NfcPass.codeFromSelectResponse(Uint8List.fromList([0x6A, 0x82])), isNull);
      expect(NfcPass.codeFromSelectResponse(Uint8List.fromList([0x90, 0x00])), isNull);
      expect(NfcPass.codeFromSelectResponse(Uint8List.fromList([0x41, 0x6A, 0x82])), isNull);
      expect(NfcPass.codeFromSelectResponse(Uint8List(0)), isNull);
    });

    test('phones present a random 4-byte UID; tags keep their serial', () {
      expect(NfcPass.isRandomUid([0x08, 0x1a, 0x2b, 0x3c]), isTrue);
      expect(NfcPass.isRandomUid([0x04, 0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6]), isFalse);
      expect(NfcPass.serialHex([0x04, 0xa1, 0x0b]), '04a10b');
    });
  });

  group('customer side', () {
    test('answers with the code of the screen showing it, and stops when that screen goes', () {
      final wallet = Object();
      final sheet = Object();
      NfcPass.show(wallet, 'dyn:t1:1:sig');
      expect(native, 'dyn:t1:1:sig');
      NfcPass.show(sheet, 'ent:v2:e1:1:n:sig');
      expect(native, 'ent:v2:e1:1:n:sig');
      NfcPass.hide(wallet); // not the owner any more: the drink stays armed
      expect(native, 'ent:v2:e1:1:n:sig');
      NfcPass.hide(sheet);
      expect(native, isNull);
    });

    test('nothing is handed over while the app is in the background', () {
      final screen = Object();
      NfcPass.show(screen, 'dyn:t2:1:sig');
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(native, isNull);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(native, 'dyn:t2:1:sig');
      NfcPass.hide(screen);
    });

    test('an empty code arms nothing', () {
      final screen = Object();
      NfcPass.show(screen, '');
      expect(native, isNull);
      NfcPass.hide(screen);
    });

    test('the scanner reading the code reaches the screen', () async {
      final screen = Object();
      var reads = 0;
      NfcPass.show(screen, 'dyn:t3:1:sig', onRead: () => reads++);
      await messenger.handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(const MethodCall('handedOver')), (_) {});
      expect(reads, 1);
      NfcPass.hide(screen);
    });

    test('off Android nothing is sent to the platform', () {
      NfcPass.debugAvailable = false;
      NfcPass.show(Object(), 'dyn:t4:1:sig');
      expect(pushes, 0);
    });

    testWidgets('the entry ticket QR hands over the code it draws, and stops when it closes', (tester) async {
      await tester.pumpWidget(ChangeNotifierProvider<I18n>(
        create: (_) => I18n(),
        child: const MaterialApp(home: Scaffold(body: DynamicQR(ticketId: 't5', secretKey: 'secret'))),
      ));
      expect(find.byType(QrImageView), findsOneWidget);
      // The code handed over is this ticket's signed dynamic code, the one the QR draws (dynamicQrValue).
      final parts = native!.split(':');
      expect(parts.sublist(0, 2), ['dyn', 't5']);
      expect(native, dynamicQrValue('t5', 'secret', DateTime.fromMillisecondsSinceEpoch(int.parse(parts[2]))));
      expect(find.byType(NfcPassHint), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(native, isNull);
    });
  });
}
