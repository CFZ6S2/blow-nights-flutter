import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart' show PurchaseStateWrapper, ReplacementMode;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../providers/platform_settings.dart';

/// Google Play Billing (docs/PLAY_BILLING.md in the web repo). In the Android app, users' digital purchases go through
/// Google, at the web's prices: Plus and Black (monthly and yearly), the Black 8h pass, 3 pings and "fuego esta noche".
/// Venue plans are never sold, priced or linked in the app; tickets, drinks, cashless and RRPP QR packs stay on Stripe.
///
/// The server decides everything: `verifyPlayPurchase` asks Google about the purchase, checks it's this account's,
/// grants it once and acknowledges or consumes it. The app only starts the purchase and hands over the token.

const playPackage = 'com.blownights.finder';

/// The account a purchase belongs to (Google's obfuscatedAccountId), as the server's lib/playBilling.accountIdFor:
/// the server only grants a purchase whose id matches the caller, so a token can't be used on another account.
String playAccountId(String uid) => sha256.convert(utf8.encode('blownights:$uid')).toString();

/// Whether the app sells digital goods: only on Android (through Google Play) and once super-admin has turned
/// "Ventas digitales en la app Android" (moduleAppPremium) on, after setting the products up in Play Console.
bool appSellsDigital(PlatformSettings settings) => PlayBilling.supported && settings.flag('moduleAppPremium');

/// Google Play's page to manage (cancel, change payment method) a subscription bought through Google.
String playSubscriptionsUrl(String? productId) => productId == null
    ? 'https://play.google.com/store/account/subscriptions'
    : 'https://play.google.com/store/account/subscriptions?sku=${Uri.encodeComponent(productId)}&package=$playPackage';

enum PlayOutcome {
  /// Paid and granted.
  done,

  /// Google is waiting for the payment (e.g. cash at a shop): granted when it completes.
  pending,
  canceled,
  failed,

  /// Google Play isn't available here, or the product isn't set up in Play Console.
  unavailable,

  /// The subscription being replaced was bought with another Google account than the one on this device.
  otherGoogleAccount,
}

class PlayBilling extends ChangeNotifier {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Product ids as created in Play Console (docs/PLAY_BILLING.md): subscriptions with "monthly" and "yearly" base
  /// plans, and consumable one-time products.
  static const subscriptionIds = {'plus', 'black'};
  static const oneTimeIds = {'black_pass_8h', 'ping_pack_3', 'vip_night'};

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchases;
  StreamSubscription<User?>? _authSub;

  /// 'plus:monthly', 'black:yearly', 'ping_pack_3', ...
  final Map<String, ProductDetails> _products = {};
  String? _uid;

  /// Purchases Google reported while nobody was signed in: verified once someone is.
  final List<PurchaseDetails> _unverified = [];
  String? _flowProduct;
  Completer<PlayOutcome>? _flow;

