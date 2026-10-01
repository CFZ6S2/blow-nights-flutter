import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/platform_settings.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

class _Module {
  final String key;
  final String title;
  final String category;
  final IconData icon;
  final String badge;
  final String description;
  final String impact;
  final String? warning;
  const _Module(this.key, this.title, this.category, this.icon, this.badge, this.description, this.impact, [this.warning]);
}

const _modules = [
  _Module(
    'moduleTicketing',
    'Venta de Entradas & Taquilla Online',
    'monetizacion',
    Icons.confirmation_number,
    'Core Monetización',
    'Permite a los usuarios comprar entradas anticipadas para eventos y locales desde la app web.',
    'Al desactivarlo, se ocultan los botones de compra directa en eventos y locales con un aviso de apertura próxima.',
  ),
  _Module(
    'moduleCashless',
    'Cashless & Pagos Directos en Barra',
    'monetizacion',
    Icons.account_balance_wallet,
    'Próxima Fase',
    'Compra de consumiciones desde el móvil y canje en barra con QR o NFC, sin pulseras ni saldo.',
    'Al activarlo, se muestra la cartera cashless en el perfil y las taquillas de consumiciones.',
    'Mantener apagado hasta que los locales de la ciudad tengan formados a sus camareros con el datáfono/escáner.',
  ),
  _Module(
    'moduleRrppLibres',
    'RRPPs Libres & Embajadores Autónomos',
    'red_comercial',
    Icons.badge,
    'Crecimiento Viral',
    'Permite que cualquier usuario solicite ser RRPP/Promotor independiente y vender entradas con sus propios enlaces/QRs.',
    'Al desactivarlo, se cierra el registro público de nuevos RRPPs y solo el SuperAdmin puede asignar promotores manualmente.',
  ),
  _Module(
    'moduleRrppCommissions',
    'Liquidación Automática de Comisiones RRPP',
    'red_comercial',
    Icons.payments,
    'Finanzas',
    'Calcula y abona las comisiones generadas por los RRPPs automáticamente cuando el cliente valida el QR en puerta.',
    'Al pausarlo, los registros de acceso se guardan pero la liquidación queda retenida para revisión manual.',
  ),
  _Module(
    'moduleChills',
    'Chills (Planes Sociales Comunitarios)',
    'comunidad',
    Icons.groups,
    'Comunidad',
    'Los usuarios verificados y VIP pueden convocar previas, quedadas y planes espontáneos geolocalizados en el mapa.',
    'Si prefieres arrancar en una ciudad centrada solo en los locales comerciales, puedes apagar Chills temporalmente.',
  ),
  _Module(
    'moduleFriendFinder',
    'Amigos cerca (Radar Bluetooth en Festivales)',
    'comunidad',
    Icons.bluetooth_searching,
    'Próxima Fase',
    'Grupos de amigos que se localizan por Bluetooth sin cobertura y se invitan acercando los móviles (NFC). Solo en la app Android.',
    'Al activarlo aparece "Amigos cerca" en el perfil de la app. Al apagarlo se oculta y se detiene el radar de quien lo tuviera encendido.',
    'Mantener apagado hasta que se vendan entradas de festivales.',
  ),
  _Module(
    'moduleVenueRegistration',
    'Reclamación y Alta Pública de Locales',
    'red_comercial',
    Icons.storefront,
    'Onboarding Negocios',
    'Muestra los accesos para que dueños de discotecas, bares o saunas reclamen su ficha o soliciten unirse.',
    'Desactívalo si deseas curar e incorporar los locales de forma 100% manual y privada desde el SuperAdmin.',
  ),
  _Module(
    'maintenanceMode',
    'Modo Mantenimiento Global',
    'sistema',
    Icons.construction,
    'Emergencia',
    'Pone la plataforma en modo mantenimiento mostrando aviso a los usuarios normales mientras tú mantienes acceso.',
    'Bloquea acciones de escritura en la app temporalmente ante despliegues mayores.',
    '¡Cuidado! Desconectará la navegación normal para todos los usuarios regulares.',
  ),
];

/// Port of features/super-admin/FeatureFlagsPanel.tsx
class FeatureFlagsPanel extends StatefulWidget {
  const FeatureFlagsPanel({super.key});

  @override
  State<FeatureFlagsPanel> createState() => _FeatureFlagsPanelState();
}

class _FeatureFlagsPanelState extends State<FeatureFlagsPanel> {
  String? _updating;
  String _category = 'all';

