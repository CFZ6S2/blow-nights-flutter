import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Port of components/DynamicQR.tsx — `dyn:{ticketId}:{ts}:{hmacSha256Hex}` rotating every 15s.
String dynamicQrValue(String ticketId, String secretKey, [DateTime? now]) {
  final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final payload = '$ticketId:$ts';
  final sig = Hmac(sha256, utf8.encode(secretKey)).convert(utf8.encode(payload));
  return 'dyn:$payload:$sig';
}

class DynamicQR extends StatefulWidget {
  final String ticketId;
  final String? secretKey;
  final String? fallbackToken;
  final double size;
  const DynamicQR({super.key, required this.ticketId, this.secretKey, this.fallbackToken, this.size = 200});

  @override
  State<DynamicQR> createState() => _DynamicQRState();
}

class _DynamicQRState extends State<DynamicQR> with SingleTickerProviderStateMixin {
  static const _period = Duration(seconds: 15);
  String _value = '';
  Timer? _timer;
  late final _progress = AnimationController(vsync: this, duration: _period);
  late final _scan = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _generate();
    if (widget.secretKey != null) _timer = Timer.periodic(_period, (_) => _generate());
  }

  void _generate() {
    final key = widget.secretKey;
    setState(() => _value = key == null ? (widget.fallbackToken ?? '') : dynamicQrValue(widget.ticketId, key));
    if (key != null) _progress.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_value.isEmpty) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(24)),
      );
    }
    final dynamicMode = widget.secretKey != null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Tw.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 25, offset: Offset(0, 10))],
        ),
        child: Stack(children: [
          QrImageView(data: _value, size: widget.size, padding: EdgeInsets.zero, backgroundColor: Tw.white),
          if (dynamicMode)
            AnimatedBuilder(
              animation: _scan,
              builder: (_, _) => Positioned(
                top: widget.size * 0.5 * _scan.value,
                left: 0,
                right: 0,
                height: widget.size * 0.5,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Tw.fuchsia500.withValues(alpha: 0.2), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      if (dynamicMode) ...[
        const SizedBox(height: 24),
        SizedBox(
          width: 192,
          child: AnimatedBuilder(
            animation: _progress,
            builder: (_, _) {
              final remaining = 1 - _progress.value;
              return Column(children: [
                Row(children: [
                  Expanded(child: Label(context.t('dynamic_qr_label', fallback: 'QR Dinámico'), weight: bold, color: Tw.fuchsia400, tracking: 0.05)),
                  Label('${(remaining * 15).ceil()}s', weight: bold, color: Tw.slate500, tracking: 0),
                ]),
                const SizedBox(height: 4),
                Container(
                  height: 4,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(99)),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: remaining,
                      child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Tw.fuchsia500, Tw.indigo500]))),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ],
    ]);
  }
}
