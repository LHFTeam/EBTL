// SpotlightMarkdownSheet: the slide a markdown-content Spotlight banner opens
// instead of the product-grid sheet. Its own H1 stands in for the sheet
// title, so it has to render at the same size/weight/color as
// SpotlightSheet's title rather than as ordinary body copy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/core/theme/ebtl_colors.dart';
import 'package:ebtl_customer_app/features/home/widgets/spotlight_markdown_sheet.dart';
import 'package:ebtl_customer_app/models/spotlight_models.dart';

SpotlightBanner banner({
  String title = 'Recipe of the week',
  String? markdownBody,
}) {
  return SpotlightBanner(
    id: 's1',
    imageUrl: 'https://cdn.ebtl.test/spotlight.webp',
    title: title,
    subtitle: null,
    displayOrder: 0,
    contentType: SpotlightContentType.markdown,
    markdownBody: markdownBody,
  );
}

Future<void> pumpSheet(WidgetTester tester, SpotlightBanner banner) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SpotlightMarkdownSheet(banner: banner)),
    ),
  );
}

/// flutter_markdown renders each block as `Text.rich`, whose style lives on
/// the wrapped `TextSpan` rather than `Text.style` — the plain fallback title
/// (empty markdown case) is the only place a real `Text.style` shows up.
TextStyle styleOf(WidgetTester tester, String text) {
  final widget = tester.widget<Text>(find.text(text));
  final span = widget.textSpan;
  if (span is TextSpan && span.style != null) return span.style!;
  return widget.style!;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('renders the markdown H1 at the sheet-title style', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      banner(markdownBody: '# Recipe of the week\n\nMuddle, shake, pour.'),
    );
    await tester.pump();

    final style = styleOf(tester, 'Recipe of the week');

    expect(style.fontSize, 24);
    expect(style.fontWeight, FontWeight.w800);
    expect(style.color, EbtlColors.navy);
    // GoogleFonts bakes the weight into the family name
    // (e.g. "PlayfairDisplay_800"), so compare the family prefix rather than
    // the exact string.
    expect(style.fontFamily, startsWith('PlayfairDisplay'));

    expect(find.textContaining('Muddle, shake, pour.'), findsOneWidget);
  });

  testWidgets('h2-h4 step down from the h1 size', (tester) async {
    await pumpSheet(
      tester,
      banner(
        markdownBody:
            '# One\n\n## Two\n\n### Three\n\n#### Four\n\nBody copy.',
      ),
    );
    await tester.pump();

    final h1 = styleOf(tester, 'One').fontSize!;
    final h2 = styleOf(tester, 'Two').fontSize!;
    final h3 = styleOf(tester, 'Three').fontSize!;
    final h4 = styleOf(tester, 'Four').fontSize!;

    expect(h1, greaterThan(h2));
    expect(h2, greaterThan(h3));
    expect(h3, greaterThan(h4));
  });

  testWidgets('an empty markdown body falls back to the banner title', (
    tester,
  ) async {
    await pumpSheet(tester, banner(title: 'Untitled slide', markdownBody: ''));
    await tester.pump();

    expect(find.text('Untitled slide'), findsOneWidget);
  });
}
