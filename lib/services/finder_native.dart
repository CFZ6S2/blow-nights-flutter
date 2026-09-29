import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import 'ble_identity.dart';

/// Android side lives in android/app/src/main/kotlin/com/blownights/finder/finder/.
class FinderState {
  final bool ble;
  final bool advertise;
  final bool enabled;
  final bool permissions;
  final bool running;
  final bool hce;
  final bool nfcOn;
  const FinderState(
      {this.ble = false,
      this.advertise = false,
      this.enabled = false,
      this.permissions = false,
      this.running = false,
      this.hce = false,
      this.nfcOn = false});

  factory FinderState.from(Map m) => FinderState(
        ble: m['ble'] == true,
        advertise: m['advertise'] == true,
        enabled: m['enabled'] == true,
        permissions: m['permissions'] == true,
        running: m['running'] == true,
        hce: m['hce'] == true,
        nfcOn: m['nfcOn'] == true,
      );
}

class FinderNative {
  static const _methods = MethodChannel('blownights/finder');
  static const _events = EventChannel('blownights/finder/events');

  /// Must match InviteHceService.AID.
  static final _aid = Uint8List.fromList([0xF0, 0x42, 0x4E, 0x46, 0x52, 0x49, 0x4E, 0x44]);

  static bool get available => Platform.isAndroid;

  static Stream<Map>? _stream;
  static Stream<Map> get events => _stream ??= available
      ? _events.receiveBroadcastStream().where((e) => e is Map).cast<Map>()
      : const Stream<Map>.empty();

  static Future<FinderState> state() async {
    if (!available) return const FinderState();
    try {
      return FinderState.from(await _methods.invokeMethod<Map>('state') ?? const {});
    } catch (_) {
      return const FinderState();
    }
  }

  static Future<bool> requestPermissions() async =>
      available && (await _methods.invokeMethod<bool>('requestPermissions') ?? false);

  static Future<void> enableBluetooth() async {
    if (available) await _methods.invokeMethod('enableBluetooth');
  }

  static List<Map<String, Object>> _keysArg(List<BleKeyUse> keys) => [for (final k in keys) {'k': k.key, 'from': k.fromMs}];

  /// [keys] is the install's advertising schedule (ble_identity.dart); the service derives and rotates the advertised
  /// id itself, switching key when the next one's time comes. [title]/[text] go in the ongoing notification.
  static Future<bool> start(List<BleKeyUse> keys, {required String title, required String text}) async =>
      available &&
      (await _methods.invokeMethod<bool>('start', {'keys': _keysArg(keys), 'title': title, 'text': text}) ?? false);

  /// Replaces the schedule of a running service (a renewed key was just published).
  static Future<void> setKeys(List<BleKeyUse> keys) async {
    if (available) await _methods.invokeMethod('setKeys', {'keys': _keysArg(keys)});
  }

  /// Lets the radar service (KeyRenewal.kt) ask this isolate to renew the BLE key; [renew] returns the new advertising
  /// schedule, or null if nothing could be done.
  static void onRenewRequest(Future<List<BleKeyUse>?> Function() renew) {
    if (!available) return;
    _methods.setMethodCallHandler((call) async {
      if (call.method != 'renewKeys') throw MissingPluginException(call.method);
      final keys = await renew();
      return keys == null ? null : _keysArg(keys);
    });
  }

  /// Result of a renewal run in the headless engine (finder_background.dart); the service then destroys that engine.
  static Future<void> reportBackgroundRenewal(List<BleKeyUse>? keys) =>
      const MethodChannel('blownights/finder_bg').invokeMethod('done', {'keys': keys == null ? null : _keysArg(keys)});

  static Future<void> stop() async {
    if (available) await _methods.invokeMethod('stop');
  }

  /// Arms (payload) or disarms (null) the NFC card emulation that hands the invite to a phone tapped against this one.
  static Future<void> setInvite(String? payload) async {
    if (available) await _methods.invokeMethod('setInvite', {'payload': payload});
  }

  /// Reader side of the phone-to-phone invite: SELECT our AID over IsoDep and return the answer.
  ///
  /// Reader mode skips the platform NDEF check, as Android's CardReader sample does to read other phones: with that
  /// check a phone emulating a card is often dropped before the app gets it, so nothing happened on tap. Without it
  /// there is no cached NDEF, so a sticker or wristband (NFC Forum Type 2, e.g. NTAG) is read page by page instead.
  /// [onPayload] gets the raw text (the caller parses the invite); [onMiss] says why a tap gave nothing.
  static Future<bool> readInvites(void Function(String payload) onPayload, {void Function(NfcInviteMiss miss)? onMiss}) async {
    try {
      if (await NfcManager.instance.checkAvailability() != NfcAvailability.enabled) return false;
      await NfcManagerAndroid.instance.enableReaderMode(
        flags: {NfcReaderFlagAndroid.nfcA, NfcReaderFlagAndroid.nfcB, NfcReaderFlagAndroid.skipNdefCheck},
        onTagDiscovered: (tag) async {
          HapticFeedback.mediumImpact();
          final iso = IsoDepAndroid.from(tag);
          if (iso != null) {
            try {
              final res = await iso.transceive(Uint8List.fromList([0x00, 0xA4, 0x04, 0x00, _aid.length, ..._aid, 0x00]));
              if (res.length > 2 && res[res.length - 2] == 0x90 && res[res.length - 1] == 0x00) {
                onPayload(utf8.decode(res.sublist(0, res.length - 2), allowMalformed: true));
              } else {
                // A phone not showing an invite (or a bank card) answers "not found".
                debugPrint('finder nfc: SELECT answered ${res.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
                onMiss?.call(NfcInviteMiss.noInvite);
              }
            } catch (e) {
              debugPrint('finder nfc: IsoDep failed: $e');
              onMiss?.call(NfcInviteMiss.lost);
            }
            return;
          }
          final ul = MifareUltralightAndroid.from(tag);
          if (ul != null) {
            try {
              onPayload(await _readType2(ul));
            } catch (e) {
              debugPrint('finder nfc: sticker read failed: $e');
              onMiss?.call(NfcInviteMiss.lost);
            }
            return;
          }
          onMiss?.call(NfcInviteMiss.notInvite);
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// User memory of a Type 2 tag from page 4 (4 pages per read) up to the terminator TLV or [maxReads] reads,
  /// as Latin-1 text: the invite ("BNG1:CODE") is plain ASCII inside the NDEF text/URL record.
  static Future<String> _readType2(MifareUltralightAndroid ul, {int maxReads = 16}) async {
    final bytes = <int>[];
    for (var i = 0; i < maxReads; i++) {
      final Uint8List chunk;
      try {
        chunk = await ul.readPages(pageOffset: 4 + i * 4);
      } catch (_) {
        if (bytes.isEmpty) rethrow;
        break; // read past the end of a small tag
      }
      bytes.addAll(chunk);
      if (chunk.contains(0xFE)) break;
    }
    return latin1.decode(bytes);
  }

  static Future<void> stopReading() async {
    try {
      await NfcManagerAndroid.instance.disableReaderMode();
    } catch (_) {}
  }
}

/// Why an NFC tap on the join screen gave no invite.
enum NfcInviteMiss {
  /// Something answered (a phone, a card) but isn't showing a group invite.
  noInvite,

  /// The phones moved apart before the answer.
  lost,

  /// A tag that can't hold an invite.
  notInvite,
}
