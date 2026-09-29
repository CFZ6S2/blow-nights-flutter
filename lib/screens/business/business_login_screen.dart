import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/address_autocomplete.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import 'rrpp_screens.dart';

const _businessRoles = ['venue', 'venueOwner', 'cityAdmin', 'admin', 'superadmin', 'masterPartner', 'door', 'rrpp'];

AppRoute roleRoute(String? role) => switch (role) {
      'superadmin' => AppRoute.superAdmin,
      'admin' => AppRoute.admin,
      'masterPartner' => AppRoute.masterPartner,
      'cityAdmin' => AppRoute.cityManager,
      'door' => AppRoute.scanner,
      'rrpp' => AppRoute.pr,
      _ => AppRoute.venueAdmin,
    };

/// Port of app/business/login/page.tsx (B2B access: venue self-registration, City Manager application, login).
class BusinessLoginScreen extends StatefulWidget {
  final String? refCode;
  /// 'rrpp' | 'venue' | 'cm' opens that sign-up directly (/business/login?type=…).
  final String? initialType;
  const BusinessLoginScreen({super.key, this.refCode, this.initialType});

  /// sessionStorage 'bn_venue_ref' equivalent (kept for the app session).
  static String? storedRef;

  @override
  State<BusinessLoginScreen> createState() => _BusinessLoginScreenState();
}

class _BusinessLoginScreenState extends State<BusinessLoginScreen> {
  late String _mode = switch (widget.initialType) {
    'rrpp' => 'apply_rrpp',
    'venue' => 'apply_venue',
    'cm' => 'apply_cm',
    _ => 'landing',
  };
  late String _ref;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _venueName = TextEditingController();
  final _venueAddress = TextEditingController();
  final _venueTypeOther = TextEditingController();
  // '' = work the city out from the venue's address (selfRegisterVenue); never Madrid by default.
  String _cityId = '';
  String _venueType = 'club';
  List<Map<String, dynamic>> _cities = [];
  bool _loading = false;
  String _error = '';
  String? _checkedUid;

  I18n get _i18n => context.read<I18n>();

  @override
  void initState() {
    super.initState();
    if (widget.refCode?.isNotEmpty == true) BusinessLoginScreen.storedRef = widget.refCode;
    if (_mode == 'apply_cm' || _mode == 'apply_venue') WidgetsBinding.instance.addPostFrameCallback((_) => _loadCities());
    _ref = widget.refCode?.isNotEmpty == true ? widget.refCode! : (BusinessLoginScreen.storedRef ?? '');
  }

