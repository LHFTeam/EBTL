import 'package:flutter/material.dart';

import '../core/theme/ebtl_colors.dart';
import '../core/utils/json_helpers.dart';

/// The card the app opens with when a beach cart is already chosen.
///
/// Which of the four time-of-day modes a customer gets is resolved on the
/// backend against Cairo local time (`server/lib/goldenHour.js`) — the app is
/// handed at most one, already picked, or nothing at all. That keeps the
/// business time zone in one place rather than depending on a device clock that
/// may be set anywhere in the world.
class GoldenHourModal {
  /// `morning` | `afternoon` | `sunset` | `evening`. Carried for analytics and
  /// debugging; nothing about the layout varies on it.
  final String mode;

  /// Which run of this mode's window the card belongs to — `'sunset:2026-08-10'`
  /// — written by the backend from Cairo time.
  ///
  /// The app shows each key at most once (`ApiService.hasSeenGoldenHour`), which
  /// is what makes the card once *per window* rather than once per launch:
  /// re-opening inside the same window is the same key, the next window of the
  /// day is a new one, and tomorrow's date makes every window new again.
  ///
  /// Empty for a payload from a backend older than the key. That degrades to the
  /// previous behaviour — shown on every launch — rather than to a card that can
  /// never be shown again.
  final String occurrenceKey;

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? imageCaption;
  final GoldenHourCocktail cocktail;

  /// The leading pill. Its text is always `Your <spirit>`, written by the
  /// backend from the cocktail's first liquor type; the dashboard only chooses
  /// the colour.
  final GoldenHourPill spiritPill;

  /// The pills after the leading one, in order. May be empty.
  final List<GoldenHourPill> pills;

  const GoldenHourModal({
    required this.mode,
    required this.occurrenceKey,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.imageCaption,
    required this.cocktail,
    required this.spiritPill,
    required this.pills,
  });

  /// Returns null for an absent, empty or unusable payload, which is the same
  /// thing to the caller: no card to open.
  static GoldenHourModal? fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return null;

    final title = readString(json['title']).trim().replaceAll('/', '\n');
    final cocktail = GoldenHourCocktail.fromJson(asMap(json['cocktail']));

    // A card with no words, or one whose button could not add anything, is not
    // worth interrupting a launch for. The backend enforces both; this is the
    // client half of the same rule, applied to a payload it does not trust.
    if (title.isEmpty || cocktail == null) return null;

    return GoldenHourModal(
      mode: readString(json['mode'], fallback: 'morning'),
      occurrenceKey: readString(json['occurrence_key']).trim(),
      title: title,
      subtitle: nullableString(json['subtitle']),
      imageUrl: nullableString(json['image_url']),
      imageCaption: nullableString(json['image_caption']),
      cocktail: cocktail,
      spiritPill: GoldenHourPill.fromJson(asMap(json['spirit_pill'])),
      pills: readMapList(json['pills'])
          .map(GoldenHourPill.fromJson)
          .where((pill) => pill.label.isNotEmpty)
          .toList(growable: false),
    );
  }

  bool get hasImage => imageUrl?.trim().isNotEmpty ?? false;
}

/// The cocktail the card pitches.
///
/// Only enough to name it and open it. The slug is what matters: Add to Cart
/// loads the cocktail's detail first, exactly as "Order It Again" does, so it
/// adds at today's price and availability rather than a snapshot taken whenever
/// marketing wrote the card.
class GoldenHourCocktail {
  final String id;
  final String slug;
  final String name;

  const GoldenHourCocktail({
    required this.id,
    required this.slug,
    required this.name,
  });

  static GoldenHourCocktail? fromJson(Map<String, dynamic> json) {
    final slug = readString(json['slug']).trim();
    if (slug.isEmpty) return null;

    return GoldenHourCocktail(
      id: readString(json['id']),
      slug: slug,
      name: readString(json['name'], fallback: 'this cocktail'),
    );
  }
}

class GoldenHourPill {
  final String label;

  /// A key from [GoldenHourPillScheme.palette]. Stored rather than resolved so
  /// an unknown one — a newer dashboard offering a scheme this app version does
  /// not have — falls back at paint time instead of dropping the pill.
  final String scheme;

  const GoldenHourPill({required this.label, required this.scheme});

  factory GoldenHourPill.fromJson(Map<String, dynamic> json) {
    return GoldenHourPill(
      label: readString(json['label']).trim(),
      scheme: readString(json['scheme'], fallback: GoldenHourPillScheme.fallbackKey),
    );
  }

  GoldenHourPillScheme get colors => GoldenHourPillScheme.forKey(scheme);
}

/// The pill palette, keyed by the same names the backend offers the dashboard
/// (`GOLDEN_HOUR_PILL_SCHEMES` in `server/lib/goldenHour.js`).
///
/// The colours live here rather than travelling in the payload: they are the
/// app's own design tokens, and a backend that could restyle the app would be a
/// backend that could break it. The cost is that adding a scheme takes both
/// sides — which is the right trade for eight fixed brand colours.
class GoldenHourPillScheme {
  final Color background;
  final Color foreground;

  const GoldenHourPillScheme({
    required this.background,
    required this.foreground,
  });

  static const String fallbackKey = 'sand';

  static const Map<String, GoldenHourPillScheme> palette = {
    'sand': GoldenHourPillScheme(
      background: EbtlColors.sand,
      foreground: EbtlColors.navy,
    ),
    'seafoam': GoldenHourPillScheme(
      background: EbtlColors.seafoam,
      foreground: EbtlColors.teal,
    ),
    'blush': GoldenHourPillScheme(
      background: EbtlColors.blush,
      foreground: EbtlColors.navy,
    ),
    'gold': GoldenHourPillScheme(
      background: EbtlColors.gold,
      foreground: EbtlColors.navy,
    ),
    'coral': GoldenHourPillScheme(
      background: EbtlColors.coral,
      foreground: EbtlColors.white,
    ),
    'teal': GoldenHourPillScheme(
      background: EbtlColors.teal,
      foreground: EbtlColors.white,
    ),
    'navy': GoldenHourPillScheme(
      background: EbtlColors.navy,
      foreground: EbtlColors.cream,
    ),
    'cream': GoldenHourPillScheme(
      background: EbtlColors.cream,
      foreground: EbtlColors.ink,
    ),
  };

  static GoldenHourPillScheme forKey(String? key) {
    return palette[key?.trim()] ?? palette[fallbackKey]!;
  }
}
