import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common.dart';

/// Shared blocks for the web's marketing landings (business, partners, pr/join, investors).

/// Fixed blurred colour blobs behind the page (`fixed inset-0 ... blur-[160px] rounded-full`).
class AmbientGlow extends StatelessWidget {
  final List<Color> colors;
  const AmbientGlow({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final spots = [Alignment(-1.2, -1.1), Alignment(1.3, -0.3), Alignment(-0.2, 1.2)];
    return IgnorePointer(
      child: Stack(children: [
        for (var i = 0; i < colors.length && i < spots.length; i++)
          Align(
            alignment: spots[i],
            child: Container(
              width: size.width * 0.6,
              height: size.width * 0.6,
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: colors[i], blurRadius: 160, spreadRadius: 40)]),
            ),
          ),
      ]),
    );
  }
}

/// `bg-clip-text text-transparent bg-gradient-to-r from-X to-Y`.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final List<Color> colors;
  final TextAlign align;
  const GradientText(this.text, {super.key, required this.style, required this.colors, this.align = TextAlign.center});

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(colors: colors).createShader(r),
        child: Text(text, textAlign: align, style: style),
      );
}

/// Rounded uppercase pill with icon (hero badges).
class PillBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const PillBadge({super.key, required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Flexible(child: Label(text, size: 11, color: color, align: TextAlign.center)),
        ]),
      );
}

/// Section heading + subtitle, centred.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SectionHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(title, textAlign: TextAlign.center, style: tw(28, weight: black, height: 1.15, tracking: -0.02)),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          Text(subtitle!, textAlign: TextAlign.center, style: tw(14, color: Tw.slate400, height: 1.6)),
        ],
      ]);
}

/// Gradient feature card: icon tile + title + description.
class FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  const FeatureCard({super.key, required this.icon, required this.color, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.05)]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 16),
          Text(title, style: tw(18, weight: bold)),
          const SizedBox(height: 8),
          Text(desc, style: tw(14, color: Tw.slate300, height: 1.6)),
        ]),
      );
}

/// Numbered step card (`01`, `02`...).
class StepCard extends StatelessWidget {
  final String step;
  final String title;
  final String desc;
  final Color color;
  const StepCard({super.key, required this.step, required this.title, required this.desc, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(step, style: tw(36, weight: black, color: color)),
          const SizedBox(height: 12),
          Text(title, style: tw(18, weight: bold)),
          const SizedBox(height: 8),
          Text(desc, style: tw(14, color: Tw.slate400, height: 1.6)),
        ]),
      );
}

/// Check-mark bullet row.
class CheckItem extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  const CheckItem(this.text, {super.key, this.color = Tw.emerald400, this.textColor = Tw.slate300});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.check_circle, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: tw(14, color: textColor))),
        ]),
      );
}

/// Big CTA button (gradient or tinted outline), full width on mobile.
class CtaButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final IconData? leadingIcon;
  final List<Color>? gradient;
  final Color? tint;
  final VoidCallback onTap;
  const CtaButton({super.key, required this.label, this.icon, this.leadingIcon, this.gradient, this.tint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = tint;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          gradient: gradient != null ? LinearGradient(colors: gradient!) : null,
          color: t?.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: t != null ? Border.all(color: t.withValues(alpha: 0.3)) : null,
          boxShadow: gradient != null ? [BoxShadow(color: gradient!.first.withValues(alpha: 0.25), blurRadius: 24)] : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (leadingIcon != null) ...[Icon(leadingIcon, size: 16, color: t ?? Tw.white), const SizedBox(width: 8)],
          Flexible(child: Label(label, size: 13, color: t != null ? Color.lerp(t, Tw.white, 0.4)! : Tw.white, align: TextAlign.center)),
          if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 16, color: t ?? Tw.white)],
        ]),
      ),
    );
  }
}

/// Fixed top navbar used by the marketing landings (back + logo + brand + CTA).
class MarketingNav extends StatelessWidget {
  final double top;
  final IconData icon;
  final List<Color> gradient;
  final String brand;
  final List<Color> brandColors;
  final String cta;
  final VoidCallback onCta;
  const MarketingNav({
    super.key,
    required this.top,
    required this.icon,
    required this.gradient,
    required this.brand,
    required this.brandColors,
    required this.cta,
    required this.onCta,
  });

  @override
  Widget build(BuildContext context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.fromLTRB(8, top + 12, 16, 12),
          decoration: BoxDecoration(color: Tw.slate950.withValues(alpha: 0.85), border: Border(bottom: BorderSide(color: Tw.w(0.1)))),
          child: Row(children: [
            IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(gradient: LinearGradient(colors: gradient), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 18, color: Tw.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(children: [
                  Text('BlowNights ', style: tw(18, weight: black)),
                  GradientText(brand, style: tw(18, weight: black), colors: brandColors),
                ]),
              ),
            ),
            Pressable(
              onTap: onCta,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(gradient: LinearGradient(colors: gradient), borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Label(cta, size: 11, color: Tw.white),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, size: 14, color: Tw.white),
                ]),
              ),
            ),
          ]),
        ),
      );
}
