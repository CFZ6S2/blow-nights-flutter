import 'package:blow_nights/services/venue_plans.dart';
import 'package:blow_nights/services/venue_trial.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// The same cases as the web's frontend/src/__tests__/venueTrial.test.ts.
void main() {
  final now = DateTime.utc(2026, 10, 19, 10);
  const day = Duration(days: 1);
  Map<String, dynamic> trialing(Duration endsIn, [Map<String, dynamic> extra = const {}]) => {
        'subscriptionTier': 'ticketing',
        'subscriptionStatus': 'trialing',
        'trialSource': 'signup',
        'trialEndsAt': Timestamp.fromDate(now.add(endsIn)),
        ...extra,
      };

  test('in the free trial: free, with the end date', () {
    final t = venueTrial(trialing(day * 40), now)!;
    expect(t.state, VenueTrialState.free);
    expect(t.endsAt.isAtSameMomentAs(now.add(day * 40)), isTrue);
    expect(venueTrial(trialing(day * 40, {'trialSource': 'claim'}), now)?.state, VenueTrialState.free);
  });

  test('subscribed during the trial: still shows until when it is free', () {
    final v = trialing(day * 40, {'subscriptionStatus': 'active', 'stripeSubscriptionId': 'sub_1'});
    expect(venueTrial(v, now)?.state, VenueTrialState.subscribed);
  });

  test('ended but not yet taken away by the daily job', () {
    expect(venueTrial(trialing(const Duration(seconds: -1)), now)?.state, VenueTrialState.ended);
  });

  test('no trial of ours: nothing', () {
    expect(venueTrial(null, now), isNull);
    expect(venueTrial({'subscriptionTier': 'promo', 'subscriptionStatus': 'active', 'stripeSubscriptionId': 'sub_1'}, now), isNull);
    expect(venueTrial(trialing(const Duration(seconds: -1), {'subscriptionStatus': 'trial_ended', 'subscriptionTier': null}), now), isNull);
    expect(venueTrial(trialing(const Duration(seconds: -1), {'subscriptionStatus': 'active', 'stripeSubscriptionId': 'sub_1'}), now), isNull);
    expect(venueTrial(trialing(day * 40, {'trialSource': null}), now), isNull); // a Stripe trial, not ours
    expect(venueTrial(trialing(day * 40, {'stripeSubscriptionId': ''}), now)?.state, VenueTrialState.free); // empty = none
  });

  test("a venue in its free month brings nothing into the City Manager's gross (venueMrr)", () {
    expect(venueMrr(trialing(day * 40)), 0);
  });
}
