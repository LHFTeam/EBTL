import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/core/theme/ebtl_colors.dart';
import 'package:ebtl_customer_app/features/home/widgets/golden_hour_modal.dart';
import 'package:ebtl_customer_app/models/golden_hour_models.dart';
import 'package:ebtl_customer_app/services/api_service.dart';

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
    'occurrence_key': 'sunset:2026-08-10',
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoldenHourModal.fromJson', () {
    test('reads a full payload', () {
      final modal = GoldenHourModal.fromJson(goldenHourPayload())!;

      expect(modal.mode, 'sunset');
      expect(modal.occurrenceKey, 'sunset:2026-08-10');
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

    // An older backend sends no key. The card falling back to once-a-launch is
    // the right failure — a card that can never be shown again is not.
    test('a payload with no occurrence key parses rather than being dropped', () {
      final payload = goldenHourPayload();
      payload.remove('occurrence_key');

      expect(GoldenHourModal.fromJson(payload)?.occurrenceKey, '');
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

  // The card is shown once per run of a window, not once per launch: reopening
  // the app inside the same window must not bring it back, the next window of
  // the day must, and every window is unseen again tomorrow. The backend names
  // the window run; this is the app's half — remembering which names it has
  // already shown.
  group('the once-per-window record', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('a window is unseen until its card is shown', () async {
      expect(await ApiService.hasSeenGoldenHour('afternoon:2026-08-10'), isFalse);

      await ApiService.recordGoldenHourSeen('afternoon:2026-08-10');

      expect(await ApiService.hasSeenGoldenHour('afternoon:2026-08-10'), isTrue);
    });

    test('the window that follows it is still unseen', () async {
      await ApiService.recordGoldenHourSeen('afternoon:2026-08-10');

      expect(await ApiService.hasSeenGoldenHour('sunset:2026-08-10'), isFalse);
    });

    test('the same window tomorrow is unseen again', () async {
      await ApiService.recordGoldenHourSeen('afternoon:2026-08-10');

      expect(await ApiService.hasSeenGoldenHour('afternoon:2026-08-11'), isFalse);
    });

    test('recording the same window twice is not a second entry', () async {
      await ApiService.recordGoldenHourSeen('sunset:2026-08-10');
      await ApiService.recordGoldenHourSeen('sunset:2026-08-10');

      expect(await ApiService.hasSeenGoldenHour('sunset:2026-08-10'), isTrue);
    });

    // Four modes a day, so the cap has to hold at least a full day behind it —
    // otherwise this morning's card would come back by this evening.
    test('a whole day of windows stays remembered', () async {
      for (final mode in ['morning', 'afternoon', 'sunset', 'evening']) {
        await ApiService.recordGoldenHourSeen('$mode:2026-08-10');
      }

      expect(await ApiService.hasSeenGoldenHour('morning:2026-08-10'), isTrue);
      expect(await ApiService.hasSeenGoldenHour('evening:2026-08-10'), isTrue);
    });

    test('a keyless card is never suppressed', () async {
      await ApiService.recordGoldenHourSeen('   ');

      expect(await ApiService.hasSeenGoldenHour(''), isFalse);
      expect(await ApiService.hasSeenGoldenHour('   '), isFalse);
    });

    test('a corrupted record costs one extra showing, not a crash', () async {
      FlutterSecureStorage.setMockInitialValues({
        'golden_hour_seen_v1': 'not json at all',
      });

      expect(await ApiService.hasSeenGoldenHour('sunset:2026-08-10'), isFalse);

      // And it recovers: the next card written is remembered normally.
      await ApiService.recordGoldenHourSeen('sunset:2026-08-10');
      expect(await ApiService.hasSeenGoldenHour('sunset:2026-08-10'), isTrue);
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
