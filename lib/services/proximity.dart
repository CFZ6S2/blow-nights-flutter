import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ble_identity.dart';
import 'finder_native.dart';

enum ProximityBand { veryClose, near, far, lost }

/// One friend's phone as heard over BLE. RSSI is noisy (bodies, pockets), so it's smoothed with an EMA.
class PeerReading {
  final String bleId;
  double rssi;
  DateTime lastSeen;
  final List<(DateTime, double)> _history = [];
  PeerReading(this.bleId, this.rssi, this.lastSeen);

  static const _lostAfter = Duration(seconds: 30);

  ProximityBand get band {
    if (DateTime.now().difference(lastSeen) > _lostAfter) return ProximityBand.lost;
    if (rssi >= -60) return ProximityBand.veryClose;
    if (rssi >= -76) return ProximityBand.near;
    return ProximityBand.far;
  }

  /// Log-distance path loss, 1 m reference −59 dBm, exponent 2.7 (crowd). Only a rough order of magnitude.
  int get approxMeters => math.pow(10, (-59 - rssi) / 27).clamp(1, 60).round();

  /// +1 getting closer, −1 moving away, 0 steady (smoothed RSSI change over the last ~8 s).
  int get trend {
    if (band == ProximityBand.lost || _history.length < 2) return 0;
    final cutoff = DateTime.now().subtract(const Duration(seconds: 8));
    final old = _history.firstWhere((h) => !h.$1.isBefore(cutoff), orElse: () => _history.first);
    final delta = rssi - old.$2;
    return delta > 4 ? 1 : (delta < -4 ? -1 : 0);
  }

  void _add(int raw, DateTime t) {
    // Stale reading: restart the average instead of dragging the old value along.
    rssi = t.difference(lastSeen) > _lostAfter ? raw.toDouble() : rssi * 0.7 + raw * 0.3;
    lastSeen = t;
    _history.add((t, rssi));
    _history.removeWhere((h) => t.difference(h.$1) > const Duration(seconds: 20));
  }
}

/// App-wide finder state. The foreground service keeps running when the screen is left; only [stop] ends it.
class Proximity extends ChangeNotifier {
  Proximity._();
  static final instance = Proximity._();

  FinderState state = const FinderState();
  final Map<String, PeerReading> _peers = {};
  StreamSubscription? _sub;
  Timer? _tick;
  bool advertiseFailed = false;

  /// Most recent reading among the ids a friend may be advertising (see FinderMember.advertisedIds).
  PeerReading? readingFor(Set<String> ids) {
    PeerReading? best;
    for (final id in ids) {
      final r = _peers[id];
      if (r != null && (best == null || r.lastSeen.isAfter(best.lastSeen))) best = r;
    }
    return best;
  }

  bool get running => state.running;

  Future<FinderState> refresh() async {
    state = await FinderNative.state();
    if (state.running) _listen();
    notifyListeners();
    return state;
  }

  void _listen() {
    _sub ??= FinderNative.events.listen((e) {
      switch (e['type']) {
        case 'peer':
          final id = e['id'] as String? ?? '';
          final rssi = e['rssi'] as int? ?? -100;
          final t = DateTime.now();
          (_peers[id] ??= PeerReading(id, rssi.toDouble(), t))._add(rssi, t);
          notifyListeners();
        case 'advertise_failed':
          advertiseFailed = true;
          notifyListeners();
      }
    });
    // Bands and "seen x min ago" change with time even without new packets.
    _tick ??= Timer.periodic(const Duration(seconds: 5), (_) {
      _peers.removeWhere((_, p) => DateTime.now().difference(p.lastSeen) > const Duration(minutes: 30));
      notifyListeners();
    });
  }

  /// Caller has already checked permissions and Bluetooth (see [state]).
  Future<bool> start({required String title, required String text}) async {
    advertiseFailed = false;
    _listen();
    if (!await FinderNative.start(advertisingSchedule(await ensureBleKeys()), title: title, text: text)) return false;
    // The service starts asynchronously (onStartCommand on the main looper); poll until BLE is up.
    for (var i = 0; i < 12 && !state.running; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      await refresh();
    }
    return state.running;
  }

  /// Hands the running service the current schedule, e.g. after syncMyBleKeys published a renewed key.
  Future<void> pushKeys() async {
    if (state.running) await FinderNative.setKeys(advertisingSchedule(await ensureBleKeys()));
  }

  Future<void> stop() async {
    await FinderNative.stop();
    await _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
    await Future.delayed(const Duration(milliseconds: 300));
    await refresh();
  }
}
