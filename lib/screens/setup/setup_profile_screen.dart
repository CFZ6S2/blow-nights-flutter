import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/city_provider.dart';
import '../../services/social.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

const citySlugs = ['madrid', 'london', 'barcelona', 'lisboa', 'paris', 'berlin'];

const _appModes = [
  ('party', '🎉', 'mode.party', 'Solo Fiesta', 'mode.party_desc', 'Música, horarios, QRs, amigos'),
  ('social', '💬', 'mode.social', 'Social / Ligar', 'mode.social_desc', 'Conectar con gente, pings, matches'),
  ('both', '🔥', 'mode.both', 'Ambos', 'mode.both_desc', 'Lo mejor de los dos mundos'),
];

int calcularEdad(DateTime nacimiento) {
  final hoy = DateTime.now();
  var edad = hoy.year - nacimiento.year;
  final mesDiff = hoy.month - nacimiento.month;
  if (mesDiff < 0 || (mesDiff == 0 && hoy.day < nacimiento.day)) edad--;
  return edad;
}

/// Mirrors the web's redirect rules (login page + map page) for sending users to /setup-profile.
bool needsProfileSetup(AuthProvider auth) {
  if (auth.user == null) return false;
  if (auth.isAdmin || auth.isCityAdmin) return false;
  const noSetup = {'rrpp', 'venueOwner', 'cityAdmin', 'admin', 'superadmin', 'door', 'masterPartner'};
  if (noSetup.contains(auth.role) || noSetup.contains(auth.profile?.role)) return false;
  final p = auth.profile;
  if (p == null) return true;
  return p.edad == null || (p.fechaNacimiento ?? '').isEmpty || (p.cityId ?? '').isEmpty || p.needsUpdate;
}

/// Port of app/setup-profile/page.tsx
class SetupProfileScreen extends StatefulWidget {
  final bool editing;
  const SetupProfileScreen({super.key, this.editing = false});

  @override
  State<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends State<SetupProfileScreen> {
  final _nick = TextEditingController();
  final _bio = TextEditingController();
  final _altura = TextEditingController();
  final _peso = TextEditingController();
  String _fechaNacimiento = '';
  String _appMode = 'both';
  String _rol = '';
  String _intencion = 'conocer';
  String? _complexion;
  List<String> _intereses = [];
  String? _mood;
  String _city = '';
  File? _imageFile;
  String? _imagePreview;
  final List<File> _extraFiles = [];
  List<String> _extraExisting = [];
  final List<File> _privateFiles = [];
  List<String> _privateExisting = [];
  bool _submitting = false;
  String? _error;
  int _step = 1;
  static const _totalSteps = 3;
  bool _prefilled = false;
  final _scroll = ScrollController();

  bool get _partyOnly => _appMode == 'party';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    final p = context.read<AuthProvider>().profile;
    if (p == null) return;
    _prefilled = true;
    _nick.text = p.nick;
    _fechaNacimiento = p.fechaNacimiento ?? '';
    final mode = p.data['appMode'] as String?;
    if (mode != null) {
      _appMode = mode;
    } else if (p.rol == 'party_only') {
      _appMode = 'party';
    }
    _rol = p.rol;
    _intencion = p.intencion.isNotEmpty ? p.intencion : 'conocer';
    _bio.text = p.bio;
    if (p.altura != null) _altura.text = '${p.altura}';
    if (p.peso != null) _peso.text = '${p.peso}';
    _complexion = p.data['complexion'] as String?;
    _intereses = [...p.intereses];
    _mood = p.mood;
    _imagePreview = p.fotoUrl.isEmpty ? null : p.fotoUrl;
    _extraExisting = [...p.extraPhotos];
    _privateExisting = [...p.privatePhotos];
    if ((p.cityId ?? '').isNotEmpty) _city = p.cityId!;
  }

  @override
  void dispose() {
    for (final c in [_nick, _bio, _altura, _peso]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickMain() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (x != null) setState(() => _imageFile = File(x.path));
  }

  Future<void> _pickMany(List<File> target, int existing) async {
    final xs = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 1600);
    if (xs.isEmpty) return;
    setState(() {
      target.addAll(xs.map((x) => File(x.path)));
      final room = 5 - existing;
      if (target.length > room) target.removeRange(room.clamp(0, target.length), target.length);
    });
  }

