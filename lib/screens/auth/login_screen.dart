import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Port of app/login/page.tsx
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _error = '';
  bool _ageConfirmed = false;
  bool _showUsername = false;
  bool _loginLoading = false;
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _username.addListener(() => setState(() {}));
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _done() {
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _google() async {
    final i18n = context.read<I18n>();
    try {
      await context.read<AuthProvider>().loginWithGoogle();
      _done();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      setState(() => _error = '${i18n.t('login.error_google', fallback: 'Error al iniciar sesión con Google.')} ${e.code.name}');
    } on FirebaseAuthException catch (e) {
      setState(() => _error = '${i18n.t('login.error_google', fallback: 'Error al iniciar sesión con Google.')} ${e.code}');
    }
  }

  Future<void> _apple() async {
    final i18n = context.read<I18n>();
    try {
      await context.read<AuthProvider>().loginWithApple();
      _done();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'web-context-canceled' || e.code == 'canceled') return;
      setState(() => _error = '${i18n.t('login.error_apple', fallback: 'Error al iniciar sesión con Apple.')} ${e.code}');
    }
  }

  Future<void> _usernameLogin() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return;
    final i18n = context.read<I18n>();
    setState(() {
      _loginLoading = true;
      _error = '';
    });
    try {
      await context.read<AuthProvider>().loginWithUsername(_username.text.trim(), _password.text);
      _done();
    } on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? '';
      setState(() => _error = msg.contains('Credenciales')
          ? i18n.t('login.error_credentials', fallback: 'Usuario o contraseña incorrectos.')
          : i18n.t('login.error_generic', fallback: 'Error al iniciar sesión.'));
    } catch (_) {
      setState(() => _error = i18n.t('login.error_generic', fallback: 'Error al iniciar sesión.'));
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: Stack(children: [
        Positioned(top: -size.height * 0.1, left: -size.width * 0.2, child: Orb(color: Tw.fuchsia600.withValues(alpha: 0.2), size: size.width * 0.9)),
        Positioned(bottom: -size.height * 0.1, right: -size.width * 0.2, child: Orb(color: Tw.indigo600.withValues(alpha: 0.2), size: size.width * 0.9)),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.95, end: 1),
                duration: const Duration(milliseconds: 300),
                builder: (_, v, c) => Opacity(opacity: ((v - 0.95) * 20).clamp(0, 1), child: Transform.scale(scale: v, child: c)),
                child: _card(context),
              ),
            ),
          ),
        ),
        if (Navigator.of(context).canPop())
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            ),
          ),
      ]),
    );
  }

  Widget _card(BuildContext context) {
    final enabled = _ageConfirmed;
    return Container(
      constraints: const BoxConstraints(maxWidth: 448),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Tw.w(0.05),
        borderRadius: BorderRadius.circular(48),
        border: Border.all(color: Tw.w(0.1)),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 100, offset: Offset(0, 50))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Transform.rotate(
          angle: 12 * math.pi / 180,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Tw.fuchsia600, Tw.indigo600]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.3), blurRadius: 40, offset: const Offset(0, 20))],
            ),
            child: const Icon(Icons.favorite, color: Tw.white, size: 30),
          ),
        ),
        const SizedBox(height: 28),
        ShaderMask(
          shaderCallback: (r) => AppTheme.wordmarkGradient.createShader(r),
          child: Text('BLOW NIGHTS', style: tw(36, weight: black, tracking: -0.05, color: Tw.white)),
        ),
        const SizedBox(height: 12),
        Label(context.t('login.subtitle'), size: 9, weight: medium, tracking: 0.3, align: TextAlign.center),
        const SizedBox(height: 32),
        if (_error.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Tw.red500.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
            ),
            child: Label(_error, color: Tw.red500, align: TextAlign.center),
          ),
          const SizedBox(height: 32),
        ],
        _ageCheckbox(context),
        const SizedBox(height: 20),
        _SocialButton(
          enabled: enabled,
          background: Tw.white,
          foreground: Tw.black,
          icon: const _GoogleLogo(),
          label: context.t('login.google'),
          onTap: _google,
        ),
        const SizedBox(height: 20),
        _SocialButton(
          enabled: enabled,
          background: Tw.black,
          foreground: Tw.white,
          border: Tw.w(0.1),
          icon: const Icon(Icons.apple, color: Tw.white, size: 22),
          label: context.t('login.apple', fallback: 'Continuar con Apple'),
          onTap: _apple,
        ),
        const SizedBox(height: 20),
        Divider(color: Tw.w(0.1), height: 1),
        const SizedBox(height: 16),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: _showUsername ? _usernameForm(context) : _usernameToggle(context, enabled),
        ),
        const SizedBox(height: 20),
        Divider(color: Tw.w(0.1), height: 1),
        const SizedBox(height: 24),
        Label(context.t('login.pro_question'), weight: bold, align: TextAlign.center),
        const SizedBox(height: 16),
        GlassCard(
          onTap: () => openRoute(context, AppRoute.business),
          radius: 16,
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.storefront, size: 16, color: Tw.indigo400),
            const SizedBox(height: 4),
            Text(context.t('login.pro_venues'), style: tw(12, weight: bold, color: Tw.indigo400)),
          ]),
        ),
        const SizedBox(height: 12),
        GlassCard(
          onTap: () => openRoute(context, AppRoute.staffJoin),
          radius: 16,
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.badge, size: 16, color: Tw.fuchsia400),
            const SizedBox(height: 4),
            Text(context.t('staff_app.entry', fallback: 'Soy personal de un local'), style: tw(12, weight: bold, color: Tw.fuchsia400)),
          ]),
        ),
        const SizedBox(height: 28),
        Opacity(
          opacity: 0.4,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final b in [
              (Icons.shield, context.t('login.badge_secure')),
              (Icons.lock, context.t('login.badge_private')),
              (Icons.verified, context.t('login.badge_real')),
            ])
              Column(children: [
                Icon(b.$1, size: 16),
                const SizedBox(height: 4),
                Label(b.$2, size: 7, color: Tw.white, tracking: -0.05),
              ]),
          ]),
        ),
      ]),
    );
  }

  Widget _ageCheckbox(BuildContext context) {
    final base = tw(10, color: Tw.slate400, height: 1.6);
    return GestureDetector(
      onTap: () => setState(() => _ageConfirmed = !_ageConfirmed),
      behavior: HitTestBehavior.opaque,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: _ageConfirmed ? Tw.fuchsia500 : Tw.w(0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _ageConfirmed ? Tw.fuchsia500 : Tw.w(0.2), width: 2),
          ),
          child: _ageConfirmed ? const Icon(Icons.check, size: 14, color: Tw.white) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(TextSpan(style: base, children: [
            TextSpan(text: '${context.t('login.confirm_age_1')} '),
            TextSpan(text: context.t('login.confirm_age_2'), style: base.copyWith(color: Tw.white, fontWeight: bold)),
            TextSpan(text: ' ${context.t('login.confirm_age_3')} '),
            TextSpan(
              text: context.t('login.terms'),
              style: base.copyWith(color: Tw.fuchsia400, decoration: TextDecoration.underline, decorationColor: Tw.fuchsia400),
              recognizer: TapGestureRecognizer()..onTap = () => openRoute(context, AppRoute.terms),
            ),
            const TextSpan(text: ' y la '),
            TextSpan(
              text: context.t('login.privacy'),
              style: base.copyWith(color: Tw.fuchsia400, decoration: TextDecoration.underline, decorationColor: Tw.fuchsia400),
              recognizer: TapGestureRecognizer()..onTap = () => openRoute(context, AppRoute.privacy),
            ),
            const TextSpan(text: '.'),
          ])),
        ),
      ]),
    );
  }

  Widget _usernameToggle(BuildContext context, bool enabled) => Opacity(
        opacity: enabled ? 1 : 0.3,
        child: GlassCard(
          onTap: enabled ? () => setState(() => _showUsername = true) : null,
          radius: 16,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.person, size: 16, color: Tw.slate300),
            const SizedBox(width: 12),
            Flexible(
              child: Label(context.t('login.username_login', fallback: 'Entrar con usuario y contraseña'),
                  weight: bold, color: Tw.slate300, tracking: 0.15, align: TextAlign.center),
            ),
          ]),
        ),
      );

  Widget _usernameForm(BuildContext context) {
    final canSubmit = !_loginLoading && _username.text.trim().isNotEmpty && _password.text.length >= 6;
    return Column(children: [
      TextField(
        controller: _username,
        maxLength: 20,
        autofillHints: const [AutofillHints.username],
        inputFormatters: [
          TextInputFormatter.withFunction((o, n) {
            final clean = n.text.toLowerCase().replaceAll(RegExp('[^a-z0-9_]'), '');
            return TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
          }),
        ],
        style: tw(14),
        decoration: InputDecoration(hintText: context.t('login.username_placeholder', fallback: 'Tu username'), counterText: ''),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        style: tw(14),
        onSubmitted: (_) => canSubmit ? _usernameLogin() : null,
        decoration: InputDecoration(hintText: context.t('login.password_placeholder', fallback: 'Contraseña')),
      ),
      const SizedBox(height: 12),
      GradientButton(
        label: context.t('login.login_button', fallback: 'Entrar'),
        icon: Icons.login,
        expand: true,
        loading: _loginLoading,
        onTap: canSubmit ? _usernameLogin : null,
      ),
      TextButton(
        onPressed: () => setState(() {
          _showUsername = false;
          _error = '';
        }),
        child: Label(context.t('common.cancel', fallback: 'Cancelar'), color: Tw.slate500, weight: FontWeight.w400),
      ),
    ]);
  }
}

