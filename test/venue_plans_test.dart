import 'package:blow_nights/services/settlement.dart';
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

  test('settlement months go back across years', () {
    expect(previousMonth('2026-09'), '2026-08');
    expect(previousMonth('2026-01'), '2025-12');
    expect(monthOf(DateTime(2026, 3, 5)), '2026-03');
  });

  test('what comes off before the 50/50 adds up', () {
    expect(settlementCostsCents({'stripeFeesCents': 450, 'ownExpensesCents': 2000, 'generalExpensesCents': 3000, 'previousLossCents': 100}), 5550);
    expect(settlementCostsCents({}), 0);
  });
}