  PlayBilling() {
    if (!supported) return;
    // Listened to from the start: Google can deliver a purchase at any time (one completed after the app closed).
    _purchases = _iap.purchaseStream.listen(_onPurchases, onError: (_) {});
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _uid = u?.uid;
      if (_uid != null) unawaited(_recover());
    });
    unawaited(_loadProducts());
  }

  @override
  void dispose() {
    _purchases?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      if (!await _iap.isAvailable()) return;
      final res = await _iap.queryProductDetails({...subscriptionIds, ...oneTimeIds});
      for (final p in res.productDetails) {
        final g = p is GooglePlayProductDetails ? p : null;
        final index = g?.subscriptionIndex;
        if (g != null && index != null) {
          final offer = g.productDetails.subscriptionOfferDetails![index];
          // Only the base plan itself (Play also lists any promotional offers on top of it).
          if (offer.offerId == null) _products['${p.id}:${offer.basePlanId}'] = p;
        } else {
          _products[p.id] = p;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Play Billing unavailable: $e');
    }
  }

  static String _key(String productId, [String? basePlan]) => basePlan == null ? productId : '$productId:$basePlan';

  /// Google's localized price, as the user will be charged, or null while it isn't known.
  String? price(String productId, [String? basePlan]) => _products[_key(productId, basePlan)]?.price;

  /// Buys [productId] ([basePlan] "monthly" or "yearly" for a subscription). Completes when Google and the server are
  /// done with it. [replacing] is the user's current Google Play subscription when this one replaces it (Plus → Black).
  Future<PlayOutcome> buy(String productId, {String? basePlan, String? replacing}) async {
    final uid = _uid;
    final details = _products[_key(productId, basePlan)];
    if (!supported || uid == null || details == null) return PlayOutcome.unavailable;
    if (_flow != null) return PlayOutcome.failed;

    ChangeSubscriptionParam? change;
    if (replacing != null) {
      // Replaced, not added: otherwise Google would keep charging the old one too.
      final old = await _ownedPurchase(replacing, uid);
      if (old == null) return PlayOutcome.otherGoogleAccount;
      change = ChangeSubscriptionParam(oldPurchaseDetails: old, replacementMode: ReplacementMode.withTimeProration);
    }
    final param = GooglePlayPurchaseParam(productDetails: details, applicationUserName: playAccountId(uid), changeSubscriptionParam: change);
    final flow = _flow = Completer<PlayOutcome>();
    _flowProduct = productId;
    try {
      final started = subscriptionIds.contains(productId)
          ? await _iap.buyNonConsumable(purchaseParam: param)
          // The server consumes it once granted (consuming here first could lose the purchase if granting failed).
          : await _iap.buyConsumable(purchaseParam: param, autoConsume: false);
      if (!started) _finish(productId, PlayOutcome.failed);
    } catch (e) {
      debugPrint('Play purchase failed to start: $e');
      _finish(productId, PlayOutcome.failed);
    }
    return flow.future;
  }

  void _finish(String productId, PlayOutcome outcome) {
    if (_flow == null || _flowProduct != productId) return;
    final flow = _flow!;
    _flow = null;
    _flowProduct = null;
    if (!flow.isCompleted) flow.complete(outcome);
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _finish(p.productID, PlayOutcome.pending);
        case PurchaseStatus.canceled:
          _finish(p.productID, PlayOutcome.canceled);
        case PurchaseStatus.error:
          _finish(p.productID, PlayOutcome.failed);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p);
      }
    }
  }

  Future<void> _verify(PurchaseDetails p) async {
    if (_uid == null) {
      _unverified.add(p);
      return;
    }
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('verifyPlayPurchase').call<Map<String, dynamic>>({
        'productId': p.productID,
        'purchaseToken': p.verificationData.serverVerificationData,
      });
      final pending = res.data['pending'] == true;
      _finish(p.productID, pending ? PlayOutcome.pending : PlayOutcome.done);
      // The server already acknowledged it; this only tells the library (an acknowledged purchase is a no-op).
      if (!pending && subscriptionIds.contains(p.productID) && p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (_) {}
      }
    } catch (e) {
      // Left unacknowledged: retried on the next start (_recover). Google refunds it if it's never granted.
      debugPrint('verifyPlayPurchase failed: $e');
      _finish(p.productID, PlayOutcome.failed);
    }
  }

  /// Purchases Google holds that the server may not have granted yet (the app closed mid-purchase, a payment that was
  /// pending, no connection): verified again. Granting is once per purchase on the server, so repeating is harmless.
  Future<void> _recover() async {
    final uid = _uid;
    if (uid == null) return;
    final waiting = [..._unverified];
    _unverified.clear();
    for (final p in waiting) {
      await _verify(p);
    }
    try {
      final res = await _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>().queryPastPurchases();
      final account = playAccountId(uid);
      for (final p in res.pastPurchases) {
        final w = p.billingClientPurchase;
        // Only this account's, paid, and not yet acknowledged or consumed (Google only lists unconsumed ones).
        if (w.obfuscatedAccountId != account || w.purchaseState != PurchaseStateWrapper.purchased || w.isAcknowledged) continue;
        await _verify(p);
      }
    } catch (e) {
      debugPrint('Play purchases check failed: $e');
    }
  }

  /// The user's active Google Play subscription to [productId] on this device's Google account, if any.
  Future<GooglePlayPurchaseDetails?> _ownedPurchase(String productId, String uid) async {
    try {
      final res = await _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>().queryPastPurchases();
      final account = playAccountId(uid);
      for (final p in res.pastPurchases) {
        if (p.productID == productId && p.billingClientPurchase.obfuscatedAccountId == account) return p;
      }
    } catch (_) {}
    return null;
  }
}
