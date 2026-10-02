/// Claims of reference venues (web docs/REFERENCE_VENUES.md §3, functions/modules/venue_claims.js).
library;

const claimRoles = ['titular', 'gerente', 'socio', 'otro'];
const claimStatuses = ['pending', 'approved', 'rejected', 'withdrawn', 'superseded'];
const claimDocumentMaxBytes = 10 * 1024 * 1024;

final _phone = RegExp(r'^\+?[0-9 ]{6,20}$');

/// Same checks as the backend's cleanContact: a name and a phone it will accept, before anything is uploaded.
bool isValidClaimContact(String name, String phone) => name.trim().length >= 2 && _phone.hasMatch(phone.trim());

/// Storage path of the claimant's document: their private folder (storage.rules venue_claims/{uid}/), which the
/// backend checks before attaching it to the claim. Same naming as the web.
String claimDocumentPath(String uid, String fileName, int nowMs) {
  // No ".." either: the backend rejects any path containing it.
  final safe = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_').replaceAll(RegExp(r'\.{2,}'), '_');
  return 'venue_claims/$uid/$nowMs-${safe.length > 80 ? safe.substring(safe.length - 80) : safe}';
}

/// The picker doesn't always know the type (Android gallery); storage.rules only take images or PDF.
String claimDocumentContentType(String fileName, String? mimeType) {
  if (mimeType != null && (mimeType.startsWith('image/') || mimeType == 'application/pdf')) return mimeType;
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'gif' => 'image/gif',
    'pdf' => 'application/pdf',
    _ => 'image/jpeg',
  };
}
