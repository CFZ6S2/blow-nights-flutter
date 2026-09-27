import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/city.dart';

const cityStorageKey = 'blownights_city';

/// Port of frontend/src/context/CityContext.tsx
class CityProvider extends ChangeNotifier {
  List<City> cities = [];
  City? currentCity;
  bool loading = true;
  bool detectedByGPS = false;
  StreamSubscription? _sub;
  bool _resolved = false;

  String? get cityId => currentCity?.id;
  String? get citySlug => currentCity?.slug;
  String get currency => currentCity?.currency ?? 'eur';

  CityProvider() {
    _sub = FirebaseFirestore.instance
        .collection('cities')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snap) async {
      cities = snap.docs.map(City.fromDoc).toList();
      if (_resolved) {
        final id = currentCity?.id;
        currentCity = cities.where((c) => c.id == id).firstOrNull ?? currentCity;
        notifyListeners();
        return;
      }
      _resolved = true;
      await _resolveInitial();
    }, onError: (_) {
      loading = false;
      notifyListeners();
    });
  }

  Future<void> _resolveInitial() async {
    String? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getString(cityStorageKey);
    } catch (_) {}
    final savedCity = cities.where((c) => c.slug == saved).firstOrNull;
    if (savedCity != null) {
      currentCity = savedCity;
      loading = false;
      notifyListeners();
      return;
    }
    await _detectByGPS();
  }

  Future<void> _detectByGPS() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return _fallbackToFirst();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(timeLimit: Duration(seconds: 5)),
      );
      City? nearest;
      var minDist = double.infinity;
      for (final c in cities) {
        if (c.lat == null || c.lng == null) continue;
        final d = haversineKm(pos.latitude, pos.longitude, c.lat!, c.lng!);
        if (d < minDist) {
          minDist = d;
          nearest = c;
        }
      }
      if (nearest != null && minDist < 100) {
        currentCity = nearest;
        detectedByGPS = true;
        _persist(nearest.slug);
        loading = false;
        notifyListeners();
      } else {
        _fallbackToFirst();
      }
    } catch (_) {
      _fallbackToFirst();
    }
  }

  void _fallbackToFirst() {
    if (cities.isNotEmpty) {
      currentCity = cities.first;
      _persist(cities.first.slug);
    }
    loading = false;
    notifyListeners();
  }

  void setCurrentCity(City? city) {
    currentCity = city;
    detectedByGPS = false;
    if (city != null) _persist(city.slug);
    notifyListeners();
  }

  Future<void> _persist(String slug) async {
    try {
      (await SharedPreferences.getInstance()).setString(cityStorageKey, slug);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
