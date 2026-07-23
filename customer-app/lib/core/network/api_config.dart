class ApiConfig {
  /// Production backend, used when no override is provided so release builds
  /// are unaffected.
  static const String _defaultBaseUrl =
      'https://ebtl-admin-dashboard.onrender.com';

  /// Backend base URL.
  ///
  /// Point the app at a different environment (e.g. staging) at build/run time
  /// without editing source:
  ///
  /// ```
  /// flutter run   --dart-define=API_BASE_URL=https://ebtl-staging.onrender.com
  /// flutter build --dart-define=API_BASE_URL=https://ebtl-staging.onrender.com
  /// ```
  ///
  /// Falls back to production when unset.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  static Uri endpoint(String path, [Map<String, String?>? query]) {
    final cleanedQuery = <String, String>{};

    query?.forEach((key, value) {
      final cleanValue = value?.trim();
      if (cleanValue != null && cleanValue.isNotEmpty) {
        cleanedQuery[key] = cleanValue;
      }
    });

    // Tolerate a trailing slash on an overridden base URL so it does not
    // collide with the leading slash on every endpoint path.
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    return Uri.parse(
      '$normalizedBase$path',
    ).replace(queryParameters: cleanedQuery.isEmpty ? null : cleanedQuery);
  }
}