  Future<void> _toggle(_Module m, bool current) async {
    setState(() => _updating = m.key);
    try {
      await FirebaseFirestore.instance.collection('settings').doc('platform').set({m.key: !current}, SetOptions(merge: true));
      if (mounted) showToast(context, '${m.title} ha sido ${!current ? 'ACTIVADO' : 'DESACTIVADO'} con éxito');
    } catch (e) {
      if (mounted) showToast(context, 'Error al actualizar el módulo. Comprueba tus permisos.', error: true);
    } finally {
      if (mounted) setState(() => _updating = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flags = context.watch<PlatformSettings>();
    bool isOn(_Module m) => flags.flag(m.key);
    final visible = _modules.where((m) => _category == 'all' || m.category == _category).toList();
    final activeCount = _modules.where(isOn).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdminCard(
        radius: 24,
        gradient: LinearGradient(colors: [
          Tw.fuchsia950.withValues(alpha: 0.4),
          Tw.purple900.withValues(alpha: 0.3),
          Tw.indigo950.withValues(alpha: 0.4),
        ]),
        borderColor: Tw.fuchsia500.withValues(alpha: 0.3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Tw.fuchsia500.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.tune, size: 12, color: Tw.fuchsia300),
              SizedBox(width: 8),
              Label('Despliegue Progresivo', color: Tw.fuchsia300),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Control de Módulos & Velocidad de Despliegue', style: tw(24, weight: black, height: 1.2)),
          const SizedBox(height: 8),
          Text(
            'Activa o apaga cada funcionalidad según la fase en la que se encuentre tu expansión. Los cambios se sincronizan en tiempo real en toda la app sin necesidad de desplegar código.',
            style: tw(14, color: Tw.slate300, height: 1.6),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.w(0.1)),
            ),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Tw.fuchsia600.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tw.fuchsia500.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.toggle_on, size: 26, color: Tw.fuchsia400),
              ),
              const SizedBox(width: 20),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: '$activeCount ', style: tw(24, weight: black)),
                  TextSpan(text: '/ ${_modules.length}', style: tw(16, color: Tw.slate500)),
                ])),
                const Label('Módulos Activos', color: Tw.fuchsia400, tracking: 0.05),
              ]),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 32),
      AdminChips(
        items: const [
          ('all', 'Todos los Módulos'),
          ('monetizacion', 'Monetización & Pagos'),
          ('red_comercial', 'RRPPs & Negocios'),
          ('comunidad', 'Comunidad & Social'),
          ('sistema', 'Sistema & Ecosistema'),
        ],
        selected: _category,
        onSelect: (c) => setState(() => _category = c),
      ),
      const SizedBox(height: 24),
      for (final m in visible) ...[_card(m, isOn(m)), const SizedBox(height: 20)],
    ]);
  }

  Widget _card(_Module m, bool active) => Opacity(
        opacity: active ? 1 : 0.75,
        child: AdminCard(
          radius: 16,
          color: active ? Tw.slate900.withValues(alpha: 0.9) : Tw.slate950.withValues(alpha: 0.6),
          borderColor: active ? Tw.fuchsia500.withValues(alpha: 0.3) : Tw.w(0.05),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: active ? Tw.fuchsia500.withValues(alpha: 0.2) : Tw.w(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: active ? Tw.fuchsia500.withValues(alpha: 0.3) : Tw.w(0.05)),
                ),
                child: Icon(m.icon, size: 20, color: active ? Tw.fuchsia400 : Tw.slate500),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Label(m.badge, size: 9, color: Tw.slate500),
                  Text(m.title, style: tw(16, weight: black, height: 1.2)),
                ]),
              ),
              const SizedBox(width: 12),
              AdminToggle(value: active, busy: _updating == m.key, onTap: () => _toggle(m, active)),
            ]),
            const SizedBox(height: 12),
            Text(m.description, style: tw(12, color: Tw.slate300, height: 1.6)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.w(0.05)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(style: tw(11, color: Tw.slate400), children: [
                  TextSpan(text: 'Efecto en la app: ', style: tw(11, weight: bold, color: const Color(0xFFE2E8F0))),
                  TextSpan(text: m.impact),
                ])),
                if (m.warning != null) ...[
                  const SizedBox(height: 6),
                  Divider(height: 1, color: Tw.w(0.05)),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.warning_amber, size: 12, color: Tw.amber400.withValues(alpha: 0.9)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(m.warning!, style: tw(11, weight: medium, color: Tw.amber400.withValues(alpha: 0.9)))),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: Tw.w(0.05)),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Label('Estado en producción:', color: Tw.slate500, weight: bold, tracking: 0.05)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: active ? Tw.emerald500.withValues(alpha: 0.2) : Tw.slate800,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: active ? Tw.emerald500.withValues(alpha: 0.3) : Tw.w(0.05)),
                ),
                child: Label(active ? 'Activo & Disponible' : 'Pausado / Oculto',
                    color: active ? Tw.emerald400 : Tw.slate400, tracking: 0.05),
              ),
            ]),
          ]),
        ),
      );
}
