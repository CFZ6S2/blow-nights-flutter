import '../models/firestore_utils.dart';

/// The free month of the Ticketing plan a venue that joins on its own gets, as frontend/src/lib/venueTrial.ts
/// (functions/lib/venueTrial.js; one a commercial brings pays from the start), then 50% off the first 3 paid months and
/// the full price. A venue may subscribe during the trial (on the web: plans aren't sold in the app).
///   free        in the trial, not subscribed
///   subscribed  subscribed during the trial, which hasn't ended yet
///   ended       the trial is over but expireVenueTrials (daily) hasn't taken the plan away yet
enum VenueTrialState { free, subscribed, ended }

class VenueTrial {
  const VenueTrial(this.state, this.endsAt);
  final VenueTrialState state;
  final DateTime endsAt;
}

// Like the web's truthiness checks: an empty string counts as missing.
bool _present(Object? v) => v is String ? v.isNotEmpty : v != null;

VenueTrial? venueTrial(Map<String, dynamic>? venue, [DateTime? now]) {
  if (venue == null || !_present(venue['trialSource'])) return null;
  final end = parseDate(venue['trialEndsAt']);
  if (end == null) return null;
  final t = now ?? DateTime.now();
  final status = venue['subscriptionStatus'];
  final subscribed = _present(venue['stripeSubscriptionId']);
  if (status == 'trialing' && !subscribed) {
    return VenueTrial(end.isAfter(t) ? VenueTrialState.free : VenueTrialState.ended, end);
  }
  if (status == 'active' && subscribed && end.isAfter(t)) return VenueTrial(VenueTrialState.subscribed, end);
  return null;
}
