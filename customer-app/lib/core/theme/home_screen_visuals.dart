import 'package:flutter/material.dart';

class HomeScreenVisuals {
  /*
    Home Screen Visual Controls

    Notes:
    - Font size values are logical pixels.
    - Line height values are Flutter text height multipliers.
      Example: 1.20 means 120% of the font size.
  */

  // Featured Products Cards
  static const bool showFeaturedProductCardPrice = false;

  static const double featuredProductCardHeight = 200;
  static const double featuredProductCardWidth = 128;
  static const double featuredProductCardImageHeight = 110;

  static const EdgeInsets featuredProductCardTextPadding = EdgeInsets.fromLTRB(
    12,
    8,
    10,
    8,
  );

  static const double featuredProductCardNameFontSize = 10;
  static const double featuredProductCardNameLineHeight = 1.12;

  static const double featuredProductCardShortDescriptionFontSize = 8;
  static const double featuredProductCardShortDescriptionLineHeight = 1.1;

  // Home Liquor Bottle Cards
  static const bool showHomeLiquorBottleCardName = false;
}
