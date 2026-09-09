import 'package:flutter/material.dart';
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

  Future<void> _handleAuth(Future<bool> Function() action) async {
    HapticFeedbackHelper.select();
    setState(() => _isLoading = true);

    try {
      final success = await action();
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          HapticFeedbackHelper.success();
          Navigator.of(context).pop(true);
          AppToast.show(
            context,
            'Вход выполнен успешно',
            type: AppToastType.success,
          );
        } else {
          AppToast.show(
            context,
            'Вход отменен или возникла ошибка',
            type: AppToastType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(
          context,
          'Ошибка авторизации: $e',
          type: AppToastType.error,
        );
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            12,
            AppDimensions.screenPadding,
            24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Close Button
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Icon(Icons.close_rounded, color: colors.secondaryText),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(height: 4),

              Text(
                'Вход в аккаунт',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Сохраните премиум-доступ и статистику при смене или переустановке устройства',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.35,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 24),

              // OAuth Buttons
              if (Theme.of(context).platform == TargetPlatform.iOS) ...[
                _buildAuthButton(
                  svgAsset: 'assets/icons/auth/apple.svg',
                  svgColor: colors.primaryText,
                  label: 'Продолжить с Apple ID',
                  onTap: () => _handleAuth(AuthService.instance.signInWithApple),
                  colors: colors,
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
              ],

              _buildAuthButton(
                svgAsset: 'assets/icons/auth/google.svg',
                label: 'Продолжить с Google',
                onTap: () => _handleAuth(AuthService.instance.signInWithGoogle),
                colors: colors,
                isDark: isDark,
              ),
              const SizedBox(height: 10),

              _buildAuthButton(
                svgAsset: 'assets/icons/auth/yandex.svg',
                label: 'Продолжить с Яндекс ID',
                onTap: () => _handleAuth(() => AuthService.instance.signInWithYandex(context)),
                colors: colors,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
            ],
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
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
