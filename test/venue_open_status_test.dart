import 'dart:convert';
import 'dart:io';

import 'package:blow_nights/models/venue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('without opening hours the status is unknown, never open', () {
    expect(const Venue('v1', {'name': 'Sala', 'source': 'reference'}).openStatus, VenueOpenStatus.unknown);
    expect(const Venue('v2', {'openingDays': ['fri'], 'openingHours': {}}).openStatus, VenueOpenStatus.unknown);
  });

  test('the city home lists open venues first, then without hours, closed last', () {
    expect(VenueOpenStatus.values, [VenueOpenStatus.open, VenueOpenStatus.unknown, VenueOpenStatus.closed]);
  });

  test('every locale says "opening hours not available"', () {
    final files = Directory('assets/i18n').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    expect(files.length, 12);
    for (final f in files) {
      final radar = (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['radar'] as Map<String, dynamic>;
      expect(radar['status_no_hours'], isA<String>(), reason: f.path);
      expect((radar['status_no_hours'] as String).isNotEmpty, isTrue, reason: f.path);
    }
  });
}
