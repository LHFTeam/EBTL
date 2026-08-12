// Every text field in the app hands `dismissKeyboard` to `onTapOutside`,
// because iOS keeps the keyboard up on a touch outside a focused field. The
// search field's own grouping with its results dropdown is covered in
// catalog_search_test.dart; this covers the plain form fields.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/shared/widgets/checkout_input_field.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a tap on the page dismisses a checkout field keyboard', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Focus(
                focusNode: focusNode,
                child: CheckoutInputField(
                  controller: controller,
                  label: 'Phone',
                  hintText: '01xxxxxxxxx',
                  icon: Icons.phone,
                  onChanged: (_) {},
                ),
              ),
              const Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Text('the rest of the form'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text('the rest of the form'));
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
  });
}
