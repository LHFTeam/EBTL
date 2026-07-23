import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Microsoft Clarity session replay + heatmaps.
///
/// Uses the EBTL Clarity project by default; enabled on release/profile builds
/// but not in debug, so day-to-day development and tests don't pollute the
/// Clarity data. Override the project ID — or disable Clarity entirely by
/// passing an empty value — at build time:
///
/// ```
/// flutter build apk --dart-define=CLARITY_PROJECT_ID=otherid   # different project
/// flutter build apk --dart-define=CLARITY_PROJECT_ID=          # disable
/// flutter run       --release                                  # test the default
/// ```
///
/// (The project ID is not a secret — it ships inside the app, like a GA
/// measurement ID — so it lives here rather than in an env file.)
///
/// Privacy: the Clarity mobile SDK masks text and input content by default, so
/// customer PII entered at checkout/profile (name, phone, delivery address,
/// payment) is not captured in replays. Wrap anything that must remain visible
/// with `ClarityUnmask`, and force-mask extra content with `ClarityMask`.
/// Verify masking against a real recording before relying on it.
class ClarityService {
  static const String _projectId = String.fromEnvironment(
    'CLARITY_PROJECT_ID',
    defaultValue: 'xr1vveuqim',
  );

  static bool get isEnabled => _projectId.isNotEmpty && !kDebugMode;

  /// Wraps [app] with Clarity when a project ID is configured, otherwise
  /// returns [app] unchanged.
  static Widget wrap(Widget app) {
    if (!isEnabled) return app;

    final config = ClarityConfig(
      projectId: _projectId,
      logLevel: kReleaseMode ? LogLevel.None : LogLevel.Info,
    );

    return ClarityWidget(app: app, clarityConfig: config);
  }
}
