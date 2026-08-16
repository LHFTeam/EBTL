import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/widgets.dart';

/// Apple's App Tracking Transparency gate.
///
/// On iOS the advertising identifier (IDFA) reads back as all zeros until the
/// customer has answered the system prompt, so Meta App Events attribute to
/// nothing without this. The prompt is an App Store platform requirement for
/// reading the IDFA, not a GDPR-style consent step — EBTL operates in Egypt —
/// so it is asked once, unconditionally, and never re-asked: iOS only shows it
/// a single time per install and answers from the cached decision afterwards.
///
/// Off iOS the plugin answers [TrackingStatus.notSupported] and nothing here
/// prompts. Android's advertising ID is governed by the device's own ads
/// setting rather than by a per-app prompt, which is why [allowsAdvertiserId]
/// treats `notSupported` as permitted — anything else would switch Android
/// attribution off.
class AppTrackingService {
  /// How long to wait for the app to reach the foreground before giving up on
  /// prompting. iOS silently drops a request made while the app is inactive,
  /// so a prompt that never gets its chance is left for the next launch —
  /// the status stays `notDetermined` and this runs again then.
  static const Duration _foregroundTimeout = Duration(seconds: 10);

  static TrackingStatus _status = TrackingStatus.notDetermined;
  static Future<TrackingStatus>? _pending;

  static TrackingStatus get status => _status;

  /// Whether the device advertising identifier may be attached to events.
  ///
  /// `authorized` is the customer saying yes on iOS; `notSupported` is every
  /// non-iOS platform, where no such prompt exists. `denied`, `restricted`
  /// and an unanswered `notDetermined` all read the identifier back as zeros,
  /// so there is nothing to collect.
  static bool allowsAdvertiserId(TrackingStatus status) {
    return status == TrackingStatus.authorized ||
        status == TrackingStatus.notSupported;
  }

  /// Resolves the tracking status, showing Apple's prompt if it has never been
  /// answered on this install. Answers whether the advertising identifier is
  /// available once the customer has decided.
  ///
  /// Must be called after the first frame — see [_waitUntilResumed]. Safe to
  /// call more than once: concurrent callers share one prompt, and later calls
  /// answer from the decision already made.
  static Future<bool> ensureResolved() async {
    final resolved = await (_pending ??= _resolve());
    return allowsAdvertiserId(resolved);
  }

  static Future<TrackingStatus> _resolve() async {
    try {
      _status = await AppTrackingTransparency.trackingAuthorizationStatus;

      // Restricted devices and a decision already on file are final: iOS will
      // not show the prompt again, and asking would return the same answer.
      if (_status != TrackingStatus.notDetermined) return _status;

      if (!await _waitUntilResumed()) return _status;

      _status = await AppTrackingTransparency.requestTrackingAuthorization();
    } catch (_) {
      // Tracking permission is best-effort. A plugin or channel failure leaves
      // the status untouched, which keeps the advertising identifier off.
    }

    return _status;
  }

  /// Waits for the app to be foregrounded, answering whether it got there.
  static Future<bool> _waitUntilResumed() async {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return true;
    }

    final resumed = Completer<bool>();
    final listener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed && !resumed.isCompleted) {
          resumed.complete(true);
        }
      },
    );

    try {
      return await resumed.future.timeout(
        _foregroundTimeout,
        onTimeout: () => false,
      );
    } finally {
      listener.dispose();
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _status = TrackingStatus.notDetermined;
    _pending = null;
  }
}
