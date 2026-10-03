import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../models/user_model.dart';
import '../navigation.dart';
import '../providers/auth_provider.dart';
import '../providers/platform_settings.dart';
import '../services/social.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'match_overlay.dart';
import 'profile_overlay.dart';

/// Port of components/SwipeCards.tsx
class SwipeCards extends StatefulWidget {
  final List<UserProfile> users;
  final String? myVenueId;
  final void Function(String userId, String direction) onSwipe;
  const SwipeCards({super.key, required this.users, required this.onSwipe, this.myVenueId});

  @override
  State<SwipeCards> createState() => _SwipeCardsState();
}

class _SwipeCardsState extends State<SwipeCards> {
  late List<UserProfile> _cards = [...widget.users];
  Offset _drag = Offset.zero;
  int _photo = 0;
  bool _limitExceeded = false;
  bool _paying = false;
  int _lastPing = 0;

  @override
  void didUpdateWidget(covariant SwipeCards old) {
    super.didUpdateWidget(old);
    if (old.users != widget.users) _cards = [...widget.users];
  }

  Future<void> _checkout(String type) async {
    final i18n = context.read<I18n>();
    final auth = context.read<AuthProvider>();
    setState(() => _paying = true);
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('createPingCheckoutSession').call<Map<String, dynamic>>({
        'type': type,
        'origin': webBase,
        // Attribution goes to the user's own city; without one, to nobody (never Madrid by default).
        if (auth.profile?.cityId != null) 'citySlug': auth.profile!.cityId,
      });
      final url = res.data['url'] as String?;
      if (url != null) await openInApp(url);
    } catch (_) {
      if (mounted) showToast(context, i18n.t('swipe.err_payment'), error: true);
    }
    if (mounted) setState(() => _paying = false);
  }

  Future<void> _action(UserProfile target, String dir) async {
    final auth = context.read<AuthProvider>();
    final i18n = context.read<I18n>();
    final uid = auth.user?.uid;
    if (dir == 'left') {
      if (uid != null) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(uid).collection('passes').doc(target.id).set({
            'targetUserId': target.id,
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
          });
        } catch (_) {}
      }
    } else if (dir == 'right') {
      if (uid != null) {
        final res = await sendLike(target.id);
        if (res.isMatch && mounted) {
          showMatchOverlay(context, res.matchData ??
              {
                'user1': {'uid': uid, 'nick': auth.profile?.nick ?? 'Tú', 'foto': auth.profile?.fotoUrl ?? ''},
                'user2': {'uid': target.id, 'nick': target.nick.isEmpty ? 'Usuario' : target.nick, 'foto': target.fotoUrl},
              });
        }
      }
    } else if (dir == 'up') {
      if (uid == null) {
        showToast(context, i18n.t('swipe.err_login', fallback: 'Debes iniciar sesión para dar un toque'), error: true);
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPing < 5000) {
        showToast(context, i18n.t('swipe.err_wait', fallback: 'Espera unos segundos antes de enviar otro toque'));
        return;
      }
      _lastPing = now;
      try {
        await FirebaseFunctions.instance
            .httpsCallable('sendPing')
            .call({'targetUserId': target.id, 'venueId': widget.myVenueId});
        if (mounted) showToast(context, i18n.t('swipe.ping_sent', fallback: '¡Toque enviado! 🔥'));
      } on FirebaseFunctionsException catch (e) {
        if (!mounted) return;
        if (e.code == 'resource-exhausted') {
          setState(() => _limitExceeded = true);
        } else if (e.code == 'already-exists') {
          showToast(context, i18n.t('swipe.err_already_pinged', fallback: 'Ya has enviado un toque a este usuario hoy'));
        } else {
          showToast(context, e.message ?? i18n.t('swipe.err_ping', fallback: 'Error al enviar el toque'), error: true);
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _cards.removeWhere((c) => c.id == target.id);
      _drag = Offset.zero;
      _photo = 0;
    });
    widget.onSwipe(target.id, dir);
  }

  @override
  Widget build(BuildContext context) {
    if (_limitExceeded) return _limitModal(context);
    if (_cards.isEmpty) {
      return Center(child: Label(context.t('swipe.no_more_profiles'), color: Tw.slate500, weight: bold));
    }
    return LayoutBuilder(builder: (context, box) {
      return Stack(alignment: Alignment.center, children: [
        for (var i = 0; i < _cards.length; i++) _card(context, _cards[i], i == _cards.length - 1, box),
      ]);
    });
  }

  Widget _card(BuildContext context, UserProfile c, bool front, BoxConstraints box) {
    final photos = [c.fotoUrl, ...c.extraPhotos].where((s) => s.isNotEmpty).toList();
    final active = front ? (photos.isNotEmpty ? photos[_photo.clamp(0, photos.length - 1)] : c.fotoUrl) : c.fotoUrl;
    final w = (box.maxWidth - 32).clamp(0.0, 384.0);
    final h = box.maxHeight - 16;

    Widget card = Container(
      width: w,
      height: h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Tw.slate900,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Tw.w(0.1)),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 25))],
      ),
      child: Stack(fit: StackFit.expand, children: [
        NetImage(active),
        if (front && photos.length > 1)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Row(children: [
              for (var p = 0; p < photos.length; p++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: p == _photo ? Tw.white : Tw.w(0.3),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
            ]),
          ),
        if (front && photos.length > 1)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: h * 0.75,
            child: Row(children: [
              Expanded(child: GestureDetector(onTap: () => setState(() => _photo = (_photo - 1).clamp(0, photos.length - 1)))),
              Expanded(child: GestureDetector(onTap: () => setState(() => _photo = (_photo + 1).clamp(0, photos.length - 1)))),
            ]),
          ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Tw.slate950, Color(0x66020617), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 96,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: GestureDetector(
                onTap: () => showProfileOverlay(context, c.id),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c.nick}${c.edad != null ? ', ${c.edad}' : ''}', style: tw(30, weight: black)),
                  const SizedBox(height: 4),
                  Label(
                    '${roleLabel(c.rol, (k, f) => context.t(k, fallback: f))}  •  ${context.t('swipe.distance')}',
                    color: Tw.slate300,
                  ),
                ]),
              ),
            ),
            Pressable(
              onTap: () => showProfileOverlay(context, c.id),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.w(0.2), border: Border.all(color: Tw.w(0.3))),
                child: const Icon(Icons.info, color: Tw.white, size: 20),
              ),
            ),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _circle(56, Tw.slate900.withValues(alpha: 0.9), Tw.w(0.1), const Icon(Icons.close, color: Tw.red400, size: 26),
                () => _action(c, 'left')),
            const SizedBox(width: 16),
            _circle(48, Tw.slate900.withValues(alpha: 0.9), Tw.amber500.withValues(alpha: 0.4),
                const Icon(Icons.card_giftcard, color: Tw.amber400, size: 20),
                () => openRoute(context, AppRoute.entradas, args: {'gift': c.id})),
            const SizedBox(width: 16),
            Pressable(
              onTap: () => _action(c, 'up'),
              scale: 0.95,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Tw.orange500, Tw.amber500]),
                  border: Border.all(color: const Color(0x80FCD34D)),
                  boxShadow: [BoxShadow(color: Tw.amber500.withValues(alpha: 0.6), blurRadius: 25)],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.local_fire_department, color: Tw.white, size: 30),
                  Label(context.t('swipe.come_here'), size: 8, color: Tw.white),
                ]),
              ),
            ),
            const SizedBox(width: 16),
            _circle(56, Tw.slate900.withValues(alpha: 0.9), Tw.w(0.1), const Icon(Icons.favorite, color: Tw.emerald400, size: 26),
                () => _action(c, 'right')),
          ]),
        ),
      ]),
    );

    if (!front) {
      return Transform.translate(offset: const Offset(0, -20), child: Transform.scale(scale: 0.95, child: card));
    }
    return GestureDetector(
      onPanUpdate: (d) => setState(() => _drag += d.delta),
      onPanEnd: (_) {
        const t = 50;
        if (_drag.dx > t) {
          _action(c, 'right');
        } else if (_drag.dx < -t) {
          _action(c, 'left');
        } else if (_drag.dy < -t) {
          setState(() => _drag = Offset.zero);
          _action(c, 'up');
        } else {
          setState(() => _drag = Offset.zero);
        }
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: _drag == Offset.zero ? 250 : 0),
        transform: Matrix4.identity()
          ..translateByDouble(_drag.dx, 0, 0, 1)
          ..rotateZ(_drag.dx / 1200)
          ..scaleByDouble(_drag == Offset.zero ? 1 : 1.05, _drag == Offset.zero ? 1 : 1.05, 1, 1),
        transformAlignment: Alignment.center,
        child: card,
      ),
    );
  }

  Widget _circle(double size, Color bg, Color border, Widget icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
        scale: 0.95,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
            border: Border.all(color: border),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 20)],
          ),
          child: icon,
        ),
      );

  // Extra pings and the VIP night pass are digital purchases: only while super-admin has moduleAppPremium on (Google
  // Play payments policy); otherwise the free pings come back tomorrow.
  Widget _limitModal(BuildContext context) {
    final selling = context.watch<PlatformSettings>().flag('moduleAppPremium');
    return Container(
        color: Colors.black.withValues(alpha: 0.8),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 384),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Tw.slate900,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Tw.slate700),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🔥', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 16),
            Text(context.t('swipe.limit_title').toUpperCase(), textAlign: TextAlign.center, style: tw(18, weight: black, height: 1.2)),
            const SizedBox(height: 8),
            Text(context.t(selling ? 'swipe.limit_desc' : 'swipe.limit_desc_free'), textAlign: TextAlign.center,
                style: tw(12, weight: medium, color: Tw.slate400)),
            const SizedBox(height: 24),
            if (selling) ...[
            Pressable(
              onTap: _paying ? () {} : () => _checkout('ping_pack'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  color: Tw.slate800,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tw.slate600),
                ),
                child: Row(children: [
                  Expanded(child: Text(context.t('swipe.pack_extra'), style: tw(14, weight: bold))),
                  Text('1,99 €', style: tw(14, weight: black, color: const Color(0xFFFB923C))),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Pressable(
              onTap: _paying ? () {} : () => _checkout('vip_night'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Tw.orange500, Tw.amber500]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Tw.amber500.withValues(alpha: 0.5), blurRadius: 15)],
                ),
                child: Row(children: [
                  Expanded(child: Text(context.t('swipe.pass_unlimited'), style: tw(14, weight: black))),
                  Text('3,99 €', style: tw(14, weight: black)),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            ],
            GestureDetector(
              onTap: () => setState(() => _limitExceeded = false),
              child: Text(context.t('swipe.back_to_radar').toUpperCase(),
                  style: tw(10, weight: bold, color: Tw.slate500, tracking: 0.05, decoration: TextDecoration.underline)),
            ),
          ]),
        ),
      );
  }
}
