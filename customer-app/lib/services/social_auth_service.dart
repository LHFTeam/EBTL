import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../models/profile_models.dart';
import 'analytics_service.dart';
import 'api_service.dart';

/*
  The one place the app talks to a social identity provider.

  Screens never touch these SDKs directly — same boundary AnalyticsService
  draws, and for the same reason: three vendors with three different notions of
  what a token is should not leak into widget code.

  What each provider hands back differs enough to matter:

  - Apple and Google both return an OIDC id_token. Both are verified server-side
    against the provider's published keys.
  - Facebook returns one of two things. With App Tracking Transparency consent
    it is a classic OAuth access token; without it — the default here, since the
    app ships with advertiser-ID collection off — Meta returns a *limited login*
    OIDC token instead, which is a different credential verified a different
    way. The app tells the backend which kind it got rather than making the
    backend guess.

  Every flow is nonce-protected: a random value is generated here, its SHA-256
  goes to the provider, and the raw value goes to the backend, which checks that
  the token it was handed carries the matching digest. That is what stops a
  token lifted from another app being replayed at ours.
*/

enum SocialProvider { facebook, google, apple }

extension SocialProviderLabel on SocialProvider {
  String get wireName => name;

  String get displayName {
    switch (this) {
      case SocialProvider.facebook:
        return 'Facebook';
      case SocialProvider.google:
        return 'Google';
      case SocialProvider.apple:
        return 'Apple';
    }
  }
}

/// Thrown when a sign-in could not be completed. [cancelled] separates "the
/// customer backed out" from "something went wrong" — the first must not put an
/// error in front of someone who has just placed an order.
class SocialAuthException implements Exception {
  final String message;
  final bool cancelled;

  const SocialAuthException(this.message, {this.cancelled = false});

  @override
  String toString() => message;
}

class SocialAuthService {
  const SocialAuthService._();

  /// Apple's sign-in sheet only exists on Apple platforms. Everywhere else the
  /// button is not offered at all rather than offered and failing.
  static bool get supportsApple {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isMacOS;
  }

  /// The OAuth client the backend checks Google's id_token audience against.
  /// Supplied at build time, the same way Firebase and Clarity are:
  /// `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`.
  static const _googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// iOS-only. Google's iOS SDK needs its own client ID, and the matching
  /// reversed-client-ID URL scheme has to be in `ios/Runner/Info.plist` for the
  /// callback to come back to the app.
  static const _googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Google sign-in is inert until those client IDs are supplied — the same
  /// rule the rest of the app's optional integrations follow. An unconfigured
  /// build hides the button rather than offering one that always fails.
  static bool get supportsGoogle => _googleServerClientId.trim().isNotEmpty;

  static bool _googleInitialized = false;

  /// Signs in with [provider] and links the identity to the current customer.
  ///
  /// Returns the profile the backend resolved. The session token swap needs no
  /// handling here: the response carries a `session` object and
  /// [ApiService] persists any it sees.
  static Future<CustomerProfile> signIn(SocialProvider provider) async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = switch (provider) {
      SocialProvider.facebook => await _facebookCredential(hashedNonce),
      SocialProvider.google => await _googleCredential(hashedNonce),
      SocialProvider.apple => await _appleCredential(hashedNonce),
    };

    final result = await ApiService.signInWithSocialProvider(
      provider: provider.wireName,
      token: credential.token,
      tokenKind: credential.tokenKind,
      nonce: rawNonce,
      fullName: credential.fullName,
    );

    // A first account and a returning sign-in are different events, and only
    // the backend can tell which this was.
    if (result.isNewCustomer) {
      AnalyticsService.logSignUp(method: provider.wireName);
    } else {
      AnalyticsService.logLogin(method: provider.wireName);
    }

