import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../navigation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart' show adminInputDecoration, callFn, errorMessage, AdminGrid, PulseDot;
import '../../widgets/common.dart';
import '../../widgets/marketing.dart';

void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Port of app/investors/page.tsx (investor portal: metrics, moat, PIN-gated data room via validateInvestorAccess).
class InvestorsScreen extends StatefulWidget {
  const InvestorsScreen({super.key});

  @override
  State<InvestorsScreen> createState() => _InvestorsScreenState();
}

class _InvestorsScreenState extends State<InvestorsScreen> {
  bool _unlocked = false;
  bool _loading = false;
  String _error = '';
  final _name = TextEditingController();
  final _firm = TextEditingController();
  final _email = TextEditingController();
  final _pin = TextEditingController();
  final _roomKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _email]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _firm, _email, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      await callFn('validateInvestorAccess', {'name': _name.text, 'firm': _firm.text, 'email': _email.text, 'pin': _pin.text});
      setState(() => _unlocked = true);
    } catch (e) {
      setState(() => _error = errorMessage(e, 'Error de validación. Inténtalo de nuevo.').replaceFirst('FirebaseError: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toRoom() {
    final ctx = _roomKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF090B10);
    return Scaffold(
      backgroundColor: bg,
      body: Stack(children: [
        AmbientGlow(colors: [Tw.purple600.withValues(alpha: 0.1), const Color(0xFFDB2777).withValues(alpha: 0.1)]),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _nav(context),
              const SizedBox(height: 40),
              _hero(),
              const SizedBox(height: 56),
              _metrics(),
              const SizedBox(height: 64),
              _moat(),
              const SizedBox(height: 64),
              _tech(),
              const SizedBox(height: 64),
              KeyedSubtree(key: _roomKey, child: _dataRoom(context)),
              const SizedBox(height: 48),
              Divider(color: Tw.w(0.1)),
              const SizedBox(height: 24),
              Text('© ${DateTime.now().year} Blow Nights LLC. Todos los derechos reservados.', textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
              const SizedBox(height: 12),
              Wrap(alignment: WrapAlignment.center, spacing: 24, crossAxisAlignment: WrapCrossAlignment.center, children: [
                GestureDetector(onTap: () => openRoute(context, AppRoute.terms), child: Text('Términos', style: tw(12, color: Tw.slate500))),
                GestureDetector(onTap: () => openRoute(context, AppRoute.privacy), child: Text('Privacidad', style: tw(12, color: Tw.slate500))),
                Text('TCS Global Solutions LLC', style: tw(12, color: Tw.slate600)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _nav(BuildContext context) => Container(
        padding: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.w(0.1)))),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Tw.purple600, Tw.pink500]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Tw.purple500.withValues(alpha: 0.2), blurRadius: 12)],
            ),
            child: Text('B', style: tw(20, weight: black)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('BLOW NIGHTS', style: tw(18, weight: black, tracking: 0.05))),
          GestureDetector(
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: Text('← Ir a la App', style: tw(12, color: Tw.slate400)),
          ),
          const SizedBox(width: 12),
          Pressable(
            onTap: _toRoom,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
              child: Text('Data Room', style: tw(12, weight: bold)),
            ),
          ),
        ]),
      );

  Widget _hero() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Tw.purple500.withValues(alpha: 0.1), Tw.pink500.withValues(alpha: 0.1)]),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Tw.purple500.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const PulseDot(color: Tw.green400),
              const SizedBox(width: 8),
              Text('RONDA SEED 1.000.000 € · EN PRODUCCIÓN', style: tw(12, weight: semibold, color: const Color(0xFFD8B4FE))),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Text.rich(
          TextSpan(style: tw(38, weight: black, height: 1.05, tracking: -0.02), children: [
            const TextSpan(text: 'El Sistema Operativo para el '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GradientText('Nightlife Global', style: tw(38, weight: black, height: 1.05), colors: const [Tw.purple400, Tw.pink400, Color(0xFFFCD34D)]),
            ),
          ]),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Text(
          'Conectamos el descubrimiento social hiperlocal en tiempo real (B2C) con el software operativo, ticketing directo y control de accesos para salas y macro-eventos (B2B SaaS).',
          textAlign: TextAlign.center,
          style: tw(18, color: Tw.slate400, height: 1.6),
        ),
        const SizedBox(height: 32),
        CtaButton(label: 'Desbloquear Data Room →', gradient: const [Tw.purple600, Color(0xFFDB2777)], onTap: _toRoom),
        const SizedBox(height: 12),
        Pressable(
          onTap: () => _open('mailto:cesar@blownights.com?subject=${Uri.encodeComponent('Blow Nights Seed Round Meeting')}'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
            child: Text('Contactar con el Fundador', textAlign: TextAlign.center, style: tw(14, weight: bold)),
          ),
        ),
      ]);

  Widget _metrics() {
    Widget m(String label, String value, String note, Color c) => Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Tw.w(0.03), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: tw(11, color: Tw.slate400, tracking: 0.1).copyWith(fontFamily: 'monospace')),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: tw(30, weight: black).copyWith(fontFamily: 'monospace')),
            ),
            const SizedBox(height: 8),
            Text(note, style: tw(12, color: c)),
          ]),
        );
    return AdminGrid(gap: 16, children: [
      m('Margen Plataforma', '85%+', '1,00 € fee ticket + 2,5% cashless', Tw.purple400),
      m('Break-Even Operativo', 'Mes 4', '<20k € consumo en valle', Tw.green400),
      m('Expansión P2', '50/50', 'Master Partners territoriales', Tw.pink400),
      m('White-Label Enterprise', 'Multi-Tenant', 'SaaS corporativo en producción', Tw.amber400),
    ]);
  }

  Widget _moat() {
    Widget card(String emoji, Color c, String title, String desc) => Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tw.w(0.05), Colors.transparent]),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Tw.w(0.1)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(height: 16),
            Text(title, style: tw(20, weight: bold)),
            const SizedBox(height: 12),
            Text(desc, style: tw(14, color: Tw.slate400, height: 1.6)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Ventajas Estructurales & Foso Tecnológico', subtitle: 'Construido para escalar sin inflar costes fijos de personal'),
      const SizedBox(height: 32),
      card('⚡', Tw.purple500, 'Merchant of Record Directo',
          'El dinero entra directo a la cuenta bancaria del local en Stripe Connect vía Direct Charges. Cero riesgo regulatorio ni custodia de fondos por Blow Nights, con fee automático retenido al instante.'),
      card('🌐', Tw.pink500, 'White-Label Multi-Tenancy',
          'Festivales, macro-salas y promotores operan con subdominio o dominio propio y temas CSS dinámicos (colores, logotipos, SEO), aprovechando la arquitectura compartida (*Powered by Blow Nights*).'),
      card('🤝', Tw.indigo500, 'Red P2 Master Partners',
          'Franquicia territorial con exclusividad blindada por geocoding e inmutabilidad en backend. Escalabilidad comercial a múltiples países con CAC tendente a cero y liquidaciones 50/50 auditadas.'),
    ]);
  }

  Widget _tech() => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF3B0764).withValues(alpha: 0.4), Tw.slate900, Tw.black]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Tw.purple500.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CERTIFICACIÓN DE GRADO INSTITUCIONAL', style: tw(12, weight: bold, color: Tw.purple400, tracking: 0.1).copyWith(fontFamily: 'monospace')),
          const SizedBox(height: 16),
          Text('Arquitectura Serverless 100% Desplegada en Producción', style: tw(24, weight: black, height: 1.2)),
          const SizedBox(height: 24),
          AdminGrid(gap: 16, children: [
            for (final (v, l) in const [('93', 'Cloud Functions v2'), ('~299', 'Tests en CI/CD'), ('<80 ms', 'Validación en Puerta'), ('12', 'Idiomas Nativos')])
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v, style: tw(24, weight: black).copyWith(fontFamily: 'monospace')),
                Text(l, style: tw(12, color: Tw.slate400)),
              ]),
          ]),
        ]),
      );

  Widget _dataRoom(BuildContext context) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Tw.w(0.02), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ACCESO CONFIDENCIAL', textAlign: TextAlign.center, style: tw(12, weight: bold, color: Tw.pink400, tracking: 0.1).copyWith(fontFamily: 'monospace')),
          const SizedBox(height: 12),
          Text('Data Room de Inversión', textAlign: TextAlign.center, style: tw(30, weight: black)),
          const SizedBox(height: 12),
          Text(
            'Documentación ejecutiva, modelo de negocio, análisis de unit economics y detalles técnicos de la Ronda Seed de 1.000.000 €.',
            textAlign: TextAlign.center,
            style: tw(14, color: Tw.slate400),
          ),
          const SizedBox(height: 40),
          if (!_unlocked) _gate() else _docs(context),
        ]),
      );

  Widget _gate() {
    InputDecoration deco(String hint) => adminInputDecoration(hint, focus: Tw.purple500).copyWith(fillColor: Colors.black.withValues(alpha: 0.4), hintStyle: tw(14, color: Tw.slate600));
    Widget label(String t, {String? trailing}) => Padding(
          padding: const EdgeInsets.only(bottom: 4, top: 16),
          child: Row(children: [
            Expanded(child: Text(t, style: tw(12, weight: semibold, color: Tw.slate400))),
            if (trailing != null) Text(trailing, style: tw(10, color: Tw.slate500).copyWith(fontFamily: 'monospace')),
          ]),
        );
    final valid = _name.text.trim().isNotEmpty && _email.text.contains('@');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Tw.red500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.red500.withValues(alpha: 0.3))),
          child: Text(_error, style: tw(12, color: const Color(0xFFFCA5A5))),
        ),
      label('Nombre Completo *'),
      TextField(controller: _name, style: tw(14), decoration: deco('Ej. Carlos Mendoza')),
      label('Fondo / Vehículo de Inversión'),
      TextField(controller: _firm, style: tw(14), decoration: deco('Ej. K Fund / Business Angel')),
      label('Email Profesional *'),
      TextField(controller: _email, keyboardType: TextInputType.emailAddress, style: tw(14), decoration: deco('carlos@fondo.vc')),
      label('PIN de Inversor (Opcional)', trailing: 'Facilitado por el fundador'),
      TextField(
        controller: _pin,
        textCapitalization: TextCapitalization.characters,
        style: tw(14).copyWith(fontFamily: 'monospace'),
        decoration: deco('Introduce PIN de invitación'),
      ),
      const SizedBox(height: 24),
      Opacity(
        opacity: _loading || !valid ? 0.5 : 1,
        child: CtaButton(
          label: _loading ? 'Accediendo...' : 'Desbloquear Documentos',
          gradient: const [Tw.purple600, Color(0xFFDB2777)],
          onTap: _loading || !valid ? () {} : _unlock,
        ),
      ),
    ]);
  }

  Widget _docs(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(color: Tw.green500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.green500.withValues(alpha: 0.2))),
        child: Row(children: [
          Expanded(child: Text('✓ Acceso concedido al Data Room de Blow Nights.', style: tw(14, color: const Color(0xFF86EFAC)))),
          GestureDetector(
            onTap: () => setState(() => _unlocked = false),
            child: Text('Cerrar Sesión', style: tw(12, color: Tw.slate400, decoration: TextDecoration.underline)),
          ),
        ]),
      ),
      // The round's documents aren't served from the web (anyone could download them without the PIN): the founder
      // sends them by email. As the web's /investors (blow-nights-app #190).
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Tw.w(0.03), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('ONE-PAGER · PITCH DECK · DOSSIER', style: tw(11, weight: bold, color: Tw.purple400).copyWith(fontFamily: 'monospace'))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text('Confidencial', style: tw(11, color: Tw.slate300)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Documentos de la Ronda', style: tw(18, weight: bold)),
          const SizedBox(height: 4),
          Text('Por confidencialidad no se descargan desde la web: te los enviamos por correo, a la dirección con la que has accedido.',
              style: tw(12, color: Tw.slate400)),
          const SizedBox(height: 16),
          Pressable(
            onTap: () => _open('mailto:cesar@blownights.com?subject=${Uri.encodeComponent('Blow Nights Seed Round - Documentos')}'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Tw.purple600, borderRadius: BorderRadius.circular(12)),
              child: Text('Solicitar documentos', textAlign: TextAlign.center, style: tw(12, weight: bold)),
            ),
          ),
        ]),
      ),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Tw.purple900.withValues(alpha: 0.3), const Color(0xFF831843).withValues(alpha: 0.3)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Tw.purple500.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('REUNIÓN DE 30 MIN', style: tw(11, weight: bold, color: Tw.green400).copyWith(fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Text('Agendar Reunión con el Fundador', style: tw(18, weight: bold)),
          const SizedBox(height: 4),
          Text('Resuelve dudas de Due Diligence directamente con César Herrera Rojo (Fundador & CTO).', style: tw(12, color: Tw.slate400)),
          const SizedBox(height: 16),
          Pressable(
            onTap: () => _open('mailto:cesar@blownights.com?subject=${Uri.encodeComponent('Blow Nights Seed Round Due Diligence')}'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(12)),
              child: Text('CESAR@BLOWNIGHTS.COM', textAlign: TextAlign.center, style: tw(12, weight: black, color: Tw.black, tracking: 0.05)),
            ),
          ),
        ]),
      ),
    ]);
  }
}
