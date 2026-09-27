import 'dart:convert';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

/// 'ndef_text' | 'ndef_url' | 'serial' — same as NFCTokenType in hooks/useNFC.ts.
typedef NfcTokenHandler = void Function(String token, String type);

const _uriPrefixes = [
  '', 'http://www.', 'https://www.', 'http://', 'https://', 'tel:', 'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.', 'ftps://',
  'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://', 'news:', 'telnet://', 'imap:', 'rtsp://', 'urn:', 'pop:', 'sip:', 'sips:', 'tftp:',
  'btspp://', 'btl2cap://', 'btgoep://', 'tcpobex://', 'irdaobex://', 'file://', 'urn:epc:id:', 'urn:epc:tag:', 'urn:epc:pat:',
  'urn:epc:raw:', 'urn:epc:', 'urn:nfc:',
];

/// Port of hooks/useNFC.ts on top of nfc_manager (Web NFC's NDEFReader equivalent).
class NfcReader {
  static bool _active = false;
  static bool get active => _active;

  static Future<bool> supported() async {
    try {
      return await NfcManager.instance.checkAvailability() == NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> start(NfcTokenHandler onToken) async {
    if (!await supported()) return false;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (tag) async {
          final ndef = NdefAndroid.from(tag);
          for (final record in ndef?.cachedNdefMessage?.records ?? const <NdefRecord>[]) {
            if (record.typeNameFormat != TypeNameFormat.wellKnown || record.payload.isEmpty) continue;
            final type = utf8.decode(record.type, allowMalformed: true);
            String? text;
            String kind = 'ndef_text';
            if (type == 'T') {
              final langLen = record.payload[0] & 0x3f;
              text = utf8.decode(record.payload.sublist(1 + langLen), allowMalformed: true);
            } else if (type == 'U') {
              final prefix = record.payload[0] < _uriPrefixes.length ? _uriPrefixes[record.payload[0]] : '';
              text = prefix + utf8.decode(record.payload.sublist(1), allowMalformed: true);
              kind = 'ndef_url';
              final match = RegExp(r'[?&]t=([^&]+)').firstMatch(text);
              if (match != null) text = match.group(1)!;
            }
            if (text == null) continue;
            text = text.replaceFirst(RegExp(r'^BN:', caseSensitive: false), '').trim();
            if (text.length >= 4) {
              onToken(text, kind);
              return;
            }
          }
          final id = NfcTagAndroid.from(tag)?.id;
          if (id != null && id.isNotEmpty) onToken(id.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), 'serial');
        },
      );
      _active = true;
      return true;
    } catch (_) {
      _active = false;
      return false;
    }
  }

  static Future<void> stop() async {
    if (!_active) return;
    _active = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }
}
