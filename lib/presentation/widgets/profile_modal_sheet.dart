import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';

class ProfileModalSheet extends ConsumerWidget {
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
        return appL10n.profileProviderGoogle;
      case AuthProviderType.apple:
        return 'Apple ID';
      case AuthProviderType.yandex:
        return appL10n.profileProviderYandex;
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    HapticFeedbackHelper.tap();
    await AuthService.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pop();
      AppToast.show(
        context,
        appL10n.profileSignedOut,
        type: AppToastType.normal,
      );
    }
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    HapticFeedbackHelper.error();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appL10n.profileDeleteConfirmTitle),
        content: Text(appL10n.profileDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(appL10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFED4621),
            ),
            child: Text(appL10n.profileDeleteConfirmAction),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleted = await AuthService.instance.deleteAccount();
      if (context.mounted) {
        if (deleted) Navigator.of(context).pop();
        AppToast.show(
          context,
          deleted ? appL10n.accountDeleted : appL10n.accountDeleteFailed,
          type: deleted ? AppToastType.normal : AppToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentUserProvider);
    final profile = current?.id == this.profile.id ? current! : this.profile;
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

              Center(
                child: UserAvatar(
                  url: profile.avatarUrl,
                  useDefault: profile.useDefaultAvatar,
                  size: 68,
                ),
              ),
              if (profile.avatarUrl?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(appL10n.avatarOwnPhoto),
                      selected: !profile.useDefaultAvatar,
                      onSelected: (_) =>
                          AuthService.instance.setDefaultAvatar(false),
                    ),
                    ChoiceChip(
                      label: Text(appL10n.avatarCone),
                      selected: profile.useDefaultAvatar,
                      onSelected: (_) =>
                          AuthService.instance.setDefaultAvatar(true),
                    ),
                  ],
                ),
              ],
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
                  style: TextStyle(fontSize: 13.5, color: colors.secondaryText),
                ),
              ],
              const SizedBox(height: 6),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
                  appL10n.profileSignOutAction,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () => _handleSignOut(context),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFED4621),
                ),
                title: Text(
                  appL10n.profileDeleteAccountAction,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFED4621),
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () => _handleDeleteAccount(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
