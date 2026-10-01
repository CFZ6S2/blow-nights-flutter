import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows a push that arrives while the app is open (Android only puts it in the tray when the app is in the
/// background). MaterialApp.scaffoldMessengerKey.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Keeps what venue promo pushes need (web repo, functions/modules/notifications.js sendPromoNotification):
/// - the push token on users/{uid}. After sign-in the app asks for notifications once per install, and with
///   permission saves the token and follows its refreshes; never when the user turned notifications off in the
///   profile (notificationsEnabled == false).
/// - push_locations/{uid}: the position rounded to ~1 km, only while notifications are allowed and only when location
///   permission was already given (it never asks for it). Rewritten when it moves or every [rewriteEvery], so the
///   server's 24 h freshness holds while the app is used.
class PushSync {
  PushSync._();

  static const askedKey = 'push_permission_asked_v1';
  static const lastPositionKey = 'push_location_last_v1';
  static const rewriteEvery = Duration(hours: 6);

  static String? _uid;
  static String? _key; // uid + the profile's choice: turning notifications on or off starts over
  static StreamSubscription<String>? _tokenRefresh;
  static StreamSubscription<RemoteMessage>? _foreground;
  static AppLifecycleListener? _lifecycle;

  /// With the signed-in user, or null after sign-out. Staff accounts (scanners only) are left out.
  static Future<void> start(String? uid, {required bool notificationsOff, String? savedToken, bool staff = false}) async {
    final key = '$uid|$notificationsOff|$staff';
    if (key == _key) return;
    stop();
    _key = key;
    if (uid == null || staff || notificationsOff || kIsWeb) return;
    _uid = uid;
    try {
      final messaging = FirebaseMessaging.instance;
      var settings = await messaging.getNotificationSettings();
      final prefs = await SharedPreferences.getInstance();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined && prefs.getBool(askedKey) != true) {
        // After the location prompt the city zone may show at launch, not on top of it.
        await Future<void>.delayed(const Duration(seconds: 3));
        if (_uid != uid) return;
        await prefs.setBool(askedKey, true);
        settings = await messaging.requestPermission();
      }
      if (_uid != uid || !allowed(settings.authorizationStatus)) return;

      final token = await messaging.getToken();
      if (token != null && token != savedToken) await _saveToken(uid, token);
      _tokenRefresh = messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
      _foreground = FirebaseMessaging.onMessage.listen(_showInApp);

      unawaited(updatePosition(uid));
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(updatePosition(uid)));
    } catch (e) {
      debugPrint('push sync: $e');
    }
  }

  static void stop() {
    _uid = null;
    _key = null;
    _tokenRefresh?.cancel();
    _tokenRefresh = null;
    _foreground?.cancel();
    _foreground = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  static bool allowed(AuthorizationStatus s) => s == AuthorizationStatus.authorized || s == AuthorizationStatus.provisional;

  static Future<void> _saveToken(String uid, String token) =>
      FirebaseFirestore.instance.collection('users').doc(uid).update({'fcmToken': token, 'notificationsEnabled': true}).catchError((_) {});

  static void _showInApp(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    rootMessengerKey.currentState?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text([n.title, n.body].whereType<String>().where((s) => s.isNotEmpty).join('\n')),
    ));
  }

  /// Writes push_locations/{uid} if location permission is already given and the rounded position changed or is
  /// older than [rewriteEvery].
  static Future<void> updatePosition(String uid) async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) return;
      final pos = await _locate();
      if (pos == null || _uid != uid) return;
      final lat = round2(pos.latitude);
      final lng = round2(pos.longitude);
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!shouldWrite(prefs.getString(lastPositionKey), uid, lat, lng, now)) return;
      await FirebaseFirestore.instance
          .collection('push_locations')
          .doc(uid)
          .set({'lat': lat, 'lng': lng, 'updatedAt': FieldValue.serverTimestamp()});
      await prefs.setString(lastPositionKey, '$uid,$lat,$lng,$now');
    } catch (e) {
      debugPrint('push location: $e');
    }
  }

  /// Rounded to 2 decimals: about 1.1 km north-south, enough for a 1 to 25 km promo radius.
  static double round2(double v) => (v * 100).round() / 100;

  /// [last] is "uid,lat,lng,epochMs" from the previous write.
  static bool shouldWrite(String? last, String uid, double lat, double lng, int nowMs) {
    final p = last?.split(',');
    if (p == null || p.length != 4 || p[0] != uid) return true;
    if (double.tryParse(p[1]) != lat || double.tryParse(p[2]) != lng) return true;
    final at = int.tryParse(p[3]) ?? 0;
    return nowMs - at >= rewriteEvery.inMilliseconds;
  }

  /// Low accuracy and no Google "Location Accuracy" dialog, like CityProvider: the last known position if it is from
  /// the last 30 minutes (an older one would be stored as fresh), else a new fix.
  static Future<Position?> _locate() async {
    final android = defaultTargetPlatform == TargetPlatform.android;
    try {
      final last = await Geolocator.getLastKnownPosition(forceAndroidLocationManager: android);
      if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 30)) return last;
    } catch (_) {}
    try {
      return await Geolocator.getCurrentPosition(
          locationSettings: android
              ? AndroidSettings(accuracy: LocationAccuracy.low, timeLimit: const Duration(seconds: 8), forceLocationManager: true)
              : const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)));
    } catch (_) {
      return null;
    }
  }
}