class _SocialButton extends StatelessWidget {
  final bool enabled;
  final Color background;
  final Color foreground;
  final Color? border;
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  const _SocialButton({
    required this.enabled,
    required this.background,
    required this.foreground,
    this.border,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: border != null ? Border.all(color: border!) : null,
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 25, offset: Offset(0, 10))],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 20, height: 20, child: icon),
        const SizedBox(width: 16),
        Flexible(child: Label(label, color: foreground, tracking: 0.2)),
      ]),
    );
    return Opacity(opacity: enabled ? 1 : 0.3, child: enabled ? Pressable(onTap: onTap, child: body) : body);
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GooglePainter());
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48;
    canvas.scale(s);
    final p = Paint()..style = PaintingStyle.fill;
    Path path(List<List<double>> pts) {
      final pa = Path()..moveTo(pts[0][0], pts[0][1]);
      for (final pt in pts.skip(1)) {
        pa.lineTo(pt[0], pt[1]);
      }
      return pa..close();
    }

    // Simplified four-colour G, same palette as the web SVG.
    const c = Offset(24, 24);
    final rect = Rect.fromCircle(center: c, radius: 20);
    p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    p.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -2.4, 1.6, false, p);
    p.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 2.3, 1.6, false, p);
    p.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.6, 1.7, false, p);
    p.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.1, 0.75, false, p);
    p.style = PaintingStyle.fill;
    canvas.drawPath(path([[24, 20], [44, 20], [44, 28], [24, 28]]), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
