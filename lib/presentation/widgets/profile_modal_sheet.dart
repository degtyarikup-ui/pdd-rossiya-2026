import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';

class ProfileModalSheet extends StatelessWidget {
  final UserProfile profile;

  const ProfileModalSheet({super.key, required this.profile});

  static Future<void> show(BuildContext context, UserProfile profile) {
    HapticFeedbackHelper.tap();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProfileModalSheet(profile: profile),
    );
  }

  String _getProviderName(AuthProviderType type) {
    switch (type) {
      case AuthProviderType.google:
        return 'Google Аккаунт';
      case AuthProviderType.apple:
        return 'Apple ID';
      case AuthProviderType.yandex:
        return 'Яндекс ID';
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    HapticFeedbackHelper.tap();
    await AuthService.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pop();
      AppToast.show(
        context,
        'Вы вышли из аккаунта',
        type: AppToastType.normal,
      );
    }
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    HapticFeedbackHelper.error();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Это действие навсегда удалит ваш профиль и привязку премиум-доступа к аккаунту.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFED4621)),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.instance.deleteAccount();
      if (context.mounted) {
        Navigator.of(context).pop();
        AppToast.show(
          context,
          'Аккаунт успешно удален',
          type: AppToastType.normal,
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
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 4),

              // Avatar Circle
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: colors.lightAccent,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty
                        ? Image.network(
                            profile.avatarUrl!,
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Center(
                              child: Text(
                                profile.name.isNotEmpty
                                    ? profile.name[0].toUpperCase()
                                    : 'U',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: colors.accent,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              profile.name.isNotEmpty
                                  ? profile.name[0].toUpperCase()
                                  : 'U',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: colors.accent,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                profile.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              if (profile.email.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  profile.email,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: colors.secondaryText,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.searchFieldFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getProviderName(profile.provider),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Actions
              ListTile(
                leading: Icon(Icons.logout_rounded, color: colors.primaryText),
                title: Text(
                  'Выйти из аккаунта',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () => _handleSignOut(context),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFED4621)),
                title: const Text(
                  'Удалить аккаунт и данные',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFED4621),
                  ),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () => _handleDeleteAccount(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
