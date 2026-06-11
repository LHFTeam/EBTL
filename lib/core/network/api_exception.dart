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