    return result.profile;
  }

  static Future<_SocialCredential> _facebookCredential(
    String hashedNonce,
  ) async {
    final LoginResult result;

    try {
      result = await FacebookAuth.instance.login(
        permissions: const ['email', 'public_profile'],
        // Limited login is the honest default for this app: advertiser-ID
        // collection is off and the ATT prompt is not guaranteed, and asking
        // for a classic token we cannot justify is worse than working with the
        // OIDC one.
        loginTracking: LoginTracking.limited,
        nonce: hashedNonce,
      );
    } catch (error) {
      throw SocialAuthException('Could not reach Facebook: $error');
    }

    switch (result.status) {
      case LoginStatus.cancelled:
        throw const SocialAuthException('Sign-in cancelled.', cancelled: true);
      case LoginStatus.operationInProgress:
        throw const SocialAuthException('A sign-in is already in progress.');
      case LoginStatus.failed:
        throw SocialAuthException(
          result.message ?? 'Facebook sign-in did not complete.',
        );
      case LoginStatus.success:
        break;
    }

    final token = result.accessToken;
    if (token == null) {
      throw const SocialAuthException('Facebook did not return a token.');
    }

    return _SocialCredential(
      token: token.tokenString,
      tokenKind: token.type == AccessTokenType.limited
          ? 'limited'
          : 'classic',
      fullName: token is LimitedToken ? token.userName : null,
    );
  }

  static Future<_SocialCredential> _googleCredential(
    String hashedNonce,
  ) async {
    if (!supportsGoogle) {
      throw const SocialAuthException(
        'Google sign-in is not configured in this build.',
      );
    }

    final signIn = GoogleSignIn.instance;

    if (!signIn.supportsAuthenticate()) {
      throw const SocialAuthException(
        'Google sign-in is not available on this device.',
      );
    }

    // initialize() is safe to call more than once, but it is a platform round
    // trip, so the first sign-in of a launch pays for it and the rest do not.
    if (!_googleInitialized) {
      await signIn.initialize(
        clientId: _googleIosClientId.trim().isEmpty
            ? null
            : _googleIosClientId.trim(),
        serverClientId: _googleServerClientId.trim(),
        nonce: hashedNonce,
      );
      _googleInitialized = true;
    }

    final GoogleSignInAccount account;

    try {
      account = await signIn.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const SocialAuthException('Sign-in cancelled.', cancelled: true);
      }

      throw SocialAuthException(
        error.description ?? 'Google sign-in did not complete.',
      );
    } catch (error) {
      throw SocialAuthException('Could not reach Google: $error');
    }

    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.trim().isEmpty) {
      throw const SocialAuthException('Google did not return an identity token.');
    }

    return _SocialCredential(
      token: idToken,
      tokenKind: 'id_token',
      fullName: account.displayName,
    );
  }

  static Future<_SocialCredential> _appleCredential(String hashedNonce) async {
    final AuthorizationCredentialAppleID credential;

    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const SocialAuthException('Sign-in cancelled.', cancelled: true);
      }

      throw SocialAuthException(
        error.message.isEmpty ? 'Apple sign-in did not complete.' : error.message,
      );
    } catch (error) {
      throw SocialAuthException('Could not reach Apple: $error');
    }

    final identityToken = credential.identityToken;
    if (identityToken == null || identityToken.trim().isEmpty) {
      throw const SocialAuthException('Apple did not return an identity token.');
    }

    // Apple sends the name on the *first* authorization only, so whatever comes
    // back here has to be forwarded now — there is no second chance to read it.
    final name = [
      credential.givenName ?? '',
      credential.familyName ?? '',
    ].where((part) => part.trim().isNotEmpty).join(' ').trim();

    return _SocialCredential(
      token: identityToken,
      tokenKind: 'id_token',
      fullName: name.isEmpty ? null : name,
    );
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();

    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}

class _SocialCredential {
  final String token;
  final String tokenKind;
  final String? fullName;

  const _SocialCredential({
    required this.token,
    required this.tokenKind,
    required this.fullName,
  });
}
