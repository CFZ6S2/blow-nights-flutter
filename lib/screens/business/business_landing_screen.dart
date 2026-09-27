import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart' show PulseDot;
import '../../widgets/common.dart';
import '../../widgets/marketing.dart';
import 'promoter_screens.dart' show openWhatsApp;

/// Port of app/business/page.tsx (venue B2B landing: Custom Mode module matrix, modules, radar pitch, steps, CTA).
class BusinessLandingScreen extends StatefulWidget {
  const BusinessLandingScreen({super.key});

  @override
  State<BusinessLandingScreen> createState() => _BusinessLandingScreenState();
}

class _BusinessLandingScreenState extends State<BusinessLandingScreen> {
  String _tab = 'all';
  final _toggles = {'radar': true, 'ticketing': true, 'drinks': true, 'door': true, 'rrpp': true};
  final _customKey = GlobalKey();
  static const _wa = 'Hola Blow Nights, tengo un local y quiero información sobre vuestros módulos en Custom Mode.';

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Stack(children: [
        AmbientGlow(colors: [Tw.fuchsia600.withValues(alpha: 0.1), Tw.indigo600.withValues(alpha: 0.1), const Color(0xFFDB2777).withValues(alpha: 0.1)]),
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, top + 96, 24, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _hero(context),
            const SizedBox(height: 56),
            KeyedSubtree(key: _customKey, child: _customMode(context)),
            const SizedBox(height: 48),
            if (_tab == 'all' || _tab == 'ticketing') _ticketingModule(context),
            if (_tab == 'all' || _tab == 'drinks') _drinksModule(context),
            if (_tab == 'all' || _tab == 'door') _doorModule(context),
            if (_tab == 'all' || _tab == 'rrpp') _rrppModule(context),
            const SizedBox(height: 32),
            _radar(context),
            const SizedBox(height: 56),
            SectionHeader(context.t('business_steps_title', fallback: 'Cómo empezamos a trabajar juntos'),
                subtitle: context.t('business_steps_subtitle', fallback: 'Sin obras, sin permanencias forzadas y con soporte personal')),
            const SizedBox(height: 32),
            StepCard(
              step: '01',
              title: context.t('business_step1_title', fallback: '1. Auditoría de tus necesidades'),
              desc: context.t('business_step1_desc',
                  fallback: 'Hablamos por llamada o WhatsApp para entender qué software o método usas hoy y qué te gustaría mejorar.'),
              color: Tw.fuchsia400,
            ),
            StepCard(
              step: '02',
              title: context.t('business_step2_title', fallback: '2. Configuración a la carta'),
              desc: context.t('business_step2_desc',
                  fallback: 'Te activamos solo lo que sume: catálogo de copas, accesos, RRPPs o simplemente visibilidad de afluencia.'),
              color: Tw.indigo400,
            ),
            StepCard(
              step: '03',
              title: context.t('business_step3_title', fallback: '3. Marcha blanca en directo'),
              desc: context.t('business_step3_desc', fallback: 'Probamos un fin de semana sin riesgo. Si te convence, sigues con nosotros.'),
              color: Tw.emerald400,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Tw.fuchsia950.withValues(alpha: 0.4), Tw.indigo950.withValues(alpha: 0.4), Tw.slate900]),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Tw.w(0.1)),
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified_user, size: 14, color: Tw.fuchsia400),
                    const SizedBox(width: 8),
                    Label(context.t('business_guarantee_badge', fallback: 'Cero Fricción'), color: Tw.white),
                  ]),
                ),
                const SizedBox(height: 16),
                Text(context.t('business_guarantee_title', fallback: '«El software que no estorba a tu equipo»'), textAlign: TextAlign.center, style: tw(24, weight: black)),
                const SizedBox(height: 12),
                Text(
                  context.t('business_guarantee_desc',
                      fallback:
                          'Los camareros y porteros no quieren cursos de 3 horas ni sistemas lentos. Nuestras herramientas de barra y puerta están diseñadas para responder en milisegundos incluso con guantes, poca luz y ruido alto.'),
                  textAlign: TextAlign.center,
                  style: tw(14, color: Tw.slate300, height: 1.6),
                ),
              ]),
            ),
            const SizedBox(height: 56),
            SectionHeader(context.t('business_cta_title', fallback: 'Hablemos de tu local y de lo que necesitas'),
                subtitle: context.t('business_cta_subtitle', fallback: 'Escríbenos directamente o regístrate en el panel en 2 minutos para ver la plataforma por dentro.')),
            const SizedBox(height: 24),
            CtaButton(
              label: context.t('business_cta_register', fallback: 'Crear Cuenta de Negocio'),
              icon: Icons.arrow_forward,
              gradient: const [Tw.fuchsia600, Tw.indigo600],
              onTap: () => openRoute(context, AppRoute.business),
            ),
            const SizedBox(height: 12),
            CtaButton(label: context.t('business_cta_whatsapp_btn', fallback: 'Contactar con el Equipo'), leadingIcon: Icons.chat, tint: Tw.emerald400, onTap: () => openWhatsApp(_wa)),
            const SizedBox(height: 48),
            Divider(color: Tw.w(0.1)),
            const SizedBox(height: 24),
            Text('© ${DateTime.now().year} ${context.t('business_footer_copyright', fallback: 'Blow Nights. Todos los derechos reservados.')}',
                textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(onPressed: () => openRoute(context, AppRoute.privacy), child: Text('Privacidad', style: tw(12, color: Tw.slate400))),
              TextButton(onPressed: () => openRoute(context, AppRoute.terms), child: Text('Términos', style: tw(12, color: Tw.slate400))),
            ]),
          ]),
        ),
        MarketingNav(
          top: top,
          icon: Icons.business,
          gradient: const [Tw.fuchsia600, Tw.indigo600],
          brand: 'Venues',
          brandColors: const [Tw.fuchsia400, Tw.indigo400],
          cta: context.t('business_nav_venue_access', fallback: 'Acceso Locales'),
          onCta: () => openRoute(context, AppRoute.business),
        ),
      ]),
    );
  }

  Widget _hero(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: PillBadge(icon: Icons.auto_awesome, text: context.t('business_hero_badge_carta_blanca', fallback: 'Custom Mode: 100% adaptable a tu operativa'), color: Tw.fuchsia400),
        ),
        const SizedBox(height: 24),
        GradientText(context.t('business_hero_title_accent', fallback: 'Tu Local, Tus Reglas.'),
            style: tw(38, weight: black, height: 1.08, tracking: -0.02), colors: const [Tw.fuchsia400, Tw.pink400, Tw.indigo400]),
        const SizedBox(height: 12),
        Text(
          context.t('business_hero_title_lead', fallback: 'La plataforma que se adapta a tu manera de trabajar con entradas, barras y promotores.'),
          textAlign: TextAlign.center,
          style: tw(22, weight: FontWeight.w800, color: const Color(0xFFF1F5F9), height: 1.2),
        ),
        const SizedBox(height: 20),
        Text(
          context.t('business_hero_subtitle_carta_blanca',
              fallback: 'Tú eliges qué servicios activas, bajo qué reglas y cómo interactúas con la app. Sin ataduras ni obligaciones de cambiar tu TPV o proveedores.'),
          textAlign: TextAlign.center,
          style: tw(16, color: Tw.slate400, height: 1.6),
        ),
        const SizedBox(height: 24),
        CtaButton(
          label: context.t('business_hero_cta_explore', fallback: 'Explorar Módulos'),
          icon: Icons.arrow_forward,
          gradient: const [Tw.fuchsia600, Tw.indigo600],
          onTap: () {
            final ctx = _customKey.currentContext;
            if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
          },
        ),
        const SizedBox(height: 12),
        CtaButton(label: context.t('business_hero_cta_whatsapp', fallback: 'Hablar por WhatsApp'), leadingIcon: Icons.chat, tint: Tw.emerald400, onTap: () => openWhatsApp(_wa)),
        const SizedBox(height: 24),
        for (final (key, fb, c) in [
          ('business_stat_venues_active', '+120 locales conectados', Tw.emerald400),
          ('business_stat_conversion', 'Venta directa sin comisiones abusivas', Tw.fuchsia400),
          ('business_stat_instant_setup', 'Listo en menos de 24h', Tw.indigo400),
        ])
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(color: Tw.w(0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle, size: 16, color: c),
              const SizedBox(width: 8),
              Flexible(child: Text(context.t(key, fallback: fb), style: tw(12, weight: semibold, color: Tw.slate400))),
            ]),
          ),
      ]);

  Widget _customMode(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: PillBadge(icon: Icons.tune, text: context.t('business_cb_badge', fallback: 'Custom Mode'), color: Tw.indigo400)),
        const SizedBox(height: 16),
        SectionHeader(context.t('business_cb_title', fallback: 'Tú decides qué funciona en tu local'),
            subtitle: context.t('business_cb_subtitle', fallback: 'Elige qué módulos activas, combínalos como quieras y define tus propias reglas de operación:')),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Tw.slate950.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              for (final (id, key, fb, icon) in const [
                ('all', 'business_cb_tab_all', 'Ver Todo el Ecosistema', Icons.layers),
                ('ticketing', 'business_cb_tab_ticketing', 'Venta de Entradas', Icons.qr_code_2),
                ('drinks', 'business_cb_tab_drinks', 'Barra & Consumiciones', Icons.wine_bar),
                ('door', 'business_cb_tab_door', 'Puerta & Aforo', Icons.verified_user),
                ('rrpp', 'business_cb_tab_rrpp', 'Listas & RRPPs', Icons.group),
              ])
                Pressable(
                  onTap: () => setState(() => _tab = id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: _tab == id ? const LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]) : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 14, color: _tab == id ? Tw.white : Tw.slate400),
                      const SizedBox(width: 6),
                      Label(context.t(key, fallback: fb), size: 11, color: _tab == id ? Tw.white : Tw.slate400, tracking: 0.05),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Tw.w(0.02), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(style: tw(12, color: Tw.slate400), children: [
                  TextSpan(text: 'Custom Mode: ', style: tw(12, weight: bold)),
                  TextSpan(text: context.t('business_cb_simulate', fallback: 'Simula tu combinación de módulos. Haz clic para activar/desactivar.')),
                ])),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (key, name) in const [
                    ('radar', 'Radar GPS'),
                    ('ticketing', 'Ticketing'),
                    ('drinks', 'Barra'),
                    ('door', 'Scanner Puerta'),
                    ('rrpp', 'Promotores Propios'),
                  ])
                    Pressable(
                      onTap: () => setState(() => _toggles[key] = !_toggles[key]!),
                      child: Opacity(
                        opacity: _toggles[key]! ? 1 : 0.6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _toggles[key]! ? Tw.fuchsia500.withValues(alpha: 0.2) : Tw.slate900,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _toggles[key]! ? Tw.fuchsia500.withValues(alpha: 0.4) : Tw.w(0.1)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            _toggles[key]!
                                ? const PulseDot(color: Tw.emerald400)
                                : Container(width: 8, height: 8, decoration: const BoxDecoration(color: Tw.slate600, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Label('$name: ${_toggles[key]! ? 'ACTIVO' : 'OFF'}', size: 11, color: _toggles[key]! ? Tw.fuchsia300 : Tw.slate500, tracking: 0.05),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            Text(context.t('business_cb_toggle_notice', fallback: 'Cualquiera de estos módulos puede funcionar de forma 100% independiente o combinada.'),
                textAlign: TextAlign.center, style: tw(12, color: Tw.slate500, style: FontStyle.italic)),
          ]),
        ),
      ]);

  Widget _module({
    required Color color,
    required IconData badgeIcon,
    required String badge,
    required String title,
    required String tagline,
    required List<String> feats,
    required Widget note,
    required Widget preview,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 32),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.slate900.withValues(alpha: 0.9), Tw.slate950]),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(badgeIcon, size: 14, color: color),
                const SizedBox(width: 8),
                Flexible(child: Label(badge, size: 11, color: color)),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Text(title, style: tw(28, weight: black, height: 1.15)),
          const SizedBox(height: 12),
          Text(tagline, style: tw(16, weight: medium, color: Tw.slate300)),
          const SizedBox(height: 16),
          for (final f in feats)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: Icon(Icons.check_circle, size: 14, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(f, style: tw(14, color: Tw.slate300))),
              ]),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.w(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
            child: note,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Tw.slate950.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
            child: preview,
          ),
        ]),
      );

  Widget _previewHeader(String title, String tag, Color tagColor) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(children: [
          Row(children: [
            Expanded(child: Label(title, size: 12, weight: bold, tracking: 0.05)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: tagColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
              child: Text(tag, style: tw(10, weight: black, color: tagColor)),
            ),
          ]),
          const SizedBox(height: 12),
          Divider(height: 1, color: Tw.w(0.1)),
        ]),
      );

  Widget _row(IconData icon, Color iconColor, String left, String right, Color rightColor) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
        child: Row(children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(child: Text(left, style: tw(12, weight: bold))),
          Text(right, style: tw(12, weight: bold, color: rightColor)),
        ]),
      );

  Widget _ticketingModule(BuildContext context) => _module(
        color: Tw.fuchsia400,
        badgeIcon: Icons.qr_code_2,
        badge: 'Módulo 01 · Ticketing & Venta',
        title: context.t('business_mod_ticketing_title', fallback: 'Ticketing Flexible y a Tu Medida'),
        tagline: context.t('business_mod_ticketing_tagline', fallback: 'Vende con tus tramos, tus cupos y tus condiciones de acceso'),
        feats: [
          context.t('business_mod_ticketing_feat1', fallback: 'Pagos directos a tu cuenta Stripe sin retenciones injustificadas.'),
          context.t('business_mod_ticketing_feat2', fallback: 'Entradas con QR dinámico anticopia y offline-first.'),
          context.t('business_mod_ticketing_feat3', fallback: 'Reservados VIP, botellas y tramos horarios con aforo configurable.'),
        ],
        note: Row(children: [
          const Icon(Icons.open_in_new, size: 16, color: Tw.fuchsia400),
          const SizedBox(width: 12),
          Expanded(
            child: Text(context.t('business_mod_ticketing_link_mode', fallback: '¿Ya vendes en otra ticketera? Enlazamos tu ticketera externa sin problema.'),
                style: tw(12, weight: bold, color: Tw.slate400)),
          ),
        ]),
        preview: Column(children: [
          _previewHeader('Preview Entrada Digital', 'VALIDADA', Tw.emerald400),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Tw.fuchsia950.withValues(alpha: 0.4), Tw.indigo950.withValues(alpha: 0.4)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
            ),
            child: Column(children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.qr_code_2, size: 60, color: Tw.slate950),
              ),
              const SizedBox(height: 12),
              Text('General + 1 Consumición', style: tw(14, weight: black)),
              Text('Acceso antes de las 02:00h', style: tw(12, weight: semibold, color: Tw.fuchsia400)),
              const SizedBox(height: 8),
              Divider(color: Tw.w(0.1)),
              Row(children: [
                Text('Pago directo Stripe', style: tw(11, color: Tw.slate400)),
                const Spacer(),
                Text('18,00 €', style: tw(11, weight: bold)),
              ]),
            ]),
          ),
        ]),
      );

  Widget _drinksModule(BuildContext context) => _module(
        color: Tw.amber400,
        badgeIcon: Icons.wine_bar,
        badge: 'Módulo 02 · Barra & Consumiciones',
        title: context.t('business_mod_drinks_title', fallback: 'Gestión de Bebidas & Consumiciones'),
        tagline: context.t('business_mod_drinks_tagline', fallback: 'Elimina colas en barra y fraudes con vales de papel'),
        feats: [
          context.t('business_mod_drinks_feat1', fallback: 'Consumiciones incluidas en entrada canjeables con 1 toque en barra.'),
          context.t('business_mod_drinks_feat2', fallback: 'Carta digital y venta anticipada de botellas y copas con descuento.'),
          context.t('business_mod_drinks_feat3', fallback: 'Scanner de barman ultra-rápido para móviles, tablets o TPV existente.'),
        ],
        note: Text.rich(TextSpan(style: tw(12, color: Tw.slate400), children: [
          TextSpan(text: 'Custom Mode: ', style: tw(12, weight: bold, color: const Color(0xFFFCD34D))),
          TextSpan(text: context.t('business_mod_drinks_custom', fallback: 'Personaliza suplementos de marcas premium según tu propio stock.')),
        ])),
        preview: Column(children: [
          _previewHeader('Barra Express / Scanner', '1-CLICK', Tw.amber400),
          _row(Icons.wine_bar, Tw.amber400, 'Copa Nacional (Valet)', 'Canjeada (0€)', Tw.emerald400),
          _row(Icons.wine_bar, Tw.amber400, 'Suplemento Premium', '+3,00 €', Tw.white),
          _row(Icons.bolt, Tw.amber400, 'Pack 2 Red Bull + Ron', '14,00 €', Tw.white),
        ]),
      );

  Widget _doorModule(BuildContext context) => _module(
        color: Tw.indigo400,
        badgeIcon: Icons.verified_user,
        badge: 'Módulo 03 · Control de Puerta',
        title: context.t('business_mod_door_title', fallback: 'Control de Accesos en Puerta'),
        tagline: context.t('business_mod_door_tagline', fallback: 'Validación en menos de 0.4 segundos sin aparatos caros'),
        feats: [
          context.t('business_mod_door_feat1', fallback: 'Escaneo desde cualquier smartphone: da de alta a porteros en segundos.'),
          context.t('business_mod_door_feat2', fallback: 'Contador de afluencia y sincronización en vivo con el Radar de la ciudad.'),
          context.t('business_mod_door_feat3', fallback: 'Modo offline garantizado ante caídas de cobertura en sótanos o salas.'),
        ],
        note: Text.rich(TextSpan(style: tw(12, color: Tw.slate400), children: [
          TextSpan(text: 'Seguridad Total: ', style: tw(12, weight: bold, color: const Color(0xFFA5B4FC))),
          TextSpan(text: context.t('business_mod_door_roles', fallback: 'Gestión de personal de puerta con permisos independientes y revocables.')),
        ])),
        preview: Column(children: [
          _previewHeader('Terminal de Puerta', 'EN LÍNEA (OFFLINE READY)', Tw.emerald400),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Tw.emerald500.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
            ),
            child: Column(children: [
              Label('Entrada Válida', size: 12, color: Tw.emerald400, tracking: 0),
              Text('Carlos Romero + 1', style: tw(18, weight: black)),
              Text('Acceso VIP · Lista RRPP: Marcos', style: tw(11, color: Tw.slate400)),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            for (final (label, value, c) in const [('AFORO ACTUAL', '412 / 600', Tw.white), ('TIEMPO ESCANEO', '0.32 s', Tw.emerald400)]) ...[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
                  child: Column(children: [
                    Text(label, style: tw(10, color: Tw.slate400)),
                    Text(value, style: tw(16, weight: black, color: c)),
                  ]),
                ),
              ),
              if (label == 'AFORO ACTUAL') const SizedBox(width: 8),
            ],
          ]),
        ]),
      );

  Widget _rrppModule(BuildContext context) => _module(
        color: Tw.emerald400,
        badgeIcon: Icons.group,
        badge: 'Módulo 04 · Promotores Propios del Local',
        title: context.t('business_mod_rrpp_title', fallback: 'Red de RRPPs y Listas Automatizadas'),
        tagline: context.t('business_mod_rrpp_tagline', fallback: 'Potencia a tu equipo de relaciones públicas con métricas reales'),
        feats: [
          context.t('business_mod_rrpp_feat1', fallback: 'Links únicos por promotor para saber exactamente quién llena tu sala.'),
          context.t('business_mod_rrpp_feat2', fallback: 'Cálculo automatizado de comisiones y liquidaciones transparentes.'),
          context.t('business_mod_rrpp_feat3', fallback: 'Validación de listas en puerta por nombre o QR sin hojas de papel mojadas.'),
        ],
        note: Text.rich(TextSpan(style: tw(12, color: Tw.slate400), children: [
          TextSpan(text: 'Independencia Controlada: ', style: tw(12, weight: bold, color: const Color(0xFF6EE7B7))),
          TextSpan(text: context.t('business_mod_rrpp_claim', fallback: 'Permite a tus RRPPs gestionar sus invitados mientras tú mantienes el control total.')),
        ])),
        preview: Column(children: [
          _previewHeader('Ranking de RRPPs (En Directo)', 'ESTA NOCHE', Tw.fuchsia400),
          for (final (rank, name, guests, commission) in const [
            ('🥇', 'Alex M. (VIP)', 64, '128 €'),
            ('🥈', 'Laura B. (Listas)', 48, '96 €'),
            ('🥉', 'Javi R. (Erasmus)', 35, '70 €'),
          ])
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
              child: Row(children: [
                Text(rank),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: tw(12, weight: bold))),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$guests pax', style: tw(12, weight: bold)),
                  Text(commission, style: tw(10, color: Tw.slate400)),
                ]),
              ]),
            ),
        ]),
      );

  Widget _radar(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Tw.w(0.02), borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(alignment: Alignment.centerLeft, child: PillBadge(icon: Icons.radar, text: context.t('business_radar_badge', fallback: 'Impacto en directo'), color: Tw.fuchsia400)),
          const SizedBox(height: 20),
          Text(context.t('business_radar_title', fallback: 'Aparece justo cuando están decidiendo'), style: tw(30, weight: black, height: 1.15)),
          const SizedBox(height: 16),
          Text(
            context.t('business_radar_desc',
                fallback:
                    'El usuario de ocio nocturno abre Blow Nights cuando está en la calle, en el taxi o en la previa decidiendo a dónde ir. Si tu local tiene ambiente o una oferta atractiva, el radar los guía directos a tu puerta.'),
            style: tw(15, color: Tw.slate400, height: 1.6),
          ),
          const SizedBox(height: 16),
          for (final (icon, c, key, fb) in const [
            (Icons.local_fire_department, Tw.orange400, 'business_radar_fuego', 'Indicador Fuego: cuando el local está al máximo'),
            (Icons.bolt, Tw.yellow400, 'business_radar_promos', 'Promos Flash: lanza ofertas en 5 km a la redonda en minutos'),
            (Icons.bar_chart, Tw.emerald400, 'business_radar_agenda', 'Agenda de Eventos: visibilidad garantizada en la ciudad'),
          ])
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
              child: Row(children: [
                Icon(icon, color: c),
                const SizedBox(width: 12),
                Expanded(child: Text(context.t(key, fallback: fb), style: tw(14, weight: semibold, color: Tw.slate300))),
              ]),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(40), border: Border.all(color: Tw.w(0.15), width: 2)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 112, height: 16, decoration: BoxDecoration(color: Tw.slate950, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 12),
              Row(children: [
                Text('BlowNights Radar', style: tw(12, weight: black, color: Tw.fuchsia400)),
                const Spacer(),
                Text('23:45 · Vía Augusta', style: tw(10, color: Tw.slate500)),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Tw.fuchsia600.withValues(alpha: 0.3), Tw.indigo600.withValues(alpha: 0.3)]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('TU LOCAL', style: tw(12, weight: black)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Tw.orange500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.local_fire_department, size: 12, color: Tw.orange400),
                        const SizedBox(width: 4),
                        Text('FUEGO', style: tw(9, weight: black, color: Tw.orange400)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('Pista al 85% · DJ Invitado', style: tw(11, color: Tw.slate300)),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: Tw.w(0.1)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Text('Promo Flash: 2x1 hasta 01:30', style: tw(10, weight: bold, color: Tw.fuchsia300))),
                    Text('A 350m', style: tw(10, weight: black)),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
                child: Row(children: [
                  Expanded(child: Text('Personas viendo tu local ahora:', style: tw(11, color: Tw.slate400))),
                  Text('+184 en directo', style: tw(11, weight: bold, color: Tw.emerald400)),
                ]),
              ),
            ]),
          ),
        ]),
      );
}
