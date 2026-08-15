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

  // The height carries the artwork plus the tallest the text block can get: a
  // two-line name, the short description over two lines, and the corner action.
  // Raising a font size here without raising this overflows the rail.
  static const double featuredProductCardHeight = 204;
  static const double featuredProductCardWidth = 128;
  static const double featuredProductCardImageHeight = 110;

  static const EdgeInsets featuredProductCardTextPadding = EdgeInsets.fromLTRB(
    12,
    8,
    10,
    8,
  );

  static const double featuredProductCardNameFontSize = 12;
  static const double featuredProductCardNameLineHeight = 1.12;

  static const double featuredProductCardShortDescriptionFontSize = 11;
  static const double featuredProductCardShortDescriptionLineHeight = 1.1;

  // Order It Again Rail (Home v2, live order only)
  //
  // The card is wider than the design's 230pt: at 230 its text column is 94pt,
  // which ellipsizes "Ordered 3 days ago" (115pt at the specified size).
  //
  // The card lays out to 78pt: the 56pt thumb — taller than the kit name, the
  // "ordered ..." line and the price stacked beside it — plus 10pt of padding
  // and 1pt of border on each side. The rail carries that and the 4pt the list
  // reserves under its cards, so raising the thumb or the padding has to be
  // paid for here.
  static const double orderAgainCardWidth = 260;
  static const double orderAgainRailHeight = 84;

  // Hero Peek Carousel (Home v2, hidden only while an order is live)
  //
  // The slide width and gap are fixed; the page viewport fraction is derived
  // from them at layout time so the neighbouring slides peek in equally on any
  // phone width.
  static const double heroSlideWidth = 362.5;
  static const double heroSlideHeight = heroSlideWidth / 2;
  static const double heroSlideGap = 2;

  // The Spotlight Rail (Home v2)
  //
  // Banner artwork is authored at 2.5:1 — the height follows from the width so
  // the card is exactly the shape of the image and nothing is cropped. The rail
  // shows two cards with the third peeking in, which is what sets the width: a
  // 393pt phone less the 22pt gutters fits one card, its gap, and a slice of the
  // next.
  static const double spotlightBannerAspectRatio = 2.5;
  static const double spotlightBannerWidth = 252;
  static const double spotlightBannerHeight =
      spotlightBannerWidth / spotlightBannerAspectRatio;
  static const double spotlightBannerGap = 14;

  // Recently Viewed Rail (Home v2)
  //
  // Drawn from the on-device snapshot of what the customer opened: artwork,
  // name, short description and price, over the add-to-cart action. The rail
  // height carries the tallest that stack gets — a two-line name, a two-line
  // description and the 30pt button — so a font size raised here has to be paid
  // for there.
  static const double recentlyViewedCardWidth = 128;
  static const double recentlyViewedCardImageHeight = 96;
  static const double recentlyViewedRailHeight = 206;

  static const double recentlyViewedCardNameFontSize = 12;
  static const double recentlyViewedCardNameLineHeight = 1.12;

  static const double recentlyViewedCardShortDescriptionFontSize = 11;
  static const double recentlyViewedCardShortDescriptionLineHeight = 1.1;

  // Home Liquor Bottle Cards
  //
  // Laid out as a fixed 3-column grid on Home. The aspect ratio is width /
  // height of each cell — below 1 the cards are taller than they are wide,
  // giving the tall bottle art room to breathe.
  static const bool showHomeLiquorBottleCardName = false;
  static const double homeLiquorBottleCardAspectRatio = 0.82;
}
