import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ebtl_colors.dart';

TextStyle sectionTitleStyle() {
  return GoogleFonts.manrope(
    fontSize: 18,
    color: EbtlColors.navy,
    fontWeight: FontWeight.w900,
  );
}

/// The type size the cocktail detail screen sets the chosen beach cart's name
/// in, on the availability card at the top of the page.
///
/// The removable-ingredient pills further down are read at the same size, so
/// the two are pinned to this rather than repeating a number that can drift.
const double detailBeachCartNameFontSize = 16;

TextStyle detailSectionTitleStyle() {
  return GoogleFonts.manrope(
    fontSize: 16,
    color: EbtlColors.navy,
    fontWeight: FontWeight.w900,
  );
}
