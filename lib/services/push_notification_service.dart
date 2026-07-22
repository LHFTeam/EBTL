import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';

/// Best-effort device registration for push notifications.
///
/// The native side of `ebtl/push_notifications` is not wired up yet, so
/// `getToken` throws [MissingPluginException] today and this is a no-op.
/// Once a platform implementation provides a token, it is registered with
/// the backend automatically.
class PushNotificationService {
  static const MethodChannel _channel = MethodChannel(
    'ebtl/push_notifications',
  );

  static Future<void> registerDeviceIfAvailable() async {
    try {
      final token = await _channel.invokeMethod<String>('getToken');
      final cleanToken = token?.trim();
      if (cleanToken == null || cleanToken.isEmpty) return;

      await ApiService.registerCustomerPushToken(
        token: cleanToken,
        platform: defaultTargetPlatform.name,
      );
    } on MissingPluginException {
      // Native push registration has not been wired yet.
    } catch (_) {
      // Push registration must never block app startup.
    }
  }
}
