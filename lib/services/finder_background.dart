import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'ble_identity.dart';
import 'finder_groups.dart';
import 'finder_native.dart';
import 'firebase_init.dart';

/// BLE key renewal without UI: renews the key when due and publishes it to every group (syncMyBleKeys), returning
/// what the radar should advertise from. Null when nobody is signed in. The radar service calls it about once an hour,
/// in the app's isolate if the app is alive, otherwise through [finderBackgroundMain].
Future<List<BleKeyUse>?> renewBleKeysNow() async {
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser ??
      await auth.authStateChanges().first.timeout(const Duration(seconds: 10), onTimeout: () => null);
  if (user == null) return null;
  return advertisingSchedule(await syncMyBleKeys(uid: user.uid));
}

/// Entry point of the headless engine KeyRenewal.kt starts when the radar runs with the app closed. Reports back on
/// "blownights/finder_bg" (keys, or null if nothing could be done) so the service can update and destroy the engine.
@pragma('vm:entry-point')
Future<void> finderBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  List<BleKeyUse>? keys;
  try {
    await initFirebase();
    keys = await renewBleKeysNow();
  } catch (e) {
    debugPrint('finder background renewal failed: $e');
  }
  await FinderNative.reportBackgroundRenewal(keys);
}
