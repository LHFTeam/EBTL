import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'firebase_bootstrap.dart';

/// Background/terminated message handler. The OS renders notification messages
/// itself; this exists so FCM has a registered background entry point.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op: order-ready notifications are display messages shown by the OS.
}

/// Firebase Cloud Messaging integration.
///
/// [initialize] is safe to call unconditionally and never throws: if Firebase
/// is not configured for the current platform/build (e.g. no
/// google-services.json / GoogleService-Info.plist), push is simply disabled
/// and the rest of the app is unaffected.
class PushNotificationService {
  static bool _initialized = false;
  static bool _tokenRegistered = false;
  static Future<void>? _registrationInFlight;

  /// How long to wait for iOS to hand the app its APNs token before giving up
  /// on this attempt. First launch spends most of it on the permission dialog.
  static const Duration _apnsTokenTimeout = Duration(seconds: 20);
  static const Duration _apnsTokenPollInterval = Duration(milliseconds: 500);

  static final StreamController<void> _messages =
      StreamController<void>.broadcast();

  /// Fires whenever a push reaches the app while it is open, or opens it from
  /// the tray. Carries no payload — it is a "something changed server-side"
  /// nudge for listeners to re-fetch. Stays silent (never errors) on builds
  /// where Firebase is not configured.
  static Stream<void> get onMessage => _messages.stream;

  /// Whether the current device token has reached the backend. Until it has,
  /// the server has nothing to push to.
  static bool get isTokenRegistered => _tokenRegistered;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      final ready = await FirebaseBootstrap.ensureInitialized();
      if (!ready) return;

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      // iOS/Android 13+ runtime permission. On older Android this is a no-op.
      await messaging.requestPermission();

      // Show foreground notifications on iOS (Android foreground display would
      // need a local-notifications plugin; background/terminated already works).
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_broadcast);
      FirebaseMessaging.onMessageOpenedApp.listen(_broadcast);
      messaging.onTokenRefresh.listen(_sendToken);

      // Set before the token round-trip rather than after it: everything above
      // must happen exactly once, while fetching and registering the token is
      // fallible and retried on its own by [refreshRegistration].
      _initialized = true;
    } catch (_) {
      // Firebase not configured for this build/platform — leave push disabled.
      return;
    }

    await refreshRegistration();
  }

  /// Registers the device token if that has not succeeded yet. Safe to call
  /// often — it is a no-op once the token is on the backend, and concurrent
  /// calls share one attempt.
  ///
  /// Worth calling on resume: the first attempt can fail because iOS had not
  /// produced an APNs token yet, or because the network was down, and without
  /// a retry the customer gets no push until the token happens to rotate.
  static Future<void> refreshRegistration() {
    if (!_initialized || _tokenRegistered) return Future<void>.value();

    final inFlight = _registrationInFlight;
    if (inFlight != null) return inFlight;

    final attempt = _register();
    _registrationInFlight = attempt;
    return attempt.whenComplete(() => _registrationInFlight = null);
  }

  static Future<void> _register() async {
    try {
      // On iOS, FCM cannot mint a token until APNs has handed one to the app,
      // and getToken() throws `apns-token-not-set` if asked before that. The
      // APNs handshake is asynchronous and typically outlives startup, so wait
      // for it instead of losing the registration to a race.
      if (_isApple) {
        final apnsToken = await _awaitApnsToken();
        if (apnsToken == null) return;
      }

      await _sendToken(await FirebaseMessaging.instance.getToken());
    } catch (_) {
      // Best-effort: a later resume retries.
    }
  }

  static Future<String?> _awaitApnsToken() async {
    final deadline = DateTime.now().add(_apnsTokenTimeout);

    while (true) {
      final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      if (apnsToken != null && apnsToken.isNotEmpty) return apnsToken;
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future<void>.delayed(_apnsTokenPollInterval);
    }
  }

  static bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static void _broadcast(RemoteMessage message) {
    if (!_messages.isClosed) _messages.add(null);
  }

  static Future<void> _sendToken(String? token) async {
    final cleanToken = token?.trim();
    if (cleanToken == null || cleanToken.isEmpty) return;

    try {
      await ApiService.registerCustomerPushToken(
        token: cleanToken,
        platform: _platformName(),
      );
      _tokenRegistered = true;
    } catch (_) {
      // Token registration is best-effort; never block startup on it. Left
      // unregistered so the next [refreshRegistration] tries again.
      _tokenRegistered = false;
    }
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return defaultTargetPlatform.name;
    }
  }
}
