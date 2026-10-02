import 'dart:convert';
import 'dart:io';

import 'package:blow_nights/models/venue.dart';
import 'package:blow_nights/models/venue_claim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reference venues', () {
    test('only an unclaimed reference counts as a reference point', () {
      expect(Venue.isUnclaimedReferenceData({'source': 'reference', 'isClaimed': false, 'ownerId': 'unclaimed'}), isTrue);
      expect(Venue.isUnclaimedReferenceData({'source': 'reference'}), isTrue);
      // Claimed: an official venue of its owner from then on.
      expect(Venue.isUnclaimedReferenceData({'source': 'reference', 'isClaimed': true}), isFalse);
      // Pending venues of the network and community spots are not references.
      expect(Venue.isUnclaimedReferenceData({'isClaimed': false, 'ownerId': 'abc'}), isFalse);
      expect(Venue.isUnclaimedReferenceData({'ownerId': 'community'}), isFalse);
      expect(Venue.isUnclaimedReferenceData(null), isFalse);
      expect(const Venue('v1', {'source': 'reference', 'isClaimed': false}).isUnclaimedReference, isTrue);
    });
  });

  group('venue claims', () {
    test('contact: same checks as the backend (cleanContact)', () {
      expect(isValidClaimContact('Ana', '+34 600 000 000'), isTrue);
      expect(isValidClaimContact('  Jo ', '600000000'), isTrue);
      expect(isValidClaimContact('A', '600000000'), isFalse);
      expect(isValidClaimContact('Ana', '12345'), isFalse);
      expect(isValidClaimContact('Ana', '600-000-000'), isFalse);
      expect(isValidClaimContact('Ana', '+34 600 000 000 000 000 0'), isFalse);
    });

    test("the document goes to the claimant's private folder, with a safe name", () {
      expect(claimDocumentPath('u1', 'licencia actividad (1).jpg', 1700000000000),
          'venue_claims/u1/1700000000000-licencia_actividad__1_.jpg');
      final long = claimDocumentPath('u1', '${'a' * 120}.png', 1);
      expect(long.startsWith('venue_claims/u1/1-'), isTrue);
      expect(long.length, 'venue_claims/u1/1-'.length + 80);
      expect(long.endsWith('.png'), isTrue);
      expect(claimDocumentPath('u1', '../../x.jpg', 1).contains('..'), isFalse);
    });

    test('content type: images or PDF, as storage.rules require', () {
      expect(claimDocumentContentType('a.jpg', null), 'image/jpeg');
      expect(claimDocumentContentType('a.PNG', null), 'image/png');
      expect(claimDocumentContentType('a.heic', null), 'image/heic');
      expect(claimDocumentContentType('scan', null), 'image/jpeg');
      expect(claimDocumentContentType('a.jpg', 'image/webp'), 'image/webp');
      expect(claimDocumentContentType('a.pdf', 'application/octet-stream'), 'application/pdf');
    });

    test('every locale has the reference and claim texts', () {
      final keys = <String>[
        for (final k in ['badge', 'not_associated', 'what_you_can_do', 'are_you_owner', 'claim_button', 'osm_attribution'])
          'reference_venue.$k',
        for (final k in [
          'title', 'login_first', 'login_button', 'intro', 'name', 'phone', 'role', 'document', 'document_hint_photo',
          'trial_note', 'fill_contact', 'bad_file', 'cancel', 'send', 'sending', 'sent', 'error', 'my_claims', 'loading',
          'none', 'reason', 'trial_until', 'open_panel', 'withdraw',
          for (final r in claimRoles) 'role_$r',
          for (final s in claimStatuses) ...['status_$s', 'explain_$s'],
        ])
          'venue_claim.$k',
      ];
      final files = Directory('assets/i18n').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
      expect(files.length, 12);
      for (final f in files) {
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        for (final key in keys) {
          final parts = key.split('.');
          final value = (json[parts[0]] as Map<String, dynamic>?)?[parts[1]];
          expect(value is String && value.isNotEmpty, isTrue, reason: '${f.path}: $key');
        }
        final claim = json['venue_claim'] as Map<String, dynamic>;
        expect(claim['title'], contains('{{name}}'), reason: f.path);
        expect(claim['reason'], contains('{{reason}}'), reason: f.path);
        expect(claim['trial_until'], contains('{{date}}'), reason: f.path);
      }
    });
  });
}
