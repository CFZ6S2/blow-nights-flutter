import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase + App Check, shared by main() and the headless engine the radar service starts to renew BLE keys
/// (services/finder_background.dart).
Future<void> initFirebase() async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  // Sideloaded APKs can't pass Play Integrity; build with --dart-define=APPCHECK_DEBUG_TOKEN=<token registered in the console>.
  const debugToken = String.fromEnvironment('APPCHECK_DEBUG_TOKEN');
  final useDebug = !kReleaseMode || debugToken.isNotEmpty;
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: useDebug
          ? AndroidDebugProvider(debugToken: debugToken.isEmpty ? null : debugToken)
          : const AndroidPlayIntegrityProvider(),
      providerApple: useDebug
          ? AppleDebugProvider(debugToken: debugToken.isEmpty ? null : debugToken)
          : const AppleAppAttestProvider(),
    );
  } catch (_) {}
}
