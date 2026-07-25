import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'firebase_bootstrap.dart';

/// Firebase Crashlytics integration + global uncaught-error handlers.
///
/// [initialize] is safe to call unconditionally and never throws: if Firebase
/// is not configured for the current platform/build (e.g. no
/// `google-services.json` / `GoogleService-Info.plist`) crash reporting is
/// simply disabled and the app is unaffected.
///
/// Collection is off in debug builds so local development and tests don't send
/// crashes to Crashlytics; it is enabled on profile/release builds where a
/// Firebase config is present.
class CrashReportingService {
  static bool _enabled = false;

  /// Whether crash reporting is active (Firebase configured and not debug).
  static bool get isEnabled => _enabled;

  static Future<void> initialize() async {
    final ready = await FirebaseBootstrap.ensureInitialized();
    if (!ready) return;

    try {
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

      // Route Flutter framework errors to Crashlytics (still printing them to
      // the console in debug via presentError).
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        previousOnError?.call(details);
        crashlytics.recordFlutterFatalError(details);
      };

      // Route errors that escape the Flutter framework (async gaps, platform
      // callbacks) to Crashlytics. Returning true marks them as handled.
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };

      _enabled = true;
    } catch (_) {
      // Crashlytics unavailable for this build — leave reporting disabled.
      _enabled = false;
    }
  }

  /// Records a non-fatal error. No-op when reporting is disabled.
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    if (!_enabled) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: fatal,
      );
    } catch (_) {
      // Never let crash reporting itself throw.
    }
  }
}
