import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import 'nfc_reader.dart';

/// Phone-to-phone NFC for entry tickets and drinks (Android only; android/.../pass/PassHceService.kt).
///
/// Customer side: while a ticket or drink QR is on screen, [show] hands its code to the phone's card emulation, so
/// tapping it on a scanner phone gives the scanner the same code the QR shows. [hide], or the app leaving the
/// foreground, stops it.
///
/// Scanner side: [read] runs reader mode like the group invite reader (finder_native.dart), skipping the platform NDEF
/// check, without which a phone emulating a card is often dropped before the app gets it. A phone answers the SELECT
/// of [aid] with its code; any other tag is reported by its serial number, which the door and bar resolve server side.
class NfcPass {
  static const _channel = MethodChannel('blownights/nfc_pass');

  /// F0 + "BNPASS". Must match PassHceService.AID and res/xml/pass_aid.xml.
  static const aid = [0xF0, 0x42, 0x4E, 0x50, 0x41, 0x53, 0x53];

  static bool get available => debugAvailable ?? (!kIsWeb && Platform.isAndroid);

  /// Tests run off Android; this lets them exercise the customer side.
  @visibleForTesting
  static bool? debugAvailable;

  static Object? _owner;
  static String? _code;
  static VoidCallback? _onRead;
  static bool _foreground = true;
  static AppLifecycleListener? _lifecycle;
  static bool _reading = false;

  /// [owner] is the screen showing [code]. A later show() from another screen takes over, and only the owner's
  /// hide() clears it. [onRead] runs when a scanner has read the code.
  static void show(Object owner, String? code, {VoidCallback? onRead}) {
    if (!available) return;
    _listen();
    _owner = owner;
    _code = code == null || code.isEmpty ? null : code;
    _onRead = onRead;
    _push();
  }

  static void hide(Object owner) {
    if (!available || !identical(_owner, owner)) return;
    _owner = null;
    _code = null;
    _onRead = null;
    _push();
  }

  /// What the card emulation should answer right now (nothing while the app is not in the foreground).
  @visibleForTesting
  static String? get armedCode => _foreground ? _code : null;

  static void _listen() {
    if (_lifecycle != null) return;
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      _foreground = state == AppLifecycleState.resumed;
      _push();
    });
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'handedOver') return;
      HapticFeedback.mediumImpact();
      _onRead?.call();
    });
  }

  static void _push() {
    unawaited(_channel.invokeMethod<void>('setPayload', {'payload': armedCode}).catchError((Object _) {}));
  }

  /// Scanner side. [onCode] gets a phone's code (type 'phone') or a tag's serial number (type 'serial'); [onEmpty]
  /// runs for a phone that isn't showing a ticket or drink. Off Android it is the NDEF reader (nfc_reader.dart).
  static Future<bool> read(NfcTokenHandler onCode, {VoidCallback? onEmpty}) async {
    if (!available) return NfcReader.start(onCode);
    try {
      if (await NfcManager.instance.checkAvailability() != NfcAvailability.enabled) return false;
      await NfcManagerAndroid.instance.enableReaderMode(
        flags: {NfcReaderFlagAndroid.nfcA, NfcReaderFlagAndroid.nfcB, NfcReaderFlagAndroid.skipNdefCheck},
        onTagDiscovered: (tag) async {
          final id = NfcTagAndroid.from(tag)?.id ?? Uint8List(0);
          final iso = IsoDepAndroid.from(tag);
          if (iso != null) {
            try {
              final code = codeFromSelectResponse(await iso.transceive(selectApdu));
              if (code != null) {
                onCode(code, 'phone');
                return;
              }
            } catch (e) {
              debugPrint('nfc pass: IsoDep failed: $e');
            }
            // A phone showing nothing answers "not found"; phones present a random UID (first byte 0x08).
            if (isRandomUid(id)) {
              onEmpty?.call();
              return;
            }
          }
          if (id.isNotEmpty) onCode(serialHex(id), 'serial');
        },
      );
      _reading = true;
      return true;
    } catch (_) {
      _reading = false;
      return false;
    }
  }

  static bool get reading => available ? _reading : NfcReader.active;

  static Future<void> stop() async {
    if (!available) return NfcReader.stop();
    _reading = false;
    try {
      await NfcManagerAndroid.instance.disableReaderMode();
    } catch (_) {}
  }

  /// SELECT by name of [aid] (CLA INS P1 P2 Lc AID Le).
  static Uint8List get selectApdu => Uint8List.fromList([0x00, 0xA4, 0x04, 0x00, aid.length, ...aid, 0x00]);

  /// The code in a SELECT answer ending in 90 00, or null for any other status or an empty answer.
  static String? codeFromSelectResponse(Uint8List res) {
    final n = res.length;
    if (n <= 2 || res[n - 2] != 0x90 || res[n - 1] != 0x00) return null;
    final code = utf8.decode(res.sublist(0, n - 2), allowMalformed: true).trim();
    return code.isEmpty ? null : code;
  }

  /// ISO 14443-3: a 4-byte UID starting with 0x08 is random, what phones emulating a card present.
  static bool isRandomUid(List<int> id) => id.length == 4 && id[0] == 0x08;

  static String serialHex(List<int> id) => id.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
