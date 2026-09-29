import 'firestore_utils.dart';

// An independent RRPP's party outside the venues of the app (createRRPPParty): an unclaimed venue flagged
// rrppParty, shown on the radar until visibleUntil and then archived by cleanupExpiredRRPPParties. It's not a venue:
// venue listings leave it out, and tapping it shows its details, never a ticket purchase. It's stored with
// isActive false so that clients listing isActive venues (the DarkNights site's build, older apps) never show it;
// the radar loads parties with their own query. (web: lib/rrppParty.ts)
bool isRRPPParty(Map<String, dynamic>? v) => v?['rrppParty'] == true;

/// Venues other than RRPP parties are always shown; a party only until it expires.
bool rrppPartyVisible(Map<String, dynamic>? v, [DateTime? now]) {
  if (!isRRPPParty(v)) return true;
  if (v!['archived'] == true) return false;
  final until = parseDate(v['visibleUntil']);
  return until != null && until.isAfter(now ?? DateTime.now());
}
