import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pdd_app/presentation/widgets/google_web_sign_in_button.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';

class AuthModalSheet extends StatefulWidget {
  const AuthModalSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    HapticFeedbackHelper.tap();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AuthModalSheet(),
    );
  }

  @override
  State<AuthModalSheet> createState() => _AuthModalSheetState();
}

class _AuthModalSheetState extends State<AuthModalSheet> {
  bool _isLoading = false;
  String? _error;

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
                  const SizedBox(height: 24),
                  if (_isLoading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
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
                  if (Theme.of(context).platform == TargetPlatform.iOS) ...[
                    _buildAuthButton(
                      svgAsset: 'assets/icons/auth/apple.svg',
                      svgColor: colors.primaryText,
                      label: appL10n.authApple,
                      onTap: () =>
                          _handleAuth(AuthService.instance.signInWithApple),
                      colors: colors,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (kIsWeb)
                    GoogleWebSignInButton(
                      enabled: !_isLoading,
                      onAccount: (account) => _handleAuth(
                        () => AuthService.instance.signInWithGoogleWebAccount(
                          account,
                        ),
                      ),
                      onError: (_) {
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
                      colors: colors,
                      isDark: isDark,
                    ),
                  const SizedBox(height: 10),

                  _buildAuthButton(
                    svgAsset: 'assets/icons/auth/yandex.svg',
                    label: appL10n.authYandex,
                    onTap: () => _handleAuth(
                      () => AuthService.instance.signInWithYandex(context),
                    ),
                    colors: colors,
                    isDark: isDark,
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
    required AppThemeColors colors,
    required bool isDark,
  }) {
    return InkWell(
      onTap: _isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: colors.searchFieldFill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              svgAsset,
              width: 22,
              height: 22,
              colorFilter: svgColor != null
                  ? ColorFilter.mode(svgColor, BlendMode.srcIn)
                  : null,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
