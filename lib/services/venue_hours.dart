// Port of frontend/src/lib/venueHours.ts
typedef Hours = ({String open, String close});

const _jsDayToKey = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

String dayKey(DateTime d) => _jsDayToKey[d.weekday % 7];

int _parse(String t) {
  final p = t.split(':');
  return (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}

({bool isOpen, Hours? todayHours}) isVenueOpenNow(List<String> days, Map<String, Hours> hours, [DateTime? now]) {
  if (days.isEmpty || hours.isEmpty) return (isOpen: false, todayHours: null);
  final n = now ?? DateTime.now();
  final cur = _jsDayToKey[n.weekday % 7];
  final prev = _jsDayToKey[(n.weekday % 7 + 6) % 7];
  final hhmm = n.hour * 60 + n.minute;

  final today = hours[cur];
  if (days.contains(cur) && today != null) {
    final o = _parse(today.open), c = _parse(today.close);
    if (c > o) {
      if (hhmm >= o && hhmm < c) return (isOpen: true, todayHours: today);
    } else if (hhmm >= o) {
      return (isOpen: true, todayHours: today);
    }
  }

  final y = hours[prev];
  if (days.contains(prev) && y != null) {
    final o = _parse(y.open), c = _parse(y.close);
    if (c <= o && hhmm < c) return (isOpen: true, todayHours: y);
  }

  return (isOpen: false, todayHours: days.contains(cur) ? today : null);
}

({String dayKey, String open, bool isToday})? getNextOpening(List<String> days, Map<String, Hours> hours) {
  if (days.isEmpty || hours.isEmpty) return null;
  final n = DateTime.now();
  final idx = n.weekday % 7;
  final cur = _jsDayToKey[idx];
  final hhmm = n.hour * 60 + n.minute;
  final today = hours[cur];
  if (days.contains(cur) && today != null && hhmm < _parse(today.open)) {
    return (dayKey: cur, open: today.open, isToday: true);
  }
  for (var i = 1; i <= 7; i++) {
    final k = _jsDayToKey[(idx + i) % 7];
    final h = hours[k];
    if (days.contains(k) && h != null) return (dayKey: k, open: h.open, isToday: false);
  }
  return null;
}

String? formatScheduleToday(List<String> days, Map<String, Hours> hours) {
  final cur = dayKey(DateTime.now());
  final h = hours[cur];
  if (!days.contains(cur) || h == null) return null;
  return '${h.open} – ${h.close}';
}
