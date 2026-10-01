/// A venue's staff invite (functions/modules/staff.js): `inviteId.code`, travelling inside its join link
/// `https://blownights.com/staff/join?i=inviteId.code` (the venue's QR, WhatsApp, or NFC from the owner's phone).
final _invite = RegExp(r'^[A-Za-z0-9]{20}\.[A-Za-z0-9_-]{22}$');

/// The invite in what was scanned or tapped (the join link or the bare invite), or null if it isn't one.
String? parseStaffInvite(String raw) {
  final text = raw.trim();
  if (_invite.hasMatch(text)) return text;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.path.endsWith('/staff/join')) return null;
  final i = uri.queryParameters['i']?.trim();
  return i != null && _invite.hasMatch(i) ? i : null;
}

/// What the staff account may scan: invite accounts carry `staffScopes`; door accounts made before invites have none
/// and keep both, as on the server (functions/lib/staffScopes.js).
List<String> staffScopes(Map<String, dynamic>? claims) {
  final s = claims?['staffScopes'];
  return s is List ? [for (final x in s) if (x == 'door' || x == 'bar') x as String] : const ['door', 'bar'];
}
