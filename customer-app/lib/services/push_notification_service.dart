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

      await _registerCurrentToken();
      messaging.onTokenRefresh.listen(_sendToken);

      _initialized = true;
    } catch (_) {
      // Firebase not configured for this build/platform — leave push disabled.
    }
  }

  static Future<void> _registerCurrentToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    await _sendToken(token);
  }

  static Future<void> _sendToken(String? token) async {
    final cleanToken = token?.trim();
    if (cleanToken == null || cleanToken.isEmpty) return;

    try {
      await ApiService.registerCustomerPushToken(
        token: cleanToken,
        platform: _platformName(),
      );
    } catch (_) {
      // Token registration is best-effort; never block startup on it.
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
