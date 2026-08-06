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

  // Order It Again Rail (Home v2, live order only)
  //
  // The card is wider than the design's 230pt: at 230 its text column is 94pt,
  // which ellipsizes "Ordered 3 days ago" (115pt at the specified size). The
  // rail is tall enough for the 56pt thumb, and for the kit name, the
  // "ordered ..." line and the price stacked beside it.
  static const double orderAgainCardWidth = 260;
  static const double orderAgainRailHeight = 88;

  // Hero Peek Carousel (Home v2, hidden only while an order is live)
  //
  // The slide width and gap are fixed; the page viewport fraction is derived
  // from them at layout time so the neighbouring slides peek in equally on any
  // phone width.
  static const double heroSlideWidth = 362.5;
  static const double heroSlideHeight = heroSlideWidth / 2;
  static const double heroSlideGap = 2;

  // Home Liquor Bottle Cards
  //
  // Laid out as a fixed 3-column grid on Home. The aspect ratio is width /
  // height of each cell — below 1 the cards are taller than they are wide,
  // giving the tall bottle art room to breathe.
  static const bool showHomeLiquorBottleCardName = false;
  static const double homeLiquorBottleCardAspectRatio = 0.82;
}
