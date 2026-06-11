String formatMoney(double value, String currency) {
  final hasDecimals = value.truncateToDouble() != value;
  final amount = hasDecimals
      ? value.toStringAsFixed(2)
      : value.toStringAsFixed(0);
  return '$currency $amount';
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
