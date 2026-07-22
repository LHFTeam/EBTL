/// User-facing message for a failed API call: the ApiException message plus
/// its blocking reasons when present, else [fallback] (or `error.toString()`
/// when no fallback is given) for non-API errors.
String apiErrorMessage(Object error, {String? fallback}) {
  if (error is ApiException) {
    if (error.blockingReasons.isEmpty) return error.message;
    return [error.message, ...error.blockingReasons].join('\n');
  }

  return fallback ?? error.toString();
}

class ApiException implements Exception {
  final String message;
  final String endpoint;
  final int? statusCode;
  final List<String> blockingReasons;
  final String? responseBody;

  const ApiException({
    required this.message,
    required this.endpoint,
    this.statusCode,
    this.blockingReasons = const [],
    this.responseBody,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln(message);
    buffer.writeln('Endpoint: $endpoint');
    if (statusCode != null) buffer.writeln('Status: $statusCode');
    if (blockingReasons.isNotEmpty) {
      buffer.writeln('Reasons:');
      for (final reason in blockingReasons) {
        buffer.writeln('- $reason');
      }
    }
    if (responseBody != null && responseBody!.trim().isNotEmpty) {
      buffer.writeln('Body: $responseBody');
    }
    return buffer.toString().trim();
  }
}
