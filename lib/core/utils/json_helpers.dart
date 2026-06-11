import 'dart:convert';

import '../network/api_exception.dart';

Map<String, dynamic> decodeJsonObject(String body, {required String endpoint}) {
  if (body.trim().isEmpty) return <String, dynamic>{};

  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    throw ApiException(
      message: 'Backend returned invalid JSON.',
      endpoint: endpoint,
      responseBody: body,
    );
  }

  if (decoded is Map<String, dynamic>) return decoded;

  throw ApiException(
    message: 'Unexpected backend response. Expected a JSON object.',
    endpoint: endpoint,
    responseBody: body,
  );
}

Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> readMapList(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value.map(asMap).where((item) => item.isNotEmpty).toList();
}

String readString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

String? nullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

List<String> readStringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }
  return <String>[];
}

List<String> readApiErrorDetails(dynamic blockingReasons, dynamic details) {
  final reasons = <String>[...readStringList(blockingReasons)];

  if (details is List) {
    for (final item in details) {
      final detail = asMap(item);
      final message = nullableString(detail['message']);
      final path = nullableString(detail['path']);

      if (message == null || message.isEmpty) continue;

      if (path != null && path.isNotEmpty) {
        reasons.add('$path: $message');
      } else {
        reasons.add(message);
      }
    }
  }

  return reasons;
}

bool readBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final clean = value.toLowerCase().trim();
    if (clean == 'true') return true;
    if (clean == 'false') return false;
  }
  return fallback;
}

int readInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double? readDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
