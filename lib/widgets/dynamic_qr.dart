import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../i18n/i18n.dart';
import '../services/nfc_pass.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Port of components/DynamicQR.tsx — `dyn:{ticketId}:{ts}:{hmacSha256Hex}` rotating every 15s.
/// On Android the same code is also handed over by NFC while it's on screen (services/nfc_pass.dart).
String dynamicQrValue(String ticketId, String secretKey, [DateTime? now]) {
  final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final payload = '$ticketId:$ts';
  final sig = Hmac(sha256, utf8.encode(secretKey)).convert(utf8.encode(payload));
  return 'dyn:$payload:$sig';
}

/// The only QR that gets anyone in (functions/lib/validateQR.js): never a static code. Without the ticket's key there
/// is no QR to show (founder, 2026-10-13).
class DynamicQR extends StatefulWidget {
  final String ticketId;
  final String? secretKey;
  final double size;
  const DynamicQR({super.key, required this.ticketId, this.secretKey, this.size = 200});

  @override
  State<DynamicQR> createState() => _DynamicQRState();
}

class _DynamicQRState extends State<DynamicQR> with TickerProviderStateMixin {
  static const _period = Duration(seconds: 15);
  String _value = '';
  Timer? _timer;
  late final _progress = AnimationController(vsync: this, duration: _period);
  late final _scan = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant DynamicQR old) {
    super.didUpdateWidget(old);
    if (old.secretKey != widget.secretKey || old.ticketId != widget.ticketId) _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = null;
    if (widget.secretKey == null) {
      _value = '';
      NfcPass.hide(this);
      return;
    }
    _generate();
    _timer = Timer.periodic(_period, (_) => _generate());
  }

  void _generate() {
    final key = widget.secretKey;
    if (key == null) return;
    setState(() => _value = dynamicQrValue(widget.ticketId, key));
    _progress.forward(from: 0);
    NfcPass.show(this, _value);
  }

  @override
  void dispose() {
    NfcPass.hide(this);
    _timer?.cancel();
    _progress.dispose();
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.secretKey == null) {
      return SizedBox(
        width: widget.size,
        child: Text(context.t('dynamic_qr_unavailable', fallback: 'Abre la entrada con conexión para ver el QR.'),
            textAlign: TextAlign.center, style: tw(13, color: Tw.slate400)),
      );
    }
    if (_value.isEmpty) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: Tw.slate800, borderRadius: BorderRadius.circular(24)),
      );
    }
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
      ...[
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
      if (NfcPass.available) const NfcPassHint(),
    ]);
  }
}

/// "You can also tap your phone on the staff's phone (NFC)", under a ticket or drink QR on Android.
class NfcPassHint extends StatelessWidget {
  const NfcPassHint({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.nfc, size: 14, color: Tw.slate400),
          const SizedBox(width: 6),
          Flexible(
            child: Text(context.t('nfc_pass.hint', fallback: 'También puedes acercar tu móvil al del personal (NFC).'),
                textAlign: TextAlign.center, style: tw(11, color: Tw.slate400)),
          ),
        ]),
      );
}
