import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctionsException;
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/nfc_pass.dart';
import '../../services/staff_invite.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import '../admin/scanner_screens.dart' show QrCamera;

/// The server's reason (invalid, expired, switched off, full) is worth showing; a network or server failure isn't.
String _reason(BuildContext context, Object e) {
  final fallback = context.t('staff_join.invalid', fallback: 'Esta invitación no es válida o ha caducado. Pide otra al local.');
  const generic = {'internal', 'unavailable', 'unknown', 'deadline-exceeded'};
  if (e is FirebaseFunctionsException && !generic.contains(e.code)) return e.message ?? fallback;
  return fallback;
}

String _scopeLabel(BuildContext context, String s) => s == 'door'
    ? context.t('staff_invite.scope_door', fallback: 'Puerta (entradas)')
    : context.t('staff_invite.scope_bar', fallback: 'Barra (consumiciones)');

/// Port of app/staff/join/page.tsx, plus the way in from the app: scan the venue's QR or tap the owner's phone (NFC).
/// A name is enough: joinVenueStaff creates the staff account and returns a token to sign in with on this phone
/// (functions/modules/staff.js); RootGate then opens the staff home.
class StaffJoinScreen extends StatefulWidget {
  final String invite;
  const StaffJoinScreen({super.key, this.invite = ''});

  @override
  State<StaffJoinScreen> createState() => _StaffJoinScreenState();
}

