import 'dart:convert';
import 'dart:io';

import 'package:blow_nights/providers/platform_settings.dart';
import 'package:blow_nights/services/play_billing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every .dart file under lib/.
String _appCode() => [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        f.readAsStringSync(),
    ].join('\n');

void main() {
  test('Premium is not sold in the app until super-admin turns moduleAppPremium on', () {
    expect(PlatformSettings.defaults['moduleAppPremium'], false);
  });

  test('the account id sent to Google is the one the server checks (lib/playBilling.accountIdFor)', () {
    // node -e "console.log(require('crypto').createHash('sha256').update('blownights:uid_123').digest('hex'))"
    expect(playAccountId('uid_123'), '4091a662757039a971a38d3e3e87f6c07ab05f36dcec629800ce5c1469cca71f');
  });

  test('the app sells the products the server knows (functions/lib/playBilling.js) and Play Console must have', () {
    expect(PlayBilling.subscriptionIds, {'plus', 'black'});
    expect(PlayBilling.oneTimeIds, {'black_pass_8h', 'ping_pack_3', 'vip_night'});
  });

  test("users' digital purchases never go through Stripe in the app, and venue plans are never bought or managed in it", () {
    final code = _appCode();
    for (final fn in [
      'createUserMembershipCheckout',
      'createBlack8hCheckout',
      'createPingCheckoutSession',
      'createVenueSubscriptionCheckout',
      'createStripePortalSession',
    ]) {
      expect(code.contains("'$fn'"), isFalse, reason: fn);
    }
  });

  test('every locale has the purchase messages, and no venue plan price', () {
    final files = Directory('assets/i18n').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    expect(files.length, 12);
    for (final f in files) {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final premium = json['premium'] as Map<String, dynamic>;
      expect((premium['unavailable_app'] as String?)?.isNotEmpty, isTrue, reason: f.path);
      final swipe = json['swipe'] as Map<String, dynamic>;
      // With the module off: the ping limit without paid packs.
      expect((swipe['limit_desc_free'] as String?)?.isNotEmpty, isTrue, reason: f.path);
      // The pack is 3 pings, as both Stripe and Google Play grant.
      expect(swipe['pack_extra'], contains('3'), reason: f.path);
      for (final k in ['play_done', 'play_pending', 'play_unavailable', 'play_other_account', 'play_error', 'manage_elsewhere']) {
        expect((json['premium.$k'] as String?)?.isNotEmpty, isTrue, reason: '${f.path} premium.$k');
      }
      for (final k in ['venue_admin_plan_ticketing_desc', 'venue_admin_plan_ticketing_tickets_desc', 'venue_admin_plan_promo_desc']) {
        final text = json[k] as String?;
        expect(text?.isNotEmpty, isTrue, reason: '${f.path} $k');
        expect(RegExp(r'\d|€').hasMatch(text!), isFalse, reason: '${f.path} $k: $text');
      }
      final priced = json.keys.where((k) => k.startsWith('venue_admin_tier_') || k == 'venue_admin_per_month').toList();
      expect(priced, isEmpty, reason: f.path);
    }
  });
}
