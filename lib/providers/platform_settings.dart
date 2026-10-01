import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../services/proximity.dart';

/// Port of hooks/usePlatformSettings.ts (`settings/platform` feature flags).
class PlatformSettings extends ChangeNotifier {
  static const defaults = <String, Object?>{
    'moduleTicketing': true,
    'moduleCashless': false,
    'moduleRrppLibres': true,
    'moduleChills': true,
    'moduleVenueRegistration': true,
    // "Amigos cerca" (BLE friend finder). Off until festival tickets are sold; super-admin turns it on.
    'moduleFriendFinder': false,
    'moduleRrppCommissions': true,
    'maintenanceMode': false,
  };

  Map<String, Object?> flags = {...defaults};
  StreamSubscription? _sub;

  PlatformSettings() {
    _sub = FirebaseFirestore.instance.collection('settings').doc('platform').snapshots().listen((s) {
      flags = {...defaults, ...?s.data()};
      notifyListeners();
      if (!flag('moduleFriendFinder')) _stopFinder();
    }, onError: (_) {
      flags = {...defaults};
      notifyListeners();
    });
  }

  bool flag(String key) => flags[key] == true;

  /// Switched off from super-admin: a radar left running (it survives the app being closed) stops too, and with it
  /// the background key renewal.
  Future<void> _stopFinder() async {
    try {
      final state = await Proximity.instance.refresh();
      if (state.running) await Proximity.instance.stop();
    } catch (_) {
      // No finder on this platform (iOS, tests).
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// crypto.randomUUID() equivalent (RFC 4122 v4) for idempotency keys.
String uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
