import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/firestore_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/admin_ui.dart';
import '../../../widgets/common.dart';

class _CityRevenue {
  final String city;
  final bool partner;
  final int value;
  const _CityRevenue(this.city, this.partner, this.value);
}

/// Port of features/super-admin/FinancePanel.tsx + hooks/useFinance.ts
class FinancePanel extends StatefulWidget {
  const FinancePanel({super.key});

  @override
  State<FinancePanel> createState() => _FinancePanelState();
}

class _FinancePanelState extends State<FinancePanel> {
  final _db = FirebaseFirestore.instance;
  bool _loading = true;
  int _globalRevenue = 0;
  num _totalExpenses = 0;
  List<_CityRevenue> _breakdown = [];
  List<Map<String, dynamic>> _expenses = [];
  final _desc = TextEditingController();
  final _amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
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
      final venues = [for (final v in (await _db.collection('venues').get()).docs) v.data()];
      var global = 0;
      final breakdown = <_CityRevenue>[];
      for (final c in cities.docs) {
        var rev = 0;
        for (final v in venues.where((v) => v['cityId'] == c.id)) {
          if (v['isActive'] != true) continue;
          rev += switch (v['subscriptionTier']) {
            'ticketing' => 100,
            'promo' => 60,
            'basico' => 30,
            _ => 60, // fallback to 60 MRR for LC-1.0 Radar
          };
        }
        global += rev;
        breakdown.add(_CityRevenue((c.data()['name'] as String?) ?? c.id, c.data()['partnerId'] != null, rev));
      }

      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month);
      final exp = await _db.collection('global_expenses').orderBy('date', descending: true).get();
      num total = 0;
      final list = <Map<String, dynamic>>[];
      for (final e in exp.docs) {
        final d = e.data();
        list.add({'id': e.id, ...d});
        final date = parseDate(d['date']);
        if (date != null && !date.isBefore(startOfMonth)) total += (d['amount'] as num?) ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _globalRevenue = global;
        _totalExpenses = total;
        _breakdown = breakdown;
        _expenses = list;
      });
    } catch (e) {
      debugPrint('finance: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addExpense() async {
    final amount = num.tryParse(_amount.text);
    if (_desc.text.isEmpty || amount == null) return;
    final desc = _desc.text;
    _desc.clear();
    _amount.clear();
    await _db.collection('global_expenses').add({'amount': amount, 'description': desc, 'date': FieldValue.serverTimestamp()});
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminEmpty('Cargando métricas financieras...', loading: true);
    final fmt = NumberFormat.decimalPattern('es');
    final mono = tw(30, weight: black).copyWith(fontFamily: 'monospace');

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
      kpi('Revenue Global App', Tw.fuchsia400, fmt.format(_globalRevenue), 'MRR Sumado de todas las ciudades',
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.fuchsia900.withValues(alpha: 0.4), Tw.black]),
          border: Tw.fuchsia500.withValues(alpha: 0.3)),
      const SizedBox(height: 16),
      kpi('Gastos Mensuales (A Escote)', Tw.red400, fmt.format(_totalExpenses), 'Servidores, APIs, Infraestructura',
          bg: Tw.red900.withValues(alpha: 0.1), border: Tw.red500.withValues(alpha: 0.3)),
      const SizedBox(height: 16),
      kpi('Royalties Red Partners', Tw.green400, fmt.format(_globalRevenue * 0.4), 'Suscripciones (60% retenido)'),
      const SizedBox(height: 32),
      AdminCard(
        color: Tw.red900.withValues(alpha: 0.05),
        borderColor: Tw.red500.withValues(alpha: 0.2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AdminSectionTitle('Añadir Gasto Operativo Global', color: Tw.red400),
          const SizedBox(height: 16),
          AdminInput(controller: _desc, hint: 'Concepto (Ej: AWS Servidores)'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: AdminInput(controller: _amount, hint: 'Importe €', keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 12),
            AdminButton(
              label: 'Añadir Gasto',
              color: Tw.red600,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              onTap: _addExpense,
            ),
          ]),
          if (_expenses.isNotEmpty) ...[
            const SizedBox(height: 24),
            for (final e in _expenses)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: Tw.w(0.05))),
                child: Row(children: [
                  Expanded(child: Text((e['description'] as String?) ?? '', style: tw(14, color: Tw.slate300))),
                  Text('${e['amount']} €', style: tw(14, weight: bold, color: Tw.red400).copyWith(fontFamily: 'monospace')),
                ]),
              ),
          ],
        ]),
      ),
      const SizedBox(height: 32),
      AdminCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AdminSectionTitle('Desglose Red de Franquicias'),
          const SizedBox(height: 24),
          for (final item in _breakdown) ...[_breakdownRow(item, fmt), const SizedBox(height: 24)],
        ]),
      ),
    ]);
  }

  Widget _breakdownRow(_CityRevenue item, NumberFormat fmt) {
    final pct = item.partner ? 40 : 100;
    final color = item.partner ? Tw.green400 : Tw.fuchsia400;
    final bar = item.partner ? Tw.green500 : Tw.fuchsia500;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text('${item.city} (${item.partner ? 'Partner' : 'Operación Propia'})', style: tw(12, weight: bold))),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            pct == 100 ? '${fmt.format(item.value)} €' : '${fmt.format(item.value)} € Royalty / ${fmt.format(item.value)} € Bruto',
            textAlign: TextAlign.end,
            style: tw(12, weight: bold, color: color).copyWith(fontFamily: 'monospace'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            Expanded(flex: pct, child: Container(color: bar)),
            if (pct < 100) Expanded(flex: 100 - pct, child: Container(color: Tw.w(0.2))),
          ]),
        ),
      ),
    ]);
  }
}
