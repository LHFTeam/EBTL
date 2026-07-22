// Smoke test: the app builds its MaterialApp shell without a backend.
//
// EbtlApp only constructs the theme and the startup gate; the gate shows a
// loading scaffold while it reads the on-device onboarding flag, so a single
// frame is enough to confirm the app boots without touching the network.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/main.dart';

void main() {
  testWidgets('EbtlApp builds its MaterialApp shell', (
    WidgetTester tester,
  ) async {
    // Avoid runtime font fetching over the network during tests.
    GoogleFonts.config.allowRuntimeFetching = false;

    await tester.pumpWidget(const EbtlApp());
    await tester.pump();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.title, 'EBTL');
    expect(materialApp.debugShowCheckedModeBanner, isFalse);
  });
}
