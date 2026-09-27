import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../navigation.dart';
import '../services/social.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Port of components/MatchOverlay.tsx
Future<void> showMatchOverlay(BuildContext context, Map<String, dynamic> matchData) => Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => MatchOverlay(matchData: matchData),
        transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
      ),
    );

class MatchOverlay extends StatefulWidget {
  final Map<String, dynamic> matchData;
  const MatchOverlay({super.key, required this.matchData});

  @override
  State<MatchOverlay> createState() => _MatchOverlayState();
}

class _MatchOverlayState extends State<MatchOverlay> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
  late final _loop = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  Map<String, dynamic> _user(String k) {
    final u = widget.matchData[k];
    return u is Map ? Map<String, dynamic>.from(u) : const {};
  }

  Future<void> _goToChat() async {
    final u1 = _user('user1')['uid'] as String?;
    final u2 = _user('user2')['uid'] as String?;
    if (u1 == null || u2 == null) return;
    final chatId = await getOrCreateChat(u1, u2);
    if (!mounted) return;
    openRoute(context, AppRoute.chatDetail, args: {'id': chatId}, replace: true);
  }

  double _seg(double start, double end) => ((_intro.value * 1.8 - start) / (end - start)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final isSuper = widget.matchData['isSuperLike'] == true;
    final accent = isSuper ? Tw.amber400 : Tw.fuchsia500;
    return Scaffold(
      backgroundColor: Tw.slate950.withValues(alpha: 0.98),
      body: AnimatedBuilder(
        animation: Listenable.merge([_intro, _loop]),
        builder: (context, _) {
          final pulse = math.sin(_loop.value * 2 * math.pi) * 0.5 + 0.5;
          final title = Curves.elasticOut.transform(_seg(0.3, 1.0));
          final left = Curves.easeOutBack.transform(_seg(0.4, 1.1));
          final right = Curves.easeOutBack.transform(_seg(0.6, 1.3));
          final heart = Curves.elasticOut.transform(_seg(1.0, 1.6));
          final buttons = _seg(1.5, 1.8);
          return Stack(alignment: Alignment.center, children: [
            Orb(color: accent.withValues(alpha: 0.2 + 0.3 * pulse), size: 600 * (1 + 0.4 * pulse)),
            for (var i = 0; i < 40; i++) _particle(i, isSuper),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Opacity(
                    opacity: title.clamp(0, 1),
                    child: Transform.scale(
                      scale: 0.5 + 0.5 * title,
                      child: Column(children: [
                        ShaderMask(
                          shaderCallback: (r) => LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isSuper
                                ? const [Color(0xFFFEF08A), Tw.amber400, Color(0xFFA16207)]
                                : const [Tw.white, Tw.fuchsia400, Tw.fuchsia600],
                          ).createShader(r),
                          child: Text(isSuper ? 'SUPER MATCH' : 'MATCH!',
                              textAlign: TextAlign.center,
                              style: tw(56, weight: black, style: FontStyle.italic, tracking: -0.05, height: 0.9)),
                        ),
                        const SizedBox(height: 8),
                        Label(context.t('match.connected'), color: Tw.w(0.6), tracking: 0.5, align: TextAlign.center),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    height: 180,
                    child: Stack(alignment: Alignment.center, children: [
                      Transform.scale(
                        scale: 1 + 0.5 * _loop.value,
                        child: Opacity(
                          opacity: (0.5 * (1 - _loop.value)).clamp(0, 1),
                          child: Container(
                            width: 192,
                            height: 192,
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent, width: 2)),
                          ),
                        ),
                      ),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Transform.translate(
                          offset: Offset(-40 + 60 * left, 0),
                          child: Transform.rotate(angle: (-12 + 6 * left) * math.pi / 180, child: _photo(_user('user1')['foto'])),
                        ),
                        Transform.translate(
                          offset: Offset(40 - 60 * right, 0),
                          child: Transform.rotate(angle: (12 - 6 * right) * math.pi / 180, child: _photo(_user('user2')['foto'])),
                        ),
                      ]),
                      Transform.scale(
                        scale: heart,
                        child: Transform.rotate(
                          angle: (1 - heart) * -math.pi,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Tw.slate950, width: 6),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isSuper ? const [Tw.amber400, Color(0xFFEA580C)] : const [Tw.fuchsia500, Tw.purple600],
                              ),
                            ),
                            child: Icon(isSuper ? Icons.star : Icons.favorite, color: Tw.white, size: 44 * (1 + 0.15 * pulse)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 48),
                  Opacity(
                    opacity: buttons,
                    child: Transform.translate(
                      offset: Offset(0, 30 * (1 - buttons)),
                      child: Column(children: [
                        _pill(
                          label: context.t('match.chat_now'),
                          bg: isSuper ? Tw.amber500 : Tw.white,
                          fg: Tw.black,
                          tracking: 0.3,
                          onTap: _goToChat,
                        ),
                        const SizedBox(height: 12),
                        _pill(
                          label: '🍹 ${context.t('match.gift_drink', fallback: 'Invitar a una copa')}',
                          bg: isSuper ? Tw.orange500 : Tw.fuchsia600,
                          fg: Tw.white,
                          tracking: 0.1,
                          onTap: () {
                            openRoute(context, AppRoute.barGift, args: {'giftNick': '${_user('user2')['nick'] ?? ''}'});
                            Navigator.of(context).pop();
                          },
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Label(context.t('match.maybe_later'), color: Tw.w(0.4), tracking: 0.4),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _particle(int i, bool isSuper) {
    final delay = ((i * 11) % 100) / 100;
    final t = ((_loop.value - delay / 4) % 1.0);
    final dist = (250 + ((i * 17) % 100) / 100 * 150) * Curves.easeOut.transform(t);
    final angle = i * 9 * math.pi / 180;
    final scale = t < 0.3 ? t / 0.3 * 1.2 : 1.2 * (1 - (t - 0.3) / 0.7);
    final color = switch (i % 4) {
      0 => isSuper ? Tw.amber400 : Tw.fuchsia500,
      1 => Tw.white,
      2 => isSuper ? Tw.orange500 : Tw.indigo500,
      _ => Tw.cyan400,
    };
    return Transform.translate(
      offset: Offset(math.cos(angle) * dist, math.sin(angle) * dist),
      child: Transform.scale(
        scale: scale.clamp(0, 2),
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.6),
            boxShadow: [BoxShadow(color: color, blurRadius: 15)],
          ),
        ),
      ),
    );
  }

  Widget _photo(Object? url) => Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(48),
          border: Border.all(color: Tw.white, width: 6),
          boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 60, offset: Offset(0, 30))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(42),
          child: NetImage(url as String?, placeholder: Container(color: Tw.slate800)),
        ),
      );

  Widget _pill({required String label, required Color bg, required Color fg, required double tracking, required VoidCallback onTap}) =>
      Pressable(
        onTap: onTap,
        scale: 0.95,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(40)),
          child: Text(label.toUpperCase(), textAlign: TextAlign.center, style: tw(14, weight: black, color: fg, tracking: tracking)),
        ),
      );
}
