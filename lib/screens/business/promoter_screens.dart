import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/platform_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/common.dart';
import '../../widgets/marketing.dart';

const whatsappNumber = '34641382137';

void openWhatsApp(String text) =>
    launchUrl(Uri.parse('https://wa.me/$whatsappNumber?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);

/// Port of app/pr/page.tsx: list-link ticket generator (token mode) and the independent RRPP wallet panel.
class PromoterScreen extends StatefulWidget {
  final String? token, eventId, venueId;
  final bool success;
  const PromoterScreen({super.key, this.token, this.eventId, this.venueId, this.success = false});

  @override
  State<PromoterScreen> createState() => _PromoterScreenState();
}

class _PromoterScreenState extends State<PromoterScreen> {
  final _client = TextEditingController();
  bool _loading = false;
  ({String ticketId, String clientName})? _result;
  String _error = '';
  int _count = 0;

  int? _quota;
  List<Map<String, dynamic>> _tickets = [];
  bool _loadingWallet = false;
  late final _venue = TextEditingController(text: widget.venueId ?? '');
  final _batch = TextEditingController();
  bool _buying = false;
  bool _walletLoaded = false;

  bool get _tokenMode => widget.token?.isNotEmpty == true && widget.eventId?.isNotEmpty == true;

  @override
  void dispose() {
    _client.dispose();
    _venue.dispose();
    _batch.dispose();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    setState(() => _loadingWallet = true);
    try {
      final res = await callFn('getRRPPWallet');
      setState(() {
        _quota = (res['quota'] as num?)?.toInt() ?? 0;
        _tickets = [for (final t in (res['tickets'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
      });
    } catch (e) {
      debugPrint('Error cargando cartera RRPP: $e');
    } finally {
      if (mounted) setState(() => _loadingWallet = false);
    }
  }

  Future<void> _generateLegacy() async {
    if (_client.text.trim().isEmpty) return;
    final i18n = context.read<I18n>();
    setState(() {
      _loading = true;
      _error = '';
      _result = null;
    });
    try {
      final res = await callFn('generateDirectPromoterTicket', {'promoterToken': widget.token, 'eventId': widget.eventId, 'clientName': _client.text.trim()});
      if (res['success'] == true) {
        setState(() {
          _result = (ticketId: '${res['ticketId']}', clientName: '${res['clientName']}');
          _count++;
        });
        _client.clear();
      }
    } catch (e) {
      final msg = errorMessage(e, i18n.t('pr_error_generating', fallback: 'Error generando entrada'));
      setState(() => _error = msg.contains('cerrada')
          ? i18n.t('pr_list_closed', fallback: 'Tu lista está cerrada. Contacta al organizador.')
          : msg.contains('agotado') || msg.contains('Límite')
              ? i18n.t('pr_limit_reached', fallback: 'Has alcanzado el límite de entradas.')
              : msg.contains('Saldo')
                  ? i18n.t('pr_no_balance', fallback: 'Sin saldo de QRs. Recarga tu saldo.')
                  : msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buyPack(int qty) async {
    setState(() => _buying = true);
    try {
      final res = await callFn('createRRPPQRPackageCheckout', {'quantity': qty, 'origin': webBase});
      if (res['url'] is String) await openInApp(res['url'] as String);
    } catch (e) {
      setState(() => _error = errorMessage(e, 'Error iniciando pago'));
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<void> _issue() async {
    if (_venue.text.trim().isEmpty) return setState(() => _error = 'Debes especificar la sala o venueId');
    final names = _batch.text.split('\n').map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return setState(() => _error = 'Introduce al menos un nombre de invitado.');
    setState(() {
      _loading = true;
      _error = '';
      _result = null;
    });
    try {
      final res = await callFn('issueRRPPTickets', {'venueId': _venue.text.trim(), 'guestNames': names});
      if (res['success'] == true) {
        _batch.clear();
        _loadWallet();
        final tickets = res['tickets'] as List? ?? const [];
        if (tickets.isNotEmpty) {
          setState(() => _result = (ticketId: '${(tickets.first as Map)['ticketId']}', clientName: '${tickets.length} pase(s) emitido(s)'));
        }
      }
    } catch (e) {
      setState(() => _error = errorMessage(e, 'Error emitiendo pases.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.user != null && !_tokenMode && !_walletLoaded) {
      _walletLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadWallet());
    }
    if (context.watch<PlatformSettings>().flags['moduleRrppLibres'] == false) {
      return _centered(Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.pause_circle, size: 48, color: Tw.amber400),
        const SizedBox(height: 16),
        Text(context.t('pr_module_paused', fallback: 'Módulo en pausa'), style: tw(20, weight: black)),
        const SizedBox(height: 8),
        Text(context.t('pr_module_paused_desc', fallback: 'El sistema de RRPPs y generación de entradas no está disponible en este momento.'),
            textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
      ]));
    }
    if (_tokenMode) return _tokenView(context);
    if (auth.user == null && !auth.loading) {
      return _centered(Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Tw.emerald500, Tw.teal600]), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.confirmation_number, size: 30, color: Tw.white),
        ),
        const SizedBox(height: 24),
        Text(context.t('pr_login_required_title', fallback: 'Portal RRPP Independiente'), textAlign: TextAlign.center, style: tw(24, weight: black)),
        const SizedBox(height: 8),
        Text(
          context.t('pr_login_required_desc', fallback: 'Inicia sesión con tu cuenta de RRPP para gestionar tus créditos y emitir pases QR independientes.'),
          textAlign: TextAlign.center,
          style: tw(14, color: Tw.slate400),
        ),
        const SizedBox(height: 24),
        AdminButton(
          label: context.t('login', fallback: 'Iniciar Sesión'),
          color: Tw.emerald500,
          textColor: Tw.slate950,
          expand: true,
          padding: const EdgeInsets.symmetric(vertical: 14),
          onTap: () => openRoute(context, AppRoute.login),
        ),
        const SizedBox(height: 12),
        AdminButton(
          label: context.t('pr_apply_link', fallback: 'Solicitar Cuenta de RRPP'),
          color: Tw.w(0.05),
          expand: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          onTap: () => openRoute(context, AppRoute.prJoin),
        ),
      ]));
    }
    return _walletView(context);
  }

  Widget _centered(Widget child) => Scaffold(
        backgroundColor: Tw.black,
        body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: child))),
      );

  Widget _banner(String text, Color color, {IconData? icon, bool center = true}) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
          if (icon != null) ...[Icon(icon, color: color), const SizedBox(width: 12)],
          Flexible(child: Text(text, textAlign: center ? TextAlign.center : TextAlign.start, style: tw(13, color: Color.lerp(color, Tw.white, 0.3)!))),
        ]),
      );

  Widget _tokenView(BuildContext context) => Scaffold(
        backgroundColor: Tw.black,
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 16),
            GradientText(context.t('pr_title', fallback: 'Generador de Entradas'), style: tw(24, weight: black), colors: const [Tw.fuchsia400, Tw.pink400]),
            const SizedBox(height: 4),
            Text(context.t('pr_subtitle', fallback: 'RRPP · Blow Nights'), textAlign: TextAlign.center, style: tw(14, color: Tw.slate400)),
            if (_count > 0)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(color: Tw.fuchsia500.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                  child: Text('$_count ${_count == 1 ? context.t('pr_ticket_generated', fallback: 'entrada generada') : context.t('pr_tickets_generated', fallback: 'entradas generadas')}',
                      style: tw(12, weight: bold, color: Tw.fuchsia300)),
                ),
              ),
            const SizedBox(height: 24),
            if (_result != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Tw.green500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.green500.withValues(alpha: 0.3))),
                child: Column(children: [
                  const Icon(Icons.check_circle, size: 36, color: Tw.green400),
                  const SizedBox(height: 8),
                  Text(context.t('pr_ticket_generated', fallback: 'Entrada generada'), style: tw(15, weight: bold, color: const Color(0xFF86EFAC))),
                  Text(_result!.clientName, style: tw(14, color: Tw.slate300)),
                  Text('ID: ${_result!.ticketId.length > 12 ? _result!.ticketId.substring(0, 12) : _result!.ticketId}...',
                      style: tw(12, color: Tw.slate500).copyWith(fontFamily: 'monospace')),
                ]),
              ),
            if (_error.isNotEmpty) _banner(_error, Tw.red400, icon: Icons.warning),
            AdminCard(
              radius: 16,
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Label(context.t('pr_guest_name_label', fallback: 'Nombre del invitado'), size: 12, weight: bold),
                const SizedBox(height: 8),
                TextField(
                  controller: _client,
                  autofocus: true,
                  enabled: !_loading,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _generateLegacy(),
                  style: tw(18),
                  decoration: adminInputDecoration(context.t('pr_guest_name_placeholder', fallback: 'Nombre y apellido...')).copyWith(fillColor: Colors.black.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 16),
                AdminButton(
                  label: _loading ? context.t('pr_generating', fallback: 'Generando...') : context.t('pr_generate_ticket', fallback: 'Generar Entrada'),
                  loading: _loading,
                  expand: true,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  onTap: _loading || _client.text.trim().isEmpty ? null : _generateLegacy,
                ),
              ]),
            ),
          ]),
        ),
      );

  Future<void> _showBuyModal() => showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.8),
        builder: (ctx) => Dialog(
          backgroundColor: Tw.slate900,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Tw.w(0.1))),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('Comprar Paquete de Créditos QR', style: tw(18, weight: black))),
                IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close, color: Tw.slate400)),
              ]),
              Text('Tarifa plana de 0,50€ por QR. Los pases son válidos para cualquier sala y se escanean en puerta al instante.',
                  style: tw(12, color: Tw.slate400)),
              const SizedBox(height: 20),
              Row(children: [
                for (final (qty, price) in const [(25, '12,50 €'), (50, '25,00 €'), (100, '50,00 €')]) ...[
                  Expanded(
                    child: Pressable(
                      onTap: _buying
                          ? () {}
                          : () {
                              Navigator.of(ctx).pop();
                              _buyPack(qty);
                            },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.1))),
                        child: Column(children: [
                          Text('$qty', style: tw(20, weight: black)),
                          const Label('Pases', weight: bold),
                          Text(price, style: tw(12, weight: bold, color: Tw.emerald400)),
                        ]),
                      ),
                    ),
                  ),
                  if (qty != 100) const SizedBox(width: 12),
                ],
              ]),
            ]),
          ),
        ),
      );

  Widget _walletView(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(8, top + 8, 16, 8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), border: Border(bottom: BorderSide(color: Tw.w(0.1)))),
          child: Row(children: [
            IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Tw.slate400)),
            const Icon(Icons.confirmation_number, color: Tw.emerald400),
            const SizedBox(width: 8),
            Expanded(child: Text('RRPP Independiente', style: tw(16, weight: bold))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Tw.emerald500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
              ),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: 'Saldo: ', style: tw(12, weight: medium, color: Tw.slate400)),
                TextSpan(text: _quota == null ? '...' : '$_quota QRs', style: tw(13, weight: black, color: Tw.emerald400)),
              ])),
            ),
            const SizedBox(width: 8),
            AdminButton(
              label: '+ Comprar QRs',
              color: Tw.emerald500,
              textColor: Tw.slate950,
              fontSize: 11,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              onTap: _showBuyModal,
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 80), children: [
            if (widget.success)
              _banner('¡Pago completado! Tus créditos QR han sido añadidos a tu cuenta.', Tw.emerald400, icon: Icons.check_circle, center: false),
            AdminCard(
              radius: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.add_circle, size: 16, color: Tw.emerald400),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Emitir Pases QR para Invitados', style: tw(15, weight: bold))),
                ]),
                Text('1 QR consumido por invitado', style: tw(12, color: Tw.slate400)),
                const SizedBox(height: 16),
                if (_result != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Tw.emerald500.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Tw.emerald500.withValues(alpha: 0.3)),
                    ),
                    child: Column(children: [
                      const Icon(Icons.check_circle, size: 30, color: Tw.emerald400),
                      Text(_result!.clientName, style: tw(14, weight: bold, color: const Color(0xFF6EE7B7))),
                      Text('Pases listos en tu lista. Los asistentes ya pueden entrar en puerta.', textAlign: TextAlign.center, style: tw(12, color: Tw.slate400)),
                    ]),
                  ),
                if (_error.isNotEmpty) _banner(_error, Tw.red400),
                const Label('ID de la Sala / Venue', size: 12, weight: bold, tracking: 0.05),
                const SizedBox(height: 6),
                TextField(
                  controller: _venue,
                  onChanged: (_) => setState(() {}),
                  style: tw(14),
                  decoration: adminInputDecoration('ej: sala-kapital o demo-venue', focus: Tw.emerald500).copyWith(fillColor: Colors.black.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 16),
                const Label('Nombres de Invitados (Uno por línea)', size: 12, weight: bold, tracking: 0.05),
                const SizedBox(height: 6),
                TextField(
                  controller: _batch,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  style: tw(14).copyWith(fontFamily: 'monospace'),
                  decoration: adminInputDecoration('Carlos García\nLaura Morales\nDavid Ruiz', focus: Tw.emerald500).copyWith(fillColor: Colors.black.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 16),
                AdminButton(
                  label: _loading ? 'Emitiendo pases...' : 'Generar Pases QR',
                  color: Tw.emerald500,
                  textColor: Tw.slate950,
                  expand: true,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  onTap: _loading || _venue.text.trim().isEmpty || _batch.text.trim().isEmpty ? null : _issue,
                ),
              ]),
            ),
            const SizedBox(height: 32),
            AdminCard(
              radius: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Pases Emitidos Recientes', style: tw(15, weight: bold))),
                  GestureDetector(
                    onTap: _loadWallet,
                    child: Row(children: [
                      const Icon(Icons.sync, size: 14, color: Tw.slate400),
                      const SizedBox(width: 4),
                      Text('Actualizar', style: tw(12, color: Tw.slate400)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                if (_loadingWallet)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Text('Cargando pases...', textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)))
                else if (_tickets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text('Aún no has emitido ningún pase. Introduce invitados arriba para comenzar.', textAlign: TextAlign.center, style: tw(14, color: Tw.slate500)),
                  )
                else
                  for (final t in _tickets)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${t['clientName'] ?? ''}', style: tw(14, weight: bold)),
                            Text('${t['venueName'] ?? t['venueId'] ?? ''} · ${t['tierName'] ?? 'Pase RRPP'}', style: tw(12, color: Tw.slate400)),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (t['status'] == 'used' ? Tw.purple500 : Tw.emerald500).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Label(t['status'] == 'used' ? 'En Sala (Validado)' : 'Listo para entrar',
                              weight: bold, color: t['status'] == 'used' ? const Color(0xFFD8B4FE) : const Color(0xFF6EE7B7), tracking: 0.05),
                        ),
                      ]),
                    ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Port of app/pr/join/page.tsx (independent RRPP recruitment landing).
