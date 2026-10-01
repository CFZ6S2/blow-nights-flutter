import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/city.dart';
import '../services/nearby.dart';

export '../services/nearby.dart' show haversineKm;

/// Only explicit choices are stored (a city slug, or [nearbySlug]); a city found by GPS is not, since next time the
/// user may be somewhere else. The old key 'blownights_city' also held the Madrid fallback, so it's no longer read.
const cityStorageKey = 'blownights_city_choice';

/// "Cerca de ti": follow the GPS, as /cerca on the web.
const nearbySlug = 'cerca';

enum PositionStatus { pending, granted, denied, unavailable }

/// Port of frontend/src/context/CityContext.tsx. [currentCity] is the city picked, or the one the user is in (GPS);
/// null means "Cerca de ti": no city nearby, everything is shown by distance around [center]. Never a fallback city.
class CityProvider extends ChangeNotifier {
  List<City> cities = [];
  bool _citiesLoaded = false;
  String? _choice;
  GeoPos? position;
  PositionStatus positionStatus = PositionStatus.pending;
  StreamSubscription? _sub;

  City? currentCity;
  bool detectedByGPS = false;

  /// Where "near" is measured from: the picked city's centre, else the user's position, else null.
  GeoPos? center;

  bool get loading => !_citiesLoaded || (positionStatus == PositionStatus.pending && currentCity == null);
  String? get cityId => currentCity?.id;
  String? get citySlug => currentCity?.slug;
  String get currency => currentCity?.currency ?? 'eur';

  CityProvider() {
    _loadChoice();
    _sub = FirebaseFirestore.instance
        .collection('cities')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      cities = snap.docs.map(City.fromDoc).toList();
      _citiesLoaded = true;
      _resolve();
    }, onError: (_) {
      _citiesLoaded = true;
      _resolve();
    });
    refreshPosition();
  }

  Future<void> _loadChoice() async {
    try {
      _choice = (await SharedPreferences.getInstance()).getString(cityStorageKey);
    } catch (_) {}
    _resolve();
  }

  Future<void> refreshPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        positionStatus = PositionStatus.denied;
        _resolve();
        return;
      }
      final pos = await _locate();
      if (pos == null) {
        positionStatus = PositionStatus.unavailable;
      } else {
        position = (lat: pos.latitude, lng: pos.longitude);
        positionStatus = PositionStatus.granted;
      }
    } catch (_) {
      positionStatus = PositionStatus.unavailable;
    }
    _resolve();
  }

  /// A 50 km zone doesn't need GPS precision. On Android, Google's fused provider shows a "Location Accuracy" dialog
  /// when that setting is off, and declining it fails the request, leaving the user without a zone; so the system
  /// LocationManager goes first (no dialog), then the fused provider, then the last known position.
  Future<Position?> _locate() async {
    const low = LocationAccuracy.low;
    const limit = Duration(seconds: 8);
    final android = defaultTargetPlatform == TargetPlatform.android;
    if (android) {
      try {
        return await Geolocator.getCurrentPosition(
            locationSettings: AndroidSettings(accuracy: low, timeLimit: limit, forceLocationManager: true));
      } catch (_) {}
    }
    try {
      return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: low, timeLimit: limit));
    } catch (_) {}
    try {
      return await Geolocator.getLastKnownPosition(forceAndroidLocationManager: android);
    } catch (_) {
      return null;
    }
  }

  void _resolve() {
    City? picked;
    if (_choice != null && _choice != nearbySlug) {
      picked = cities.where((c) => c.slug == _choice || c.id == _choice).firstOrNull;
    }
    final here = picked == null ? _nearest() : null;
    currentCity = picked ?? here;
    detectedByGPS = here != null;
    final c = currentCity;
    final cityCenter = c != null && c.lat != null && c.lng != null ? (lat: c.lat!, lng: c.lng!) : null;
    center = picked != null ? (cityCenter ?? position) : (position ?? cityCenter);
    notifyListeners();
  }

  City? _nearest() {
    final pos = position;
    if (pos == null) return null;
    City? best;
    var bestKm = double.infinity;
    for (final c in cities) {
      if (c.lat == null || c.lng == null) continue;
      final d = haversineKm(pos.lat, pos.lng, c.lat!, c.lng!);
      if (d < bestKm) {
        bestKm = d;
        best = c;
      }
    }
    return bestKm < cityMatchKm ? best : null;
  }

  /// Pick a city, or null for "Cerca de ti". Remembered on this device.
  void setCurrentCity(City? city) {
    final choice = city?.slug ?? nearbySlug;
    _choice = choice;
    _persist(choice);
    _resolve();
  }

  Future<void> _persist(String value) async {
    try {
      (await SharedPreferences.getInstance()).setString(cityStorageKey, value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
