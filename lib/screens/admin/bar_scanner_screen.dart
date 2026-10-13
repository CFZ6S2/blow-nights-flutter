import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/nfc_pass.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import 'scanner_screens.dart' show QrCamera, nfcPassEmpty, scanFeedback;

String _now() {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

/// Port of app/bar/scanner/page.tsx ("SCAN & POUR": redeem drink entitlements by dynamic QR, NFC or keyboard-wedge gun).
/// On Android it also reads the customer's phone by NFC (services/nfc_pass.dart): the drink's own QR code.
class BarScannerScreen extends StatefulWidget {
  final String venueId;
  const BarScannerScreen({super.key, required this.venueId});

  @override
  State<BarScannerScreen> createState() => _BarScannerScreenState();
}

class _BarScannerScreenState extends State<BarScannerScreen> {
  ({String status, String? productName, num? price, String message, String timestamp})? _result;
  bool _scanning = false;
  int _served = 0;
  final _manual = TextEditingController();
  bool _camera = false;
  String _point = 'barra-1';
  String _last = '';
  String _buffer = '';
  DateTime _lastKey = DateTime.now();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    if (NfcPass.available) {
      NfcPass.read(
        (code) => _scan(code, method: 'nfc'),
        onEmpty: () => nfcPassEmpty(context, drink: true),
      ).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    if (NfcPass.available) NfcPass.stop();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _manual.dispose();
    super.dispose();
  }

  /// Keyboard-wedge scanners type fast and end with Enter (same 100ms buffer as the web listener).
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final now = DateTime.now();
    if (now.difference(_lastKey).inMilliseconds > 100) _buffer = '';
    _lastKey = now;
    if (e.logicalKey == LogicalKeyboardKey.enter) {
      if (_buffer.length >= 4) {
        _scan(_buffer);
        _buffer = '';
      }
    } else if (e.character != null && e.character!.length == 1) {
      _buffer += e.character!;
    }
    return false;
  }

  /// [method] says how the code arrived when the code itself doesn't ('nfc' for a phone tapped on this one).
  Future<void> _scan(String payload, {String? method}) async {
    final clean = payload.trim();
    if (clean.isEmpty || _scanning || clean == _last) return;
    _last = clean;
    setState(() => _scanning = true);
    try {
      Map<String, dynamic> data;
      try {
        data = await callFn('redeemConsumptionEntitlement', {
          // Only the customer's dynamic QR (no PIN since 2026-10-13).
          'token': clean,
          'venueId': widget.venueId,
          'terminalId': 'scanner_web_${context.read<AuthProvider>().user?.uid ?? 'anon'}',
          'redemptionPoint': _point,
          'scanMethod': method ?? 'qr',
        }).timeout(const Duration(seconds: 4), onTimeout: () => throw Exception('Red inestable: Tiempo de espera agotado. Verifica la conexión y reintenta.'));
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'not-found' || (e.message ?? '').contains('NOT_FOUND')) {
          data = await callFn('redeemConsumptionTicket', {'code': clean, 'qrPayload': clean, 'venueId': widget.venueId, 'redemptionPoint': _point});
        } else {
          rethrow;
        }
      }

      if (data['success'] != true && data['status'] == 'already_used') {
        scanFeedback(false);
        final t = (data['ticket'] ?? data['entitlement']) as Map?;
        setState(() => _result = (
              status: 'already_redeemed',
              productName: t?['productName'] as String?,
              price: (data['ticket'] as Map?)?['price'] as num?,
              message: (data['message'] as String?) ?? 'Esta consumición ya fue servida',
              timestamp: _now(),
            ));
        return;
      }
      final item = Map<String, dynamic>.from((data['entitlement'] ?? data['ticket'] ?? data) as Map);
      scanFeedback(true);
      final name = (item['productName'] as String?) ?? 'Consumición';
      final face = item['faceValueCents'] as num?;
      setState(() {
        _served++;
        _result = (
          status: 'success',
          productName: name,
          price: (item['price'] as num?) ?? (face != null ? face / 100 : null),
          message: '$name${item['selectedMixer'] != null ? ' + ${item['selectedMixer']}' : ''}${item['isPremium'] == true ? ' (PREMIUM)' : ''}',
          timestamp: _now(),
        );
      });
    } catch (e) {
      scanFeedback(false);
      final details = e is FirebaseFunctionsException && e.details is Map ? (e.details as Map)['reason'] as String? : null;
      final msg = details ?? errorMessage(e, 'Error al validar ticket').replaceFirst('Exception: ', '');
      final friendly = [
        ('CASHLESS_CLOSED', 'Barra digital cerrada en este local'),
        ('UNAUTHORIZED_TERMINAL', 'No tienes permisos de barra en este local'),
        ('ALREADY_REDEEMED', 'Esta consumición ya fue servida'),
        ('PRESENCE_REQUIRED', 'Este local exige entrada por puerta: el cliente no tiene la entrada validada'),
        ('PRESENCE_EXPIRED', 'La entrada del cliente se validó hace más de 12 horas'),
        ('EXPIRED', 'Consumición caducada'),
        ('VENUE_MISMATCH', 'Esta consumición pertenece a otro local'),
        ('INVALID_TOKEN', 'QR expirado o inválido (solicita refrescar pantalla)'),
        ('PROOF_REQUIRED', 'Escanea el QR dinámico del móvil del cliente'),
        ('ENTITLEMENT_BLOCKED', 'Consumición bloqueada'),
      ].where((p) => msg.contains(p.$1)).firstOrNull?.$2;
      setState(() => _result = (
            status: msg.contains('ALREADY_REDEEMED') ? 'already_redeemed' : 'error',
            productName: null,
            price: null,
            message: friendly ?? msg,
            timestamp: _now(),
          ));
    } finally {
      if (mounted) setState(() => _scanning = false);
      Future.delayed(const Duration(seconds: 2), () => _last = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.venueId.isEmpty) {
      return Scaffold(
        backgroundColor: Tw.slate950,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 48, color: Tw.red400),
              const SizedBox(height: 16),
              Text('Falta el local', style: tw(20, weight: black)),
              const SizedBox(height: 8),
              Text('Accede al escáner desde el panel de tu local con el parámetro ?venue=ID', textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
            ]),
          ),
        ),
      );
    }
    final r = _result;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(12, top + 12, 16, 12),
          decoration: const BoxDecoration(color: Tw.slate900, border: Border(bottom: BorderSide(color: Tw.slate800))),
          child: Row(children: [
            IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Tw.emerald500.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.qr_code_scanner, color: Tw.emerald400),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('SCAN & POUR', style: tw(16, weight: black)),
                  const SizedBox(width: 8),
                  AdminSelect<String>(
                    dense: true,
                    value: _point,
                    items: const [('barra-1', 'BARRA 1'), ('barra-2', 'BARRA 2'), ('terraza', 'TERRAZA'), ('vip', 'VIP')],
                    onChanged: (v) => setState(() => _point = v ?? _point),
                  ),
                ]),
                Text('Canje de consumiciones', style: tw(11, weight: medium, color: Tw.slate400)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Tw.slate800.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.slate700)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Label('Servidas', weight: bold, tracking: 0),
                Text('$_served', style: tw(18, weight: black, color: Tw.emerald400, height: 1)),
              ]),
            ),
            const SizedBox(width: 12),
            Pressable(
              onTap: () => setState(() => _camera = !_camera),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _camera ? Tw.red500.withValues(alpha: 0.2) : Tw.fuchsia600,
                  borderRadius: BorderRadius.circular(12),
                  border: _camera ? Border.all(color: Tw.red500.withValues(alpha: 0.4)) : null,
                ),
                child: Icon(_camera ? Icons.videocam_off : Icons.photo_camera, color: _camera ? Tw.red400 : Tw.white),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (_camera)
              Container(
                height: 192,
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: Tw.black, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.slate800)),
                child: QrCamera(frameSize: 150, paused: _scanning, onCode: _scan),
              ),
            if (_scanning)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 64),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3), width: 2)),
                child: Column(children: [
                  const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: Tw.fuchsia400)),
                  const SizedBox(height: 12),
                  Text('Validando...', style: tw(14, weight: bold, color: Tw.fuchsia400)),
                ]),
              )
            else if (r != null)
              _resultCard(r)
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.slate800, width: 2)),
                child: Column(children: [
                  const Icon(Icons.qr_code, size: 40, color: Tw.slate500),
                  const SizedBox(height: 16),
                  Text('LISTO PARA ESCANEAR', style: tw(18, weight: black)),
                  const SizedBox(height: 4),
                  Text(
                      NfcPass.reading
                          ? 'Acerca el móvil del cliente a este (NFC) o usa la pistola en su QR dinámico'
                          : 'Acerca la pistola al QR dinámico del móvil del cliente',
                      textAlign: TextAlign.center,
                      style: tw(12, color: Tw.slate500)),
                ]),
              ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _manual,
                  onSubmitted: (v) {
                    if (v.isNotEmpty) {
                      _scan(v);
                      _manual.clear();
                    }
                  },
                  style: tw(14).copyWith(fontFamily: 'monospace'),
                  decoration: adminInputDecoration('Código leído por la pistola', focus: Tw.emerald500).copyWith(fillColor: Tw.slate900),
                ),
              ),
              const SizedBox(width: 8),
              AdminButton(
                label: 'Validar',
                color: Tw.slate800,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                onTap: _scanning
                    ? null
                    : () {
                        if (_manual.text.isNotEmpty) {
                          _scan(_manual.text);
                          _manual.clear();
                        }
                      },
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _resultCard(({String status, String? productName, num? price, String message, String timestamp}) r) {
    final ok = r.status == 'success';
    final color = ok ? Tw.emerald400 : Tw.red400;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: (ok ? const Color(0xFF022C22) : const Color(0xFF450A0A)).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ok ? Tw.emerald500 : Tw.red500, width: 2),
        boxShadow: [BoxShadow(color: (ok ? Tw.emerald500 : Tw.red500).withValues(alpha: 0.2), blurRadius: 30)],
      ),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.4))),
          child: Icon(ok ? Icons.check_circle : Icons.cancel, size: 36, color: color),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
          child: Label(ok ? 'SERVIR AHORA' : 'NO SERVIR', size: 12, color: color),
        ),
        const SizedBox(height: 8),
        if (ok) ...[
          Text(r.productName ?? '', textAlign: TextAlign.center, style: tw(30, weight: black)),
          if (r.price != null) Text('${r.price!.toStringAsFixed(2)}€', style: tw(14, color: const Color(0xFF6EE7B7))),
        ] else
          Text(r.message, textAlign: TextAlign.center, style: tw(18, weight: black)),
        const SizedBox(height: 16),
        Text(r.timestamp, style: tw(10, color: Tw.slate500)),
      ]),
    );
  }
}
