import 'package:blow_nights/services/staff_invite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const invite = 'Ab3dEf5hIj7lMn9pQr1t.xY_z-0123456789abcdEFG';

  group('parseStaffInvite', () {
    test('reads the join link the venue QR, WhatsApp or the owner phone (NFC) carries', () {
      expect(parseStaffInvite('https://blownights.com/staff/join?i=$invite'), invite);
      expect(parseStaffInvite('  https://blownights.com/staff/join?i=$invite\n'), invite);
      expect(parseStaffInvite('https://blownights.web.app/staff/join?i=$invite&utm=x'), invite);
    });

    test('takes a bare invite too', () => expect(parseStaffInvite(invite), invite));

    test('anything else is not an invite', () {
      expect(parseStaffInvite('https://blownights.com/door?venue=v1&event=e1&token=abc'), isNull);
      expect(parseStaffInvite('https://blownights.com/staff/join?i=short.code'), isNull);
      expect(parseStaffInvite('https://blownights.com/staff/join'), isNull);
      expect(parseStaffInvite('dyn:t1:1700000000000:sig'), isNull); // a ticket QR
      expect(parseStaffInvite(''), isNull);
    });
  });

  group('staffScopes', () {
    test('invite accounts get exactly what the invite allowed', () {
      expect(staffScopes({'role': 'door', 'staffScopes': ['bar']}), ['bar']);
      expect(staffScopes({'role': 'door', 'staffScopes': ['door', 'kitchen']}), ['door']);
    });

    test('door accounts from before invites keep both', () {
      expect(staffScopes({'role': 'door', 'venueId': 'v1'}), ['door', 'bar']);
      expect(staffScopes(null), ['door', 'bar']);
    });
  });
}
