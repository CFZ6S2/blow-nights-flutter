import 'package:cloud_functions/cloud_functions.dart';

/// Port of the callable helpers in hooks/useChills.ts
final _fn = FirebaseFunctions.instance;

Future<String> createChill({
  required String title,
  String description = '',
  required String exactAddress,
  required double approxLat,
  required double approxLng,
  required int maxCapacity,
  // null outside any city: plans are found by their coordinates.
  String? citySlug,
  List<String> tags = const [],
}) async {
  final res = await _fn.httpsCallable('createChill').call<Map<String, dynamic>>({
    'title': title,
    'description': description,
    'exact_address': exactAddress,
    'approx_lat': approxLat,
    'approx_lng': approxLng,
    'max_capacity': maxCapacity,
    'city_slug': ?citySlug,
    'tags': tags,
  });
  return res.data['chillId'] as String;
}

Future<void> requestChillAccess(String chillId) => _fn.httpsCallable('requestChillAccess').call({'chillId': chillId});

Future<void> respondChillRequest(String chillId, String userId, String action) =>
    _fn.httpsCallable('respondChillRequest').call({'chillId': chillId, 'userId': userId, 'action': action});

Future<void> endChill(String chillId) => _fn.httpsCallable('endChill').call({'chillId': chillId});

/// FirebaseFunctionsException.message, like `e.message` on the web.
String fnMessage(Object e, String fallback) => e is FirebaseFunctionsException ? (e.message ?? fallback) : fallback;
