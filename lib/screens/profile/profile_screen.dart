import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../build_info.dart';
import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/platform_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Port of app/[city]/profile/page.tsx
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _db = FirebaseFirestore.instance;
  int _plans = 0, _tickets = 0, _checkins = 0;
  final List<StreamSubscription> _subs = [];
  String? _uid;
  bool _deleting = false;
  bool _hasDoors = false;
  bool _showCreds = false;
  final _credUser = TextEditingController();
  final _credPass = TextEditingController();
  final _credConfirm = TextEditingController();
  bool _credLoading = false;
  String? _credError;
  bool _credSuccess = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_credUser, _credPass, _credConfirm]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthProvider>().user?.uid;
    if (uid == _uid) return;
    _uid = uid;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    if (uid == null) return;
    _subs.add(_db.collection('chills').where('host_uid', isEqualTo: uid).snapshots().listen((s) => setState(() => _plans = s.size), onError: (_) {}));
    _subs.add(_db.collection('tickets').where('userId', isEqualTo: uid).snapshots().listen((s) => setState(() => _tickets = s.size), onError: (_) {}));
    // Door links saved with saveDoorAccess: "Mis puertas" only shows up once there is one.
    _subs.add(_db.collection('users').doc(uid).collection('doors').limit(1).snapshots().listen((s) => setState(() => _hasDoors = s.size > 0), onError: (_) {}));
    _subs.add(_db.collection('checkins').where('userId', isEqualTo: uid).snapshots().listen((s) => setState(() => _checkins = s.size), onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _credUser.dispose();
    _credPass.dispose();
    _credConfirm.dispose();
    super.dispose();
  }

  Future<void> _toggleNotifications() async {
    final uid = _uid;
    if (uid == null) return;
    HapticFeedback.mediumImpact();
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await _db.collection('users').doc(uid).update({'fcmToken': token, 'notificationsEnabled': true});
        }
      } else {
        await _db.collection('users').doc(uid).update({'notificationsEnabled': false});
      }
    } catch (_) {}
  }

  Future<void> _saveCredentials() async {
    final i18n = context.read<I18n>();
    setState(() {
      _credError = null;
      _credSuccess = false;
    });
    if (_credUser.text.length < 3) {
      setState(() => _credError = i18n.t('credentials.error_username_short', fallback: 'El usuario debe tener al menos 3 caracteres.'));
      return;
    }
    if (_credPass.text.length < 6) {
      setState(() => _credError = i18n.t('credentials.error_password_short', fallback: 'La contraseña debe tener al menos 6 caracteres.'));
      return;
    }
    if (_credPass.text != _credConfirm.text) {
      setState(() => _credError = i18n.t('credentials.error_mismatch', fallback: 'Las contraseñas no coinciden.'));
      return;
    }
    setState(() => _credLoading = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('setLoginCredentials')
          .call({'username': _credUser.text, 'password': _credPass.text});
      setState(() => _credSuccess = true);
      _credPass.clear();
      _credConfirm.clear();
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showCreds = false;
            _credSuccess = false;
          });
        }
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() => _credError = (e.message ?? '').contains('ya está en uso')
          ? i18n.t('credentials.error_taken', fallback: 'Ese usuario ya está en uso.')
          : i18n.t('credentials.error_generic', fallback: 'Error al guardar las credenciales.'));
    } catch (_) {
      setState(() => _credError = i18n.t('credentials.error_generic', fallback: 'Error al guardar las credenciales.'));
    }
    if (mounted) setState(() => _credLoading = false);
  }

  Future<void> _share() async {
    final i18n = context.read<I18n>();
    await SharePlus.instance.share(ShareParams(title: 'BLOW NIGHTS', text: '${i18n.t('profile.share_text')} $webBase'));
  }

  Future<void> _delete() async {
    final auth = context.read<AuthProvider>();
    final i18n = context.read<I18n>();
    setState(() => _deleting = true);
    try {
      await auth.deleteAccount();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        await auth.logout();
        return;
      }
      if (!mounted) return;
      setState(() => _deleting = false);
      Navigator.of(context).pop();
      showToast(context, i18n.t('profile.delete_error'), error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      Navigator.of(context).pop();
      showToast(context, i18n.t('profile.delete_error'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final p = auth.profile;
    if (auth.loading || p == null) return const _ProfileSkeleton();
    final vip = ['plus', 'black'].contains(p.membershipTier);
    final photos = [p.fotoUrl, ...p.extraPhotos].where((s) => s.isNotEmpty).toList();
    final size = MediaQuery.of(context).size;

    String subtitle() {
      if (p.role == 'rrpp') return context.t('profile.role_promoter');
      if (['admin', 'superadmin', 'cityAdmin', 'venue'].contains(p.role)) return context.t('profile.role_staff');
      final r = p.rol == 'party_only' ? context.t('profile.role_party_only') : p.rol;
      return '$r ${p.intencion.isNotEmpty ? '• ${p.intencion}' : ''}';
    }

    final subtitleColor = p.role == 'rrpp'
        ? Tw.fuchsia400
        : ['admin', 'superadmin', 'cityAdmin', 'venue'].contains(p.role)
            ? Tw.blue400
            : Tw.slate500;

    final menu = <(String, IconData, AppRoute, Color)>[
      (context.t('profile.my_visits', fallback: 'Visitas a mi perfil'), Icons.visibility, AppRoute.visits, Tw.purple400),
      (context.t('profile.my_plans', fallback: 'Mis Chills'), Icons.groups, AppRoute.myPlans, Tw.amber400),
      (context.t('profile.my_tickets', fallback: 'Mis Entradas'), Icons.confirmation_number, AppRoute.tickets, Tw.fuchsia400),
      (context.t('profile.my_chats', fallback: 'Mis Chats'), Icons.chat, AppRoute.chat, Tw.blue400),
      if (context.watch<PlatformSettings>().flag('moduleFriendFinder'))
        (context.t('finder.title'), Icons.bluetooth_searching, AppRoute.friendGroups, Tw.cyan400),
      (context.t('profile.edit_profile', fallback: 'Ajustes'), Icons.settings, AppRoute.setupProfile, const Color(0xFFE2E8F0)),
      if (p.role == 'venueOwner' || p.role == 'admin')
        (context.t('profile.venue_panel', fallback: 'Panel de Local'), Icons.storefront, AppRoute.venueAdmin, Tw.fuchsia400),
      if (p.role == 'door')
        (context.t('profile.staff_scanners', fallback: 'Escáneres del local'), Icons.qr_code_scanner, AppRoute.staffHome, Tw.fuchsia400),
      if (p.role == 'admin')
        (context.t('profile.scan_tickets', fallback: 'Escanear Entradas'), Icons.qr_code_scanner, AppRoute.scanner, Tw.fuchsia400),
      if (p.role == 'rrpp') (context.t('rrpp_panel_title', fallback: 'RRPP independiente'), Icons.confirmation_number, AppRoute.pr, Tw.emerald400),
      if (_hasDoors) (context.t('door_my_doors', fallback: 'Mis puertas'), Icons.qr_code_scanner, AppRoute.door, Tw.teal400),
    ];

    return Scaffold(
      body: Stack(children: [
        Positioned(top: -size.height * 0.1, left: -size.width * 0.2, child: Orb(color: Tw.fuchsia600.withValues(alpha: 0.1), size: size.width * 0.8)),
        Positioned(top: size.height * 0.2, right: -size.width * 0.2, child: Orb(color: Tw.indigo600.withValues(alpha: 0.1), size: size.width * 0.7)),
        SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 128), children: [
            // Header
            Center(
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 128,
                  height: 128,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.fuchsia500, Tw.indigo600]),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3), width: 2),
                    boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.2), blurRadius: 50, offset: const Offset(0, 20))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(35),
                    child: NetImage(p.fotoUrl, placeholder: Container(color: Tw.slate800, child: const Icon(Icons.public, size: 48, color: Tw.slate500))),
                  ),
                ),
                if (vip)
                  Positioned(
                    top: -8,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Tw.amber400, Color(0xFFCA8A04)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.stars, size: 14, color: Tw.black),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              Text('${p.nick}${p.edad != null ? ', ${p.edad}' : ''}', style: tw(30, weight: black, tracking: -0.025)),
              if (p.verified) const Icon(Icons.verified, size: 20, color: Tw.blue500),
              if (vip)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Tw.amber400, Color(0xFFCA8A04)]),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: Tw.amber400.withValues(alpha: 0.4), blurRadius: 15)],
                  ),
                  child: Label(context.t('profile.founder'), size: 8, color: Tw.black, tracking: -0.05),
                ),
            ]),
            const SizedBox(height: 4),
            Label(subtitle(), size: 12, color: subtitleColor, tracking: 0.2, align: TextAlign.center),
            const SizedBox(height: 32),
            // Stats
            Row(
              spacing: 12,
              children: [
                for (final s in [
                  (context.t('profile.plans', fallback: 'Planes'), _plans, Icons.groups, Tw.amber400),
                  (context.t('profile.tickets', fallback: 'Entradas'), _tickets, Icons.confirmation_number, Tw.fuchsia400),
                  (context.t('profile.checkins', fallback: 'Check-ins'), _checkins, Icons.location_on, Tw.emerald400),
                ])
                  Expanded(
                    child: GlassCard(
                      radius: 24,
                      child: Column(children: [
                        Icon(s.$3, size: 20, color: s.$4),
                        const SizedBox(height: 4),
                        Text('${s.$2}', style: tw(20, weight: black)),
                        const SizedBox(height: 4),
                        Label(s.$1, size: 8, color: Tw.slate500, maxLines: 1),
                      ]),
                    ),
                  ),
              ],
            ),
            if (p.cityId != null && p.cityId!.isNotEmpty) ...[
              const SizedBox(height: 32),
              GlassCard(
                radius: 40,
                padding: const EdgeInsets.all(24),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Label(context.t('profile.city'), size: 14, color: Tw.white),
                      const SizedBox(height: 4),
                      Text(context.t('profile.city_permanent', fallback: 'Tu ciudad es permanente'), style: tw(10, color: Tw.slate500)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Tw.fuchsia600,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Tw.fuchsia500),
                      boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.2), blurRadius: 15)],
                    ),
                    child: Label('${p.cityId![0].toUpperCase()}${p.cityId!.substring(1)}', color: Tw.white),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 32),
            // Push notifications
            GlassCard(
              radius: 40,
              padding: const EdgeInsets.all(24),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Label(context.t('profile.push_notifications'), size: 14, color: Tw.white)),
                      const SizedBox(width: 8),
                      _miniPill('FCM', Tw.green400),
                    ]),
                    const SizedBox(height: 4),
                    Text(context.t('profile.push_desc'), style: tw(10, color: Tw.slate500)),
                  ]),
                ),
                const SizedBox(width: 12),
                _Switch(on: p.notificationsEnabled, onTap: _toggleNotifications),
              ]),
            ),
            const SizedBox(height: 32),
            _credentialsSection(context, p.hasLoginCredentials, p.loginUsername),
            const SizedBox(height: 32),
            GradientButton(
              label: context.t('profile.share_app'),
              icon: Icons.share,
              expand: true,
              radius: 40,
              padding: const EdgeInsets.symmetric(vertical: 24),
              onTap: _share,
            ),
            const SizedBox(height: 32),
            // Photos
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Label(context.t('profile.my_photos'), size: 14, color: Tw.slate500, tracking: 0.2)),
              GestureDetector(
                onTap: () => openRoute(context, AppRoute.setupProfile),
                child: Label(context.t('profile.manage'), color: Tw.fuchsia500),
              ),
            ]),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              padding: EdgeInsets.zero,
              children: [
                for (final url in photos)
                  Pressable(
                    onTap: () => _showImage(context, url),
                    scale: 0.95,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Tw.w(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Tw.w(0.1)),
                      ),
                      child: NetImage(url),
                    ),
                  ),
                if (photos.length < 6)
                  Pressable(
                    onTap: () => openRoute(context, AppRoute.setupProfile),
                    child: CustomPaint(
                      painter: _DashedBorder(Tw.w(0.2), 16),
                      child: Container(
                        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16)),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.add_a_photo, size: 20, color: Tw.slate500),
                          const SizedBox(height: 4),
                          Label(context.t('profile.add_photo'), size: 8, color: Tw.slate500, tracking: -0.05),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            for (final m in menu) ...[
              GlassCard(
                onTap: () => openRoute(context, m.$3),
                radius: 24,
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  Icon(m.$2, color: m.$4),
                  const SizedBox(width: 16),
                  Expanded(child: Text(m.$1, style: tw(14, weight: bold, tracking: -0.025))),
                  const Icon(Icons.chevron_right, color: Tw.slate600),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 4),
            Pressable(
              onTap: () async {
                HapticFeedback.heavyImpact();
                await context.read<AuthProvider>().logout();
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Tw.red500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.logout, color: Tw.red500),
                  const SizedBox(width: 16),
                  Text(context.t('profile.logout'), style: tw(14, weight: bold, color: Tw.red500, tracking: -0.025)),
                ]),
              ),
            ),
            const SizedBox(height: 32),
            Pressable(
              onTap: _deleting
                  ? () {}
                  : () {
                      HapticFeedback.heavyImpact();
                      _showDeleteModal(context);
                    },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Tw.w(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Tw.w(0.05)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_deleting ? Icons.sync : Icons.delete_forever, size: 14, color: Tw.slate600),
                  const SizedBox(width: 12),
                  Label(_deleting ? context.t('profile.deleting') : context.t('profile.delete_account'), color: Tw.slate600),
                ]),
              ),
            ),
            // Which build this is (version, commit, build time): to match a report on an APK to its exact commit.
            const SizedBox(height: 24),
            Center(child: SelectableText(BuildInfo.label, style: tw(10, color: Tw.slate600))),
          ]),
        ),
      ]),
    );
  }

  Widget _credentialsSection(BuildContext context, bool active, String? username) {
    final canSave = !_credLoading && _credUser.text.length >= 3 && _credPass.text.length >= 6 && _credPass.text == _credConfirm.text;
    InputDecoration dec(String hint) => InputDecoration(
          hintText: hint,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        );
    return GlassCard(
      radius: 40,
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Label(context.t('credentials.title', fallback: 'Acceso alternativo'), size: 14, color: Tw.white)),
                if (active) ...[const SizedBox(width: 8), _miniPill(context.t('credentials.active', fallback: 'Activo'), Tw.green400)],
              ]),
              const SizedBox(height: 4),
              Text(
                active
                    ? context.t('credentials.current_user', fallback: 'Tu usuario: ') + (username ?? '')
                    : context.t('credentials.description', fallback: 'Crea un usuario y contraseña para acceder desde otro dispositivo.'),
                style: tw(10, color: Tw.slate500),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() {
              _showCreds = !_showCreds;
              _credError = null;
              _credSuccess = false;
            }),
            child: Label(
              _showCreds
                  ? context.t('common.cancel', fallback: 'Cancelar')
                  : active
                      ? context.t('credentials.change', fallback: 'Cambiar')
                      : context.t('credentials.setup', fallback: 'Configurar'),
              color: Tw.fuchsia500,
            ),
          ),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: !_showCreds
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: _credUser,
                      maxLength: 20,
                      style: tw(14),
                      inputFormatters: [
                        TextInputFormatter.withFunction((o, n) {
                          final c = n.text.toLowerCase().replaceAll(RegExp('[^a-z0-9_]'), '');
                          return TextEditingValue(text: c, selection: TextSelection.collapsed(offset: c.length));
                        }),
                      ],
                      decoration: dec(context.t('credentials.username_placeholder', fallback: 'username (letras, números, _)')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _credPass,
                      obscureText: true,
                      style: tw(14),
                      decoration: dec(context.t('credentials.password_placeholder', fallback: 'Contraseña (mín. 6 caracteres)')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _credConfirm,
                      obscureText: true,
                      style: tw(14),
                      decoration: dec(context.t('credentials.confirm_placeholder', fallback: 'Confirmar contraseña')),
                    ),
                    if (_credError != null) ...[
                      const SizedBox(height: 12),
                      Text(_credError!, style: tw(12, color: Tw.red400)),
                    ],
                    if (_credSuccess) ...[
                      const SizedBox(height: 12),
                      Text(context.t('credentials.success', fallback: 'Credenciales guardadas correctamente.'), style: tw(12, color: Tw.green400)),
                    ],
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: canSave ? 1 : 0.5,
                      child: Pressable(
                        onTap: canSave ? _saveCredentials : () {},
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Tw.fuchsia600,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Tw.fuchsia500.withValues(alpha: 0.2), blurRadius: 15)],
                          ),
                          child: _credLoading
                              ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.white)))
                              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  const Icon(Icons.save, size: 14, color: Tw.white),
                                  const SizedBox(width: 8),
                                  Label(context.t('credentials.save', fallback: 'Guardar credenciales'), color: Tw.white, tracking: 0.2),
                                ]),
                        ),
                      ),
                    ),
                  ]),
                ),
        ),
      ]),
    );
  }

  Widget _miniPill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
        child: Label(text, size: 8, color: c, tracking: -0.05),
      );

  void _showImage(BuildContext context, String url) => showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'img',
        barrierColor: Tw.slate950.withValues(alpha: 0.9),
        pageBuilder: (ctx, _, _) => SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Stack(clipBehavior: Clip.none, children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
                  child: ClipRRect(borderRadius: BorderRadius.circular(24), child: NetImage(url, fit: BoxFit.contain)),
                ),
                Positioned(
                  top: -48,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.w(0.1), border: Border.all(color: Tw.w(0.1))),
                      child: const Icon(Icons.close, color: Tw.white),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  void _showDeleteModal(BuildContext context) => showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.8),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => Dialog(
            backgroundColor: Tw.slate900,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(48), side: BorderSide(color: Tw.w(0.1))),
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(color: Tw.red500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(32)),
                  child: const Icon(Icons.warning, color: Tw.red500, size: 36),
                ),
                const SizedBox(height: 32),
                Text(ctx.t('profile.say_goodbye'), textAlign: TextAlign.center, style: tw(24, weight: black, tracking: -0.025)),
                const SizedBox(height: 8),
                Text(ctx.t('profile.delete_desc'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate400, height: 1.6)),
                const SizedBox(height: 32),
                Pressable(
                  onTap: _deleting
                      ? () {}
                      : () {
                          setLocal(() {});
                          _delete();
                        },
                  scale: 0.95,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: const Color(0xFFDC2626).withValues(alpha: 0.2), blurRadius: 50)],
                    ),
                    child: Label(_deleting ? ctx.t('profile.deleting') : ctx.t('profile.yes_delete'), size: 12, color: Tw.white,
                        tracking: 0.2, align: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 12),
                Pressable(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16)),
                    child: Label(ctx.t('profile.no_stay'), size: 12, tracking: 0.2, align: TextAlign.center),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _Switch extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  const _Switch({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 56,
          height: 32,
          decoration: BoxDecoration(color: on ? Tw.fuchsia600 : Tw.slate800, borderRadius: BorderRadius.circular(99)),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Tw.white,
                boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 8)],
              ),
            ),
          ),
        ),
      );
}

class _DashedBorder extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBorder(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
        d += 8;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w, double r = 24}) =>
        Container(height: h, width: w, decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(r)));
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), children: [
          Center(child: box(128, w: 128, r: 40)),
          const SizedBox(height: 16),
          Center(child: box(32, w: 160, r: 12)),
          const SizedBox(height: 8),
          Center(child: box(12, w: 96, r: 4)),
          const SizedBox(height: 32),
          Row(children: [
            Expanded(child: box(96)),
            const SizedBox(width: 12),
            Expanded(child: box(96)),
            const SizedBox(width: 12),
            Expanded(child: box(96)),
          ]),
          const SizedBox(height: 32),
          box(80, r: 40),
          const SizedBox(height: 32),
          for (var i = 0; i < 4; i++) ...[box(64), const SizedBox(height: 12)],
        ]),
      ),
    );
  }
}
