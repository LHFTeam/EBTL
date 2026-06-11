class ApiConfig {
  static const String baseUrl = 'https://ebtl-admin-dashboard.onrender.com';

  static Uri endpoint(String path, [Map<String, String?>? query]) {
    final cleanedQuery = <String, String>{};

    query?.forEach((key, value) {
      final cleanValue = value?.trim();
      if (cleanValue != null && cleanValue.isNotEmpty) {
        cleanedQuery[key] = cleanValue;
      }
    });

    return Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: cleanedQuery.isEmpty ? null : cleanedQuery);
  }
}
