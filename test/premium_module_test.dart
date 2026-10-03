import 'dart:convert';
import 'dart:io';

import 'package:blow_nights/providers/platform_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Premium is not sold in the app until super-admin turns moduleAppPremium on', () {
    expect(PlatformSettings.defaults['moduleAppPremium'], false);
  });

  test('every locale explains that Premium is not available in the app', () {
    final files = Directory('assets/i18n').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    expect(files.length, 12);
    for (final f in files) {
      final premium = (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['premium'] as Map<String, dynamic>;
      expect(premium['unavailable_app'], isA<String>(), reason: f.path);
      expect((premium['unavailable_app'] as String).isNotEmpty, isTrue, reason: f.path);
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      // With the module off: the ping limit without paid packs, and venue plans not bought in the app.
      expect(((json['swipe'] as Map<String, dynamic>)['limit_desc_free'] as String?)?.isNotEmpty, isTrue, reason: f.path);
      expect((json['venue_admin_plans_unavailable_app'] as String?)?.isNotEmpty, isTrue, reason: f.path);
    }
  });
}