class _StaffJoinScreenState extends State<StaffJoinScreen> {
  String? _invite;
  Map<String, dynamic>? _info;
  String? _error;
  bool _checking = false;
  bool _joining = false;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    final given = parseStaffInvite(widget.invite);
    if (given != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check(given));
    } else if (NfcPass.available) {
      NfcPass.read((code, _) => _found(code)).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    NfcPass.stop();
    _name.dispose();
    super.dispose();
  }

  void _found(String raw) {
    if (_checking || _info != null) return;
    final invite = parseStaffInvite(raw);
    if (invite == null) {
      showToast(context, context.t('staff_app.not_invite', fallback: 'Eso no es una invitación de personal.'), error: true);
      return;
    }
    _check(invite);
  }

  Future<void> _check(String invite) async {
    setState(() {
      _checking = true;
      _error = null;
      _invite = invite;
    });
    try {
      final info = await callFn('getStaffInvite', {'invite': invite});
      if (!mounted) return;
      if (info['venueId'] is! String) throw Exception();
      await NfcPass.stop();
      setState(() => _info = info);
    } catch (e) {
      if (mounted) {
        setState(() => _error = _reason(context, e));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _join() async {
    final name = _name.text.trim();
    if (_joining || name.length < 2 || _invite == null) return;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final res = await callFn('joinVenueStaff', {'invite': _invite, 'name': name});
      await FirebaseAuth.instance.signInWithCustomToken(res['token'] as String);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _reason(context, e);
          _joining = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final signedIn = context.watch<AuthProvider>().user != null;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.badge, size: 40, color: Tw.fuchsia400),
                const SizedBox(height: 8),
                Text(context.t('staff_join.title', fallback: 'Únete al equipo'), textAlign: TextAlign.center, style: tw(24, weight: black)),
                if (info != null) ...[
                  const SizedBox(height: 4),
                  Text(context.t('staff_join.subtitle', fallback: 'Personal de {{venue}}', params: {'venue': info['venueName'] ?? ''}),
                      textAlign: TextAlign.center, style: tw(14, color: Tw.slate300)),
                ],
                const SizedBox(height: 20),
                if (info == null) ...[
                  Text(context.t('staff_app.scan_or_tap', fallback: 'Escanea el QR del local o acerca tu móvil al del encargado (NFC).'),
                      textAlign: TextAlign.center, style: tw(13, color: Tw.slate400)),
                  const SizedBox(height: 16),
                  // QrCamera fills its box (StackFit.expand): it needs a bounded one inside the scroll view.
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(width: 280, height: 280, child: QrCamera(paused: _checking, onCode: _found, frameSize: 200)),
                    ),
                  ),
                  if (_checking) ...[
                    const SizedBox(height: 12),
                    Text(context.t('staff_join.loading', fallback: 'Comprobando la invitación…'), textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
                  ],
                ] else ...[
                  AdminCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Label(context.t('staff_join.scopes', fallback: 'Podrás escanear:'), color: Tw.slate500),
                      const SizedBox(height: 8),
                      for (final s in [for (final x in (info['scopes'] as List? ?? const [])) '$x'])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            Icon(s == 'door' ? Icons.qr_code_scanner : Icons.local_bar, size: 18, color: Tw.fuchsia400),
                            const SizedBox(width: 8),
                            Text(_scopeLabel(context, s), style: tw(14, weight: bold)),
                          ]),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  FieldLabel(context.t('staff_join.name_label', fallback: 'Tu nombre')),
                  AdminInput(controller: _name, hint: context.t('staff_join.name_placeholder', fallback: 'Ej. Laura'), onSubmitted: (_) => _join()),
                  if (signedIn) ...[
                    const SizedBox(height: 8),
                    Text(context.t('staff_join.session_note', fallback: 'Si hay una sesión abierta en este dispositivo, se cerrará.'),
                        style: tw(11, color: Tw.amber400)),
                  ],
                  const SizedBox(height: 16),
                  AdminButton(label: context.t('staff_join.cta', fallback: 'Entrar'), loading: _joining, expand: true, onTap: _join),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center, style: tw(13, color: Tw.red400)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Port of app/staff/page.tsx: the scanners this staff account may use, for its venue.
class StaffHomeScreen extends StatelessWidget {
  const StaffHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final venueId = auth.claims?['venueId'];
    if (auth.role != 'door' || venueId is! String || venueId.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.t('staff_home.not_staff', fallback: 'Esta pantalla es para el personal de un local. Pide al local un QR de acceso.'),
                textAlign: TextAlign.center, style: tw(14, color: Tw.slate300)),
          ),
        ),
      );
    }
    final scopes = staffScopes(auth.claims);
    Widget tile(String scope, IconData icon, String title, String desc, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GlassCard(
            onTap: onTap,
            radius: 24,
            padding: const EdgeInsets.all(24),
            child: Row(children: [
              Icon(icon, size: 48, color: Tw.fuchsia400),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: tw(20, weight: black)),
                  Text(desc, style: tw(13, color: Tw.slate400)),
                ]),
              ),
            ]),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance.collection('venues').doc(venueId).get(),
                  builder: (context, snap) => Text(
                    context.t('staff_home.title', fallback: 'Personal de {{venue}}', params: {'venue': snap.data?.data()?['name'] ?? ''}),
                    textAlign: TextAlign.center,
                    style: tw(24, weight: black),
                  ),
                ),
                if (auth.user?.displayName?.isNotEmpty == true)
                  Text(auth.user!.displayName!, textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
                const SizedBox(height: 24),
                if (scopes.contains('door'))
                  tile('door', Icons.qr_code_scanner, context.t('staff_home.door', fallback: 'Puerta'),
                      context.t('staff_home.door_desc', fallback: 'Validar entradas'), () => openRoute(context, AppRoute.scanner)),
                if (scopes.contains('bar'))
                  tile('bar', Icons.local_bar, context.t('staff_home.bar', fallback: 'Barra'),
                      context.t('staff_home.bar_desc', fallback: 'Canjear consumiciones'), () => openRoute(context, AppRoute.barScanner, args: {'venue': venueId})),
                TextButton(
                  onPressed: () => context.read<AuthProvider>().logout(),
                  child: Text(context.t('staff_home.logout', fallback: 'Cerrar sesión'), style: tw(13, weight: bold, color: Tw.slate400)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
