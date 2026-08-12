import 'package:flutter/material.dart';

/// Puts the keyboard away, whatever is focused.
///
/// Every text field in the app hands this to `TextField.onTapOutside`, because
/// iOS does not do it on its own: unlike desktop and the web, a *touch*
/// outside a focused field leaves the keyboard up, with nothing on screen to
/// dismiss it. Android behaves the same way, so this is what makes the field
/// close what it opened on both.
///
/// A field that is grouped with something else — the catalog search field and
/// the results dropdown hanging off it, say — widens what counts as "outside"
/// with `TextField.groupId`; this only decides what happens once a tap really
/// is outside.
void dismissKeyboard([PointerDownEvent? _]) {
  FocusManager.instance.primaryFocus?.unfocus();
}
