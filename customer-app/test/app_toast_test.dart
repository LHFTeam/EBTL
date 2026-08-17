// The in-app toast is rendered into the root Overlay, which sits outside the
// app's Material tree. Text there inherits MaterialApp's error placeholder
// style unless something re-establishes a default, so these tests pin down
// that the toast's own text carries no decoration.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/shared/widgets/app_toast.dart';

/// The style a [Text] actually paints with: its own style layered onto the
/// inherited [DefaultTextStyle].
TextStyle _resolvedStyle(WidgetTester tester, String text) {
  final finder = find.text(text);
  final inherited = DefaultTextStyle.of(tester.element(finder)).style;
  return inherited.merge(tester.widget<Text>(finder).style);
}

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext hostContext;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return hostContext;
}

void main() {
  testWidgets('toast title and message render without text decoration', (
    tester,
  ) async {
    final context = await _pumpHost(tester);

    showAppToast(
      context,
      title: 'Order ready',
      message: 'Your order is waiting at the bar.',
    );
    await tester.pumpAndSettle();

    for (final text in ['Order ready', 'Your order is waiting at the bar.']) {
      final style = _resolvedStyle(tester, text);
      expect(
        style.decoration ?? TextDecoration.none,
        TextDecoration.none,
        reason: '"$text" should not inherit the error placeholder underline',
      );
    }

    hideAppToast();
    await tester.pumpAndSettle();
  });

  testWidgets('toast keeps its own typography through the Material wrapper', (
    tester,
  ) async {
    final context = await _pumpHost(tester);

    showAppToast(context, title: 'Order ready', message: 'Ready for pickup.');
    await tester.pumpAndSettle();

    final title = _resolvedStyle(tester, 'Order ready');
    expect(title.fontSize, 15);
    expect(title.fontWeight, FontWeight.w800);

    final message = _resolvedStyle(tester, 'Ready for pickup.');
    expect(message.fontSize, 13);

    hideAppToast();
    await tester.pumpAndSettle();
  });

  testWidgets('snackbar pill text renders without text decoration', (
    tester,
  ) async {
    final context = await _pumpHost(tester);

    showAppSnackBar(context, 'Added to cart');
    await tester.pumpAndSettle();

    final style = _resolvedStyle(tester, 'Added to cart');
    expect(style.decoration ?? TextDecoration.none, TextDecoration.none);
  });
}
