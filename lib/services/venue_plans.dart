/// Venue SaaS plans, as frontend/src/lib/venuePlans.ts: €/month at list price (venue_admin_tier_*_price). The launch
/// promo halves them for the first 3 months; a venue doc doesn't say whether it's still in promo, so MRR is at list
/// price.
const venuePlanPriceEur = {'basico': 50, 'promo': 100, 'ticketing': 180};

/// What the platform keeps of a venue payment in a city whose partner has a Stripe account: territorialSplit in
/// functions/modules/stripe.js transfers 55% to the partner. Without one, the platform keeps 100%.
const platformShareWithPartner = 0.45;

/// A venue's contribution to MRR: only a paid subscription that is currently active (not a test one) to a known plan.
int venueMrr(Map<String, dynamic> venue) {
  if (venue['subscriptionStatus'] != 'active' || venue['isTestSubscription'] == true) return 0;
  return venuePlanPriceEur[venue['subscriptionTier']] ?? 0;
}
