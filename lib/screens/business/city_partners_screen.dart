import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../navigation.dart';
import '../../providers/city_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart' show adminInputDecoration, AdminSelect, PulseDot, errorMessage;
import '../../widgets/common.dart';
import '../../widgets/marketing.dart';

/// Port of components/CityPartnersLanding.tsx (+ app/[city]/partners). Its own ES/CA/EN/PT/FR/DE copy lives in
/// assets/data/city_partners_i18n.json, extracted verbatim from the component; the language follows the city slug.
class CityPartnersScreen extends StatefulWidget {
  final String citySlug;
  const CityPartnersScreen({super.key, required this.citySlug});

  @override
  State<CityPartnersScreen> createState() => _CityPartnersScreenState();
}

class _CityPartnersScreenState extends State<CityPartnersScreen> {
  static Map<String, dynamic>? _dict;
  ({int users, int venues, int chills}) _stats = (users: 0, venues: 0, chills: 0);
  final _form = {for (final k in const ['name', 'email', 'phone', 'businessName', 'message']) k: TextEditingController()};
  String _type = '';
  bool _submitting = false;
  bool _success = false;
  final _formKey = GlobalKey();
  final _flowKey = GlobalKey();
  final _venuesKey = GlobalKey();

  String get _slug => widget.citySlug.toLowerCase();
  String get _lang => switch (_slug) { 'barcelona' => 'ca', 'london' => 'en', 'lisboa' => 'pt', 'paris' => 'fr', 'berlin' => 'de', _ => 'es' };

  String t(String key) {
    final d = _dict;
    if (d == null) return '';
    return ((d[_lang] as Map?)?[key] ?? (d['es'] as Map?)?[key] ?? key) as String;
  }

  @override
  void initState() {
    super.initState();
    if (_dict == null) {
      rootBundle.loadString('assets/data/city_partners_i18n.json').then((s) {
        if (mounted) setState(() => _dict = jsonDecode(s) as Map<String, dynamic>);
      });
    }
    for (final c in _form.values) {
      c.addListener(() => setState(() {}));
    }
    _loadStats();
  }

