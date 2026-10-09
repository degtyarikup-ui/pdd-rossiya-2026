import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_identity_services_web/oauth2.dart' as google;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/web_oauth_state.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/auth_provider_button.dart';

class GoogleWebSignInButton extends StatefulWidget {
  const GoogleWebSignInButton({
    super.key,
    required this.onSignIn,
    required this.onError,
    required this.enabled,
  });
  final Future<void> Function(Future<String> Function()) onSignIn;
  final ValueChanged<Object> onError;
  final bool enabled;

  @override
  State<GoogleWebSignInButton> createState() => _GoogleWebSignInButtonState();
}

class _GoogleWebSignInButtonState extends State<GoogleWebSignInButton> {
  static Future<bool>? _sdkReady;
  bool _ready = false;
  bool _preparing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    if (_preparing) return;
    setState(() {
      _preparing = true;
      _failed = false;
    });
    try {
      // Reuse the plugin's loader: loading GIS twice can break Trusted Types.
      // This read-only check never opens an account prompt.
      await (_sdkReady ??= GoogleSignIn(
        clientId: AuthService.googleWebClientId,
      ).isSignedIn().timeout(const Duration(seconds: 15)));
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      _sdkReady = null;
      if (mounted) {
        setState(() => _failed = true);
        widget.onError(PlatformException(code: 'google_sdk_unavailable'));
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<String> _requestToken() {
    final result = Completer<String>();
    final state = newWebOAuthState();
    void fail(String code) {
      if (!result.isCompleted) {
        result.completeError(PlatformException(code: code));
      }
    }

    final client = google.oauth2.initTokenClient(
      google.TokenClientConfig(
        client_id: AuthService.googleWebClientId,
        scope: ['openid', 'email', 'profile'],
        include_granted_scopes: false,
        prompt: 'select_account',
        state: state,
        callback: (response) {
          if (result.isCompleted) return;
          final token = response.access_token;
          if (response.error != null) {
            fail(
              response.error == 'access_denied'
                  ? 'sign_in_cancelled'
                  : 'google_oauth_failed',
            );
          } else if (response.state != state ||
              token == null ||
              token.isEmpty) {
            fail('google_oauth_invalid_response');
          } else {
            result.complete(token);
          }
        },
        error_callback: (error) => fail(
          error?.type == google.GoogleIdentityServicesErrorType.popup_closed
              ? 'sign_in_cancelled'
              : 'google_popup_unavailable',
        ),
      ),
    );
    // No await before this call: iOS must retain the original tap gesture.
    client.requestAccessToken();
    return result.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        if (!result.isCompleted) {
          result.completeError(TimeoutException('Google'));
        }
        throw TimeoutException('Google sign-in timed out');
      },
    );
  }

  @override
  Widget build(BuildContext context) => AuthProviderButton(
    svgAsset: 'assets/icons/auth/google.svg',
    label: appL10n.authGoogle,
    busy: _preparing,
    onTap: !widget.enabled || (!_ready && !_failed)
        ? null
        : !_ready
        ? () => unawaited(_prepare())
        : () => unawaited(widget.onSignIn(_requestToken)),
  );
}
