import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Tailwind-like text style: size in px, tracking in em (tracking-widest = 0.1).
/// Big heavy titles use the headings font like the web's `font-party` (Bricolage Grotesque); the rest inherit the
/// theme's text font (Figtree). [party] forces one or the other.
TextStyle tw(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Tw.white,
  double tracking = 0,
  double? height,
  bool uppercase = false,
  FontStyle? style,
  TextDecoration? decoration,
  bool? party,
}) =>
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: tracking * size,
      height: height,
      fontStyle: style,
      decoration: decoration,
      decorationColor: color,
      fontFamily: (party ?? (size >= 18 && weight.value >= 800)) ? AppTheme.partyFont : null,
    );

const black = FontWeight.w900;
const bold = FontWeight.w700;
const semibold = FontWeight.w600;
const medium = FontWeight.w500;

/// Uppercase label, e.g. `text-[10px] font-black uppercase tracking-widest`.
class Label extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final FontWeight weight;
  final double tracking;
  final TextAlign? align;
  final int? maxLines;
  const Label(this.text,
      {super.key,
      this.size = 10,
      this.color = Tw.inkSoft,
      this.weight = black,
      this.tracking = 0.1,
      this.align,
      this.maxLines});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        textAlign: align,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
        style: tw(size, weight: weight, color: color, tracking: tracking),
      );
}

/// `bg-white/5 border border-white/10 rounded-*`
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;
  final Gradient? gradient;
  const GlassCard({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
    this.color,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Tw.panelSoft) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? Tw.line),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Pressable(onTap: onTap!, child: box);
  }
}

/// whileTap scale like framer-motion + haptic like navigator.vibrate(10).
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scale;
  final bool haptic;
  const Pressable({super.key, required this.child, required this.onTap, this.scale = 0.97, this.haptic = false});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        if (widget.haptic) HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

/// Gradient CTA (`bg-gradient-to-r from-fuchsia-600 to-indigo-600`).
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  final double radius;
  final EdgeInsets padding;
  final Gradient gradient;
  final double fontSize;
  final bool expand;
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.loading = false,
    this.radius = 16,
    this.padding = const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
    this.gradient = AppTheme.ctaGradient,
    this.fontSize = 10,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        // .bn-cta: 0 12px 30px -12px rgba(232, 49, 138, 0.7)
        boxShadow: const [BoxShadow(color: Color(0xB3E8318A), blurRadius: 30, spreadRadius: -12, offset: Offset(0, 12))],
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: loading
            ? const [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.white)),
              ]
            : [
                if (icon != null) ...[Icon(icon, size: 16, color: Tw.white), const SizedBox(width: 10)],
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: tw(fontSize, weight: black, tracking: 0.2),
                  ),
                ),
              ],
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: enabled ? Pressable(onTap: onTap!, child: content) : content,
    );
  }
}

/// Square icon button: `w-10 h-10 rounded-xl border border-white/10 bg-white/5`.
class SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color color;
  const SquareIconButton({super.key, required this.icon, required this.onTap, this.size = 40, this.color = Tw.inkSoft});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.95,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Tw.panelSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Tw.line),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
      );
}

/// Blurred colour orb used as page background decoration.
class Orb extends StatelessWidget {
  final Color color;
  final double size;
  const Orb({super.key, required this.color, required this.size});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );
}

/// Network image with the web's gradient placeholder fallback.
class NetImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  const NetImage(this.url, {super.key, this.width, this.height, this.fit = BoxFit.cover, this.placeholder});

  @override
  Widget build(BuildContext context) {
    final fallback = placeholder ?? Container(width: width, height: height, color: Tw.panelSoft);
    if (url == null || url!.isEmpty) return fallback;
    return Image.network(
      url!,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (c, child, p) => p == null ? child : fallback,
    );
  }
}

/// Port of components/ConfirmModal.tsx (`confirm({ message, variant, confirmText })`).
Future<bool> confirmDialog(BuildContext context,
    {required String message, String? confirmText, String? cancelText, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (ctx) => Dialog(
      backgroundColor: Tw.panel,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Tw.line)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(danger ? Icons.warning_amber_rounded : Icons.help_outline,
              size: 36, color: danger ? Tw.red400 : Tw.sun),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: tw(14, weight: medium, color: Tw.inkSoft, height: 1.5)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: Pressable(
                onTap: () => Navigator.of(ctx).pop(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: Tw.panelSoft, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.line)),
                  child: Label(cancelText ?? 'Cancelar', color: Tw.inkSoft, align: TextAlign.center),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Pressable(
                onTap: () => Navigator.of(ctx).pop(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: danger ? Tw.red500 : Tw.party, borderRadius: BorderRadius.circular(16)),
                  child: Label(confirmText ?? 'Confirmar', color: Tw.white, align: TextAlign.center),
                ),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
  return ok == true;
}

void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline,
            color: error ? Tw.red400 : Tw.live, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    ));
}

/// Stripe checkouts and third-party pages open in an in-app browser tab (Custom Tabs / SFSafariViewController):
/// the user never leaves the app and closing the tab returns to the screen that opened it.
/// WhatsApp, mail and Google Maps links keep opening their own apps.
Future<void> openInApp(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);

/// Round call-to-action (`bn-cta w-11 h-11 rounded-full`): sunset -> party with the pink glow.
class CtaCircle extends StatelessWidget {
  final IconData icon;
  final double size;
  const CtaCircle({super.key, required this.icon, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: AppTheme.ctaGradient,
      boxShadow: [BoxShadow(color: Color(0xB3E8318A), blurRadius: 30, spreadRadius: -12, offset: Offset(0, 12))],
    ),
    child: Icon(icon, size: size * 0.45, color: Tw.white),
  );
}

/// The warm glows behind the web's fiesta pages (`bg-party/15` and `bg-sunset/10` blurred blobs).
class PartyGlow extends StatelessWidget {
  final Widget child;
  const PartyGlow({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : 400.0;
      return Stack(
        children: [
          Positioned(
            top: -w * 0.35,
            left: -w * 0.4,
            child: Orb(color: Tw.party.withValues(alpha: 0.2), size: w * 1.1),
          ),
          Positioned(
            top: w * 0.45,
            right: -w * 0.5,
            child: Orb(color: Tw.sunset.withValues(alpha: 0.12), size: w),
          ),
          Positioned.fill(child: child),
        ],
      );
    },
  );
}
