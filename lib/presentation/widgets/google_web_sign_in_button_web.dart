import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as google_web;
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';

class GoogleWebSignInButton extends StatefulWidget {
  const GoogleWebSignInButton({
    super.key,
    required this.onAccount,
    required this.onError,
    required this.enabled,
  });
  final ValueChanged<GoogleSignInAccount> onAccount;
  final ValueChanged<Object> onError;
  final bool enabled;

  @override
  State<GoogleWebSignInButton> createState() => _GoogleWebSignInButtonState();
}

class _GoogleWebSignInButtonState extends State<GoogleWebSignInButton> {
  late final GoogleSignIn _google;
  late final StreamSubscription<GoogleSignInAccount?> _subscription;

  @override
  void initState() {
    super.initState();
    _google = GoogleSignIn(clientId: AuthService.googleWebClientId);
    _subscription = _google.onCurrentUserChanged.listen(
      (account) {
        if (mounted && widget.enabled && account != null) {
          widget.onAccount(account);
        }
      },
      onError: (Object error) {
        if (mounted && widget.enabled) widget.onError(error);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    absorbing: !widget.enabled,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(400.0, constraints.maxWidth);
        return Center(
          child: SizedBox(
            width: width,
            height: 44,
            child: google_web.renderButton(
              configuration: google_web.GSIButtonConfiguration(
                theme: Theme.of(context).brightness == Brightness.dark
                    ? google_web.GSIButtonTheme.filledBlack
                    : google_web.GSIButtonTheme.outline,
                size: google_web.GSIButtonSize.large,
                text: google_web.GSIButtonText.continueWith,
                shape: google_web.GSIButtonShape.pill,
                minimumWidth: width,
                locale: CountryConfig.current.language,
              ),
            ),
          ),
        );
      },
    ),
  );
}