  @override
  void dispose() {
    for (final c in _form.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadStats() async {
    final db = FirebaseFirestore.instance;
    try {
      // Venues of the network: active ones minus reference venues not claimed yet, which are real places seeded for
      // the map, not venues on Blow Nights (web docs/REFERENCE_VENUES.md).
      final v = await db.collection('venues').where('isActive', isEqualTo: true).count().get();
      final refs = await db
          .collection('venues')
          .where('isActive', isEqualTo: true)
          .where('source', isEqualTo: 'reference')
          .where('isClaimed', isEqualTo: false)
          .count()
          .get();
      final u = await db.collection('users').count().get();
      final c = await db.collection('chills').where('city_slug', isEqualTo: _slug).count().get();
      if (mounted) setState(() => _stats = (users: u.count ?? 0, venues: (v.count ?? 0) - (refs.count ?? 0), chills: c.count ?? 0));
    } catch (e) {
      debugPrint('Stats fetch error: $e');
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final cityName = context.read<CityProvider>().currentCity?.name ?? _slug;
    try {
      await FirebaseFirestore.instance.collection('partner_leads').add({
        for (final e in _form.entries) e.key: e.value.text,
        'type': _type,
        'citySlug': _slug.isEmpty ? 'unknown' : _slug,
        'cityName': cityName,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'new',
      });
      for (final c in _form.values) {
        c.clear();
      }
      setState(() {
        _type = '';
        _success = true;
      });
    } catch (e) {
      if (mounted) showToast(context, t('form_error'), error: true);
      debugPrint(errorMessage(e, ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    if (_dict == null) return const Scaffold(backgroundColor: Tw.slate950);
    final top = MediaQuery.of(context).padding.top;
    final city = _slug.toUpperCase();
    final cityDisplay = context.watch<CityProvider>().currentCity?.name ?? _slug;
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Stack(children: [
        SingleChildScrollView(
          padding: EdgeInsets.only(top: top + 64),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _hero(city),
            _section(child: _ecosystem()),
            KeyedSubtree(key: _flowKey, child: _section(tinted: true, child: _flow())),
            _section(child: _radar()),
            KeyedSubtree(key: _venuesKey, child: _section(tinted: true, child: _venuesBlock())),
            _section(child: _associations()),
            _section(tinted: true, child: _territorial()),
            _section(child: _nodes(city, cityDisplay)),
            _section(tinted: true, child: _early()),
            KeyedSubtree(key: _formKey, child: _section(child: _formBlock(cityDisplay))),
            _footer(),
          ]),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: EdgeInsets.fromLTRB(8, top + 8, 16, 8),
                decoration: BoxDecoration(color: Tw.slate950.withValues(alpha: 0.8), border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
                child: Row(children: [
                  IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Tw.purple600, Tw.pink500]), borderRadius: BorderRadius.circular(6)),
                    child: Text('B', style: tw(14, weight: bold)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Blow Nights', style: tw(16, weight: bold))),
                  Pressable(
                    onTap: () => _scrollTo(_formKey),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(99)),
                      child: Text(t('contact'), style: tw(12, weight: semibold, color: Tw.black)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _section({required Widget child, bool tinted = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 72),
        decoration: BoxDecoration(color: tinted ? Tw.slate900.withValues(alpha: 0.4) : null, border: Border(top: BorderSide(color: Tw.w(0.05)))),
        child: child,
      );

  Widget _eyebrow(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Label(text, size: 11, weight: semibold, color: color, tracking: 0.2, align: TextAlign.center),
      );

  Widget _h2(String text, {String? sub}) => Column(children: [
        Text(text, textAlign: TextAlign.center, style: tw(30, weight: black, height: 1.1, tracking: -0.02)),
        if (sub != null) ...[const SizedBox(height: 12), Text(sub, textAlign: TextAlign.center, style: tw(14, color: Tw.slate500))],
        const SizedBox(height: 48),
      ]);

  Widget _pillButton(String label, VoidCallback onTap, {List<Color>? gradient}) => Pressable(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: gradient != null ? LinearGradient(colors: gradient) : null,
            color: gradient == null ? Tw.w(0.05) : null,
            borderRadius: BorderRadius.circular(99),
            border: gradient == null ? Border.all(color: Tw.w(0.1)) : null,
          ),
          child: Text(label, textAlign: TextAlign.center, style: tw(14, weight: gradient != null ? bold : semibold)),
        ),
      );

  Widget _hero(String city) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 48),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Tw.purple500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Tw.purple500.withValues(alpha: 0.2)),
              ),
              child: Label('Blow Nights', size: 11, weight: semibold, color: Tw.purple400, tracking: 0.15),
            ),
          ),
          const SizedBox(height: 24),
          Text.rich(
            TextSpan(style: tw(38, weight: black, height: 1.05, tracking: -0.02), children: [
              TextSpan(text: '${t('hero_h1_pre')} '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GradientText(city, style: tw(38, weight: black, height: 1.05), colors: const [Tw.purple400, Tw.pink500]),
              ),
              TextSpan(text: ',\n${t('hero_h1_post')}'),
            ]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(t('hero_subtitle'), textAlign: TextAlign.center, style: tw(16, color: Tw.slate400, height: 1.6)),
          const SizedBox(height: 40),
          _pillButton(t('cta_participate'), () => _scrollTo(_formKey), gradient: const [Tw.purple600, Tw.pink500]),
          const SizedBox(height: 12),
          _pillButton(t('cta_how'), () => _scrollTo(_flowKey)),
          const SizedBox(height: 40),
          _EcosystemDiagram(label: t),
        ]),
      );

  Widget _card(IconData icon, Color color, String title, String desc, {bool center = false}) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
        child: Column(crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: center ? TextAlign.center : TextAlign.start, style: tw(13, weight: black, tracking: 0.05)),
          const SizedBox(height: 8),
          Text(desc, textAlign: center ? TextAlign.center : TextAlign.start, style: tw(12, color: Tw.slate500, height: 1.6)),
        ]),
      );

  Widget _ecosystem() => Column(children: [
        _h2(t('eco_h2'), sub: t('eco_sub')),
        _card(Icons.groups_outlined, Tw.purple400, t('card_users'), t('card_users_d')),
        _card(Icons.apartment, Tw.pink400, t('card_venues'), t('card_venues_d')),
        _card(Icons.campaign_outlined, Tw.blue400, t('card_promoters'), t('card_promoters_d')),
        _card(Icons.favorite_border, Tw.green400, t('card_orgs'), t('card_orgs_d')),
      ]);

  Widget _flow() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _eyebrow(t('flow_label'), Tw.purple400),
        _h2(t('flow_h2')),
        Stack(children: [
          Positioned(
            left: 24,
            top: 0,
            bottom: 0,
            child: Container(
              width: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Tw.purple500.withValues(alpha: 0.5), Tw.pink500.withValues(alpha: 0.3), Colors.transparent],
                ),
              ),
            ),
          ),
          Column(children: [
            for (var i = 1; i <= 6; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == 6 ? Tw.purple500.withValues(alpha: 0.2) : Tw.slate800,
                      shape: BoxShape.circle,
                      border: Border.all(color: i == 6 ? Tw.purple500.withValues(alpha: 0.5) : Tw.w(0.1)),
                    ),
                    child: Text('0$i', style: tw(12, weight: black, color: i == 6 ? Tw.purple400 : Tw.slate500)),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('flow_$i'), style: tw(13, weight: black, tracking: 0.05)),
                        const SizedBox(height: 4),
                        Text(t('flow_${i}d'), style: tw(12, color: Tw.slate500, height: 1.6)),
                      ]),
                    ),
                  ),
                ]),
              ),
          ]),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 64),
          child: Row(children: [
            Icon(Icons.autorenew, size: 16, color: Tw.purple400.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Flexible(child: Label(t('flow_loop'), weight: bold, color: Tw.purple400.withValues(alpha: 0.7))),
          ]),
        ),
      ]);

  Widget _radar() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: Tw.green500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99), border: Border.all(color: Tw.green500.withValues(alpha: 0.2))),
          child: Label(t('radar_badge'), color: Tw.green400),
        ),
        const SizedBox(height: 16),
        Text(t('radar_h2'), style: tw(30, weight: black, height: 1.1)),
        const SizedBox(height: 16),
        Text(t('radar_desc'), style: tw(14, color: Tw.slate400, height: 1.6)),
        const SizedBox(height: 24),
        for (final k in const ['radar_f1', 'radar_f2', 'radar_f3', 'radar_f4'])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Tw.green500, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(t(k), style: tw(14, color: Tw.slate500))),
            ]),
          ),
        const SizedBox(height: 24),
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
            child: Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: _GridPainter()),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tw.purple500.withValues(alpha: 0.05), Colors.transparent]),
                ),
              ),
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Tw.purple600.withValues(alpha: 0.3), Tw.pink500.withValues(alpha: 0.3)]),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.map_outlined, size: 28, color: Tw.white),
                ),
                const SizedBox(height: 16),
                Text('RADAR', style: tw(18, weight: black)),
                Label(t('radar_mock'), color: Tw.slate500, weight: FontWeight.w400),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < 5; i++) ...[
                    PulseDot(color: Tw.purple500.withValues(alpha: 0.6)),
                    if (i < 4) const SizedBox(width: 12),
                  ],
                ]),
              ]),
            ]),
          ),
        ),
      ]);

  Widget _venuesBlock() => Column(children: [
        _eyebrow(t('venues_label'), Tw.pink400),
        _h2(t('venues_h2')),
        _card(Icons.visibility_outlined, Tw.pink400, t('v_vis'), t('v_vis_d')),
        _card(Icons.calendar_today_outlined, Tw.pink400, t('v_ev'), t('v_ev_d')),
        _card(Icons.location_on_outlined, Tw.pink400, t('v_pre'), t('v_pre_d')),
        _card(Icons.bar_chart, Tw.pink400, t('v_dat'), t('v_dat_d')),
        const SizedBox(height: 24),
        _pillButton(t('v_cta'), () => _scrollTo(_formKey), gradient: const [Color(0xFFDB2777), Tw.purple600]),
      ]);

  Widget _associations() => Column(children: [
        _eyebrow(t('assoc_label'), Tw.green400),
        _h2(t('assoc_h2'), sub: t('assoc_sub')),
        _card(Icons.favorite_border, Tw.green400, t('a_col'), t('a_col_d'), center: true),
        _card(Icons.public, Tw.green400, t('a_dif'), t('a_dif_d'), center: true),
        _card(Icons.groups_outlined, Tw.green400, t('a_eco'), t('a_eco_d'), center: true),
        const SizedBox(height: 24),
        _pillButton(t('a_cta'), () => _scrollTo(_formKey)),
      ]);

  Widget _territorial() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _eyebrow(t('cm_label'), Tw.blue400),
        _h2('${t('cm_h2_1')}\n${t('cm_h2_2')}', sub: t('cm_sub')),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Tw.slate800.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.purple500.withValues(alpha: 0.2))),
          child: Column(children: [
            Label(t('cm_plat'), weight: bold, color: Tw.purple400, align: TextAlign.center),
            const SizedBox(height: 4),
            Text(t('cm_plat_d'), textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
          ]),
        ),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 3; i++) ...[
            Container(
              width: 1,
              height: 32,
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tw.purple500.withValues(alpha: 0.4), Colors.transparent])),
            ),
            if (i < 2) const SizedBox(width: 4),
          ],
        ]),
        const SizedBox(height: 24),
        for (final (name, key, active) in const [('MADRID', 'cm_madrid', true), ('BARCELONA', 'cm_barcelona', false), ('LONDON', 'cm_london', false)])
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: active ? Tw.purple500.withValues(alpha: 0.1) : Tw.slate900.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: active ? Tw.purple500.withValues(alpha: 0.3) : Tw.w(0.05)),
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (active) ...[const PulseDot(color: Tw.green500), const SizedBox(width: 8)],
                Text(name, style: tw(14, weight: black, color: active ? Tw.white : Tw.slate600)),
              ]),
              const SizedBox(height: 4),
              Text(t(key), style: tw(10, color: active ? Tw.purple400 : Tw.slate600)),
            ]),
          ),
      ]);

  Widget _nodes(String city, String cityDisplay) => Column(children: [
        _eyebrow(city, Tw.purple400),
        _h2(t('nodes_h2'), sub: '${t('nodes_sub_pre')}$cityDisplay${t('nodes_sub_post')}'),
        Row(children: [
          Expanded(child: _Counter(value: _stats.users, label: t('nodes_users'))),
          Expanded(child: _Counter(value: _stats.venues, label: t('nodes_venues'))),
          Expanded(child: _Counter(value: _stats.chills, label: t('nodes_chills'))),
        ]),
        const SizedBox(height: 32),
        Label(t('nodes_foot'), color: Tw.slate600, weight: FontWeight.w400, align: TextAlign.center),
      ]);

  Widget _early() => Column(children: [
        _h2(t('early_h2'), sub: t('early_sub')),
        _card(Icons.auto_awesome_outlined, Tw.purple400, t('e_ea'), t('e_ea_d'), center: true),
        _card(Icons.star_border, Tw.purple400, t('e_vis'), t('e_vis_d'), center: true),
        _card(Icons.verified_user_outlined, Tw.purple400, t('e_pos'), t('e_pos_d'), center: true),
      ]);

  InputDecoration _deco(String hint) => adminInputDecoration(hint, focus: Tw.purple500).copyWith(fillColor: Tw.slate950, hintStyle: tw(14, color: Tw.slate700));

  Widget _field(String label, String key, String hint, {TextInputType? kb, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Label(label, weight: bold, color: Tw.slate500)),
          TextField(controller: _form[key], keyboardType: kb, maxLines: lines, style: tw(14), decoration: _deco(hint)),
        ]),
      );

  Widget _formBlock(String cityDisplay) {
    final valid = _form['name']!.text.trim().isNotEmpty && _form['email']!.text.contains('@') && _type.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _h2(t('form_h2'), sub: t('form_sub')),
      if (_success)
        Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.green500.withValues(alpha: 0.2))),
          child: Column(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: Tw.green500.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline, size: 40, color: Tw.green500),
            ),
            const SizedBox(height: 16),
            Text(t('form_ok_h'), style: tw(20, weight: black)),
            const SizedBox(height: 8),
            Text('${t('form_ok_p_pre')}$cityDisplay.', textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
            const SizedBox(height: 24),
            GestureDetector(onTap: () => setState(() => _success = false), child: Label(t('form_ok_btn'), size: 12, color: Tw.purple400)),
          ]),
        )
      else
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _field('${t('form_name')} *', 'name', t('form_name')),
            _field('${t('form_email')} *', 'email', 'tu@email.com', kb: TextInputType.emailAddress),
            _field(t('form_phone'), 'phone', '+34 600 000 000', kb: TextInputType.phone),
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Label('${t('form_type')} *', weight: bold, color: Tw.slate500)),
            AdminSelect<String>(
              value: _type.isEmpty ? null : _type,
              hint: t('form_type_ph'),
              items: [
                ('local', t('form_type_local')),
                ('asociacion', t('form_type_assoc')),
                ('promotor', t('form_type_prom')),
                ('otro', t('form_type_other')),
              ],
              onChanged: (v) => setState(() => _type = v ?? ''),
            ),
            const SizedBox(height: 16),
            _field(t('form_biz'), 'businessName', t('form_biz_ph')),
            _field(t('form_msg'), 'message', t('form_msg_ph'), lines: 3),
            Opacity(
              opacity: _submitting || !valid ? 0.5 : 1,
              child: Pressable(
                onTap: _submitting || !valid ? () {} : _submit,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Tw.purple600, Tw.pink500]), borderRadius: BorderRadius.circular(12)),
                  child: Text(_submitting ? t('form_submitting') : t('form_submit'), textAlign: TextAlign.center, style: tw(14, weight: bold)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(t('form_foot'), textAlign: TextAlign.center, style: tw(10, color: Tw.slate600)),
          ]),
        ),
    ]);
  }

  Widget _footer() {
    Widget link(String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(onTap: onTap, child: Text(label, style: tw(12, color: Tw.slate500))),
        );
    Widget col(String title, List<Widget> links) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(title, weight: bold, color: Tw.slate600),
          const SizedBox(height: 16),
          ...links,
        ]);
    void openCity(String slug) => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => CityPartnersScreen(citySlug: slug)));
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 64, 20, 48),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.w(0.05)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: col(t('foot_eco'), [
              link(t('foot_radar'), () => openRoute(context, AppRoute.map)),
              link(t('foot_venues'), () => openRoute(context, AppRoute.venues)),
              link(t('foot_events'), () => openRoute(context, AppRoute.events)),
              link(t('foot_chills'), () => openRoute(context, AppRoute.chills)),
            ]),
          ),
          Expanded(
            child: col(t('foot_partners'), [
              link(t('foot_for_venues'), () => _scrollTo(_venuesKey)),
              link(t('foot_contact'), () => _scrollTo(_formKey)),
              link(t('foot_cm'), () => openRoute(context, AppRoute.partners)),
            ]),
          ),
        ]),
        const SizedBox(height: 32),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: col(t('foot_legal'), [
              link(t('foot_privacy'), () => openRoute(context, AppRoute.privacy)),
              link(t('foot_terms'), () => openRoute(context, AppRoute.terms)),
            ]),
          ),
          Expanded(
            child: col(t('foot_cities'), [
              for (final (slug, name) in const [
                ('madrid', 'Madrid'),
                ('barcelona', 'Barcelona'),
                ('london', 'London'),
                ('lisboa', 'Lisboa'),
                ('paris', 'Paris'),
                ('berlin', 'Berlin'),
              ])
                link(name, () => openCity(slug)),
            ]),
          ),
        ]),
        const SizedBox(height: 32),
        Divider(color: Tw.w(0.05)),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Tw.slate700, Tw.slate900]), borderRadius: BorderRadius.circular(4)),
            child: Text('B', style: tw(9, weight: bold)),
          ),
          const SizedBox(width: 8),
          Text('Blow Nights Network', style: tw(12, weight: semibold, color: Tw.slate600)),
        ]),
        const SizedBox(height: 12),
        Text('© ${DateTime.now().year} Blow Nights. ${t('foot_copy')}', textAlign: TextAlign.center, style: tw(10, color: Tw.slate700)),
      ]),
    );
  }
}

