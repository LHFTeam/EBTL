import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Microsoft Clarity session replay + heatmaps.
///
/// Enabled only when a project ID is provided at build time, so ordinary
/// builds are completely unaffected:
///
/// ```
/// flutter run   --dart-define=CLARITY_PROJECT_ID=xxxxxxxx
/// flutter build --dart-define=CLARITY_PROJECT_ID=xxxxxxxx
/// ```
///
/// When the ID is unset, [wrap] returns the app unchanged and Clarity does not
/// initialize.
///
/// Privacy: the Clarity mobile SDK masks text and input content by default, so
/// customer PII entered at checkout/profile (name, phone, delivery address,
/// payment) is not captured in replays. Wrap anything that must remain visible
/// with `ClarityUnmask`, and force-mask extra content with `ClarityMask`.
/// Verify masking against a real recording before relying on it.
class ClarityService {
  static const String _projectId = String.fromEnvironment(
    'CLARITY_PROJECT_ID',
    defaultValue: '',
  );

  static bool get isEnabled => _projectId.isNotEmpty;

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
