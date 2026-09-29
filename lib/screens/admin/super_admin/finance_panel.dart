import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/settlement.dart';
import '../../../services/venue_plans.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

const _categories = [('infraestructura', 'Infraestructura'), ('marketing', 'Marketing'), ('otros', 'Otros')];
const _transferLabels = {
  'paid': 'Transferido',
  'none': 'Sin importe',
  'failed': 'Falló la transferencia',
  'no_account': 'Sin cuenta Stripe',
  'pending': 'En curso',
};

class _CityRevenue {
  final String id;
  final String city;
  final bool partner;
  final int mrr;
  const _CityRevenue(this.id, this.city, this.partner, this.mrr);
}

Map<String, dynamic> _map(Object? o) => Map<String, dynamic>.from(o as Map);
int _int(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;

/// Port of features/super-admin/FinancePanel.tsx + hooks/useFinance.ts
class FinancePanel extends StatefulWidget {
  const FinancePanel({super.key});

  @override
  State<FinancePanel> createState() => _FinancePanelState();
}

class _FinancePanelState extends State<FinancePanel> {
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  bool _loading = true;
  int _globalRevenue = 0;
  int _partnerRevenue = 0;
  List<_CityRevenue> _breakdown = [];
  List<(String, String)> _cities = [];
  // Costs are entered per month and each month is settled once it has ended, so start on last month.
  String _month = previousMonth(monthOf(DateTime.now()));
  List<Map<String, dynamic>> _expenses = [];
  bool _monthLocked = false;
  String _category = 'infraestructura';
  String _city = '';
  Map<String, dynamic>? _settlement;
  bool _busy = false;
  String? _settlementError;
  final _desc = TextEditingController();
  final _amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
    _fetchExpenses();
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final cities = await _db.collection('cities').get();
      // MRR: venues with an active paid subscription, at the plans' list prices (services/venue_plans.dart), per city.
      final mrrByCity = <String, int>{};
      for (final v in (await _db.collection('venues').get()).docs) {
        final mrr = venueMrr(v.data());
        if (mrr > 0) mrrByCity.update((v.data()['cityId'] as String?) ?? '', (x) => x + mrr, ifAbsent: () => mrr);
      }
      var global = 0;
      var withPartner = 0;
      final breakdown = <_CityRevenue>[];
      final cityList = <(String, String)>[];
      for (final c in cities.docs) {
        final mrr = mrrByCity.remove(c.id) ?? 0;
        final name = (c.data()['name'] as String?) ?? c.id;
        // Same condition as territorialSplit: shared with the partner only when it has a Stripe account.
        final partner = (c.data()['partner_stripe_account_id'] as String?)?.isNotEmpty == true;
        global += mrr;
        if (partner) withPartner += mrr;
        breakdown.add(_CityRevenue(c.id, name, partner, mrr));
        cityList.add((c.id, name));
      }
      // Paying venues whose cityId has no city doc yet (location-first sign-ups): platform revenue.
      final unassigned = mrrByCity.values.fold(0, (a, b) => a + b);
      if (unassigned > 0) {
        global += unassigned;
        breakdown.add(_CityRevenue('_none', 'Sin ciudad asignada', false, unassigned));
      }
      if (!mounted) return;
      setState(() {
        _globalRevenue = global;
        _partnerRevenue = withPartner;
        _breakdown = breakdown..sort((a, b) => b.mrr - a.mrr);
        _cities = cityList..sort((a, b) => a.$2.compareTo(b.$2));
      });
    } catch (e) {
      debugPrint('finance: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchExpenses() async {
    final month = _month;
    try {
      final [y, m] = month.split('-').map(int.parse).toList();
      final results = await Future.wait([
        _db.collection('global_expenses').where('period', isEqualTo: month).get(),
        _db
            .collection('global_expenses')
            .where('date', isGreaterThanOrEqualTo: DateTime(y, m))
            .where('date', isLessThan: DateTime(y, m + 1))
            .get(),
      ]);
      final lock = await _db.collection('settlement_periods').doc(month).get();
      final list = <String, Map<String, dynamic>>{};
      for (final d in results[0].docs) {
        list[d.id] = {'id': d.id, ...d.data()};
      }
      // Costs recorded before expenses had a month count by their date, as in the settlement.
      for (final d in results[1].docs) {
        if (d.data()['period'] == null) list[d.id] = {'id': d.id, ...d.data()};
      }
      if (!mounted || month != _month) return;
      setState(() {
        _expenses = list.values.toList();
        _monthLocked = lock.exists;
      });
    } catch (e) {
      debugPrint('finance expenses: $e');
    }
  }

  void _setMonth(String month) {
    setState(() {
      _month = month;
      _settlement = null;
      _settlementError = null;
      _expenses = [];
    });
    _fetchExpenses();
  }

  Future<void> _addExpense() async {
    final amount = num.tryParse(_amount.text.replaceAll(',', '.'));
    final desc = _desc.text.trim();
    if (desc.isEmpty || amount == null || amount <= 0) return;
    _desc.clear();
    _amount.clear();
    await _db.collection('global_expenses').add({
      'amount': (amount * 100).round() / 100,
      'description': desc.length > 200 ? desc.substring(0, 200) : desc,
      'category': _category,
      'cityId': _city.isEmpty ? null : _city,
      'period': _month,
      'date': FieldValue.serverTimestamp(),
    });
    setState(() => _settlement = null);
    await _fetchExpenses();
  }

  Future<void> _deleteExpense(String id) async {
    await _db.collection('global_expenses').doc(id).delete();
    setState(() => _settlement = null);
    await _fetchExpenses();
  }

  Future<void> _runSettlement({bool close = false}) async {
    setState(() {
      _busy = true;
      _settlementError = null;
    });
    try {
      if (close) await _functions.httpsCallable('closePartnerSettlement').call({'period': _month});
      // The preview of a closed month reads back what was settled, without calling Stripe.
      final res = await _functions.httpsCallable('previewPartnerSettlement').call({'period': _month});
      if (!mounted) return;
      setState(() => _settlement = _map(res.data));
      if (close) await _fetchExpenses();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _settlementError = e.message ?? 'No se pudo calcular la liquidación.');
    } catch (e) {
      if (mounted) setState(() => _settlementError = 'No se pudo calcular la liquidación.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClose() async {
    final total = _settlementCities.fold(0, (a, c) => a + _int(c, 'partnerCents'));
    if (await confirmDialog(context,
        message: 'Cerrar $_month y transferir ${_eur(total)} € a los partners. Los gastos de ese mes ya no se podrán cambiar.',
        confirmText: 'Cerrar mes')) {
      await _runSettlement(close: true);
    }
  }

  List<Map<String, dynamic>> get _settlementCities => [for (final c in (_settlement?['cities'] as List?) ?? const []) _map(c)];

  String _eur(int cents) => NumberFormat.decimalPatternDigits(locale: 'es', decimalDigits: 2).format(cents / 100);

  String _cityName(Object? id) => id == null ? 'General' : _cities.firstWhere((c) => c.$1 == id, orElse: () => (id as String, id)).$2;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminEmpty('Cargando métricas financieras...', loading: true);
    final fmt = NumberFormat.decimalPattern('es');
    final mono = tw(30, weight: black).copyWith(fontFamily: 'monospace');
    final monthTotal = _expenses.fold<num>(0, (a, e) => a + ((e['amount'] as num?) ?? 0));

    Widget kpi(String title, Color color, String value, String note, {Gradient? gradient, Color? bg, Color? border}) => AdminCard(
          gradient: gradient,
          color: bg,
          borderColor: border,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label(title, size: 12, weight: bold, color: color),
            const SizedBox(height: 8),
            Text.rich(TextSpan(children: [
              TextSpan(text: '$value ', style: mono),
              TextSpan(text: '€', style: tw(18, color: color)),
            ])),
            const SizedBox(height: 8),
            Text(note, style: tw(11, color: Tw.slate400)),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      kpi('Revenue Global App', Tw.fuchsia400, fmt.format(_globalRevenue), 'MRR de suscripciones activas de locales, a precio de tarifa (sin pruebas)',
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.fuchsia900.withValues(alpha: 0.4), Tw.black]),
          border: Tw.fuchsia500.withValues(alpha: 0.3)),
      const SizedBox(height: 16),
      kpi('Gastos de $_month', Tw.red400, fmt.format(monthTotal), 'Infraestructura, marketing y demás gastos de la plataforma',
          bg: Tw.red900.withValues(alpha: 0.1), border: Tw.red500.withValues(alpha: 0.3)),
      const SizedBox(height: 16),
      kpi('MRR en ciudades con partner', Tw.green400, fmt.format(_partnerRevenue), 'Se reparte al cerrar cada mes: 50% del beneficio neto, tras descontar gastos'),
      const SizedBox(height: 32),
      Row(children: [
        Label('Mes', size: 12, weight: bold, color: Tw.slate400),
        const SizedBox(width: 12),
        Expanded(
          child: AdminSelect<String>(
            value: _month,
            items: [for (final m in recentMonths(DateTime.now())) (m, m)],
            onChanged: (m) => m == null ? null : _setMonth(m),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      _expensesCard(),
      const SizedBox(height: 32),
      _settlementCard(),
      const SizedBox(height: 32),
      AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AdminSectionTitle('MRR por ciudad'),
          const SizedBox(height: 24),
          for (final item in _breakdown) ...[_breakdownRow(item, fmt), const SizedBox(height: 24)],
        ]),
      ),
    ]);
  }

  Widget _expensesCard() => AdminCard(
        color: Tw.red900.withValues(alpha: 0.05),
        borderColor: Tw.red500.withValues(alpha: 0.2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminSectionTitle('Gastos de la plataforma · $_month', color: Tw.red400),
          const SizedBox(height: 8),
          Text('Se descuentan antes del 50/50. Un gasto de una ciudad cuenta entero para ella; uno general se reparte según lo que factura cada ciudad.',
              style: tw(12, color: Tw.slate500)),
          const SizedBox(height: 16),
          if (_monthLocked)
            Text('Mes liquidado: sus gastos ya no se pueden cambiar.', style: tw(12, color: Tw.amber400))
          else ...[
            AdminInput(controller: _desc, hint: 'Concepto (Ej: Servidores Google Cloud)'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: AdminInput(controller: _amount, hint: 'Importe €', keyboardType: const TextInputType.numberWithOptions(decimal: true))),
              const SizedBox(width: 12),
              Expanded(
                child: AdminSelect<String>(value: _category, items: _categories, onChanged: (v) => setState(() => _category = v ?? _category)),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: AdminSelect<String>(
                  value: _city,
                  items: [('', 'General (todas)'), ..._cities],
                  onChanged: (v) => setState(() => _city = v ?? ''),
                ),
              ),
              const SizedBox(width: 12),
              AdminButton(
                label: 'Añadir Gasto',
                color: Tw.red600,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                onTap: _addExpense,
              ),
            ]),
          ],
          const SizedBox(height: 16),
          if (_expenses.isEmpty)
            Text('Sin gastos en $_month.', style: tw(12, color: Tw.slate500))
          else
            for (final e in _expenses)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: Tw.w(0.05))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((e['description'] as String?) ?? '', style: tw(14, color: Tw.slate300)),
                      Text(
                        '${_categories.firstWhere((c) => c.$1 == e['category'], orElse: () => ('otros', 'Otros')).$2} · ${_cityName(e['cityId'])}'.toUpperCase(),
                        style: tw(10, color: Tw.slate500, tracking: 0.1),
                      ),
                    ]),
                  ),
                  Text('${e['amount']} €', style: tw(14, weight: bold, color: Tw.red400).copyWith(fontFamily: 'monospace')),
                  if (!_monthLocked)
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Tw.slate500),
                      tooltip: 'Borrar',
                      onPressed: () => _deleteExpense(e['id'] as String),
                    ),
                ]),
              ),
        ]),
      );

  Widget _settlementCard() {
    final s = _settlement;
    final cities = _settlementCities;
    final closed = s?['closed'] == true;
    final canClose = s != null && !closed && s['ended'] == true && s['openBefore'] == null && _int(s, 'missingFees') == 0;
    final retry = closed && cities.any((c) => c['transferStatus'] == 'failed' || c['transferStatus'] == 'no_account');
    Widget warn(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: tw(12, color: Tw.amber400)));

    return AdminCard(
      color: Tw.green500.withValues(alpha: 0.03),
      borderColor: Tw.green500.withValues(alpha: 0.2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AdminSectionTitle('Liquidación de partners · $_month', color: Tw.green400),
        const SizedBox(height: 8),
        Text(
          'Cada partner recibe el 50% del neto de su ciudad: lo facturado menos las comisiones de pago, los gastos de su ciudad, '
          'su parte de los generales y la pérdida de meses anteriores, más $venueFeeEur € por cada local que ha pagado su cuota ese mes. '
          'Si sale negativo, no cobra y la pérdida pasa al mes siguiente.',
          style: tw(12, color: Tw.slate500),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          AdminButton(label: _busy ? 'Calculando…' : 'Calcular', color: Tw.w(0.1), loading: _busy, onTap: _busy ? null : () => _runSettlement()),
          if (canClose) AdminButton(label: 'Cerrar mes y transferir', color: Tw.green600, onTap: _busy ? null : _confirmClose),
          if (retry) AdminButton(label: 'Reintentar transferencias', color: Tw.amber500, onTap: _busy ? null : () => _runSettlement(close: true)),
        ]),
        const SizedBox(height: 16),
        if (_settlementError != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_settlementError!, style: tw(12, color: Tw.red400))),
        if (s != null) ...[
          Text(
            '${closed ? 'Mes liquidado. ' : s['ended'] == true ? 'Mes sin cerrar. ' : 'El mes aún no ha terminado. '}'
            'Facturado en la plataforma: ${_eur(_int(s, 'platformRevenueCents'))} € · gastos generales: ${_eur(_int(s, 'generalExpensesCents'))} €',
            style: tw(12, color: Tw.slate400),
          ),
          const SizedBox(height: 8),
          if (s['openBefore'] != null) warn('Cierra antes ${s['openBefore']}: los meses se liquidan en orden.'),
          if (_int(s, 'missingFees') > 0) warn('No se encontró la comisión de Stripe de ${_int(s, 'missingFees')} cobro(s). Vuelve a calcular en unos minutos.'),
          if (_int(s, 'otherCurrencyEntries') > 0) warn('${_int(s, 'otherCurrencyEntries')} cobro(s) en otra moneda quedan fuera: se liquidan a mano.'),
          if (cities.isEmpty)
            Text('Ninguna ciudad con partner tiene cobros ni gastos este mes.', style: tw(12, color: Tw.slate500))
          else
            for (final c in cities) _settlementRow(c),
        ],
      ]),
    );
  }

  Widget _settlementRow(Map<String, dynamic> c) {
    Widget line(String label, int cents, {Color color = Tw.slate300, bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: tw(12, color: Tw.slate500))),
            Text('${_eur(cents)} €', style: tw(12, weight: strong ? bold : medium, color: color).copyWith(fontFamily: 'monospace')),
          ]),
        );
    final status = c['transferStatus'] as String?;
    final net = _int(c, 'netCents');
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.05))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${c['cityName']} · ${_int(c, 'entryCount')} cobros', style: tw(14, weight: bold))),
          Text(
            (status != null ? _transferLabels[status] ?? status : c['hasAccount'] == true ? 'Pendiente de cierre' : 'Sin cuenta Stripe').toUpperCase(),
            style: tw(10, color: Tw.slate400, tracking: 0.1),
          ),
        ]),
        const SizedBox(height: 12),
        line('Facturado', _int(c, 'revenueCents'), color: Tw.white),
        line('Comisiones de pago', -_int(c, 'stripeFeesCents')),
        line('Gastos de la ciudad', -_int(c, 'ownExpensesCents')),
        line('Parte de gastos generales', -_int(c, 'generalExpensesCents')),
        line('Pérdida de meses anteriores', -_int(c, 'previousLossCents')),
        line('Total descontado', -settlementCostsCents(c)),
        line('Comisión por locales (${_int(c, 'payingVenues')} × $venueFeeEur €)', _int(c, 'venueFeeCents')),
        line('Beneficio neto', net, color: net < 0 ? Tw.red400 : Tw.white),
        line('Partner (50%)', _int(c, 'partnerCents'), color: Tw.green400, strong: true),
        line('Queda a la plataforma, antes de gastos', _int(c, 'platformCents')),
        if (_int(c, 'carryForwardLossCents') > 0) line('Pérdida que pasa al mes siguiente', _int(c, 'carryForwardLossCents'), color: Tw.amber400),
      ]),
    );
  }

  Widget _breakdownRow(_CityRevenue item, NumberFormat fmt) {
    final maxMrr = _breakdown.fold(1, (a, b) => b.mrr > a ? b.mrr : a);
    final color = item.partner ? Tw.green400 : Tw.fuchsia400;
    final bar = item.partner ? Tw.green500 : Tw.fuchsia500;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text('${item.city} (${item.partner ? 'Partner' : 'Operación Propia'})', style: tw(12, weight: bold))),
        const SizedBox(width: 8),
        Text('${fmt.format(item.mrr)} €', style: tw(12, weight: bold, color: color).copyWith(fontFamily: 'monospace')),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 8,
          color: Colors.black.withValues(alpha: 0.5),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: item.mrr / maxMrr, child: Container(color: bar)),
        ),
      ),
    ]);
  }
}