  @override
  void dispose() {
    for (final c in [_email, _password, _confirm, _name, _phone, _venueName, _venueAddress, _venueTypeOther]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final u = auth.user;
    if (u != null && _checkedUid != u.uid) {
      _checkedUid = u.uid;
      _checkAccess(u, auth.role, auth.profile?.data['nick'] as String?);
    }
  }

  // Auto-redirect business roles / venue owners; otherwise prefill the registration.
  Future<void> _checkAccess(User u, String? role, String? nick) async {
    try {
      var r = role;
      r ??= (await u.getIdTokenResult(true)).claims?['role'] as String?;
      if (!mounted) return;
      if (r != null && _businessRoles.contains(r)) {
        openRoute(context, roleRoute(r), replace: true);
        return;
      }
      final owned = await FirebaseFirestore.instance.collection('venues').where('ownerId', isEqualTo: u.uid).get();
      if (!mounted) return;
      if (owned.docs.isNotEmpty) {
        openRoute(context, AppRoute.venueAdmin, replace: true);
        return;
      }
      setState(() {
        if (u.email != null && _email.text.isEmpty) _email.text = u.email!;
        final n = u.displayName ?? nick;
        if (n != null && _name.text.isEmpty) _name.text = n;
      });
    } catch (e) {
      debugPrint('Error verifying business access: $e');
    }
  }

  Future<void> _loadCities() async {
    if (_cities.isNotEmpty) return;
    try {
      final s = await FirebaseFirestore.instance.collection('cities').where('readyForFranchise', isEqualTo: true).get();
      if (mounted) setState(() => _cities = [for (final d in s.docs) {'id': d.id, ...d.data()}]);
    } catch (e) {
      debugPrint('Error fetching cities: $e');
    }
  }

  void _setMode(String m) {
    setState(() {
      _mode = m;
      _error = '';
    });
    if (m == 'apply_cm' || m == 'apply_venue') _loadCities();
  }

  Future<void> _afterAuth(User u) async {
    final role = (await u.getIdTokenResult(true)).claims?['role'] as String?;
    if (!mounted) return;
    if (role != null && _businessRoles.contains(role)) {
      openRoute(context, roleRoute(role), replace: true);
      return;
    }
    final owned = await FirebaseFirestore.instance.collection('venues').where('ownerId', isEqualTo: u.uid).get();
    if (!mounted) return;
    if (owned.docs.isNotEmpty) {
      openRoute(context, AppRoute.venueAdmin, replace: true);
      return;
    }
    _setMode('apply_venue');
    if (u.email != null) _email.text = u.email!;
    if (u.displayName != null) _name.text = u.displayName!;
  }

  Future<void> _google() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await context.read<AuthProvider>().loginWithGoogle();
    } catch (e) {
      if (mounted) setState(() => _error = _i18n.t('business_login_google_error', fallback: 'Error al iniciar sesión con Google.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _emailLogin() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final r = await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      await _afterAuth(r.user!);
    } catch (_) {
      if (mounted) setState(() => _error = _i18n.t('business_login_invalid_credentials', fallback: 'Email o contraseña incorrectos.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final user = context.read<AuthProvider>().user;
    setState(() {
      _loading = true;
      _error = '';
    });
    if (_mode == 'apply_venue' && user == null) {
      if (_password.text.length < 6) {
        setState(() {
          _error = _i18n.t('business_login_password_too_short', fallback: 'La contraseña debe tener al menos 6 caracteres');
          _loading = false;
        });
        return;
      }
      if (_password.text != _confirm.text) {
        setState(() {
          _error = _i18n.t('business_login_password_mismatch', fallback: 'Las contraseñas no coinciden');
          _loading = false;
        });
        return;
      }
    }
    try {
      if (_mode == 'apply_venue') {
        var active = user;
        if (active == null) {
          try {
            final c = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
            await c.user!.updateDisplayName(_name.text);
            active = c.user!;
          } on FirebaseAuthException catch (e) {
            if (e.code != 'email-already-in-use') rethrow;
            try {
              active = (await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text)).user!;
            } catch (_) {
              throw Exception('EMAIL_EXISTS_AUTH_FAILED');
            }
          }
        }
        await callFn('selfRegisterVenue', {
          'name': _name.text.isNotEmpty ? _name.text : (active.displayName ?? _venueName.text),
          'email': active.email ?? _email.text,
          'phone': _phone.text,
          'venueName': _venueName.text,
          'venueAddress': _venueAddress.text,
          'venueType': _venueType == 'other' ? _venueTypeOther.text : _venueType,
          if (_cityId.isNotEmpty) 'cityId': _cityId,
          if (_ref.isNotEmpty) 'referralCode': _ref,
        });
        BusinessLoginScreen.storedRef = null;
        await _afterAuth(active);
        return;
      }
      await callFn('requestPartnerAccess', {
        'name': _name.text,
        'email': _email.text,
        'phone': _phone.text,
        if (_cityId.isNotEmpty) 'cityId': _cityId,
        'type': 'city_manager',
        if (_ref.isNotEmpty) 'referralCode': _ref,
      });
      _setMode('success');
    } catch (e) {
      final s = e.toString();
      final exists = s.contains('EMAIL_EXISTS_AUTH_FAILED') ||
          (e is FirebaseAuthException && (e.code == 'wrong-password' || e.code == 'invalid-credential'));
      if (mounted) {
        setState(() => _error = exists
            ? 'EMAIL_EXISTS_AUTH_FAILED'
            : errorMessage(e, _i18n.t('business_login_apply_error', fallback: 'Error al procesar el registro. Inténtalo de nuevo.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await context.read<AuthProvider>().logout();
    _email.clear();
    _password.clear();
    _name.clear();
    setState(() {
      _error = '';
      _checkedUid = null;
    });
  }

  bool get _applyValid {
    final user = context.read<AuthProvider>().user;
    final common = _name.text.trim().isNotEmpty && (user != null && _mode == 'apply_venue' || _email.text.contains('@')) && _phone.text.trim().isNotEmpty;
    if (_mode == 'apply_cm') return common && _cityId.isNotEmpty;
    final pw = user != null || (_password.text.isNotEmpty && _confirm.text.isNotEmpty);
    return common && _venueName.text.trim().isNotEmpty && _venueAddress.text.trim().isNotEmpty && pw && (_venueType != 'other' || _venueTypeOther.text.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (_mode) {
      'login' => context.t('business_login_subtitle_login', fallback: 'Accede a tu panel de gestión'),
      'apply_venue' => context.t('business_login_subtitle_venue', fallback: 'Registra tu local y accede al instante'),
      'apply_cm' => context.t('business_login_subtitle_cm', fallback: 'Gestiona Blow Nights en tu ciudad'),
      'apply_rrpp' => context.t('business_login_subtitle_rrpp', fallback: 'Pases QR para tus eventos, sin local fijo'),
      'success' => context.t('business_login_subtitle_success', fallback: 'Solicitud enviada correctamente'),
      _ => context.t('business_login_subtitle_landing', fallback: 'La plataforma de ocio nocturno que conecta locales con su público'),
    };
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Stack(children: [
        Positioned(
          top: -120,
          left: -80,
          child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Tw.fuchsia600.withValues(alpha: 0.12), blurRadius: 150, spreadRadius: 60)])),
        ),
        Positioned(
          bottom: -120,
          right: -80,
          child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Tw.indigo600.withValues(alpha: 0.12), blurRadius: 150, spreadRadius: 60)])),
        ),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 48), children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate500)),
            ),
            Center(
              child: Transform.rotate(
                angle: 0.1,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.fuchsia600, Tw.indigo600]),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.2), blurRadius: 30)],
                  ),
                  child: const Icon(Icons.business, size: 40, color: Tw.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Blow Nights ', style: tw(30, weight: black, tracking: -0.03)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: ShaderMask(
                    shaderCallback: (r) => const LinearGradient(colors: [Tw.fuchsia400, Tw.indigo400]).createShader(r),
                    child: Text('Business', style: tw(30, weight: black, tracking: -0.03)),
                  ),
                ),
              ]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: tw(14, weight: medium, color: Tw.slate500)),
            const SizedBox(height: 40),
            switch (_mode) {
              'login' => _login(context),
              'apply_venue' || 'apply_cm' => _applyForm(context),
              'apply_rrpp' => RRPPSignupForm(onBack: () => _setMode('landing')),
              'success' => _success(context),
              _ => _landing(context),
            },
          ]),
        ),
      ]),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(28)}) => Container(
        padding: padding,
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
        child: child,
      );

  Widget _choice(IconData icon, List<Color> grad, String title, String desc, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Pressable(
          onTap: onTap,
          child: _card(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grad), borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, size: 28, color: Tw.white),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: tw(18, weight: black)),
                  const SizedBox(height: 4),
                  Text(desc, style: tw(14, color: Tw.slate400, height: 1.5)),
                ]),
              ),
              const Icon(Icons.arrow_forward, color: Tw.slate600),
            ]),
          ),
        ),
      );

  Widget _landing(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _choice(Icons.business, const [Tw.fuchsia600, Color(0xFF86198F)], context.t('business_login_register_venue', fallback: 'Registrar mi Local'),
            context.t('business_login_register_venue_desc', fallback: 'Discoteca, bar, pub o sala de eventos. Gestión de eventos, ticketing y accesos.'), () => _setMode('apply_venue')),
        _choice(Icons.language, const [Tw.emerald600, Color(0xFF065F46)], context.t('business_login_become_cm', fallback: 'Ser City Manager'),
            context.t('business_login_become_cm_desc', fallback: 'Opera Blow Nights en tu ciudad. Captación de locales, gestión territorial y revenue share.'), () => _setMode('apply_cm')),
        _choice(Icons.confirmation_number, const [Tw.teal500, Color(0xFF115E59)], context.t('business_login_become_rrpp', fallback: 'Soy RRPP independiente'),
            context.t('business_login_become_rrpp_desc', fallback: 'Sin local fijo o con uno que no está en la app. Pases QR a 0,50 € para tus eventos; cobras tú por fuera.'),
            () => _setMode('apply_rrpp')),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Row(children: [
            Expanded(child: Divider(color: Tw.w(0.1))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Label(context.t('business_login_already_have_account', fallback: 'ya tienes cuenta'), color: Tw.slate600),
            ),
            Expanded(child: Divider(color: Tw.w(0.1))),
          ]),
        ),
        Pressable(
          onTap: () => _setMode('login'),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Tw.indigo600.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.indigo500.withValues(alpha: 0.2)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock, size: 16, color: Tw.indigo400),
              const SizedBox(width: 12),
              Label(context.t('business_login_access_panel', fallback: 'Acceder a mi panel'), size: 14, color: const Color(0xFFA5B4FC), tracking: 0.05),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward, size: 16, color: Tw.indigo400),
            ]),
          ),
        ),
      ]);

  Widget _back() => Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => _setMode('landing'),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back, size: 16, color: Tw.slate500),
            const SizedBox(width: 8),
            Label(context.t('business_login_back', fallback: 'Volver'), size: 12, weight: bold, color: Tw.slate500, tracking: 0.05),
          ]),
        ),
      );

  Widget _errorBox(String text) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Tw.red500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.red500.withValues(alpha: 0.2))),
        child: Text(text, textAlign: TextAlign.center, style: tw(12, weight: bold, color: Tw.red400)),
      );

  Widget _field(String label, TextEditingController c, IconData icon, {String? hint, bool obscure = false, TextInputType? kb, bool enabled = true, Color focus = Tw.fuchsia500}) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Label(label, color: Tw.slate500, tracking: 0.2)),
          Opacity(
            opacity: enabled ? 1 : 0.6,
            child: TextField(
              controller: c,
              obscureText: obscure,
              enabled: enabled,
              keyboardType: kb,
              onChanged: (_) => setState(() {}),
              style: tw(14),
              decoration: adminInputDecoration(hint, focus: focus).copyWith(
                fillColor: Tw.w(0.05),
                prefixIcon: Icon(icon, size: 16, color: Tw.slate500),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tw.w(0.1))),
                disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tw.w(0.1))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: focus)),
              ),
            ),
          ),
        ]),
      );

  Widget _googleButton(String label) => Pressable(
        onTap: _loading ? () {} : _google,
        child: Opacity(
          opacity: _loading ? 0.5 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('G', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF4285F4))),
              const SizedBox(width: 12),
              Label(label, size: 14, color: Tw.slate900, tracking: 0.1),
            ]),
          ),
        ),
      );

  Widget _orDivider(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(children: [
          Expanded(child: Divider(color: Tw.w(0.1))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Label(text, color: Tw.slate600)),
          Expanded(child: Divider(color: Tw.w(0.1))),
        ]),
      );

  Widget _login(BuildContext context) => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _back(),
          if (_error.isNotEmpty) _errorBox(_error),
          _field(context.t('business_login_corporate_email', fallback: 'Email Corporativo'), _email, Icons.email,
              hint: 'gerencia@milocal.com', kb: TextInputType.emailAddress, focus: Tw.indigo500),
          _field(context.t('business_login_password', fallback: 'Contraseña'), _password, Icons.lock, hint: '••••••••', obscure: true, focus: Tw.indigo500),
          const SizedBox(height: 16),
          AdminButton(
            label: _loading ? context.t('business_login_verifying', fallback: 'Verificando...') : context.t('business_login_enter', fallback: 'Entrar'),
            icon: Icons.arrow_forward,
            color: Tw.indigo600,
            expand: true,
            fontSize: 14,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onTap: _loading || !_email.text.contains('@') || _password.text.isEmpty ? null : _emailLogin,
          ),
          _orDivider(context.t('business_login_or_continue_with', fallback: 'o continúa con')),
          _googleButton('Google'),
        ]),
      );

  Widget _applyForm(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final venue = _mode == 'apply_venue';
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _back(),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (venue ? Tw.fuchsia600 : Tw.emerald600).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: (venue ? Tw.fuchsia500 : Tw.emerald500).withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Icon(venue ? Icons.business : Icons.language, color: venue ? Tw.fuchsia400 : Tw.emerald400),
            const SizedBox(width: 12),
            Label(venue ? context.t('business_login_register_venue_short', fallback: 'Registrar Local') : context.t('business_login_become_cm', fallback: 'Ser City Manager'),
                size: 14, color: venue ? Tw.fuchsia300 : const Color(0xFF6EE7B7), tracking: 0.05),
          ]),
        ),
        if (venue && user != null)
          Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Tw.fuchsia950.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]), borderRadius: BorderRadius.circular(12)),
                child: Text((user.displayName ?? user.email ?? 'U')[0].toUpperCase(), style: tw(12, weight: black)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Label(context.t('business_login_signed_in_as', fallback: 'Sesión iniciada'), color: Tw.fuchsia400, weight: bold),
                  Text(user.email ?? '', overflow: TextOverflow.ellipsis, style: tw(12, weight: bold)),
                ]),
              ),
              GestureDetector(
                onTap: _signOut,
                child: Row(children: [
                  const Icon(Icons.logout, size: 14, color: Tw.slate400),
                  const SizedBox(width: 6),
                  Text(context.t('business_login_change_account', fallback: 'Cambiar'), style: tw(12, weight: semibold, color: Tw.slate400)),
                ]),
              ),
            ]),
          ),
        if (_error == 'EMAIL_EXISTS_AUTH_FAILED')
          Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Tw.amber500.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.amber500.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(context.t('business_login_email_exists_title', fallback: 'Ya existe una cuenta con este email.'), style: tw(12, weight: bold, color: const Color(0xFFFCD34D))),
              const SizedBox(height: 8),
              Text(
                context.t('business_login_email_exists_desc',
                    fallback: 'Si te registraste con Google, pulsa en continuar con Google. Si usas contraseña, introduce la contraseña habitual de tu cuenta.'),
                style: tw(12, color: Tw.slate300, height: 1.5),
              ),
              const SizedBox(height: 12),
              _googleButton(context.t('business_login_continue_with_google', fallback: 'Continuar con Google')),
            ]),
          )
        else if (_error.isNotEmpty)
          _errorBox(_error),
        if (venue && user == null) ...[
          const SizedBox(height: 24),
          _googleButton(context.t('business_login_continue_with_google', fallback: 'Continuar con Google')),
          _orDivider(context.t('business_login_or_fill_form', fallback: 'o completa el formulario')),
        ],
        if (venue) ...[
          _field(context.t('business_login_venue_name', fallback: 'Nombre del Local'), _venueName, Icons.business,
              hint: context.t('business_login_venue_name_placeholder', fallback: 'Ej: Club Noche, Bar Aurora...')),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Label(context.t('business_login_venue_address', fallback: 'Dirección del Local'), color: Tw.slate500, tracking: 0.2),
              ),
              AddressAutocomplete(
                controller: _venueAddress,
                placeholder: context.t('business_login_venue_address_placeholder', fallback: 'Ej: Calle Gran Vía 42, Madrid'),
                onSelect: (_) => setState(() {}),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Label(context.t('business_login_venue_type', fallback: 'Tipo de Local'), color: Tw.slate500, tracking: 0.2)),
                AdminSelect<String>(
                  value: _venueType,
                  items: [
                    ('club', context.t('business_login_type_club', fallback: 'Discoteca / Club')),
                    ('bar', context.t('business_login_type_bar', fallback: 'Bar / Pub')),
                    ('sauna', context.t('business_login_type_sauna', fallback: 'Sauna')),
                    ('chiringuito', context.t('business_login_type_chiringuito', fallback: 'Chiringuito')),
                    ('cruising', context.t('business_login_type_cruising', fallback: 'Cruising')),
                    ('other', context.t('business_login_type_other', fallback: 'Otro')),
                  ],
                  onChanged: (v) => setState(() => _venueType = v ?? 'club'),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Label(context.t('business_login_city', fallback: 'Ciudad'), color: Tw.slate500, tracking: 0.2)),
                AdminSelect<String>(
                  value: _cityId,
                  items: [
                    ('', context.t('business_login_city_auto')),
                    for (final c in _cities) (c['id'] as String, (c['name'] ?? c['id']) as String),
                    ('other', context.t('business_login_other_city', fallback: 'Otra ciudad / Aún no listada')),
                  ],
                  onChanged: (v) => setState(() => _cityId = v ?? ''),
                ),
              ]),
            ),
          ]),
          if (_venueType == 'other')
            _field(context.t('business_login_type_other_specify', fallback: 'Especifica el tipo'), _venueTypeOther, Icons.business,
                hint: context.t('business_login_type_other_placeholder', fallback: 'Ej: Terraza, Sala de eventos, Rooftop...')),
          _field(context.t('business_login_owner_name', fallback: 'Tu Nombre'), _name, Icons.person,
              hint: context.t('business_login_full_name_placeholder', fallback: 'Nombre completo')),
        ] else
          _field(context.t('business_login_your_name', fallback: 'Tu Nombre'), _name, Icons.person,
              hint: context.t('business_login_full_name_placeholder', fallback: 'Nombre completo')),
        _field(
          context.t('business_login_contact_email', fallback: 'Email de Contacto'),
          _email,
          Icons.email,
          hint: 'gerencia@milocal.com',
          kb: TextInputType.emailAddress,
          enabled: !(venue && user != null),
        ),
        _field(context.t('business_login_phone', fallback: 'Teléfono'), _phone, Icons.phone, hint: '+34 600 000 000', kb: TextInputType.phone),
        if (venue && user == null) ...[
          _field(context.t('business_login_create_password', fallback: 'Crear Contraseña'), _password, Icons.lock, hint: '••••••••', obscure: true),
          _field(context.t('business_login_confirm_password', fallback: 'Confirmar Contraseña'), _confirm, Icons.lock, hint: '••••••••', obscure: true),
        ],
        if (!venue) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Label(context.t('business_login_cm_city', fallback: 'Ciudad que quieres gestionar'), color: Tw.slate500, tracking: 0.2),
          ),
          AdminSelect<String>(
            value: _cityId.isEmpty ? null : _cityId,
            hint: context.t('business_login_select_city', fallback: 'Selecciona una ciudad'),
            items: [
              for (final c in _cities) (c['id'] as String, (c['name'] ?? c['id']) as String),
              ('other', context.t('business_login_other_city', fallback: 'Otra ciudad / Aún no listada')),
            ],
            onChanged: (v) => setState(() => _cityId = v ?? ''),
          ),
        ],
        const SizedBox(height: 20),
        venue
            ? GradientButton(
                label: _loading ? context.t('business_login_processing', fallback: 'Procesando...') : context.t('business_login_register_venue_submit', fallback: 'Registrar Local y Entrar'),
                icon: Icons.arrow_forward,
                expand: true,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(vertical: 16),
                gradient: const LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]),
                onTap: _loading || !_applyValid ? null : _apply,
              )
            : AdminButton(
                label: _loading ? context.t('business_login_processing', fallback: 'Procesando...') : context.t('business_login_submit', fallback: 'Enviar Solicitud'),
                icon: Icons.arrow_forward,
                color: Tw.emerald600,
                expand: true,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(vertical: 16),
                onTap: _loading || !_applyValid ? null : _apply,
              ),
      ]),
    );
  }

  Widget _success(BuildContext context) => _card(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(color: Tw.green500.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, size: 40, color: Tw.green500),
          ),
          const SizedBox(height: 24),
          Text(context.t('business_login_request_received', fallback: 'Solicitud Recibida'), textAlign: TextAlign.center, style: tw(24, weight: black)),
          const SizedBox(height: 12),
          Text(
            context.t('business_login_request_received_desc',
                fallback: 'Hemos recibido tu solicitud. Nuestro equipo la revisará y te contactaremos por email en las próximas 24-48h.'),
            textAlign: TextAlign.center,
            style: tw(14, color: Tw.slate400, height: 1.6),
          ),
          const SizedBox(height: 24),
          AdminButton(
            label: context.t('business_login_back_to_start', fallback: 'Volver al inicio'),
            color: Tw.w(0.05),
            expand: true,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onTap: () => _setMode('landing'),
          ),
        ]),
      );
}
