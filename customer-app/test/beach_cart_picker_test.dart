import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/home/widgets/beach_cart_picker_sheet.dart';
import 'package:ebtl_customer_app/models/common_models.dart';

ServiceLocation cart(String id) => ServiceLocation(
  id: id,
  name: '$id Cart',
  type: 'beach_cart',
  compoundName: '$id Compound',
  beachName: null,
  latitude: null,
  longitude: null,
  isActive: true,
  isAvailable: true,
);

Future<void> openPicker(
  WidgetTester tester, {
  Map<String, double> distances = const {},
  Future<Map<String, double>> Function()? onUseMyLocation,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showBeachCartPickerSheet(
            context: context,
            serviceAreas: [cart('Missing'), cart('Far'), cart('Near')],
            selectedLocationId: null,
            distanceMetersById: distances,
            onUseMyLocation: onUseMyLocation,
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('renders distances nearest-first and leaves missing cart last', (
    tester,
  ) async {
    await openPicker(tester, distances: const {'Far': 2400, 'Near': 350});

    expect(find.text('350 m away'), findsOneWidget);
    expect(find.text('2.4 km away'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Near Cart')).dy,
      lessThan(tester.getTopLeft(find.text('Far Cart')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Far Cart')).dy,
      lessThan(tester.getTopLeft(find.text('Missing Cart')).dy),
    );
  });

  testWidgets('Use my location refreshes and re-sorts the rows', (
    tester,
  ) async {
    var calls = 0;
    await openPicker(
      tester,
      distances: const {'Far': 100, 'Near': 200},
      onUseMyLocation: () async {
        calls += 1;
        return const {'Far': 500, 'Near': 50};
      },
    );

    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('50 m away'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Near Cart')).dy,
      lessThan(tester.getTopLeft(find.text('Far Cart')).dy),
    );
  });

  testWidgets('an empty location result shows the Settings note', (
    tester,
  ) async {
    await openPicker(tester, onUseMyLocation: () async => const {});

    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(
      find.text('Location is off. Turn it on in Settings to sort by distance.'),
      findsOneWidget,
    );
  });
}
