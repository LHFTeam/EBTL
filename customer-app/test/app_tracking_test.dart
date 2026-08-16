// Covers which App Tracking Transparency outcomes let the advertising
// identifier be attached to analytics events. The prompt itself is a platform
// channel and is not exercised here; this pins the decision made from its
// answer, which is what silently switches Meta attribution on or off.

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/services/app_tracking_service.dart';

void main() {
  group('AppTrackingService.allowsAdvertiserId', () {
    test('the customer allowing tracking permits the identifier', () {
      expect(
        AppTrackingService.allowsAdvertiserId(TrackingStatus.authorized),
        isTrue,
      );
    });

    // Android and every other non-iOS platform answer notSupported: there is
    // no per-app prompt there, and the advertising ID is governed by the
    // device's own ads setting. Treating it as a refusal would turn Android
    // attribution off.
    test('a platform without the prompt is not treated as a refusal', () {
      expect(
        AppTrackingService.allowsAdvertiserId(TrackingStatus.notSupported),
        isTrue,
      );
    });

    test('a refusal withholds the identifier', () {
      expect(
        AppTrackingService.allowsAdvertiserId(TrackingStatus.denied),
        isFalse,
      );
    });

    // A restricted device cannot be prompted at all, and an unanswered prompt
    // has granted nothing yet — iOS reads the identifier back as zeros in both
    // cases, so there is nothing worth collecting.
    test('a device that cannot be asked withholds the identifier', () {
      expect(
        AppTrackingService.allowsAdvertiserId(TrackingStatus.restricted),
        isFalse,
      );
    });

    test('an unanswered prompt withholds the identifier', () {
      expect(
        AppTrackingService.allowsAdvertiserId(TrackingStatus.notDetermined),
        isFalse,
      );
    });
  });

  group('AppTrackingService.status', () {
    test('starts undecided, so nothing is collected before the prompt', () {
      AppTrackingService.resetForTesting();

      expect(AppTrackingService.status, TrackingStatus.notDetermined);
      expect(
        AppTrackingService.allowsAdvertiserId(AppTrackingService.status),
        isFalse,
      );
    });
  });
}
