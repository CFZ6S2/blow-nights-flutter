import 'package:blow_nights/services/venue_plans.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an active paid subscription counts at the plan list price', () {
    expect(venueMrr({'subscriptionTier': 'basico', 'subscriptionStatus': 'active'}), 50);
    expect(venueMrr({'subscriptionTier': 'promo', 'subscriptionStatus': 'active'}), 100);
    expect(venueMrr({'subscriptionTier': 'ticketing', 'subscriptionStatus': 'active'}), 180);
  });

  test('no plan, cancelled, past due or test subscriptions count nothing', () {
    expect(venueMrr({}), 0);
    expect(venueMrr({'subscriptionTier': 'ticketing', 'subscriptionStatus': 'canceled'}), 0);
    expect(venueMrr({'subscriptionTier': 'promo', 'subscriptionStatus': 'past_due'}), 0);
    expect(venueMrr({'subscriptionTier': 'ticketing', 'subscriptionStatus': 'active', 'isTestSubscription': true}), 0);
  });

  test('the platform keeps 45% where a partner has a Stripe account', () {
    expect(platformShareWithPartner, 0.45);
  });
}
