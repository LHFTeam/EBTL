// The corner action on a cocktail card.
//
// One shell draws every cocktail card in the app, and the corner is what tells
// the two surfaces apart: browsing surfaces (Explore's grid, the Cocktail
// Finder) carry the plus that adds the cocktail to the cart, while the
// favorites surfaces keep the heart. The shell picks between them from whether
// an `onAdd` was passed, so a call site that forgets it silently falls back to
// a heart that does nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/models/cocktail_models.dart';
import 'package:ebtl_customer_app/shared/widgets/cocktail_card_widgets.dart';

final _cocktail = Cocktail.fromCustomerJson({
  'id': 'c1',
  'slug': 'mojito',
  'name': 'Classic Mojito',
  'short_description': 'White rum, lime, mint and soda over crushed ice.',
  'price': {'starting_price_inc_vat': 320.0, 'currency': 'EGP'},
  'variants': [
    {
      'id': 'v1',
      'name': 'Standard',
      'price_inc_vat': 320.0,
      'currency': 'EGP',
      'is_active': true,
      'availability': {'is_orderable': true},
    },
  ],
  'availability': {'is_orderable': true},
});

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 170, height: 280, child: child)),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a card given an add callback carries the plus, not the heart', (
    tester,
  ) async {
    var addCount = 0;

    await tester.pumpWidget(
      wrap(
        CocktailGridCard(
          cocktail: _cocktail,
          onTap: () {},
          onAdd: () => addCount++,
        ),
      ),
    );

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    await tester.tap(find.byType(CocktailCardAddButton));
    expect(addCount, 1);
  });

  testWidgets('the plus is inert while its add is in flight', (tester) async {
    var addCount = 0;

    await tester.pumpWidget(
      wrap(
        CocktailGridCard(
          cocktail: _cocktail,
          onTap: () {},
          onAdd: () => addCount++,
          isAdding: true,
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);

    await tester.tap(find.byType(CocktailCardAddButton));
    expect(addCount, 0);
  });

  testWidgets('a card with no add callback keeps the favorite heart', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(CocktailGridCard(cocktail: _cocktail, onTap: () {})),
    );

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });
}
