import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/notification_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/presentation/widgets/premium_banner_card.dart';
import 'package:pdd_app/presentation/widgets/profile_modal_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static final Uri _telegramSupportUri = Uri.parse(
    'https://t.me/sergei_degtyarik',
  );

  Future<void> _showThemePicker(
    AppSettings settings,
    AppSettingsController controller,
  ) async {
    HapticFeedbackHelper.tap();
    final colors = AppColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.cardBackground,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            0,
            AppDimensions.screenPadding,
            AppDimensions.spacingL,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimensions.spacingM,
                ),
                child: Text(
                  appL10n.themeChoose,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              _ThemeOptionTile(
                icon: Icons.brightness_auto_rounded,
                label: appL10n.themeSystem,
                selected: settings.themeMode == ThemeMode.system,
                onTap: () {
                  HapticFeedbackHelper.select();
                  controller.setThemeMode(ThemeMode.system);
                  Navigator.pop(sheetCtx);
                },
              ),
              const SizedBox(height: AppDimensions.spacingS),
              _ThemeOptionTile(
                icon: Icons.light_mode_outlined,
                label: appL10n.themeLight,
                selected: settings.themeMode == ThemeMode.light,
                onTap: () {
                  HapticFeedbackHelper.select();
                  controller.setThemeMode(ThemeMode.light);
                  Navigator.pop(sheetCtx);
                },
              ),
              const SizedBox(height: AppDimensions.spacingS),
              _ThemeOptionTile(
                icon: Icons.dark_mode_outlined,
                label: appL10n.themeDark,
                selected: settings.themeMode == ThemeMode.dark,
                onTap: () {
                  HapticFeedbackHelper.select();
                  controller.setThemeMode(ThemeMode.dark);
                  Navigator.pop(sheetCtx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTelegramSupport() async {
    HapticFeedbackHelper.tap();
    final ok = await launchUrl(
      _telegramSupportUri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      AppToast.show(
        context,
        appL10n.linkOpenFailed,
        type: AppToastType.error,
      );
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final url = CountryConfig.current.privacyUrl;
    if (url.isEmpty) return;
    HapticFeedbackHelper.tap();
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      AppToast.show(
        context,
        appL10n.linkOpenFailed,
        type: AppToastType.error,
      );
    }
  }

  Future<void> _openTermsOfUse() async {
    final url = CountryConfig.current.termsUrl;
    if (url.isEmpty) return;
    HapticFeedbackHelper.tap();
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      AppToast.show(
        context,
        appL10n.linkOpenFailed,
        type: AppToastType.error,
      );
    }
  }

  Future<void> _toggleTicketCategory() async {
    HapticFeedbackHelper.select();
    final settings = ref.read(appSettingsProvider);
    final next = settings.ticketCategory == TicketCategory.ab
        ? TicketCategory.cd
        : TicketCategory.ab;
    await ref.read(appSettingsProvider.notifier).setTicketCategory(next);
  }

  Future<void> _handleResetStats() async {
    HapticFeedbackHelper.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appL10n.resetStats),
        content: Text(appL10n.resetStatsDetail),
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
            child: Text(appL10n.reset),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final dataSource = ref.read(progressDataSourceProvider);
    await dataSource.resetAllProgress();
    unawaited(StreakNotifier.instance.cancelStreakReminder());
    ref.read(appDataRefreshProvider.notifier).state++;
    ref.invalidate(statsProvider);
    ref.invalidate(favoriteQuestionsProvider);

    if (!mounted) return;

    HapticFeedbackHelper.success();
    AppToast.show(
      context,
      appL10n.statsReset,
      type: AppToastType.success,
    );
  }

  Future<void> _openExternalUrl(String url) async {
    HapticFeedbackHelper.tap();
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      AppToast.show(
        context,
        appL10n.linkOpenFailed,
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final settings = ref.watch(appSettingsProvider);
    final settingsController = ref.read(appSettingsProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double topInset = MediaQuery.paddingOf(context).top;
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarColor: colors.cardBackground,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            topInset + 16,
            AppDimensions.screenPadding,
            32,
          ),
        children: [
          if (currentUser != null) ...[
            _buildUserProfileCard(colors, currentUser),
            const SizedBox(height: AppDimensions.spacingM),
          ] else ...[
            _buildSignInCard(colors),
            const SizedBox(height: AppDimensions.spacingM),
          ],
          _buildPremiumBannerCard(colors),
          const SizedBox(height: AppDimensions.spacingXL),

          _buildSectionTitle(appL10n.preparation),
          _buildSectionCard(
            children: [
              _buildSettingItem(
                icon: Icons.palette_outlined,
                title: appL10n.themeSetting,
                trailing: _buildThemeBadge(settings),
                onTap: () => _showThemePicker(settings, settingsController),
              ),
              if (CountryConfig.current.hasCdCategory) ...[
                _buildDivider(),
                _buildSettingItem(
                  icon: Icons.badge_outlined,
                  title: appL10n.ticketCategorySetting,
                  trailing: _buildTicketCategoryBadge(settings),
                  onTap: _toggleTicketCategory,
                ),
              ],
              _buildDivider(),
              _buildSettingItem(
                icon: Icons.check_circle_outline,
                title: appL10n.confirmAnswerSetting,
                subtitle: appL10n.confirmAnswerHint,
                trailing: Switch(
                  value: settings.confirmAnswerEnabled,
                  onChanged: (value) {
                    HapticFeedbackHelper.select();
                    settingsController.setConfirmAnswerEnabled(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingXL),

          _buildSectionTitle(appL10n.feedbackSection),
          _buildSectionCard(
            children: [
              _buildSettingItem(
                icon: Icons.vibration_rounded,
                title: appL10n.hapticFeedback,
                trailing: Switch(
                  value: settings.hapticsEnabled,
                  onChanged: (value) {
                    HapticFeedbackHelper.select();
                    settingsController.setHapticsEnabled(value);
                  },
                ),
              ),
              _buildDivider(),
              _buildSettingItem(
                icon: Icons.volume_up_outlined,
                title: appL10n.soundEffects,
                trailing: Switch(
                  value: settings.soundEffectsEnabled,
                  onChanged: (value) {
                    HapticFeedbackHelper.select();
                    settingsController.setSoundEffectsEnabled(value);
                  },
                ),
              ),
              _buildDivider(),
              _buildSettingItem(
                icon: Icons.record_voice_over_outlined,
                title: appL10n.voiceOverQuestions,
                trailing: Switch(
                  value: settings.voiceEnabled,
                  onChanged: (value) {
                    HapticFeedbackHelper.select();
                    settingsController.setVoiceEnabled(value);
                  },
                ),
              ),
              _buildDivider(),
              _buildSettingItem(
                icon: Icons.notifications_none_rounded,
                title: appL10n.notificationsSetting,
                subtitle: appL10n.notificationsHint,
                trailing: Switch(
                  value: settings.notificationsEnabled,
                  onChanged: (value) {
                    HapticFeedbackHelper.select();
                    settingsController.setNotificationsEnabled(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingXL),

          _buildSectionTitle(appL10n.dataSection),
          _buildSectionCard(
            children: [
              _buildSettingItem(
                icon: Icons.restart_alt_rounded,
                title: appL10n.resetStats,
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: colors.secondaryText,
                ),
                onTap: _handleResetStats,
              ),
            ],
          ),

          if (CountryConfig.current.dataSources.isNotEmpty ||
              CountryConfig.current.notAffiliatedNote.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spacingXL),
            _buildSectionTitle(appL10n.aboutSection),
            _buildSectionCard(
              children: [
                for (final src in CountryConfig.current.dataSources) ...[
                  _buildSettingItem(
                    icon: Icons.link_rounded,
                    title: src.label,
                    subtitle: appL10n.dataSourceTitle,
                    trailing: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: colors.secondaryText,
                    ),
                    onTap: () => _openExternalUrl(src.url),
                  ),
                  _buildDivider(),
                ],
                if (CountryConfig.current.notAffiliatedNote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Text(
                      CountryConfig.current.notAffiliatedNote,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: AppDimensions.spacingXXL),
          // Clean footer links: Tech Support, Terms of Use, and Privacy Policy
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              GestureDetector(
                onTap: _openTelegramSupport,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingS,
                    vertical: AppDimensions.spacingS,
                  ),
                  child: Text(
                    appL10n.techSupport,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.secondaryText,
                      decoration: TextDecoration.underline,
                      decorationColor: colors.secondaryText.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
              if (CountryConfig.current.termsUrl.isNotEmpty) ...[
                Text('•', style: TextStyle(color: colors.secondaryText, fontSize: 11)),
                GestureDetector(
                  onTap: _openTermsOfUse,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spacingS,
                      vertical: AppDimensions.spacingS,
                    ),
                    child: Text(
                      appL10n.termsOfUse,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.secondaryText,
                        decoration: TextDecoration.underline,
                        decorationColor: colors.secondaryText.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
              if (CountryConfig.current.privacyUrl.isNotEmpty) ...[
                Text('•', style: TextStyle(color: colors.secondaryText, fontSize: 11)),
                GestureDetector(
                  onTap: _openPrivacyPolicy,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spacingS,
                      vertical: AppDimensions.spacingS,
                    ),
                    child: Text(
                      appL10n.privacyPolicy,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.secondaryText,
                        decoration: TextDecoration.underline,
                        decorationColor: colors.secondaryText.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _buildUserProfileCard(AppThemeColors colors, UserProfile profile) {
    return GestureDetector(
      onTap: () => ProfileModalSheet.show(context, profile),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.lightAccent,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty
                    ? Image.network(
                        profile.avatarUrl!,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Text(
                            profile.name.isNotEmpty
                                ? profile.name[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              fontSize: 18,
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
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                  if (profile.email.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      profile.email,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.secondaryText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInCard(AppThemeColors colors) {
    return GestureDetector(
      onTap: () => AuthModalSheet.show(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.searchFieldFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_circle_outlined,
                color: colors.secondaryText,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Войти в аккаунт',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Сохранить прогресс и премиум',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.secondaryText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumBannerCard(AppThemeColors colors) {
    return const PremiumBannerCard();
  }

  Widget _buildSectionTitle(String title) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppDimensions.spacingXS,
        bottom: AppDimensions.spacingS,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.secondaryText,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingM,
          vertical: 14,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colors.primaryText),
            const SizedBox(width: AppDimensions.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colors.primaryText,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final colors = AppColors.of(context);
    return Divider(
      height: 1,
      thickness: 1,
      indent: 52,
      color: colors.divider,
    );
  }

  Widget _buildThemeBadge(AppSettings settings) {
    final colors = AppColors.of(context);
    String label;
    switch (settings.themeMode) {
      case ThemeMode.system:
        label = appL10n.themeSystem;
        break;
      case ThemeMode.light:
        label = appL10n.themeLight;
        break;
      case ThemeMode.dark:
        label = appL10n.themeDark;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.searchFieldFill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: colors.secondaryText,
        ),
      ),
    );
  }

  Widget _buildTicketCategoryBadge(AppSettings settings) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.searchFieldFill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        settings.ticketCategory.name.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: selected ? colors.accentSurface10 : colors.background,
      borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingM,
            vertical: 16,
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? colors.accent : colors.secondaryText),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? colors.accent : colors.primaryText,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, color: colors.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
