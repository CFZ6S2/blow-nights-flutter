import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Port of components/LanguageSelector.tsx
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (btnCtx) => SquareIconButton(
        icon: Icons.translate,
        onTap: () => _open(btnCtx),
      ),
    );
  }

  void _open(BuildContext btnCtx) {
    final box = btnCtx.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.of(btnCtx).size;
    final isRtl = Directionality.of(btnCtx) == TextDirection.rtl;
    showGeneralDialog(
      context: btnCtx,
      barrierDismissible: true,
      barrierLabel: 'lang',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, _, _) {
        final i18n = ctx.watch<I18n>();
        return Stack(children: [
          Positioned(
            top: origin.dy + box.size.height + 8,
            left: isRtl ? origin.dx : null,
            right: isRtl ? null : screen.width - origin.dx - box.size.width,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 208,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Tw.slate900.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Tw.w(0.1)),
                  boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 50, offset: Offset(0, 20))],
                ),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  childAspectRatio: 2.6,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    for (final l in appLanguages)
                      _LangTile(
                        lang: l,
                        active: i18n.language == l.code,
                        onTap: () {
                          i18n.changeLanguage(l.code);
                          Navigator.of(ctx).pop();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ]);
      },
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(anim), alignment: Alignment.topRight, child: child),
      ),
    );
  }
}

class _LangTile extends StatelessWidget {
  final AppLanguage lang;
  final bool active;
  final VoidCallback onTap;
  const _LangTile({required this.lang, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? Tw.fuchsia600.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? Tw.fuchsia500.withValues(alpha: 0.3) : Colors.transparent),
          ),
          child: Row(children: [
            Text(lang.flag, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(lang.label, style: tw(12, weight: bold, color: active ? Tw.fuchsia400 : Tw.slate300)),
          ]),
        ),
      );
}
