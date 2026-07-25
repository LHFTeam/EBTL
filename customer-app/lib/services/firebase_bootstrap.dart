import 'package:firebase_core/firebase_core.dart';

/// Single, shared entry point for initializing Firebase.
///
/// Both crash reporting and push notifications need the default Firebase app,
/// but calling [Firebase.initializeApp] twice throws `duplicate-app`. This
/// initializes at most once and returns whether Firebase is available.
///
/// It never throws: if Firebase is not configured for the current
/// platform/build (e.g. no `google-services.json` / `GoogleService-Info.plist`)
/// it simply reports `false` and the dependent features stay disabled.
class FirebaseBootstrap {
  static bool _attempted = false;
  static bool _available = false;

  /// Whether Firebase finished initializing successfully.
  static bool get isAvailable => _available;

  static Future<bool> ensureInitialized() async {
    if (_attempted) return _available;
    _attempted = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _available = true;
    } catch (_) {
      _available = false;
    }

    return _available;
  }
}