/// AnimatedCounter: counts up to [value] over 1.5s the first time it is built.
class _Counter extends StatelessWidget {
  final int value;
  final String label;
  const _Counter({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(children: [
        TweenAnimationBuilder<double>(
          key: ValueKey(value),
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 1500),
          builder: (_, v, _) => GradientText('${v.round()}', style: tw(40, weight: black), colors: const [Tw.purple400, Tw.pink500]),
        ),
        const SizedBox(height: 4),
        Label(label, weight: semibold, color: Tw.slate500, align: TextAlign.center),
      ]);
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x08FFFFFF)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

/// EcosystemDiagram: the web's 400×300 SVG (nodes, links and dots flowing along them), drawn with a CustomPainter.
class _EcosystemDiagram extends StatefulWidget {
  final String Function(String) label;
  const _EcosystemDiagram({required this.label});

  @override
  State<_EcosystemDiagram> createState() => _EcosystemDiagramState();
}

class _EcosystemDiagramState extends State<_EcosystemDiagram> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _activity() {
    final c = widget.label('contact');
    if (c == 'Kontakt') return 'AKTIVITÄT';
    if (c == 'Contact') return 'ACTIVITY';
    if (c == 'Contacto') return 'ATIVIDADE';
    if (c == 'Contactar') return widget.label('hero_h1_pre') == 'EL OCIO NOCTURNO DE' ? 'ACTIVIDAD' : 'ACTIVITAT';
    return 'ACTIVITÉ';
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 4 / 3,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: _EcoPainter(
              t: _c.value * 12,
              orgs: widget.label('card_orgs').toUpperCase(),
              venues: widget.label('card_venues').toUpperCase(),
              events: widget.label('foot_events').toUpperCase(),
              users: widget.label('card_users').toUpperCase(),
              activity: _activity(),
            ),
          ),
        ),
      );
}

