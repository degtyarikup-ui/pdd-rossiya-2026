import 'package:flutter/material.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:pdd_app/presentation/widgets/google_web_sign_in_button.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/auth_provider_button.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/web_oauth_redirect_stub.dart'
    if (dart.library.js_interop) 'package:pdd_app/data/services/web_oauth_redirect.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';

class AuthModalSheet extends StatefulWidget {
  const AuthModalSheet({super.key, this.initialAction});
  final Future<bool> Function()? initialAction;

  static Future<bool?> show(
    BuildContext context, {
    Future<bool> Function()? initialAction,
  }) {
    HapticFeedbackHelper.tap();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AuthModalSheet(initialAction: initialAction),
    );
  }

  @override
  State<AuthModalSheet> createState() => _AuthModalSheetState();
}

class _AuthModalSheetState extends State<AuthModalSheet> {
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final action = widget.initialAction;
    if (action != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleAuth(action);
      });
    }
  }

  String _failureMessage() {
    final auth = AuthService.instance;
    final message = switch (auth.lastFailure) {
      AuthFailure.cancelled => appL10n.authErrorCancelled,
      AuthFailure.provider => appL10n.authErrorProvider,
      AuthFailure.network => appL10n.authErrorNetwork,
      AuthFailure.timeout => appL10n.authErrorTimeout,
      AuthFailure.appKey => appL10n.authErrorAppKey,
      AuthFailure.credential => appL10n.authErrorCredential,
      AuthFailure.server => appL10n.authErrorServer,
      AuthFailure.response => appL10n.authErrorResponse,
      null => appL10n.authFailed,
    };
    final id = auth.lastDiagnosticId;
    return id == null ? message : '$message\n${appL10n.authDiagnosticCode(id)}';
  }

  Future<void> _handleAuth(Future<bool> Function() action) async {
    if (_isLoading) return;
    HapticFeedbackHelper.select();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final success = await action();
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          HapticFeedbackHelper.success();
          Navigator.of(context).pop(true);
          AppToast.show(
            context,
            AuthService.instance.sessionIsTemporary
                ? appL10n.authSessionTemporary
                : appL10n.authSuccess,
            type: AppToastType.success,
            duration: const Duration(seconds: 6),
          );
        } else {
          setState(() => _error = _failureMessage());
        }
      }
    } catch (e) {
      ErrorReporter.report(ErrorCategory.auth, 'auth.dialog', error: e);
      if (mounted) {
        setState(() => _isLoading = false);
        setState(() => _error = _failureMessage());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.screenPadding,
              12,
              AppDimensions.screenPadding,
              24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Close Button
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: colors.secondaryText,
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(height: 4),

                  Text(
                    appL10n.authTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    appL10n.authDescription,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      color: colors.secondaryText,
                    ),
                  ),
                  SizedBox(
                    height: 24,
                    child: _isLoading
                        ? const Center(child: LinearProgressIndicator())
                        : null,
                  ),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // OAuth Buttons
                  if (kIsWeb ||
                      Theme.of(context).platform == TargetPlatform.iOS) ...[
                    _buildAuthButton(
                      svgAsset: 'assets/icons/auth/apple.svg',
                      svgColor: colors.primaryText,
                      label: appL10n.authApple,
                      onTap: () =>
                          _handleAuth(AuthService.instance.signInWithApple),
                    ),
                    if (appleWebNeedsSafariHint) ...[
                      const SizedBox(height: 8),
                      Text(
                        appL10n.authAppleSafariHint,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.secondaryText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 10),
                  ],

                  if (kIsWeb)
                    GoogleWebSignInButton(
                      enabled: !_isLoading,
                      onSignIn: (request) => _handleAuth(
                        () => AuthService.instance.signInWithGoogleWeb(request),
                      ),
                      onError: (error) {
                        ErrorReporter.report(
                          ErrorCategory.auth,
                          'google.web_button',
                          error: error,
                          provider: 'google',
                        );
                        if (mounted) {
                          setState(() => _error = appL10n.authErrorProvider);
                        }
                      },
                    )
                  else
                    _buildAuthButton(
                      svgAsset: 'assets/icons/auth/google.svg',
                      label: appL10n.authGoogle,
                      onTap: () =>
                          _handleAuth(AuthService.instance.signInWithGoogle),
                    ),
                  const SizedBox(height: 10),

                  _buildAuthButton(
                    svgAsset: 'assets/icons/auth/yandex.svg',
                    label: appL10n.authYandex,
                    onTap: () => _handleAuth(
                      () => AuthService.instance.signInWithYandex(context),
                    ),
                  ),
                  if (AuthService.debugSignInAvailable) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _handleAuth(AuthService.instance.signInDebug),
                      icon: const Icon(Icons.bug_report_outlined),
                      label: Text(appL10n.authDebug),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthButton({
    required String svgAsset,
    Color? svgColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return AuthProviderButton(
      svgAsset: svgAsset,
      svgColor: svgColor,
      label: label,
      onTap: _isLoading ? null : onTap,
    );
  }
}
