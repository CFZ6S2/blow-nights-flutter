import 'dart:convert';
import 'dart:io';

import 'package:blow_nights/widgets/dynamic_qr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every .dart file under lib/.
String _appCode() => [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        f.readAsStringSync(),
    ].join('\n');

void main() {
  test('the app draws the same dynamic QR the door checks (functions/lib/validateQR.js)', () {
    // node -e "require('crypto').createHmac('sha256','ticket-secret-key').update('t1:1760000000000').digest('hex')"
    expect(dynamicQrValue('t1', 'ticket-secret-key', DateTime.fromMillisecondsSinceEpoch(1760000000000)),
        'dyn:t1:1760000000000:60f1263918e9c9f8c46e034aead1a6e96684700b90b753fd07a16ff90d2953f6');
  });

  test('only the dynamic QR (2026-10-13): no static fallback, no PIN, no simulated menu in the code', () {
    final code = _appCode();
    expect(code.contains('fallbackToken'), isFalse, reason: 'DynamicQR never shows a static code');
    expect(code.contains("'pinCode'"), isFalse, reason: 'no PIN is shown or sent');
    expect(code.contains('VenueMenuScreen'), isFalse, reason: 'the simulated menu is gone');
    expect(code.contains("'dyn:\$_id:"), isFalse, reason: 'no unsigned drink QR is made up');
    expect(RegExp(r"'manual'").hasMatch(code), isFalse, reason: 'no manual (typed) scanner mode');
  });

  test('no locale speaks of a PIN or of printing the ticket', () {
    final files = Directory('assets/i18n').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    expect(files.length, 12);
    for (final f in files) {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect((json['dynamic_qr_unavailable'] as String?)?.isNotEmpty, isTrue, reason: f.path);
      expect((json['door_camera_needed_app'] as String?)?.isNotEmpty, isTrue, reason: f.path);
      expect(json.keys.where((k) => k.startsWith('door_manual_pin') || k.startsWith('venue_menu_')), isEmpty, reason: f.path);
      expect((json['wallet'] as Map<String, dynamic>).containsKey('download_pdf'), isFalse, reason: f.path);
      expect((json['pass'] as Map<String, dynamic>).containsKey('door_pin'), isFalse, reason: f.path);
    }
  });
}
