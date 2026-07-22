import 'package:flutter/material.dart';

import '../theme/ebtl_colors.dart';

Color colorFromHex(String hex, {Color fallback = EbtlColors.teal}) {
  final cleaned = hex.trim().replaceFirst('#', '');

  if (cleaned.length != 6) return fallback;

  final value = int.tryParse('FF$cleaned', radix: 16);
  if (value == null) return fallback;

  return Color(value);
}
