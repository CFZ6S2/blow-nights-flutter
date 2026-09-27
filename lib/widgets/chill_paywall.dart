import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../navigation.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Port of components/ChillPaywall.tsx (bottom sheet on mobile).
Future<void> showChillPaywall(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tw.slate900, Tw.black]),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Tw.slate700),
        ),
        child: SafeArea(
          top: false,
          child: Stack(children: [
            Positioned(top: -64, left: 0, right: 0, child: Center(child: Orb(color: Tw.slate500.withValues(alpha: 0.1), size: 256))),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(onTap: () => Navigator.of(ctx).pop(), child: const Icon(Icons.close, color: Tw.slate600)),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(99), border: Border.all(color: Tw.w(0.1))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.nightlife, size: 14, color: Tw.w(0.7)),
                      const SizedBox(width: 8),
                      Label(ctx.t('paywall.exclusive_black'), color: Tw.white),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Text(ctx.t('paywall.only_black'), textAlign: TextAlign.center, style: tw(24, weight: black, height: 1.2)),
                const SizedBox(height: 8),
                Text(ctx.t('paywall.black_desc'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
                const SizedBox(height: 32),
                Pressable(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    openRoute(context, AppRoute.premium);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFE2E8F0), Tw.white]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Tw.w(0.3), blurRadius: 20)],
                    ),
                    child: Label(ctx.t('paywall.view_plans'), color: Tw.black, align: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 16),
                for (final k in ['paywall.feat_chills', 'paywall.feat_create', 'paywall.feat_vip', 'paywall.feat_pings'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      const Icon(Icons.check, size: 14, color: Color(0xFFF1F5F9)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(ctx.t(k), style: tw(12, color: Tw.slate400))),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
