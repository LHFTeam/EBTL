// The bottom nav decorates tabs by hardcoded index — the cart count sits on
// one index and the profile unread dot on another. Those literals silently
// drift onto the wrong icons whenever a tab is added or removed, which is
// exactly what happened when Shop and Cocktail Finder were replaced by
// Explore. These tests pin the tab set and both badge positions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/shared/widgets/ebtl_bottom_nav.dart';

Widget wrap(Widget child) {
  return MaterialApp(home: Scaffold(bottomNavigationBar: child));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('shows exactly the four tabs, in order', (tester) async {
    await tester.pumpWidget(
      wrap(EbtlBottomNav(selectedIndex: 0, onTap: (_) {})),
    );

    for (final label in ['Home', 'Explore', 'Cart', 'Profile']) {
      expect(find.text(label), findsOneWidget);
    }

    expect(find.text('Shop'), findsNothing);
    expect(find.text('Cocktail Finder'), findsNothing);
  });

  testWidgets('reports the tapped index', (tester) async {
    final tapped = <int>[];

    await tester.pumpWidget(
      wrap(EbtlBottomNav(selectedIndex: 0, onTap: tapped.add)),
    );

    await tester.tap(find.text('Explore'));
    await tester.tap(find.text('Profile'));

    expect(tapped, [EbtlBottomNav.exploreIndex, EbtlBottomNav.profileIndex]);
  });

  testWidgets('cart count renders on the Cart tab only', (tester) async {
    await tester.pumpWidget(
      wrap(EbtlBottomNav(selectedIndex: 0, onTap: (_) {}, cartItemCount: 4)),
    );

    final badge = find.text('4');
    expect(badge, findsOneWidget);

    // The badge is a sibling of the Cart icon inside the same tab column.
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('Cart'), matching: find.byType(Column)),
        matching: badge,
      ),
      findsOneWidget,
    );
  });

  testWidgets('cart badge is hidden at zero and clamps above 99', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(EbtlBottomNav(selectedIndex: 0, onTap: (_) {})),
    );
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(
      wrap(EbtlBottomNav(selectedIndex: 0, onTap: (_) {}, cartItemCount: 150)),
    );
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('profile dot renders on the Profile tab only', (tester) async {
    await tester.pumpWidget(
      wrap(
        EbtlBottomNav(selectedIndex: 0, onTap: (_) {}, showProfileDot: true),
      ),
    );

    final dots = find.descendant(
      of: find.ancestor(
        of: find.text('Profile'),
        matching: find.byType(Column),
      ),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
    );

    expect(dots, findsOneWidget);

    // …and nowhere else.
    await tester.pumpWidget(
      wrap(EbtlBottomNav(selectedIndex: 0, onTap: (_) {})),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
      findsNothing,
    );
  });

  testWidgets('the selected tab is the highlighted one', (tester) async {
    await tester.pumpWidget(
      wrap(
        EbtlBottomNav(selectedIndex: EbtlBottomNav.exploreIndex, onTap: (_) {}),
      ),
    );

    // Only the selected tab swaps to its filled icon.
    expect(find.byIcon(Icons.explore), findsOneWidget);
    expect(find.byIcon(Icons.explore_outlined), findsNothing);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.home), findsNothing);
  });
}
