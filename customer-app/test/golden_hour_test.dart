import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/core/theme/ebtl_colors.dart';
import 'package:ebtl_customer_app/features/home/widgets/golden_hour_modal.dart';
import 'package:ebtl_customer_app/models/golden_hour_models.dart';

Map<String, dynamic> goldenHourPayload({
  Object? title = 'Golden hour is calling',
  Object? cocktail = const {
    'id': 'product-1',
    'slug': 'spicy-margarita',
    'name': 'Spicy Margarita',
  },
  List<Map<String, dynamic>> pills = const [
    {'label': 'Ready in 5', 'scheme': 'seafoam'},
    {'label': 'Serves 2', 'scheme': 'gold'},
  ],
}) {
  return <String, dynamic>{
    'mode': 'sunset',
    'title': title,
    'subtitle': 'The sun is doing its thing.',
    'image_url': 'https://example.test/sunset.webp',
    'image_caption': 'Served long, over ice',
    'cocktail': cocktail,
    'spirit_pill': {'label': 'Your Tequila', 'scheme': 'coral'},
    'pills': pills,
  };
}

void main() {
  group('GoldenHourModal.fromJson', () {
    test('reads a full payload', () {
      final modal = GoldenHourModal.fromJson(goldenHourPayload())!;

      expect(modal.mode, 'sunset');
      expect(modal.title, 'Golden hour is calling');
      expect(modal.subtitle, 'The sun is doing its thing.');
      expect(modal.imageCaption, 'Served long, over ice');
      expect(modal.hasImage, isTrue);
      expect(modal.cocktail.slug, 'spicy-margarita');
      expect(modal.spiritPill.label, 'Your Tequila');
      expect(modal.pills.map((pill) => pill.label), ['Ready in 5', 'Serves 2']);
    });

    test('an absent modal is null rather than an empty card', () {
      expect(GoldenHourModal.fromJson(const {}), isNull);
    });

    // Both are enforced by the backend before a mode can go live. The client
    // half of the rule matters because the payload is untrusted like any other.
    test('a modal with no title or no cocktail is not shown', () {
      expect(GoldenHourModal.fromJson(goldenHourPayload(title: '   ')), isNull);
      expect(GoldenHourModal.fromJson(goldenHourPayload(title: null)), isNull);
      expect(
        GoldenHourModal.fromJson(goldenHourPayload(cocktail: const {})),
        isNull,
      );
      expect(
        GoldenHourModal.fromJson(
          goldenHourPayload(cocktail: const {'id': 'product-1', 'slug': ''}),
        ),
        isNull,
      );
    });

    test('pills with no text are dropped', () {
      final modal = GoldenHourModal.fromJson(
        goldenHourPayload(
          pills: const [
            {'label': 'Ready in 5', 'scheme': 'teal'},
            {'label': '   ', 'scheme': 'teal'},
          ],
        ),
      )!;

      expect(modal.pills.map((pill) => pill.label), ['Ready in 5']);
    });
  });

  group('GoldenHourPillScheme', () {
    test('resolves the palette the dashboard offers', () {
      expect(
        GoldenHourPillScheme.forKey('coral').background,
        EbtlColors.coral,
      );
      expect(GoldenHourPillScheme.forKey('navy').foreground, EbtlColors.cream);
    });

    // A newer dashboard offering a scheme this app version does not know must
    // still draw the pill, not drop it.
    test('an unknown scheme falls back rather than failing', () {
      final unknown = GoldenHourPillScheme.forKey('ultraviolet');

      expect(unknown.background, EbtlColors.sand);
      expect(GoldenHourPillScheme.forKey(null).background, EbtlColors.sand);
    });
  });

  group('the Golden Hour card', () {
    // No image_url: CachedNetworkImage would reach for the network under test,
    // and the image is not what these assertions are about.
    Map<String, dynamic> imagelessPayload() {
      final payload = goldenHourPayload();
      payload['image_url'] = null;
      return payload;
    }

    Future<void> openCard(WidgetTester tester, GoldenHourModal modal) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showGoldenHourModal(
                  context: context,
                  modal: modal,
                  locationId: 'location-1',
                  onCartChanged: (_) {},
                  onOpenCocktail: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('draws the copy marketing wrote', (tester) async {
      final modal = GoldenHourModal.fromJson(imagelessPayload())!;
      await openCard(tester, modal);

      expect(find.text('Golden hour is calling'), findsOneWidget);
      expect(find.text('The sun is doing its thing.'), findsOneWidget);
      expect(find.text('Served long, over ice'), findsOneWidget);
      expect(find.text('Add to cart'), findsOneWidget);
    });

    testWidgets('leads the pill row with the spirit pill', (tester) async {
      final modal = GoldenHourModal.fromJson(imagelessPayload())!;
      await openCard(tester, modal);

      final pills = tester
          .widgetList<Text>(
            find.descendant(of: find.byType(Wrap), matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .toList();

      expect(pills, ['Your Tequila', 'Ready in 5', 'Serves 2']);
    });

    testWidgets('a card with no extra pills still shows the spirit', (
      tester,
    ) async {
      final payload = imagelessPayload();
      payload['pills'] = const <Map<String, dynamic>>[];

      await openCard(tester, GoldenHourModal.fromJson(payload)!);

      expect(find.text('Your Tequila'), findsOneWidget);
    });

    testWidgets('closes on the close button', (tester) async {
      final modal = GoldenHourModal.fromJson(imagelessPayload())!;
      await openCard(tester, modal);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Golden hour is calling'), findsNothing);
    });
  });
}
