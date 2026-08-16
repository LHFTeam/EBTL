// The onboarding primer that precedes the OS notification prompt.
//
// Two things about it are easy to break. It may only promise what the backend
// actually pushes — the order-ready notification and the referral-credit one —
// so the copy is pinned here. And it shares its screen with the onboarding
// button, which floats over every page: copy that grows past the fold ends up
// underneath that button, where the customer never reads it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/onboarding/widgets/notification_permission_page.dart';

/// Ceiling on where the page's last line may sit at 390x844, **in test-font
/// units**. `flutter test` renders with the bundled test font rather than
/// Manrope/Playfair, and its square glyphs wrap far wider than the real faces,
/// so this is a canary rather than a device measurement: today's layout lands
/// at 766 here and at 606 with the real fonts loaded, against a button top of
/// 686. Adding a line of copy moves this 20–30, which trips the test and is the
/// cue to re-measure on a device (or with a local `FontLoader` harness) before
/// raising the number.
const _testFontCeiling = 800.0;

Widget _wrap({EdgeInsets padding = EdgeInsets.zero, Size? size}) {
  return MediaQuery(
    data: MediaQueryData(size: size ?? const Size(390, 844), padding: padding),
    child: const MaterialApp(
      home: Scaffold(body: NotificationPermissionPage()),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('NotificationPermissionPage', () {
    testWidgets('promises only what the backend actually pushes', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());

      expect(
        find.text(
          'Turn on notifications and we’ll tell you the moment your order '
          'is ready.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pick up at the perfect time'), findsOneWidget);
      expect(find.text('Store credit when friends order'), findsOneWidget);
      expect(find.text(NotificationPermissionPage.reassurance), findsOneWidget);
    });

    testWidgets('keeps its copy from growing under the onboarding button', (
      tester,
    ) async {
      const screen = Size(390, 844);
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          padding: const EdgeInsets.only(top: 47, bottom: 34),
          size: screen,
        ),
      );

      // The reassurance is the last thing on the page; if it stays put,
      // everything above it does too.
      final bottom = tester
          .getBottomLeft(find.text(NotificationPermissionPage.reassurance))
          .dy;

      expect(bottom, lessThan(_testFontCeiling));
    });

    testWidgets('reserves the button and dots below its content', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());

      final padding = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .padding!
          .resolve(TextDirection.ltr);

      expect(
        padding.bottom,
        greaterThanOrEqualTo(NotificationPermissionPage.controlsReserve),
      );
    });

    testWidgets('scrolls rather than overflowing on a small phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(size: const Size(360, 640)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
