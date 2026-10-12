import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';

/// Port of frontend/src/context/AuthContext.tsx (with hooks/usePresence.ts: presence follows the app lifecycle).
class AuthProvider extends ChangeNotifier with WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;

  User? user;
  UserProfile? profile;
  Map<String, dynamic>? claims;
  bool loading = true;

  StreamSubscription? _authSub;
  StreamSubscription? _profileSub;
  bool _googleReady = false;
  bool _foreground = true;
  bool? _onlineWritten;

  AuthProvider() {
    WidgetsBinding.instance.addObserver(this);
    final failsafe = Timer(const Duration(seconds: 5), () {
      if (loading) {
        loading = false;
        notifyListeners();
      }
    });
    _authSub = _auth.idTokenChanges().listen((u) {
      failsafe.cancel();
      _profileSub?.cancel();
      _profileSub = null;
      if (u == null) {
        user = null;
        profile = null;
        claims = null;
        loading = false;
        notifyListeners();
        return;
      }
      user = u;
      _loadClaims(u);
      _onlineWritten = null;
      _profileSub = _db.collection('users').doc(u.uid).snapshots().listen((doc) {
        profile = doc.exists ? UserProfile.fromDoc(doc) : null;
        loading = false;
        notifyListeners();
        _syncPresence();
      }, onError: (_) {
        loading = false;
        notifyListeners();
      });
    });
  }

  Future<void> _loadClaims(User u) async {
    try {
      var res = await u.getIdTokenResult();
      if (res.claims?['role'] == null) res = await u.getIdTokenResult(true);
      final c = <String, dynamic>{...?res.claims};
      if (c['role'] == 'venue') c['role'] = 'venueOwner';
      claims = c;
      notifyListeners();
    } catch (_) {}
  }

  String? get role => claims?['role'] as String?;
  bool get isSuperAdmin => role == 'superadmin';
  bool get isAdmin => isSuperAdmin || role == 'admin';
  bool get isCityAdmin => role == 'cityAdmin';
  bool get isMasterPartner => role == 'masterPartner';
  bool get isCityManager => isMasterPartner && claims?['partnerType'] == 'cityManager';
  bool get isVenueManager => isAdmin || isCityAdmin || role == 'venueOwner';

  String get membershipTier => profile?.membershipTier ?? 'free';
  // The server sets membershipTier from the active Stripe or Google Play subscription (functions/lib/membership) and
  // clears it when it ends; nothing writes a membershipStatus, so requiring it kept paying users from being recognised
  // (as on the web).
  bool get isPlus => membershipTier == 'plus';
  bool get isBlack => membershipTier == 'black';
  bool get isPromoLifetime => profile?.promoMember == true;

  int? get _boostExpiresMs {
    final p = profile?.blackBoostExpires?.millisecondsSinceEpoch;
    if (p != null) return p;
    final c = claims?['blackBoostExpires'];
    return c is num ? c.toInt() : null;
  }

  bool get hasBlackAccess {
    final now = DateTime.now().millisecondsSinceEpoch;
    final b = _boostExpiresMs;
    return isAdmin || isBlack || isPromoLifetime || (b != null && b > now);
  }

  bool get hasChillAccess {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pass = claims?['pass_expires'];
    final boost = claims?['blackBoostExpires'];
    return isAdmin ||
        claims?['premium'] == true ||
        ['plus', 'black'].contains(profile?.membershipTier) ||
        (pass is num && pass > now) ||
        (boost is num && boost > now);
  }

  Future<void> loginWithGoogle() async {
    final g = GoogleSignIn.instance;
    if (!_googleReady) {
      await g.initialize();
      _googleReady = true;
    }
    final account = await g.authenticate();
    final idToken = account.authentication.idToken;
    await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
  }

  Future<void> loginWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    await _auth.signInWithProvider(provider);
  }

  Future<void> loginWithUsername(String username, String password) async {
    final res = await _functions
        .httpsCallable('loginWithUsername')
        .call<Map<String, dynamic>>({'username': username, 'password': password});
    final token = res.data['token'] as String;
    await _auth.signInWithCustomToken(token);
  }

  Future<void> logout() async {
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  Future<void> deleteAccount() async {
    await _functions.httpsCallable('deleteUserData').call();
    await logout();
  }

  Future<void> refreshToken() async {
    await user?.getIdToken(true);
    final u = user;
    if (u != null) await _loadClaims(u);
  }

  // `online` (what the radar and the swipe list) = app in the foreground AND visible (radarVisible not false).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.inactive || foreground == _foreground) return;
    _foreground = foreground;
    _syncPresence();
  }

  Future<void> _syncPresence() async {
    final u = user, p = profile;
    if (u == null || p == null) return;
    final online = _foreground && p.radarVisible;
    if (online == _onlineWritten && online == p.online) return;
    _onlineWritten = online;
    try {
      await _db.collection('users').doc(u.uid).set({'online': online, 'lastSeen': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (_) {
      _onlineWritten = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
