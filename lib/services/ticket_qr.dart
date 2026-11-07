/// Port of frontend/src/lib/ticketQr.ts: which id and which key draw a ticket's dynamic QR (widgets/dynamic_qr.dart).
///
/// Blow Nights tickets use their own id and `secretKey`. TCS Gate tickets (`accessProvider: "tcs_gate"`, bought in an
/// event whose door is TCS's; functions/lib/tcsCheckout.js) use TCS's ticket id and its key (`gateSecretKey`), with the
/// same `dyn:<id>:<ms>:<hmac>` format, and get in through TCS's door.
const tcsAccess = 'tcs_gate';

bool isTcsTicket(Map<String, dynamic> ticket) => ticket['accessProvider'] == tcsAccess;

({String id, String? secretKey}) ticketQrSource(Map<String, dynamic> ticket, Map<String, dynamic>? secrets) {
  final id = ticket['id'] is String ? ticket['id'] as String : '';
  if (isTcsTicket(ticket)) {
    final gateId = ticket['gateTicketId'];
    if (gateId is String && gateId.isNotEmpty) {
      final key = secrets?['gateSecretKey'];
      return (id: gateId, secretKey: key is String && key.isNotEmpty ? key : null);
    }
    // A TCS ticket without TCS's id can't draw a QR TCS's door accepts.
    return (id: id, secretKey: null);
  }
  final key = secrets?['secretKey'];
  return (id: id, secretKey: key is String && key.isNotEmpty ? key : null);
}