  void _next() {
    final i18n = context.read<I18n>();
    if (_step == 1 && _city.isEmpty) {
      setState(() => _error = i18n.t('setup_error_city_required', fallback: 'Debes seleccionar tu ciudad. Es obligatorio y permanente.'));
      return;
    }
    if (_step == 2 && _appMode != 'party' && (_rol.isEmpty || _rol == 'party_only')) {
      setState(() => _error = i18n.t('setup_error_role', fallback: 'Debes elegir tu rol o vibe en Blow Nights.'));
      return;
    }
    setState(() {
      _error = null;
      _step = (_step + 1).clamp(1, _totalSteps);
    });
    _scroll.jumpTo(0);
  }

  void _prev() {
    setState(() => _step = (_step - 1).clamp(1, _totalSteps));
    _scroll.jumpTo(0);
  }

  Future<void> _submit() async {
    final i18n = context.read<I18n>();
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    if (_nick.text.isEmpty || _fechaNacimiento.isEmpty || (_imageFile == null && _imagePreview == null)) {
      setState(() => _error = i18n.t('setup_error_basic', fallback: 'Por favor, rellena los datos básicos y sube una foto principal.'));
      return;
    }
    if (_city.isEmpty) {
      setState(() => _error = i18n.t('setup_error_city', fallback: 'Debes seleccionar una ciudad.'));
      return;
    }
    if (_rol.isEmpty) {
      setState(() => _error = i18n.t('setup_error_role', fallback: 'Debes elegir qué buscas en Blow Nights.'));
      return;
    }
    final edad = calcularEdad(DateTime.parse(_fechaNacimiento));
    if (edad < 18) {
      setState(() => _error = i18n.t('setup_error_underage', fallback: 'Debes ser mayor de 18 años. Tu cuenta será eliminada.'));
      try {
        await FirebaseFunctions.instance.httpsCallable('deleteUserData').call();
      } catch (_) {}
      await auth.logout();
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final storage = FirebaseStorage.instance;
    try {
      var fotoUrl = _imagePreview;
      if (_imageFile != null) {
        final ref = storage.ref('profilePictures/$uid/main.jpg');
        await ref.putFile(_imageFile!, SettableMetadata(contentType: 'image/jpeg'));
        fotoUrl = await ref.getDownloadURL();
      }
      Future<List<String>> upload(List<File> files, String prefix) => Future.wait([
            for (var i = 0; i < files.length; i++)
              () async {
                final ref = storage.ref('profilePictures/$uid/$prefix-${DateTime.now().millisecondsSinceEpoch}-$i.jpg');
                await ref.putFile(files[i], SettableMetadata(contentType: 'image/jpeg'));
                return ref.getDownloadURL();
              }(),
          ]);
      final extra = [..._extraExisting, ...await upload(_extraFiles, 'extra')];
      final priv = [..._privateExisting, ...await upload(_privateFiles, 'private')];

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'nick': _nick.text,
        'email': auth.user?.email?.toLowerCase(),
        'fechaNacimiento': _fechaNacimiento,
        'edad': edad,
        'appMode': _appMode,
        'rol': _partyOnly ? 'party_only' : (_rol.isEmpty ? 'fiesta' : _rol),
        'intencion': _partyOnly ? 'fiesta' : _intencion,
        'bio': _bio.text,
        'altura': !_partyOnly && _altura.text.isNotEmpty ? int.tryParse(_altura.text) : null,
        'peso': !_partyOnly && _peso.text.isNotEmpty ? int.tryParse(_peso.text) : null,
        'complexion': !_partyOnly ? _complexion : null,
        'intereses': _intereses,
        'mood': _mood,
        'fotoUrl': fotoUrl,
        'extraPhotos': extra,
        'privatePhotos': priv,
        'cityId': _city,
        'platform': 'blownights',
        'updatedAt': DateTime.now(),
        'needsUpdate': false,
      }, SetOptions(merge: true));

      try {
        (await SharedPreferences.getInstance()).setString(cityStorageKey, _city);
      } catch (_) {}
      if (!mounted) return;
      final cp = context.read<CityProvider>();
      final match = cp.cities.where((c) => c.slug == _city || c.id == _city).firstOrNull;
      if (match != null) cp.setCurrentCity(match);
      if (widget.editing && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      setState(() => _error = (e.code == 'unauthorized' || e.code == 'retry-limit-exceeded')
          ? i18n.t('setup_error_storage', fallback: 'Error de permisos en las fotos. Por favor, asegúrate de que el almacenamiento está activado.')
          : i18n.t('setup_error_save', fallback: 'Hubo un error al guardar tu perfil. Revisa tu conexión o las fotos.'));
    } catch (_) {
      setState(() => _error = i18n.t('setup_error_save', fallback: 'Hubo un error al guardar tu perfil. Revisa tu conexión o las fotos.'));
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final lockedCity = (context.watch<AuthProvider>().profile?.cityId ?? '').isNotEmpty;
    final icons = [Icons.location_city, Icons.local_fire_department, Icons.person];
    final titles = [
      context.t('setup_step_city', fallback: 'Tu Ciudad'),
      context.t('setup_step_seeking', fallback: '¿Qué Buscas?'),
      context.t('setup_step_profile', fallback: 'Tu Perfil'),
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(24, 24, 24, 96), children: [
          Row(children: [
            for (var i = 0; i < _totalSteps; i++)
              Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(right: i < _totalSteps - 1 ? 8 : 0),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(99)),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 300),
                      widthFactor: _step > i ? 1 : 0,
                      child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Tw.fuchsia500, Tw.indigo500]))),
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Tw.w(0.05),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Tw.w(0.1)),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 50, offset: Offset(0, 25))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Tw.fuchsia500, Tw.indigo500]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(icons[_step - 1], color: Tw.white, size: 30),
                ),
              ),
              const SizedBox(height: 16),
              Text(titles[_step - 1], textAlign: TextAlign.center, style: tw(26, weight: black, tracking: -0.05)),
              const SizedBox(height: 8),
              Label('${context.t('setup.step_prefix')}$_step${context.t('setup.step_infix')}$_totalSteps',
                  size: 12, color: Tw.slate500, tracking: 0.2, align: TextAlign.center),
              const SizedBox(height: 32),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Tw.red500.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
                  ),
                  child: Label(_error!, color: Tw.red500, align: TextAlign.center),
                ),
                const SizedBox(height: 32),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(a), child: c),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: switch (_step) {
                    1 => _stepCity(context, lockedCity),
                    2 => _stepMode(context),
                    _ => _stepProfile(context),
                  },
                ),
              ),
              const SizedBox(height: 40),
              Row(children: [
                if (_step > 1) ...[
                  Expanded(
                    child: Pressable(
                      onTap: _prev,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(32), border: Border.all(color: Tw.w(0.1))),
                        child: Label(context.t('setupProfile.skip'), size: 12, color: Tw.white, align: TextAlign.center),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  flex: 2,
                  child: _step < _totalSteps
                      ? Pressable(
                          onTap: _next,
                          scale: 0.95,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(32)),
                            child: Label(context.t('setupProfile.continue'), size: 12, color: Tw.black, tracking: 0.3, align: TextAlign.center),
                          ),
                        )
                      : Opacity(
                          opacity: _submitting ? 0.5 : 1,
                          child: Pressable(
                            onTap: _submitting ? () {} : _submit,
                            scale: 0.95,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              decoration: BoxDecoration(
                                gradient: AppTheme.ctaGradient,
                                borderRadius: BorderRadius.circular(32),
                                boxShadow: [BoxShadow(color: Tw.fuchsia600.withValues(alpha: 0.3), blurRadius: 50, offset: const Offset(0, 20))],
                              ),
                              child: Label(
                                _submitting ? context.t('setup_saving', fallback: 'Guardando...') : context.t('setupProfile.continue'),
                                size: 12,
                                color: Tw.white,
                                tracking: 0.3,
                                align: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 32),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${context.t('setupProfile.subtitle').toUpperCase()}\n'),
              TextSpan(text: '${context.t('setup_terms_prefix', fallback: 'Al continuar, aceptas nuestras').toUpperCase()} '),
              WidgetSpan(
                child: GestureDetector(
                  onTap: () => openRoute(context, AppRoute.rules),
                  child: Text(context.t('setup_community_rules', fallback: 'Normas de la Comunidad').toUpperCase(),
                      style: tw(9, color: Tw.slate500, tracking: 0.2, decoration: TextDecoration.underline)),
                ),
              ),
              const TextSpan(text: '.'),
            ]),
            textAlign: TextAlign.center,
            style: tw(9, color: Tw.slate600, tracking: 0.2, height: 1.6),
          ),
          if (!widget.editing) ...[
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: () => context.read<AuthProvider>().logout(),
                child: Label(context.t('profile.logout'), color: Tw.slate600),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _selectable({required bool selected, required Widget child, required VoidCallback onTap, Color color = Tw.fuchsia500, EdgeInsets padding = const EdgeInsets.all(16)}) =>
      Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: padding,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.2) : Tw.w(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? color : Tw.w(0.1), width: 2),
            boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 15)] : null,
          ),
          child: child,
        ),
      );

  Widget _stepCity(BuildContext context, bool locked) => Column(children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${context.t('setup_city_description', fallback: 'Elige la ciudad donde sales de fiesta.')}\n'),
            TextSpan(
              text: context.t('setup_city_permanent', fallback: 'Es permanente y no se puede cambiar.'),
              style: tw(14, weight: bold, color: Tw.fuchsia400),
            ),
          ]),
          textAlign: TextAlign.center,
          style: tw(14, color: Tw.slate400, height: 1.5),
        ),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: [
            for (final c in citySlugs)
              Opacity(
                opacity: locked ? 0.6 : 1,
                child: _selectable(
                  selected: _city == c,
                  onTap: locked ? () {} : () => setState(() => _city = c),
                  child: Center(
                    child: Label('${c[0].toUpperCase()}${c.substring(1)}', size: 14, color: _city == c ? Tw.white : Tw.slate400, tracking: 0.05),
                  ),
                ),
              ),
          ],
        ),
      ]);

  Widget _stepMode(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('setup_mode_question', fallback: '¿Cómo quieres usar Blow Nights?'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
        const SizedBox(height: 4),
        Text(context.t('setup_mode_subtitle', fallback: 'Puedes cambiarlo en cualquier momento desde tu perfil'),
            textAlign: TextAlign.center, style: tw(11, color: Tw.slate500)),
        const SizedBox(height: 24),
        for (final m in _appModes) ...[
          _selectable(
            selected: _appMode == m.$1,
            onTap: () => setState(() {
              _appMode = m.$1;
              if (m.$1 == 'party') {
                _rol = 'party_only';
              } else if (_rol == 'party_only' || _rol.isEmpty) {
                _rol = 'fiesta';
              }
            }),
            child: Column(children: [
              Text(m.$2, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Label(context.t(m.$3, fallback: m.$4), size: 12, color: Tw.white, tracking: 0.05),
              const SizedBox(height: 4),
              Text(context.t(m.$5, fallback: m.$6), textAlign: TextAlign.center, style: tw(10, color: Tw.slate400, height: 1.2)),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (!_partyOnly) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Divider(color: Tw.w(0.1))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Label(context.t('setup_role_select', fallback: 'Tu rol o vibe'), size: 9, color: Tw.slate500),
            ),
            Expanded(child: Divider(color: Tw.w(0.1))),
          ]),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: [
              for (final r in platformRoles)
                _selectable(
                  selected: _rol == r.value,
                  onTap: () => setState(() => _rol = r.value),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(r.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 4),
                    Label(context.t(r.labelKey, fallback: r.fallbackLabel), size: 12, color: Tw.white, tracking: 0.05),
                    const SizedBox(height: 4),
                    Text(context.t(r.descKey, fallback: r.fallbackDesc), textAlign: TextAlign.center, style: tw(9, color: Tw.slate400, height: 1)),
                  ]),
                ),
            ],
          ),
          if (_rol.isNotEmpty && _rol != 'party_only') ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Label(context.t('setup_intention', fallback: 'Intención'), color: Tw.slate500, tracking: 0.2),
            ),
            const SizedBox(height: 8),
            Row(children: [
              for (final i in [
                ('conocer', context.t('setup_intention_conocer', fallback: 'Conocer'), context.t('setup_intention_conocer_desc', fallback: 'Hablar, ver qué pasa')),
                ('quedar', context.t('setup_intention_quedar', fallback: 'Quedar'), context.t('setup_intention_quedar_desc', fallback: 'Ir al grano')),
              ]) ...[
                Expanded(
                  child: _selectable(
                    selected: _intencion == i.$1,
                    color: Tw.indigo500,
                    padding: const EdgeInsets.all(12),
                    onTap: () => setState(() => _intencion = i.$1),
                    child: Column(children: [
                      Text(i.$2, style: tw(12, weight: bold)),
                      const SizedBox(height: 2),
                      Text(i.$3, textAlign: TextAlign.center, style: tw(9, color: Tw.slate400)),
                    ]),
                  ),
                ),
                if (i.$1 == 'conocer') const SizedBox(width: 12),
              ],
            ]),
          ],
        ],
      ]);

  Widget _fieldLabel(String t, {Color color = Tw.slate500, IconData? icon}) => Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 12),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 8)],
          Flexible(child: Label(t, color: color, tracking: 0.2)),
        ]),
      );

  InputDecoration _dec(String? hint, {double radius = 16}) => InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.all(20),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: Tw.w(0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: Tw.w(0.2))),
      );

  Widget _stepProfile(BuildContext context) {
    final moods = [
      ('🔥', context.t('setup_mood_hot', fallback: 'Hot')),
      ('🍕', context.t('setup_mood_hungry', fallback: 'Hambre')),
      ('😴', context.t('setup_mood_tired', fallback: 'Cansado')),
      ('🎮', context.t('setup_mood_gaming', fallback: 'Gaming')),
      ('💪', context.t('setup_mood_gym', fallback: 'Gym')),
      ('🎥', context.t('setup_mood_cinema', fallback: 'Cine')),
      ('🍺', context.t('setup_mood_drinks', fallback: 'Cañas')),
      ('🎒', context.t('setup_mood_travel', fallback: 'Viaje')),
      ('🏠', context.t('setup_mood_chill', fallback: 'Chill')),
      ('💬', context.t('setup_mood_chat', fallback: 'Chat')),
    ];
    final tags = [
      context.t('setup_tag_chill_plan', fallback: 'Plan Tranquilo'),
      context.t('setup_tag_party', fallback: 'Fiesta'),
      context.t('setup_tag_gym', fallback: 'Gimnasio'),
      context.t('setup_tag_cinema', fallback: 'Cine'),
      context.t('setup_tag_gaming', fallback: 'Gaming'),
      context.t('setup_tag_travel', fallback: 'Viajes'),
      context.t('setup_tag_music', fallback: 'Música'),
      context.t('setup_tag_food', fallback: 'Gastronomía'),
      context.t('setup_tag_chat_only', fallback: 'Solo Chat'),
      context.t('setup_tag_meetup', fallback: 'Quedada Real'),
    ];
    final maxBirth = DateTime.now().subtract(const Duration(days: 365 * 18 + 5));
    final birth = DateTime.tryParse(_fechaNacimiento);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: GestureDetector(
          onTap: _pickMain,
          child: Stack(children: [
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Tw.w(0.05), width: 4)),
              child: ClipOval(
                child: _imageFile != null
                    ? Image.file(_imageFile!, fit: BoxFit.cover)
                    : _imagePreview != null
                        ? NetImage(_imagePreview)
                        : Container(color: Tw.slate900, child: const Icon(Icons.add_a_photo, size: 48, color: Tw.slate700)),
              ),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.edit, size: 14, color: Tw.black),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Label(context.t('setupProfile.upload'), size: 9, color: Tw.slate500, align: TextAlign.center),
      const SizedBox(height: 32),
      _fieldLabel(context.t('setupProfile.name')),
      TextField(controller: _nick, style: tw(14, weight: bold), decoration: _dec(context.t('setupProfile.namePlaceholder'))),
      const SizedBox(height: 24),
      _fieldLabel(context.t('setup_birthdate', fallback: 'Fecha de Nacimiento')),
      Pressable(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: birth ?? DateTime(maxBirth.year - 7, 1, 1),
            firstDate: DateTime(1920),
            lastDate: maxBirth,
            builder: (c, child) => Theme(
              data: Theme.of(c).copyWith(colorScheme: const ColorScheme.dark(primary: Tw.fuchsia500, surface: Tw.slate900)),
              child: child!,
            ),
          );
          if (picked != null) setState(() => _fechaNacimiento = DateFormat('yyyy-MM-dd').format(picked));
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
          child: Row(children: [
            Expanded(
              child: Text(birth != null ? DateFormat('dd/MM/yyyy').format(birth) : 'dd/mm/aaaa',
                  style: tw(14, weight: bold, color: birth != null ? Tw.white : Tw.slate500)),
            ),
            const Icon(Icons.calendar_today, size: 16, color: Tw.slate400),
          ]),
        ),
      ),
      const SizedBox(height: 32),
      _fieldLabel(context.t('setup_mood', fallback: '¿Cómo te sientes hoy? (Mood)')),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.4,
        children: [
          for (final m in moods)
            Pressable(
              onTap: () => setState(() => _mood = m.$1),
              child: Container(
                decoration: BoxDecoration(
                  color: _mood == m.$1 ? Tw.fuchsia600 : Tw.w(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _mood == m.$1 ? Tw.fuchsia500 : Tw.w(0.1)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(m.$1, style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 4),
                  Label(m.$2, size: 8, color: Tw.w(0.6), maxLines: 1),
                ]),
              ),
            ),
        ],
      ),
      const SizedBox(height: 32),
      _fieldLabel(context.t('setupProfile.interests')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final tag in tags)
          Pressable(
            onTap: () => setState(() {
              if (_intereses.contains(tag)) {
                _intereses.remove(tag);
              } else if (_intereses.length < 5) {
                _intereses.add(tag);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _intereses.contains(tag) ? Tw.fuchsia600 : Tw.w(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _intereses.contains(tag) ? Tw.fuchsia500 : Tw.w(0.1)),
              ),
              child: Label(tag, weight: bold, color: _intereses.contains(tag) ? Tw.white : Tw.slate400, tracking: 0.05),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Label(context.t('setup_tags_limit', fallback: 'Elige hasta 5 tags'), size: 8, weight: FontWeight.w400, color: Tw.slate600),
      ),
      const SizedBox(height: 32),
      _fieldLabel(context.t('setupProfile.bio')),
      TextField(
        controller: _bio,
        maxLines: 3,
        style: tw(14, weight: bold),
        decoration: _dec(context.t('setupProfile.bioPlaceholder'), radius: 24),
      ),
      if (!_partyOnly) ...[
        const SizedBox(height: 32),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _fieldLabel(context.t('setup_height', fallback: 'Altura')),
              TextField(
                controller: _altura,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: tw(14, weight: bold),
                decoration: _dec('180').copyWith(contentPadding: const EdgeInsets.all(16)),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _fieldLabel(context.t('setup_weight', fallback: 'Peso')),
              TextField(
                controller: _peso,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: tw(14, weight: bold),
                decoration: _dec('75').copyWith(contentPadding: const EdgeInsets.all(16)),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _fieldLabel(context.t('setup_body', fallback: 'Cuerpo')),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _complexion,
                    isExpanded: true,
                    dropdownColor: Tw.slate900,
                    style: tw(12, weight: bold),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('--')),
                      DropdownMenuItem(value: 'delgado', child: Text(context.t('setup_body_slim', fallback: 'Delgado'))),
                      DropdownMenuItem(value: 'normal', child: Text(context.t('setup_body_normal', fallback: 'Normal'))),
                      DropdownMenuItem(value: 'musculado', child: Text(context.t('setup_body_strong', fallback: 'Fuerte'))),
                    ],
                    onChanged: (v) => setState(() => _complexion = v),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ],
      const SizedBox(height: 32),
      _fieldLabel(context.t('setup_gallery_public', fallback: 'Galería Pública')),
      _gallery(_extraExisting, _extraFiles, Tw.w(0.1), Icons.add, () => _pickMany(_extraFiles, _extraExisting.length)),
      const SizedBox(height: 32),
      _fieldLabel(context.t('setup_gallery_private', fallback: 'Álbum Privado'), color: const Color(0xFFEAB308), icon: Icons.lock),
      _gallery(_privateExisting, _privateFiles, const Color(0x33EAB308), Icons.lock_outline, () => _pickMany(_privateFiles, _privateExisting.length)),
    ]);
  }

  Widget _gallery(List<String> existing, List<File> files, Color dashed, IconData addIcon, VoidCallback onAdd) {
    final count = existing.length + files.length;
    Widget tile(Widget img) => Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.05))),
          child: img,
        );
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        for (final u in existing) tile(NetImage(u)),
        for (final f in files) tile(Image.file(f, fit: BoxFit.cover)),
        if (count < 5)
          Pressable(
            onTap: onAdd,
            child: Container(
              decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: dashed, width: 2)),
              child: Icon(addIcon, color: Tw.slate600),
            ),
          ),
      ],
    );
  }
}