class PrJoinScreen extends StatelessWidget {
  const PrJoinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wa = 'Hola, quiero solicitar acceso como RRPP en Blow Nights.';
    final benefits = [
      (Icons.link, Tw.emerald400, 'pr_join_benefit1_title', 'Tu enlace personal de venta', 'pr_join_benefit1_desc',
          'Un link único que puedes compartir por Instagram, WhatsApp o donde quieras. Cada entrada vendida se te atribuye automáticamente.'),
      (Icons.bar_chart, Tw.teal400, 'pr_join_benefit2_title', 'Tracking en tiempo real', 'pr_join_benefit2_desc',
          'Ve cuántas entradas has generado, cuántas se validaron en puerta y tu ranking frente a otros RRPPs — todo en directo.'),
      (Icons.account_balance_wallet, Tw.cyan400, 'pr_join_benefit3_title', 'Comisiones transparentes', 'pr_join_benefit3_desc',
          'Liquidación automática por cada entrada validada. Sin papeleos, sin negociaciones turbias. Ves lo que ganas al céntimo.'),
      (Icons.language, Tw.emerald400, 'pr_join_benefit4_title', 'Libertad entre locales', 'pr_join_benefit4_desc',
          'No estás atado a una sala. Trabaja con el local que quieras cada noche, o con varios a la vez. Tú eliges.'),
      (Icons.qr_code_2, Tw.teal400, 'pr_join_benefit5_title', 'QR anticopia con tu nombre', 'pr_join_benefit5_desc',
          'Cada entrada lleva QR dinámico verificable en puerta. Tu invitado entra sin problemas y tú te llevas la comisión.'),
      (Icons.smartphone, Tw.cyan400, 'pr_join_benefit6_title', 'Todo desde tu móvil', 'pr_join_benefit6_desc',
          'Sin apps raras ni software de escritorio. Tu generador de entradas funciona desde el navegador del móvil, en cualquier momento.'),
    ];
    final steps = [
      ('01', 'pr_join_step1_title', '1. Regístrate gratis', 'pr_join_step1_desc', 'Crea tu cuenta con Google o email. Sin papeleo, sin cuotas, sin permanencias.', Tw.emerald400),
      ('02', 'pr_join_step2_title', '2. Recibe tu enlace', 'pr_join_step2_desc',
          'Te asignamos un link personal de venta para cada evento o local disponible. Compártelo donde quieras.', Tw.teal400),
      ('03', 'pr_join_step3_title', '3. Genera y cobra', 'pr_join_step3_desc', 'Cada invitado que entre con tu enlace se te atribuye. Comisiones liquidadas automáticamente.', Tw.cyan400),
    ];
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Tw.slate950,
      body: Stack(children: [
        AmbientGlow(colors: [Tw.emerald600.withValues(alpha: 0.08), Tw.fuchsia600.withValues(alpha: 0.08), Tw.indigo600.withValues(alpha: 0.08)]),
        ListView(padding: EdgeInsets.fromLTRB(24, top + 88, 24, 40), children: [
          Center(child: PillBadge(icon: Icons.auto_awesome, text: context.t('pr_join_hero_badge', fallback: 'RRPP Independiente · Sin ataduras'), color: Tw.emerald400)),
          const SizedBox(height: 24),
          GradientText(context.t('pr_join_hero_title', fallback: 'Tú Decides Dónde, Cuándo y Con Quién.'),
              style: tw(36, weight: black, height: 1.08, tracking: -0.02), colors: const [Tw.emerald400, Tw.teal400, Tw.cyan400]),
          const SizedBox(height: 12),
          Text(context.t('pr_join_hero_lead', fallback: 'Genera entradas, mueve listas y cobra comisiones sin depender de ningún local.'),
              textAlign: TextAlign.center, style: tw(22, weight: FontWeight.w800, color: const Color(0xFFF1F5F9), height: 1.2)),
          const SizedBox(height: 20),
          Text(
            context.t('pr_join_hero_subtitle',
                fallback:
                    'Blow Nights te da tu propio espacio como RRPP libre. Enlace personal de venta, tracking en tiempo real, liquidaciones automáticas y libertad total para moverte entre locales y eventos.'),
            textAlign: TextAlign.center,
            style: tw(16, color: Tw.slate400, height: 1.6),
          ),
          const SizedBox(height: 24),
          CtaButton(
            label: context.t('pr_join_hero_cta', fallback: 'Registrarme como RRPP'),
            icon: Icons.arrow_forward,
            gradient: const [Tw.emerald600, Tw.teal600],
            onTap: () => openRoute(context, AppRoute.login),
          ),
          const SizedBox(height: 12),
          CtaButton(
            label: context.t('pr_join_hero_whatsapp', fallback: 'Preguntar por WhatsApp'),
            leadingIcon: Icons.chat,
            tint: Tw.emerald400,
            onTap: () => openWhatsApp(wa),
          ),
          const SizedBox(height: 24),
          for (final (key, fb, c) in [
            ('pr_join_stat_free', 'Gratis, sin cuotas mensuales', Tw.emerald400),
            ('pr_join_stat_independent', '100% independiente de locales', Tw.teal400),
            ('pr_join_stat_instant', 'Empieza esta noche', Tw.cyan400),
          ])
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(color: Tw.w(0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: Tw.w(0.05))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle, size: 16, color: c),
                const SizedBox(width: 8),
                Text(context.t(key, fallback: fb), style: tw(12, weight: semibold, color: Tw.slate400)),
              ]),
            ),
          const SizedBox(height: 56),
          SectionHeader(context.t('pr_join_benefits_title', fallback: '¿Por qué ser RRPP en Blow Nights?'),
              subtitle: context.t('pr_join_benefits_subtitle', fallback: 'No eres un empleado. Eres un agente libre con herramientas profesionales.')),
          const SizedBox(height: 32),
          for (final (icon, color, tk, tf, dk, df) in benefits) FeatureCard(icon: icon, color: color, title: context.t(tk, fallback: tf), desc: context.t(dk, fallback: df)),
          const SizedBox(height: 48),
          SectionHeader(context.t('pr_join_how_title', fallback: 'Así de fácil es empezar'),
              subtitle: context.t('pr_join_how_subtitle', fallback: 'De cero a generar entradas en menos de 5 minutos')),
          const SizedBox(height: 32),
          for (final (n, tk, tf, dk, df, c) in steps) StepCard(step: n, title: context.t(tk, fallback: tf), desc: context.t(dk, fallback: df), color: c),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [const Color(0xFF022C22).withValues(alpha: 0.4), const Color(0xFF042F2E).withValues(alpha: 0.4), Tw.slate900]),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Tw.w(0.1)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Tw.w(0.1), borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.shield, size: 14, color: Tw.emerald400),
                  const SizedBox(width: 8),
                  Label(context.t('pr_join_diff_badge', fallback: 'RRPP Libre vs Promotor de Local'), color: Tw.white),
                ]),
              ),
              const SizedBox(height: 20),
              Text(context.t('pr_join_diff_free_title', fallback: 'RRPP Independiente (tú)'), style: tw(18, weight: bold, color: Tw.emerald400)),
              const SizedBox(height: 12),
              for (final (k, f) in const [
                ('pr_join_diff_free1', 'Vas por libre: eliges local y evento cada noche'),
                ('pr_join_diff_free2', 'Tu enlace personal, tus métricas, tus comisiones'),
                ('pr_join_diff_free3', 'No dependes de la estructura de ninguna sala'),
                ('pr_join_diff_free4', 'Puedes trabajar con varios locales a la vez'),
              ])
                CheckItem(context.t(k, fallback: f)),
              const SizedBox(height: 20),
              Text(context.t('pr_join_diff_venue_title', fallback: 'Promotor de Local (staff)'), style: tw(18, weight: bold, color: Tw.slate400)),
              const SizedBox(height: 12),
              for (final (k, f) in const [
                ('pr_join_diff_venue1', 'Contratado por una sala concreta'),
                ('pr_join_diff_venue2', 'Condiciones y comisiones fijadas por la gerencia'),
                ('pr_join_diff_venue3', 'Acceso solo al panel del local que le contrata'),
                ('pr_join_diff_venue4', 'Gestionado desde el Custom Mode del venue'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 16, height: 16, margin: const EdgeInsets.only(top: 2), decoration: const BoxDecoration(color: Tw.slate700, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(context.t(k, fallback: f), style: tw(14, color: Tw.slate500))),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 56),
          SectionHeader(context.t('pr_join_cta_title', fallback: 'Empieza a mover gente esta noche'),
              subtitle: context.t('pr_join_cta_subtitle',
                  fallback: 'Regístrate gratis, recibe tu enlace y empieza a generar entradas en minutos. Sin papeleo ni compromiso.')),
          const SizedBox(height: 24),
          CtaButton(
            label: context.t('pr_join_cta_register', fallback: 'Crear Cuenta de RRPP'),
            icon: Icons.person_add,
            gradient: const [Tw.emerald600, Tw.teal600],
            onTap: () => openRoute(context, AppRoute.login),
          ),
          const SizedBox(height: 12),
          CtaButton(label: context.t('pr_join_cta_whatsapp', fallback: 'Hablar con el Equipo'), leadingIcon: Icons.chat, tint: Tw.emerald400, onTap: () => openWhatsApp(wa)),
          const SizedBox(height: 48),
          Divider(color: Tw.w(0.1)),
          const SizedBox(height: 24),
          Text('© ${DateTime.now().year} ${context.t('pr_join_footer', fallback: 'Blow Nights. Todos los derechos reservados.')}',
              textAlign: TextAlign.center, style: tw(12, color: Tw.slate500)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(onPressed: () => openRoute(context, AppRoute.privacy), child: Text(context.t('pr_join_privacy', fallback: 'Privacidad'), style: tw(12, color: Tw.slate400))),
            TextButton(onPressed: () => openRoute(context, AppRoute.terms), child: Text(context.t('pr_join_terms', fallback: 'Términos'), style: tw(12, color: Tw.slate400))),
          ]),
        ]),
        MarketingNav(
          top: top,
          icon: Icons.group,
          gradient: const [Tw.emerald600, Tw.teal600],
          brand: 'RRPP',
          brandColors: const [Tw.emerald400, Tw.teal400],
          cta: context.t('pr_join_nav_cta', fallback: 'Unirme'),
          onCta: () => openRoute(context, AppRoute.login),
        ),
      ]),
    );
  }
}
