import 'package:flutter/material.dart';

import 'common.dart';

/// Port of the web's components/party/Poster.tsx + globals.css (.bn-poster, .bn-shade): a venue's photo when it has
/// one, otherwise a generated poster coloured by the kind of venue, so venues without photos still look alive.
/// Like `.bn-poster-still` (used in lists on the web), the light rays don't spin.
enum PosterKind { club, copas, teal, sun, violet }

const _kindByType = <String, PosterKind>{
  'club': PosterKind.club,
  'event': PosterKind.club,
  'bar': PosterKind.copas,
  'bar-copas': PosterKind.copas,
  'sauna': PosterKind.teal,
  'chiringuito': PosterKind.sun,
};

PosterKind posterKind(String? type) => _kindByType[type ?? ''] ?? PosterKind.violet;

/// --bn-a, --bn-b, --bn-c of each `.bn-poster-<kind>`.
const _palette = <PosterKind, (Color, Color, Color)>{
  PosterKind.club: (Color(0xFFE8318A), Color(0xFFFF5A36), Color(0xFF4A1350)),
  PosterKind.copas: (Color(0xFFFFD23D), Color(0xFFFF5A36), Color(0xFF5A1A2A)),
  PosterKind.teal: (Color(0xFF3DF5C1), Color(0xFFE8318A), Color(0xFF1B2A55)),
  PosterKind.sun: (Color(0xFFFF5A36), Color(0xFFFFD23D), Color(0xFF4A1520)),
  PosterKind.violet: (Color(0xFF9B5CF6), Color(0xFFE8318A), Color(0xFF26124D)),
};

class Poster extends StatelessWidget {
  final String? type;
  final PosterKind? kind;
  final String? imageUrl;
  final double? width;
  final double? height;
  final BorderRadius? radius;

  /// Darkens the bottom so white text reads on it (.bn-shade).
  final bool shade;
  final Widget? child;

  const Poster({
    super.key,
    this.type,
    this.kind,
    this.imageUrl,
    this.width,
    this.height,
    this.radius,
    this.shade = true,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final body = Stack(
      fit: StackFit.expand,
      children: [
        if (hasImage) NetImage(imageUrl, placeholder: _generated()) else _generated(),
        if (shade)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.3, 0.45, 1],
                  colors: [Color(0x400C0516), Color(0x000C0516), Color(0x000C0516), Color(0xEB0C0516)],
                ),
              ),
            ),
          ),
        ?child,
      ],
    );
    return SizedBox(
      width: width,
      height: height,
      child: radius == null ? body : ClipRRect(borderRadius: radius!, child: body),
    );
  }

  Widget _generated() {
    final (a, b, c) = _palette[kind ?? posterKind(type)]!;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.35, -1),
              end: const Alignment(0.35, 1),
              colors: [c, const Color(0xFF12081F)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.84, 0.7),
              radius: 0.85,
              colors: [b, b.withValues(alpha: 0)],
              stops: const [0, 0.62],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.64, -0.76),
              radius: 0.95,
              colors: [a, a.withValues(alpha: 0)],
              stops: const [0, 0.58],
            ),
          ),
        ),
        // The conic light rays (.bn-poster::before), still.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: SweepGradient(
              colors: [
                Color(0x00FFFFFF),
                Color(0x00FFFFFF),
                Color(0x26FFFFFF),
                Color(0x00FFFFFF),
                Color(0x00FFFFFF),
                Color(0x1CFFFFFF),
                Color(0x00FFFFFF),
                Color(0x00FFFFFF),
                Color(0x22FFFFFF),
                Color(0x00FFFFFF),
                Color(0x00FFFFFF),
                Color(0x18FFFFFF),
                Color(0x00FFFFFF),
                Color(0x00FFFFFF),
              ],
              stops: [0, 0.05, 0.061, 0.078, 0.228, 0.239, 0.256, 0.444, 0.456, 0.472, 0.694, 0.706, 0.722, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// Live "vibe" bars (.bn-eq): six bars bouncing in sun -> party.
class LiveBars extends StatefulWidget {
  final double height;
  const LiveBars({super.key, this.height = 34});

  @override
  State<LiveBars> createState() => _LiveBarsState();
}

class _LiveBarsState extends State<LiveBars> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  static const _delays = [0.2, 0.7, 0.4, 0.9, 0.1, 0.5];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _delays.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Container(
              width: 5,
              // 1s ease-in-out alternate, like the CSS animation.
              height: 6 + (widget.height - 6) * _wave((_c.value * 2 + _delays[i]) % 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFD23D), Color(0xFFE8318A)],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  static double _wave(double t) => Curves.easeInOut.transform(t < 1 ? t : 2 - t);
}
