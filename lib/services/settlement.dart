/// Monthly Master Partner settlement, as functions/lib/settlement.js: the partner gets 50% of its territory's net
/// (billing minus payment fees and platform costs, plus 20 € per venue that paid its plan), paid when super-admin
/// closes the month.
library;

const venueFeeEur = 20;

/// 'YYYY-MM' of a date (device time; the platform settles on the Madrid calendar).
String monthOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

String previousMonth(String period) {
  final [y, m] = period.split('-').map(int.parse).toList();
  return m == 1 ? '${y - 1}-12' : '$y-${(m - 1).toString().padLeft(2, '0')}';
}

/// The last [count] months, newest first.
List<String> recentMonths(DateTime now, {int count = 12}) =>
    [for (var i = 0; i < count; i++) monthOf(DateTime(now.year, now.month - i))];

int _cents(Map<String, dynamic> s, String k) => (s[k] as num?)?.toInt() ?? 0;

/// A settlement's costs: payment fees, the city's own costs, its share of general costs and last months' loss.
int settlementCostsCents(Map<String, dynamic> s) =>
    _cents(s, 'stripeFeesCents') + _cents(s, 'ownExpensesCents') + _cents(s, 'generalExpensesCents') + _cents(s, 'previousLossCents');
