import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/nfc_reader.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import '../business/rrpp_screens.dart';

const _doorBg = Color(0xFF07080D);
const _doorPanel = Color(0xFF11131F);
const _doorBorder = Color(0xFF23273F);
const _doorRow = Color(0xFF1C1F38);
const _doorRowBorder = Color(0xFF3B3F68);

/// feedbackValid / feedbackInvalid (web: 880Hz beep + 120ms vibration / 220Hz + double vibration).
Future<void> scanFeedback(bool valid) async {
  if (valid) {
    await SystemSound.play(SystemSoundType.click);
    await HapticFeedback.heavyImpact();
  } else {
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.vibrate();
    await Future.delayed(const Duration(milliseconds: 160));
    await HapticFeedback.vibrate();
  }
}

String normalizeScan(String raw) => raw.trim().replaceAll(RegExp(r'[\r\n]+'), '').replaceFirst(RegExp(r'^BN:', caseSensitive: false), '');

/// Serial-number NFC tags are resolved to a QR token first (resolveNFCTag), like the web.
Future<String> resolveNfcToken(String token, String type) async {
  if (type == 'serial') {
    try {
      final res = await callFn('resolveNFCTag', {'tagId': token});
      if (res['success'] == true && res['qrToken'] is String) return res['qrToken'] as String;
    } catch (_) {}
  }
  return token;
}

/// Camera QR reader (jsQR loop equivalent). [onCode] fires once per detection while [paused] is false.
class QrCamera extends StatefulWidget {
  final ValueChanged<String> onCode;
  final bool paused;
  final double frameSize;
  /// Replaces the default "no camera" panel (DoorScreen offers the PIN and the app settings there).
  final Widget Function(BuildContext context, MobileScannerException error)? errorBuilder;
  const QrCamera({super.key, required this.onCode, this.paused = false, this.frameSize = 208, this.errorBuilder});

  @override
  State<QrCamera> createState() => _QrCameraState();
}

class _QrCameraState extends State<QrCamera> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.normal);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (widget.paused) return;
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (value != null && value.isNotEmpty) widget.onCode(value);
          },
          errorBuilder: (context, error) => widget.errorBuilder?.call(context, error) ?? Container(
            color: Colors.black.withValues(alpha: 0.8),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.videocam_off, size: 40, color: Tw.red500),
              const SizedBox(height: 12),
              Text(error.errorDetails?.message ?? context.t('scanner_camera_error', fallback: 'No se pudo acceder a la cámara'),
                  textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
            ]),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: PulseBox(size: widget.frameSize),
          ),
        ),
      ]);
}

/// `w-52 h-52 border-2 border-dashed border-fuchsia-500/60 rounded-2xl animate-pulse` frame.
class PulseBox extends StatefulWidget {
  final double size;
  const PulseBox({super.key, required this.size});

  @override
  State<PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<PulseBox> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.5).animate(_c),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.6), width: 2)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
/// Opens this app's page in the system settings, to allow the camera after denying it.
Future<void> openAppSettings() async {
  if (Platform.isAndroid) {
    await const MethodChannel('blownights/system').invokeMethod('openAppSettings');
  } else {
    await launchUrl(Uri.parse('app-settings:'));
  }
}

/// Port of app/door/page.tsx: tokenised door scanner (no login), camera + NFC + manual PIN.
/// Without a link it lists the doors saved in the account (web: /door with no params).
class DoorScreen extends StatefulWidget {
  final String venueId, eventId, token;
  const DoorScreen({super.key, required this.venueId, required this.eventId, required this.token});

  @override
  State<DoorScreen> createState() => _DoorScreenState();
}

class _DoorScreenState extends State<DoorScreen> {
  bool _authLoading = true;
  bool _authorized = false;
  String _authError = '';
  String _eventTitle = '';
  int _cameraAttempt = 0;
  bool _scanning = true;
  ({String status, String? name, String message})? _result;
  int _count = 0;
  bool _nfcSupported = false;

  I18n get _i18n => context.read<I18n>();

