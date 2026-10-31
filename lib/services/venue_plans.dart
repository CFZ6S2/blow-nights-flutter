/// Venue SaaS plans, as frontend/src/lib/venuePlans.ts: €/month at list price (venue_admin_tier_*_price). The launch
/// promo halves them for the first 3 months; a venue doc doesn't say whether it's still in promo, so MRR is at list
/// price. Ticketing has no list price: each venue pays the one agreed with it (ticketingPriceCents, set by the
/// superadmin on the web).
const venuePlanPriceEur = {'basico': 50, 'promo': 100};

/// Ticketing subscriptions from before the agreed prices were paid at 180 €.
const _oldTicketingPriceEur = 180;

/// A venue's contribution to MRR, in whole euros: only a paid subscription that is currently active (not a test one)
/// to a known plan.
int venueMrr(Map<String, dynamic> venue) {
  if (venue['subscriptionStatus'] != 'active' || venue['isTestSubscription'] == true) return 0;
  if (venue['subscriptionTier'] == 'ticketing') {
    final cents = venue['ticketingPriceCents'];
    return cents is int ? (cents / 100).round() : _oldTicketingPriceEur;
  }
  return venuePlanPriceEur[venue['subscriptionTier']] ?? 0;
}
