import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart' show PulseDot;
import '../../widgets/common.dart';
import '../../widgets/marketing.dart';

void mailPartners([String? subject]) =>
    launchUrl(Uri.parse('mailto:partners@blownights.com${subject != null ? '?subject=${Uri.encodeComponent(subject)}' : ''}'), mode: LaunchMode.externalApplication);

/// Port of components/PartnersLanding.tsx (City Manager franchise pitch: hot cities, 4 engines, split table, projections).
class PartnersLandingScreen extends StatefulWidget {
  const PartnersLandingScreen({super.key});

  @override
  State<PartnersLandingScreen> createState() => _PartnersLandingScreenState();
}

class _PartnersLandingScreenState extends State<PartnersLandingScreen> {
  List<Map<String, dynamic>> _hot = [];
  final _enginesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.collection('cities').where('readyForFranchise', isEqualTo: true).get().then((s) {
      if (mounted) setState(() => _hot = [for (final d in s.docs) {'id': d.id, ...d.data()}]);
    }).catchError((Object e) => debugPrint('Error fetching hot cities $e'));
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Stack(children: [
        SingleChildScrollView(
          padding: EdgeInsets.only(top: top + 80),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _hero(context),
            if (_hot.isNotEmpty) _hotCities(context),
            KeyedSubtree(key: _enginesKey, child: _engines(context)),
            _economics(context),
            _projections(context),
            _launch(context),
            Container(
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.w(0.1)))),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Tw.slate700, Tw.slate900]), borderRadius: BorderRadius.circular(4)),
                    child: Text('B', style: tw(12, weight: bold)),
                  ),
                  const SizedBox(width: 8),
                  Text('Blow Nights Network', style: tw(14, weight: semibold, color: Tw.slate400)),
                ]),
                const SizedBox(height: 12),
                Text('© ${DateTime.now().year} Blow Nights. ${context.t('partners_all_rights', fallback: 'Todos los derechos reservados.')}',
                    textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
              ]),
            ),
          ]),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(8, top + 12, 16, 12),
            decoration: BoxDecoration(color: Tw.slate950.withValues(alpha: 0.8), border: Border(bottom: BorderSide(color: Tw.w(0.1)))),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Tw.purple600, Tw.pink500]), borderRadius: BorderRadius.circular(4)),
                child: Text('B', style: tw(18, weight: bold)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('Blow Nights', style: tw(20, weight: bold))),
              Pressable(
                onTap: mailPartners,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(99)),
                  child: Text(context.t('request_territory'), style: tw(13, weight: semibold, color: Tw.black)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _hero(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 64),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Tw.purple500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Tw.purple500.withValues(alpha: 0.2)),
              ),
              child: Text(context.t('opportunity_city_managers'), style: tw(14, weight: medium, color: Tw.purple400)),
            ),
          ),
          const SizedBox(height: 24),
          Text.rich(
            TextSpan(style: tw(44, weight: FontWeight.w800, height: 1.1, tracking: -0.02), children: [
              const TextSpan(text: 'El '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GradientText(context.t('operating_system'), style: tw(44, weight: FontWeight.w800, height: 1.1), colors: const [Tw.purple400, Tw.pink500]),
              ),
              TextSpan(text: '\n${context.t('lgtbiq_nightlife')}'),
            ]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            context.t('partners_hero_desc',
                fallback:
                    'Las apps de citas y las ticketeras genéricas son obsoletas. Únete a la plataforma definitiva que unifica radar social, venta de entradas, RRPPs y afters privados. Operamos la tecnología, tú lideras tu ciudad.'),
            textAlign: TextAlign.center,
            style: tw(18, color: Tw.slate400, height: 1.6),
          ),
          const SizedBox(height: 40),
          CtaButton(label: context.t('contact_team'), gradient: const [Tw.purple600, Tw.pink500], onTap: mailPartners),
          const SizedBox(height: 12),
          Pressable(
            onTap: () {
              final ctx = _enginesKey.currentContext;
              if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(99), border: Border.all(color: Tw.w(0.1))),
              child: Text(context.t('view_business_model'), textAlign: TextAlign.center, style: tw(17, weight: semibold)),
            ),
          ),
        ]),
      );

  Widget _hotCities(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        decoration: BoxDecoration(
          color: Tw.slate900,
          border: Border.symmetric(horizontal: BorderSide(color: Tw.purple500.withValues(alpha: 0.2))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Tw.red500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Tw.red500.withValues(alpha: 0.2)),
              ),
              child: Label(context.t('immediate_opportunities'), size: 12, color: Tw.red400),
            ),
          ),
          const SizedBox(height: 12),
          Text(context.t('partners_hot_cities_title', fallback: 'Plazas con tracción listas para operar'), textAlign: TextAlign.center, style: tw(28, weight: bold)),
          const SizedBox(height: 8),
          Text(
            context.t('partners_hot_cities_desc',
                fallback: 'Estos territorios ya tienen locales usando la plataforma y pagando su cuota. Reclama la plaza hoy y empieza a cobrar su margen mañana.'),
            textAlign: TextAlign.center,
            style: tw(14, color: Tw.slate400),
          ),
          const SizedBox(height: 32),
          for (final c in _hot)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(_cap((c['name'] ?? c['slug'] ?? c['id']) as String), style: tw(24, weight: black)),
                  ),
                  Icon(Icons.map_outlined, size: 32, color: Tw.w(0.1)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const PulseDot(color: Tw.green500),
                  const SizedBox(width: 8),
                  Text(context.t('partners_active_venues', fallback: '{{count}} locales activos', params: {'count': c['activeVenuesCount'] ?? 2}),
                      style: tw(14, weight: bold, color: Tw.green400)),
                ]),
                const SizedBox(height: 24),
                Pressable(
                  onTap: () => mailPartners('Solicitud Franquicia ${c['slug']}'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
                    child: Text(context.t('request_exclusivity'), textAlign: TextAlign.center, style: tw(15, weight: bold)),
                  ),
                ),
              ]),
            ),
        ]),
      );

  Widget _engines(BuildContext context) {
    Widget engine(IconData icon, Color color, String tk, String tf, String dk, String df, List<(String, String)> feats) => Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Tw.slate900, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tw.w(0.05))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: 24),
            Text(context.t(tk, fallback: tf), style: tw(22, weight: bold)),
            const SizedBox(height: 12),
            Text(context.t(dk, fallback: df), style: tw(15, color: Tw.slate400, height: 1.5)),
            const SizedBox(height: 16),
            for (final (k, f) in feats)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.t(k, fallback: f), style: tw(14, color: Tw.slate500))),
                ]),
              ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 48),
      decoration: BoxDecoration(color: Tw.slate950, border: Border(top: BorderSide(color: Tw.w(0.1)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionHeader(context.t('four_engines_title'),
            subtitle: context.t('partners_engines_desc', fallback: 'Infraestructura probada y lista para desplegar en tu ciudad en 48 horas.')),
        const SizedBox(height: 48),
        engine(Icons.confirmation_number_outlined, Tw.purple400, 'partners_engine1_title', '1. Ticketing & Control de Puerta', 'partners_engine1_desc',
            'Cobros online directos mediante Stripe. El local emite factura (0 riesgo para ti). Escáner de porteros vía navegador (<300ms) sin apps ni colas.', const [
          ('partners_engine1_feat1', 'Split de pagos automatizado'),
          ('partners_engine1_feat2', 'Venta anticipada sin fricción'),
        ]),
        engine(Icons.groups_outlined, Tw.pink400, 'partners_engine2_title', '2. Sistema RRPP y Bizum', 'partners_engine2_desc',
            'Emisión libre de QR y cobro en mano/Bizum sin intermediación. Liquidación a dos bandas a final de la noche que evita discrepancias de caja.', const [
          ('partners_engine2_feat1', 'Enlaces promotor que se autodestruyen'),
          ('partners_engine2_feat2', 'Gestión ultra-rápida por WhatsApp'),
        ]),
        engine(Icons.dark_mode_outlined, Tw.blue400, 'partners_engine3_title', '3. Afters / Chills Privados', 'partners_engine3_desc',
            'El negocio de las 05:00 AM. Radar difuso de afters bajo "Hard Paywall". Para ver la ubicación y chatear, el usuario paga una membresía VIP.', const [
          ('partners_engine3_feat1', 'Autodestrucción a las 8h (TTL)'),
          ('partners_engine3_feat2', 'Ingreso altísimo por suscripciones'),
        ]),
        engine(Icons.map_outlined, Tw.green400, 'partners_engine4_title', '4. Radar Social en Vivo', 'partners_engine4_desc',
            'Directorio interactivo de discotecas, bares de copas y saunas. Aforos en tiempo real y check-in presencial para ver quién está en cada local.', const [
          ('partners_engine4_feat1', 'Interacción sin fricción'),
          ('partners_engine4_feat2', 'Retención brutal de usuarios'),
        ]),
      ]),
    );
  }

  Widget _economics(BuildContext context) {
    final rows = [
      (context.t('partners_row_tickets_cm', fallback: 'Venta de Entradas (City Manager)'), '5% + 0,50€', '4% + 0,25€', '1% + 0,25€', false, false),
      (context.t('partners_row_basic', fallback: 'Plan Basic (SaaS)*'), context.t('super_admin.price_50_month', fallback: '50,00€ / mes'), '20,00€ / mes', '30,00€ / mes', true, false),
      (context.t('partners_row_promo', fallback: 'Plan Promo (SaaS + Promos)*'), context.t('super_admin.price_100_month', fallback: '100,00€ / mes'), '40,00€ / mes', '60,00€ / mes', true,
          false),
      (context.t('partners_row_ticketing', fallback: 'Plan Ticketing (SaaS + Eventos)*'), context.t('super_admin.price_180_month', fallback: '180,00€ / mes'), '72,00€ / mes',
          '108,00€ / mes', true, false),
      (context.t('partners_row_ticketing_partner', fallback: 'Ticketing (Partner Asociado)*'), '5% + 0,50€', '2% + 0,25€', '3% + 0,25€', true, false),
      (context.t('partners_row_weekend_pass', fallback: 'Pase Fin de Semana VIP (48h)'), '10,00€', '4,00€ (40%)', '6,00€ (60%)', false, false),
      (context.t('partners_row_vip_monthly', fallback: 'Blow VIP Mensual'), '20,00€/mes', '8,00€/mes (40%)', '12,00€/mes (60%)', false, true),
      (context.t('partners_row_vip_season', fallback: 'Blow VIP Temporada (3 Meses)'), '50,00€', '20,00€ (40%)', '30,00€ (60%)', false, false),
    ];
    Widget cell(String text, {TextStyle? style, Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(text, style: style ?? tw(14, color: Tw.slate400)), ?trailing]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 48),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.w(0.1)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Label(context.t('super_admin.revenue_split_tag', fallback: 'Revenue Split'), size: 14, weight: semibold, color: Tw.purple400, align: TextAlign.center),
        const SizedBox(height: 8),
        SectionHeader(context.t('economic_model'),
            subtitle: context.t('partners_economic_desc',
                fallback:
                    'Un modelo diseñado para que el City Manager gane por dos vías: comisión de entradas y suscripciones VIP de usuarios. Todo liquidado automáticamente a tu cuenta bancaria vía Stripe.')),
        const SizedBox(height: 40),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              TableRow(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.w(0.1)))), children: [
                cell(context.t('partners_th_channel', fallback: 'Canal de Ingreso'), style: tw(14, weight: medium, color: Tw.slate400)),
                cell(context.t('partners_th_price', fallback: 'Tarifa PVP'), style: tw(14, weight: medium, color: Tw.slate400)),
                cell(context.t('partners_th_partner', fallback: 'Socio Local (Tú)'), style: tw(14, weight: semibold)),
                cell(context.t('partners_th_platform', fallback: 'Plataforma'), style: tw(14, weight: medium, color: Tw.slate400)),
              ]),
              for (final (channel, price, partner, platform, amber, popular) in rows)
                TableRow(
                  decoration: BoxDecoration(
                    color: amber ? Tw.amber500.withValues(alpha: 0.05) : popular ? Tw.w(0.02) : null,
                    border: Border(
                      bottom: BorderSide(color: Tw.w(0.05)),
                      left: amber ? const BorderSide(color: Tw.amber500, width: 4) : BorderSide.none,
                    ),
                  ),
                  children: [
                    cell(
                      channel,
                      style: tw(14, weight: medium, color: amber ? Tw.amber500 : Tw.white),
                      trailing: popular
                          ? Container(
                              margin: const EdgeInsets.only(left: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Tw.purple500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                              child: Label(context.t('partners_popular', fallback: 'Popular'), weight: bold, color: Tw.purple400, tracking: 0),
                            )
                          : null,
                    ),
                    cell(price),
                    cell(partner, style: tw(14, weight: bold, color: amber ? Tw.amber500 : Tw.green400)),
                    cell(platform),
                  ],
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _projections(BuildContext context) {
    Widget line(String label, String value, {Color valueColor = Tw.white, Color labelColor = Tw.slate400, bool last = false, bool red = false}) => Container(
          padding: const EdgeInsets.only(bottom: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: Tw.w(0.05)))),
          child: Row(children: [
            Expanded(child: Text(label, style: tw(14, color: red ? Tw.red400 : labelColor))),
            Text(value, style: tw(14, weight: red ? FontWeight.w400 : semibold, color: red ? Tw.red400 : valueColor)),
          ]),
        );
    Widget phase({
      required String title,
      required String sub,
      required String amount,
      required String unit,
      required List<Widget> lines,
      bool featured = false,
      Widget? footnote,
    }) =>
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: featured ? Tw.slate800 : Tw.slate900,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: featured ? Tw.purple500 : Tw.w(0.1), width: featured ? 2 : 1),
                boxShadow: featured ? [BoxShadow(color: Tw.purple500.withValues(alpha: 0.3), blurRadius: 40, spreadRadius: -10)] : null,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, style: tw(20, weight: semibold, color: featured ? Tw.white : Tw.slate300)),
                Text(sub, style: tw(14, color: featured ? const Color(0xFFD8B4FE) : Tw.slate500)),
                const SizedBox(height: 24),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '$amount ', style: tw(featured ? 44 : 36, weight: bold)),
                  TextSpan(text: unit, style: tw(featured ? 18 : 16, color: featured ? const Color(0xFFD8B4FE) : Tw.slate500)),
                ])),
                const SizedBox(height: 24),
                ...lines,
                ?footnote,
              ]),
            ),
            if (featured)
              Positioned(
                top: -12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(color: Tw.purple500, borderRadius: BorderRadius.circular(99)),
                    child: Label(context.t('partners_realistic_target', fallback: 'Objetivo Realista'), size: 12, weight: bold, color: Tw.white, tracking: 0.05),
                  ),
                ),
              ),
          ]),
        );
    String tickets = context.t('partners_tickets_month', fallback: 'Tickets/mes');
    String ticketRev = context.t('partners_ticketing_revenue', fallback: 'Ingreso Ticketing');
    String vip = context.t('partners_vip_users', fallback: 'Usuarios VIP');
    String subs = context.t('partners_subscription_revenue', fallback: 'Ingreso Suscripciones');
    String fee = context.t('partners_annual_fee', fallback: 'Canon anual');
    String active(int n) => context.t('partners_active_count', fallback: '{{count}} activos', params: {'count': n});

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 48),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tw.slate950, Tw.slate900]),
        border: Border(top: BorderSide(color: Tw.w(0.1))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionHeader(context.t('financial_projection'),
            subtitle: context.t('partners_projection_desc',
                fallback:
                    'Estimación de rentabilidad para una ciudad con circuito nocturno activo. Un modelo de alto margen (canon de 5.000€/año) que recuperas en el primer cuatrimestre.')),
        const SizedBox(height: 48),
        phase(
          title: context.t('partners_phase_initial', fallback: 'Fase Inicial'),
          sub: context.t('partners_phase_initial_sub', fallback: '1-2 locales captados'),
          amount: '~15.100€',
          unit: '/ año netos',
          lines: [
            line(tickets, '1.500 (18€/ud)'),
            line(ticketRev, '+17.460€', valueColor: Tw.green400),
            line(vip, active(50)),
            line(subs, '+2.640€', valueColor: Tw.green400),
            line(fee, '-5.000€', red: true, last: true),
          ],
        ),
        const SizedBox(height: 8),
        phase(
          featured: true,
          title: context.t('partners_phase_moderate', fallback: 'Fase Moderada'),
          sub: context.t('partners_phase_moderate_sub', fallback: '2-3 locales / 1 sesión fuerte'),
          amount: '~35.100€',
          unit: '/ año',
          lines: [
            line(tickets, '3.000 (20€/ud)', labelColor: Tw.slate300),
            line(ticketRev, '+37.800€', valueColor: Tw.green400, labelColor: Tw.slate300),
            line(vip, active(150), labelColor: Tw.slate300),
            line(subs, '+7.920€', valueColor: Tw.green400, labelColor: Tw.slate300),
            line(fee, '-5.000€', red: true, last: true),
          ],
          footnote: Text(context.t('partners_footnote_tickets', fallback: '*3.000 tickets/mes son apenas el 5-8% del ocio de una capital.'),
              textAlign: TextAlign.center, style: tw(12, color: Tw.slate400, style: FontStyle.italic)),
        ),
        phase(
          title: context.t('partners_phase_consolidated', fallback: 'Fase Consolidada'),
          sub: context.t('partners_phase_consolidated_sub', fallback: 'Circuito completo dominado'),
          amount: '~72.600€',
          unit: '/ año netos',
          lines: [
            line(tickets, '6.000 (20€/ud)'),
            line(ticketRev, '+75.600€', valueColor: Tw.green400),
            line(vip, active(300)),
            line(subs, '+15.840€', valueColor: Tw.green400),
            line(fee, '-5.000€', red: true, last: true),
          ],
        ),
      ]),
    );
  }

  Widget _launch(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 72, 24, 72),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Tw.purple900.withValues(alpha: 0.2), Colors.transparent]),
        ),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Tw.slate900.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(40), border: Border.all(color: Tw.w(0.1))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.t('launch_48h'), textAlign: TextAlign.center, style: tw(28, weight: bold)),
            const SizedBox(height: 24),
            Text(
              context.t('partners_launch_desc',
                  fallback:
                      'Te entregamos la plataforma operativa en tu ciudad ([ciudad].blownights.com), vinculada a tu cuenta de Stripe. Arranca ofreciendo un "Piloto sin Fricción" a los garitos 100% gratis la primera sesión para demostrar el valor.'),
              textAlign: TextAlign.center,
              style: tw(17, color: Tw.slate400, height: 1.6),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('partners_cm_exclusive', fallback: 'City Manager (Exclusivo)'), style: tw(14, color: Tw.slate500)),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '5.000 € ', style: tw(24, weight: bold)),
                  TextSpan(text: '/ año', style: tw(14, color: Tw.slate500)),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
            Pressable(
              onTap: mailPartners,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(16)),
                child: Text(context.t('request_interview'), textAlign: TextAlign.center, style: tw(18, weight: bold, color: Tw.black)),
              ),
            ),
            const SizedBox(height: 24),
            Text(context.t('partners_one_license', fallback: 'Solo 1 licencia exclusiva por área metropolitana.'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
            const SizedBox(height: 40),
            Divider(color: Tw.w(0.1)),
            const SizedBox(height: 40),
            Row(children: [
              const Icon(Icons.star, color: Tw.amber500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.t('partners_macro_city_q', fallback: '¿Vives en una macro-ciudad (Madrid/Barcelona)?'), style: tw(20, weight: bold, color: Tw.amber500)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              context.t('partners_associated_desc',
                  fallback:
                      'Aplica a la figura de Partner Asociado. Sin exclusividad territorial y sin canon de entrada (0€). Cobra comisión (2% + 0,10€) por cada entrada de los locales que afilies a la red. Tus locales tendrán visibilidad plus (anclados arriba y destacados en oro en el mapa).'),
              style: tw(14, color: Tw.slate400, height: 1.5),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => mailPartners('Partner Asociado'),
              child: Text('${context.t('partners_apply_associated', fallback: 'Aplicar como Partner Asociado')} →', style: tw(14, weight: bold, color: Tw.amber400)),
            ),
          ]),
        ),
      );
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