  @override
  void initState() {
    super.initState();
    if (_hasLink) WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  bool get _hasLink => widget.token.isNotEmpty && widget.eventId.isNotEmpty;

  @override
  void dispose() {
    NfcReader.stop();
    super.dispose();
  }

  Future<void> _verify() async {
    if (widget.token.isEmpty || widget.eventId.isEmpty) {
      setState(() {
        _authError = _i18n.t('door_invalid_link', fallback: 'Link inválido. Pide al administrador un link de acceso.');
        _authLoading = false;
      });
      return;
    }
    try {
      final res = await callFn('checkDoorToken', {'eventId': widget.eventId, 'venueId': widget.venueId, 'token': widget.token});
      if (res['valid'] == true) {
        setState(() {
          _authorized = true;
          _eventTitle = (res['title'] as String?) ?? _i18n.t('door_event', fallback: 'Evento');
        });
        _nfcSupported = await NfcReader.start((token, type) async => _handleScan(await resolveNfcToken(token, type)));
        if (mounted) setState(() {});
      } else {
        setState(() => _authError = _i18n.t('door_token_expired', fallback: 'Token de puerta inválido o expirado.'));
      }
    } catch (e) {
      setState(() => _authError = errorMessage(e, _i18n.t('door_error_verifying', fallback: 'Error verificando acceso.')));
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _handleScan(String code) async {
    if (!_scanning) return;
    setState(() => _scanning = false);
    try {
      final res = await callFn('validateTicketByDoorToken', {
        'qrToken': code.trim(),
        'doorAccessToken': widget.token,
        'eventId': widget.eventId,
        'venueId': widget.venueId,
        'scanSource': 'token',
      });
      if (res['valid'] == true) {
        scanFeedback(true);
        setState(() {
          _result = (
            status: 'VALID',
            name: ((res['ticket'] as Map?)?['userName'] as String?) ?? _i18n.t('door_guest', fallback: 'Invitado'),
            message: (res['message'] as String?) ?? _i18n.t('door_access_correct', fallback: 'ACCESO CORRECTO'),
          );
          _count++;
        });
      } else {
        scanFeedback(false);
        final msg = (res['message'] as String?) ?? _i18n.t('door_not_valid', fallback: 'NO VÁLIDA');
        setState(() => _result = (status: msg.contains('YA ESCANEADA') ? 'USED' : 'INVALID', name: null, message: msg));
      }
    } catch (e) {
      scanFeedback(false);
      setState(() => _result = (status: 'INVALID', name: null, message: errorMessage(e, 'ERROR')));
    }
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() {
          _result = null;
          _scanning = true;
        });
      }
    });
  }

  Future<void> _pinDialog() async {
    final ctrl = TextEditingController();
    var validating = false;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Dialog(
            backgroundColor: _doorPanel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _doorBorder)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Tw.fuchsia600.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.pin, color: Tw.fuchsia400),
                ),
                const SizedBox(height: 16),
                Text(ctx.t('door_manual_pin_title', fallback: 'Validación Manual por PIN'), style: tw(18, weight: bold)),
                const SizedBox(height: 4),
                Text(ctx.t('door_manual_pin_desc', fallback: 'Introduce el PIN de 4 dígitos impreso en la entrada del cliente.'),
                    textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setLocal(() {}),
                  style: tw(30, weight: black, color: Tw.fuchsia400, tracking: 0.1).copyWith(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: ctx.t('door_manual_pin_placeholder', fallback: '0000'),
                    hintStyle: tw(30, weight: black, color: Tw.slate700),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.5),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _doorRowBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tw.fuchsia500)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: AdminButton(label: ctx.t('door_close', fallback: 'Cerrar'), color: Tw.w(0.05), textColor: Tw.slate300, expand: true, onTap: () => Navigator.of(ctx).pop()),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AdminButton(
                      label: validating ? '...' : ctx.t('door_validate_pin_btn', fallback: 'Validar PIN'),
                      expand: true,
                      onTap: ctrl.text.length < 4 || validating
                          ? null
                          : () async {
                              setLocal(() => validating = true);
                              await _handleScan(ctrl.text.trim());
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    ctrl.dispose();
  }

  Widget _cameraError(BuildContext context, MobileScannerException error) => Container(
        color: Colors.black.withValues(alpha: 0.85),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam_off, size: 40, color: Tw.amber400),
          const SizedBox(height: 12),
          Text(context.t('door_camera_denied_app', fallback: 'No podemos usar la cámara. Valida con el PIN del pase o permite la cámara en los ajustes de la app.'),
              textAlign: TextAlign.center, style: tw(13, color: Tw.slate300)),
          const SizedBox(height: 16),
          AdminButton(
            label: context.t('door_manual_pin_btn', fallback: 'Entrada Manual / PIN'),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onTap: _pinDialog,
          ),
          const SizedBox(height: 8),
          if (error.errorCode == MobileScannerErrorCode.permissionDenied)
            AdminButton(
              label: context.t('door_open_settings', fallback: 'Abrir ajustes'),
              color: Tw.w(0.05),
              textColor: Tw.slate300,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              onTap: () => openAppSettings().catchError((_) {}),
            ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => setState(() => _cameraAttempt++),
            child: Text(context.t('door_camera_retry', fallback: 'Reintentar cámara'), style: tw(12, weight: bold, color: Tw.fuchsia400)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (!_hasLink) return const MyDoorsScreen();
    if (_authLoading) return const Scaffold(backgroundColor: _doorBg, body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)));
    if (_authError.isNotEmpty || !_authorized) {
      return Scaffold(
        backgroundColor: _doorBg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock, size: 60, color: Tw.red500),
              const SizedBox(height: 16),
              Text(context.t('door_access_denied', fallback: 'Acceso denegado'), style: tw(20, weight: black)),
              const SizedBox(height: 8),
              Text(_authError, textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
            ]),
          ),
        ),
      );
    }
    final r = _result;
    final resultColor = r == null ? Tw.white : r.status == 'VALID' ? Tw.emerald400 : r.status == 'USED' ? Tw.amber400 : Tw.red400;
    final resultBg = r == null
        ? Colors.transparent
        : r.status == 'VALID'
            ? const Color(0xE6022C22)
            : r.status == 'USED'
                ? const Color(0xE6451A03)
                : const Color(0xE6450A0A);

    return Scaffold(
      backgroundColor: _doorBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: _doorPanel, borderRadius: BorderRadius.circular(12), border: Border.all(color: _doorBorder)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Label(context.t('door_access_control', fallback: 'Control de Acceso'), size: 9, color: Tw.fuchsia500, tracking: 0),
                    Text(_eventTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: tw(14, weight: bold)),
                  ]),
                ),
                if (_nfcSupported)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: NfcReader.active ? Tw.emerald500.withValues(alpha: 0.1) : Tw.w(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: NfcReader.active ? Tw.emerald500.withValues(alpha: 0.3) : Tw.w(0.1)),
                    ),
                    child: Icon(Icons.nfc, size: 16, color: NfcReader.active ? Tw.emerald400 : Tw.slate600),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: _doorRow, borderRadius: BorderRadius.circular(8), border: Border.all(color: _doorRowBorder)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Label(context.t('door_validated', fallback: 'Validados'), size: 8, weight: bold, tracking: 0),
                    Text('$_count', style: tw(18, weight: black, color: Tw.emerald400, height: 1)),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(color: Tw.black, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF2B2F52))),
                        child: Stack(fit: StackFit.expand, children: [
                          QrCamera(key: ValueKey(_cameraAttempt), paused: !_scanning, onCode: _handleScan, errorBuilder: _cameraError),
                          if (r != null)
                            Container(
                              color: resultBg,
                              padding: const EdgeInsets.all(24),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(r.status == 'VALID' ? Icons.check_circle : r.status == 'USED' ? Icons.warning : Icons.cancel, size: 60, color: resultColor),
                                const SizedBox(height: 12),
                                Text(r.message.toUpperCase(), textAlign: TextAlign.center, style: tw(24, weight: black)),
                                if (r.name != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.name!, style: tw(16, weight: bold))),
                              ]),
                            ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Pressable(
                    onTap: _pinDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(color: _doorRow, borderRadius: BorderRadius.circular(12), border: Border.all(color: _doorRowBorder)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.pin, size: 16, color: Tw.fuchsia400),
                        const SizedBox(width: 8),
                        Text(context.t('door_manual_pin_btn', fallback: 'Entrada Manual / PIN'), style: tw(12, weight: bold, color: const Color(0xFFE2E8F0))),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            SaveDoorBar(eventId: widget.eventId, venueId: widget.venueId, token: widget.token),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Port of app/scanner/page.tsx: authenticated staff scanner (camera, manual, PDA keyboard-wedge, NFC).
class ScannerScreen extends StatefulWidget {
  final String? mode;
  final String? deviceId;
  const ScannerScreen({super.key, this.mode, this.deviceId});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late String _mode = widget.mode == 'hardware' ? 'hardware' : 'camera';
  bool _cameraOn = false;
  Map<String, dynamic>? _result;
  final _manual = TextEditingController();
  final _hw = TextEditingController();
  final _hwFocus = FocusNode();
  bool _validating = false;
  int _count = 0;
  int? _latency;
  bool _nfcSupported = false;
  Timer? _reset;

  I18n get _i18n => context.read<I18n>();

  @override
  void initState() {
    super.initState();
    NfcReader.supported().then((s) {
      if (mounted) setState(() => _nfcSupported = s);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.user == null || (auth.claims != null && !const ['door', 'venueOwner', 'cityAdmin', 'admin', 'superadmin'].contains(auth.role))) {
        openRoute(context, AppRoute.login, replace: true);
      }
      if (_mode == 'hardware') _hwFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    NfcReader.stop();
    _manual.dispose();
    _hw.dispose();
    _hwFocus.dispose();
    super.dispose();
  }

  Future<void> _validate(String token, String source) async {
    if (token.isEmpty || _validating) return;
    setState(() {
      _validating = true;
      _result = null;
    });
    _reset?.cancel();
    final start = DateTime.now();
    try {
      final res = await callFn('validateTicket', {'qrToken': token.trim(), 'scanSource': source, if (widget.deviceId?.isNotEmpty == true) 'deviceId': widget.deviceId})
          .timeout(const Duration(seconds: 4), onTimeout: () => throw Exception('Red inestable: Tiempo de espera agotado. Verifica la conexión y reintenta.'));
      setState(() {
        _latency = DateTime.now().difference(start).inMilliseconds;
        _result = res;
        if (res['valid'] == true) _count++;
      });
      scanFeedback(res['valid'] == true);
    } catch (e) {
      setState(() {
        _latency = DateTime.now().difference(start).inMilliseconds;
        _result = {'valid': false, 'message': errorMessage(e, _i18n.t('scanner_error_validating', fallback: 'Error al validar')).replaceFirst('Exception: ', ''), 'reason': 'error'};
      });
      scanFeedback(false);
    } finally {
      if (mounted) setState(() => _validating = false);
    }
    if (_mode == 'nfc' || _mode == 'hardware') {
      _reset = Timer(Duration(milliseconds: _mode == 'nfc' ? 2500 : 2000), () {
        if (!mounted) return;
        setState(() => _result = null);
        if (_mode == 'hardware') {
          _hw.clear();
          _hwFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _setMode(String m) async {
    if (m != 'nfc') await NfcReader.stop();
    setState(() {
      if (m != 'camera') _cameraOn = false;
      _mode = m;
      _result = null;
    });
    if (m == 'nfc') {
      await NfcReader.start((token, type) async => _validate(await resolveNfcToken(token, type), 'nfc'));
      if (mounted) setState(() {});
    }
    if (m == 'hardware') _hwFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading || auth.claims == null) {
      return const Scaffold(backgroundColor: Tw.slate950, body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Tw.fuchsia500)));
    }
    final modes = ['camera', 'manual', 'hardware', if (_nfcSupported) 'nfc'];
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 120), children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            const Icon(Icons.qr_code_scanner, color: Tw.fuchsia400),
            const SizedBox(width: 12),
            Expanded(child: Text(context.t('scanner_title'), style: tw(22, weight: black))),
            if (_mode == 'hardware')
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Tw.w(0.1))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Label(context.t('scanner_validated_count', fallback: 'Validados'), size: 8, weight: bold, color: Tw.slate600, tracking: 0),
                  Text('$_count', style: tw(14, weight: black, color: Tw.emerald400, height: 1)),
                ]),
              ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: _latency != null && _latency! > 2000 ? Tw.amber500 : Tw.green500, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(_latency != null ? '${_latency}ms' : '', style: tw(10, weight: bold, color: Tw.slate500)),
          ]),
          Text(context.t('scanner_subtitle'), style: tw(12, color: Tw.slate500)),
          const SizedBox(height: 24),
          Row(children: [
            for (final m in modes) ...[
              Expanded(
                child: Pressable(
                  onTap: () => _setMode(m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _mode == m ? Tw.fuchsia500.withValues(alpha: 0.2) : Tw.w(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _mode == m ? Tw.fuchsia500.withValues(alpha: 0.3) : Tw.w(0.1)),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(
                        switch (m) { 'camera' => Icons.photo_camera, 'manual' => Icons.keyboard, 'nfc' => Icons.nfc, _ => Icons.settings_remote },
                        size: 14,
                        color: _mode == m ? Tw.fuchsia400 : Tw.slate500,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Label(
                          switch (m) { 'camera' => context.t('scanner_camera'), 'manual' => context.t('scanner_manual'), 'nfc' => 'NFC', _ => 'PDA' },
                          color: _mode == m ? Tw.fuchsia400 : Tw.slate500,
                          maxLines: 1,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              if (m != modes.last) const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 24),
          ..._body(context),
        ]),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final r = _result;
    if (_mode == 'camera' && r == null) {
      return [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Tw.black, borderRadius: BorderRadius.circular(24)),
            child: _cameraOn
                ? QrCamera(frameSize: 192, paused: _validating, onCode: (c) => _validate(c, 'camera'))
                : Center(
                    child: AdminButton(
                      icon: Icons.photo_camera,
                      label: context.t('scanner_activate_camera', fallback: 'Activar Cámara'),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      onTap: () => setState(() => _cameraOn = true),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Text(context.t('scanner_camera_hint', fallback: 'Apunta la cámara al código QR de la entrada'), textAlign: TextAlign.center, style: tw(10, color: Tw.slate600)),
      ];
    }
    if (_mode == 'manual' && r == null) {
      return [
        AdminCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.t('scanner_token_label', fallback: 'Token de la entrada'), style: tw(12, weight: bold, color: Tw.slate400)),
            const SizedBox(height: 16),
            TextField(
              controller: _manual,
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) => _validate(v, 'manual'),
              style: tw(14).copyWith(fontFamily: 'monospace'),
              decoration: adminInputDecoration(context.t('scanner_token_placeholder', fallback: 'Pega aquí el token QR del cliente...')),
            ),
            const SizedBox(height: 16),
            AdminButton(
              label: _validating ? context.t('scanner_validating', fallback: 'Validando...') : context.t('scanner_validate_ticket', fallback: 'Validar Entrada'),
              expand: true,
              padding: const EdgeInsets.symmetric(vertical: 16),
              onTap: _manual.text.isEmpty || _validating ? null : () => _validate(_manual.text, 'manual'),
            ),
          ]),
        ),
      ];
    }
    if (_mode == 'nfc' && r == null) {
      return [
        AdminCard(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(Icons.nfc, size: 72, color: Tw.fuchsia500.withValues(alpha: 0.6)),
              if (NfcReader.active)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(color: Tw.emerald500, shape: BoxShape.circle, border: Border.all(color: Tw.slate950, width: 2)),
                  ),
                ),
            ]),
            const SizedBox(height: 24),
            Text(_validating ? context.t('scanner_validating', fallback: 'Validando...') : context.t('scanner_nfc_prompt', fallback: 'Acerca el tag NFC al dispositivo'),
                textAlign: TextAlign.center, style: tw(16, weight: bold, color: Tw.slate400)),
            const SizedBox(height: 8),
            Text(NfcReader.active ? context.t('scanner_nfc_listening', fallback: 'Escuchando NFC...') : context.t('scanner_nfc_starting', fallback: 'Iniciando lector NFC...'),
                style: tw(10, color: Tw.slate600)),
          ]),
        ),
      ];
    }
    if (_mode == 'hardware') {
      return [
        if (r == null)
          AdminCard(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: Column(children: [
              Icon(Icons.qr_code_scanner, size: 72, color: Tw.fuchsia500.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(_validating ? context.t('scanner_validating', fallback: 'Validando...') : context.t('scanner_trigger_prompt', fallback: 'Pulsa el gatillo para escanear'),
                  textAlign: TextAlign.center, style: tw(16, weight: bold, color: Tw.slate400)),
              const SizedBox(height: 8),
              Text.rich(TextSpan(style: tw(10, color: Tw.slate600), children: [
                TextSpan(text: context.t('scanner_pda_mode', fallback: 'Modo PDA / Hardware Scanner')),
                if (widget.deviceId?.isNotEmpty == true) TextSpan(text: '  (${widget.deviceId})', style: tw(10, color: Tw.fuchsia500.withValues(alpha: 0.6))),
              ])),
            ]),
          )
        else
          _bigResult(context, r),
        // Hidden keyboard-wedge input (DataWedge keystrokes + Enter).
        SizedBox(
          height: 1,
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _hw,
              focusNode: _hwFocus,
              keyboardType: TextInputType.none,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (raw) {
                _hw.clear();
                final token = normalizeScan(raw);
                if (token.isNotEmpty) _validate(token, 'hardware');
                _hwFocus.requestFocus();
              },
            ),
          ),
        ),
      ];
    }
    if (_mode == 'nfc' && r != null) return [_bigResult(context, r)];
    if (r == null) return const [];

    final valid = r['valid'] == true;
    final color = valid ? Tw.green400 : Tw.red400;
    final ticket = r['ticket'] is Map ? r['ticket'] as Map : null;
    return [
      Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: (valid ? Tw.green500 : Tw.red500).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(48),
          border: Border.all(color: (valid ? Tw.green500 : Tw.red500).withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: (valid ? Tw.green500 : Tw.red500).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(32)),
              child: Icon(valid ? Icons.check_circle : Icons.cancel, size: 48, color: color),
            ),
          ),
          const SizedBox(height: 24),
          Text(valid ? context.t('scanner_access_granted', fallback: 'ACCESO PERMITIDO') : context.t('scanner_access_denied', fallback: 'ACCESO DENEGADO'),
              textAlign: TextAlign.center, style: tw(20, weight: black, color: color)),
          const SizedBox(height: 8),
          Text('${r['message'] ?? ''}', textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
          if (ticket != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if ((ticket['userPhoto'] as String?)?.isNotEmpty == true) ...[
                  ClipRRect(borderRadius: BorderRadius.circular(16), child: NetImage(ticket['userPhoto'] as String, width: 48, height: 48)),
                  const SizedBox(width: 12),
                ],
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${ticket['userName'] ?? ''}', style: tw(14, weight: black)),
                  Text('${ticket['ticketType'] ?? ''}', style: tw(10, color: Tw.slate500)),
                ]),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          AdminButton(
            label: context.t('scanner_scan_another', fallback: 'Escanear otra entrada'),
            color: Tw.w(0.1),
            expand: true,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onTap: () => setState(() {
              _result = null;
              _manual.clear();
            }),
          ),
        ]),
      ),
    ];
  }

  Widget _bigResult(BuildContext context, Map<String, dynamic> r) {
    final valid = r['valid'] == true;
    final color = valid ? Tw.green400 : Tw.red400;
    final ticket = r['ticket'] is Map ? r['ticket'] as Map : null;
    return Container(
      constraints: const BoxConstraints(minHeight: 320),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: (valid ? Tw.green500 : Tw.red500).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: (valid ? Tw.green500 : Tw.red500).withValues(alpha: 0.2)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(valid ? Icons.check_circle : Icons.cancel, size: 80, color: color),
        const SizedBox(height: 16),
        Text(valid ? context.t('scanner_access_granted', fallback: 'ACCESO PERMITIDO') : context.t('scanner_access_denied', fallback: 'ACCESO DENEGADO'),
            textAlign: TextAlign.center, style: tw(24, weight: black, color: color)),
        const SizedBox(height: 8),
        Text('${r['message'] ?? ''}', textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
        if (ticket != null) ...[
          const SizedBox(height: 16),
          Text('${ticket['userName'] ?? ''}', style: tw(18, weight: bold)),
          Text('${ticket['ticketType'] ?? ''}', style: tw(10, color: Tw.slate500)),
        ],
      ]),
    );
  }
}
