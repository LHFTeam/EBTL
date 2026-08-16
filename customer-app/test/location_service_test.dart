import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/core/utils/formatters.dart';
import 'package:ebtl_customer_app/models/common_models.dart';
import 'package:ebtl_customer_app/services/location_service.dart';

ServiceLocation cart(String id, {double? latitude, double? longitude}) {
  return ServiceLocation(
    id: id,
    name: id,
    type: 'beach_cart',
    compoundName: 'North Coast',
    beachName: null,
    latitude: latitude,
    longitude: longitude,
    isActive: true,
    isAvailable: true,
  );
}

void main() {
  test('nearestWithin picks the closest cart inside the radius', () {
    final carts = [cart('far'), cart('near')];
    final nearest = LocationService.nearestWithin(carts, const {
      'far': 25000,
      'near': 500,
    });
    expect(nearest?.id, 'near');
  });

  test('nearestWithin rejects a cart just outside the radius', () {
    final carts = [cart('outside')];
    expect(
      LocationService.nearestWithin(carts, const {'outside': 30000.1}),
      isNull,
    );
  });

  test('missing coordinates are excluded and sort last stably', () {
    final carts = [
      cart('missing-first'),
      cart('far', latitude: 0.02, longitude: 0),
      cart('missing-second'),
      cart('near', latitude: 0.01, longitude: 0),
    ];
    final distances = LocationService.distancesById(carts, 0, 0);

    expect(distances.keys, containsAll(['far', 'near']));
    expect(distances.keys, isNot(contains('missing-first')));
    expect(
      LocationService.sortedByDistance(carts, distances).map((item) => item.id),
      ['near', 'far', 'missing-first', 'missing-second'],
    );
  });

  test('empty cart lists are safe', () {
    expect(LocationService.distancesById(const [], 0, 0), isEmpty);
    expect(LocationService.nearestWithin(const [], const {}), isNull);
    expect(LocationService.sortedByDistance(const [], const {}), isEmpty);
  });

  test('formatDistance formats metre and kilometre boundaries', () {
    expect(formatDistance(1000), '1.0 km away');
    expect(formatDistance(2449), '2.4 km away');
  });

  test('formatDistance rounds metres to the nearest ten', () {
    expect(formatDistance(346), '350 m away');
    expect(formatDistance(354), '350 m away');

    // Rounding up out of metres reads as kilometres rather than "1000 m away".
    expect(formatDistance(999), '1.0 km away');
  });

  test('formatDistance drops the decimal past 100 km', () {
    expect(formatDistance(99940), '99.9 km away');
    expect(formatDistance(247300), '247 km away');
  });
}
