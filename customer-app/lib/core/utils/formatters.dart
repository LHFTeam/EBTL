String formatMoney(double value, String currency) {
  final hasDecimals = value.truncateToDouble() != value;
  final amount = hasDecimals
      ? value.toStringAsFixed(2)
      : value.toStringAsFixed(0);
  return '$currency $amount';
}

/// How far away a beach cart is, for the picker's rows — "350 m away" close in,
/// "2.4 km away" further out, "250 km away" once the decimal stops meaning
/// anything.
///
/// The precision drops as the distance grows because a phone fix does not carry
/// enough accuracy to justify the last digit: metres round to the nearest 10,
/// and past 100 km the tenth of a kilometre is noise on a number the customer
/// is only reading as "not near me".
String formatDistance(double meters) {
  if (meters < 1000) {
    // Rounding can reach 1000, which belongs on the kilometre branch below
    // rather than reading as "1000 m away".
    final roundedMeters = (meters / 10).round() * 10;
    if (roundedMeters < 1000) return '$roundedMeters m away';
  }

  final km = meters / 1000;
  if (km < 100) return '${km.toStringAsFixed(1)} km away';
  return '${km.round()} km away';
}

/// Formats an optional price, falling back to the bare [currency] label when
/// no price is available (used by product/cocktail `priceLabel` getters).
String formatOptionalPrice(double? price, String currency) {
  if (price == null) return currency;
  return formatMoney(price, currency);
}

/// Builds a beach-cart location subtitle from its compound and beach names,
/// joined with ' • ', falling back to [fallback] when both are blank.
String locationSubtitle(
  String? compoundName,
  String? beachName, {
  required String fallback,
}) {
  final parts = [
    compoundName,
    beachName,
  ].whereType<String>().where((part) => part.trim().isNotEmpty).toList();

  return parts.isEmpty ? fallback : parts.join(' • ');
}

/// A coarse "how long ago" label for a past date — "today", "yesterday",
/// "3 days ago", "last week", "3 weeks ago", "2 months ago". Returns null when
/// the value is missing, unparseable or in the future.
String? formatRelativeDay(String? isoValue) {
  if (isoValue == null || isoValue.trim().isEmpty) return null;

  final parsed = DateTime.tryParse(isoValue);
  if (parsed == null) return null;

  final local = parsed.toLocal();
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(local.year, local.month, local.day)).inDays;

  if (days < 0) return null;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return 'last week';
  if (days < 30) return '${days ~/ 7} weeks ago';
  if (days < 60) return 'last month';
  return '${days ~/ 30} months ago';
}

String formatProfileDateTime(String? isoValue) {
  if (isoValue == null || isoValue.trim().isEmpty) return 'Time unavailable';

  final parsed = DateTime.tryParse(isoValue);
  if (parsed == null) return isoValue;

  final local = parsed.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final diffDays = date.difference(today).inDays;
  final time = formatProfileTime(local);

  if (diffDays == 0) return 'Today, $time';
  if (diffDays == -1) return 'Yesterday, $time';

  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return '${weekdays[local.weekday - 1]} ${local.day}, ${months[local.month - 1]}, $time';
}

String formatProfileTime(DateTime value) {
  final hour12 = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:$minute $suffix';
}