class _EcoPainter extends CustomPainter {
  final double t;
  final String orgs, venues, events, users, activity;
  _EcoPainter({required this.t, required this.orgs, required this.venues, required this.events, required this.users, required this.activity});

  static const _purple = Color(0xFFA855F7), _pink = Color(0xFFEC4899), _blue = Color(0xFF3B82F6), _green = Color(0xFF22C55E), _orange = Color(0xFFFB923C);

  void _node(Canvas c, Rect r, double radius, Color color, double fillA, double strokeA, String text, Color textColor, double fontSize, FontWeight w) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    c.drawRRect(rr, Paint()..color = color.withValues(alpha: fillA));
    c.drawRRect(
        rr,
        Paint()
          ..color = color.withValues(alpha: strokeA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: textColor, fontSize: fontSize, fontWeight: w, letterSpacing: 0.5)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: r.width + 20);
    tp.paint(c, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
  }

  Path _dashed(Path src) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        out.addPath(m.extractPath(d, d + 4), Offset.zero);
        d += 6;
      }
    }
    return out;
  }

  void _dot(Canvas c, Path path, double duration, double begin, double r, Color color, double opacity) {
    if (t < begin) return;
    final progress = ((t - begin) % duration) / duration;
    final m = path.computeMetrics().first;
    final pos = m.getTangentForOffset(m.length * progress)?.position;
    if (pos != null) c.drawCircle(pos, r, Paint()..color = color.withValues(alpha: opacity));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 400, size.height / 300);
    _node(canvas, const Rect.fromLTWH(10, 120, 80, 36), 8, _purple, 0.15, 0.4, orgs, const Color(0xFFC084FC), 8, FontWeight.w700);
    _node(canvas, const Rect.fromLTWH(120, 120, 70, 36), 8, _pink, 0.15, 0.4, venues, const Color(0xFFF472B6), 8, FontWeight.w700);
    _node(canvas, const Rect.fromLTWH(215, 60, 60, 30), 6, _blue, 0.1, 0.3, events, const Color(0xFF60A5FA), 7, FontWeight.w600);
    _node(canvas, const Rect.fromLTWH(215, 120, 60, 30), 6, _green, 0.1, 0.3, 'PROMOS', const Color(0xFF4ADE80), 7, FontWeight.w600);
    _node(canvas, const Rect.fromLTWH(215, 180, 60, 30), 6, _orange, 0.1, 0.3, activity, _orange, 7, FontWeight.w600);
    final glow = 0.2 + 0.1 * (0.5 + 0.5 * (t * 2 % 2 < 1 ? t * 2 % 1 : 1 - t * 2 % 1));
    _node(canvas, const Rect.fromLTWH(300, 120, 60, 36), 8, _purple, glow, 0.5, 'RADAR', const Color(0xFFC084FC), 8, FontWeight.w800);
    _node(canvas, const Rect.fromLTWH(300, 220, 70, 36), 8, _pink, 0.15, 0.4, users, const Color(0xFFF472B6), 8, FontWeight.w700);
    _node(canvas, const Rect.fromLTWH(120, 230, 80, 30), 6, _orange, 0.1, 0.3, '+ ACTIVIDAD', _orange, 7, FontWeight.w600);

    Paint line(Color c, double a) => Paint()
      ..color = c.withValues(alpha: a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    Path seg(double x1, double y1, double x2, double y2) => Path()
      ..moveTo(x1, y1)
      ..lineTo(x2, y2);
    final a = seg(90, 138, 120, 138);
    final b1 = seg(190, 130, 215, 75), b2 = seg(190, 138, 215, 135), b3 = seg(190, 148, 215, 195);
    final c1 = seg(275, 75, 300, 130), c2 = seg(275, 135, 300, 138), c3 = seg(275, 195, 300, 148);
    final d = seg(330, 156, 335, 220);
    final e = Path()
      ..moveTo(300, 238)
      ..quadraticBezierTo(250, 270, 200, 249);
    final f = Path()
      ..moveTo(130, 230)
      ..quadraticBezierTo(100, 200, 140, 156);
    canvas.drawPath(_dashed(a), line(_purple, 0.3));
    canvas.drawPath(b1, line(_blue, 0.2));
    canvas.drawPath(b2, line(_green, 0.2));
    canvas.drawPath(b3, line(_orange, 0.2));
    canvas.drawPath(c1, line(_blue, 0.2));
    canvas.drawPath(c2, line(_green, 0.2));
    canvas.drawPath(c3, line(_orange, 0.2));
    canvas.drawPath(_dashed(d), line(_pink, 0.3));
    canvas.drawPath(_dashed(e), line(_orange, 0.25));
    canvas.drawPath(_dashed(f), line(_purple, 0.2));

    _dot(canvas, a, 3, 0, 2.5, const Color(0xFFC084FC), 0.9);
    _dot(canvas, b1, 2.5, 0.5, 2, const Color(0xFF60A5FA), 0.8);
    _dot(canvas, b2, 2.5, 1, 2, const Color(0xFF4ADE80), 0.8);
    _dot(canvas, b3, 2.5, 1.5, 2, _orange, 0.8);
    _dot(canvas, c1, 3, 0.8, 2.5, const Color(0xFFC084FC), 0.9);
    _dot(canvas, d, 3, 1.2, 2.5, const Color(0xFFF472B6), 0.9);
    _dot(canvas, e, 4, 2, 2, _orange, 0.7);
    _dot(canvas, f, 4, 2.5, 2, const Color(0xFFC084FC), 0.7);
  }

  @override
  bool shouldRepaint(_EcoPainter old) => old.t != t || old.orgs != orgs;
}
