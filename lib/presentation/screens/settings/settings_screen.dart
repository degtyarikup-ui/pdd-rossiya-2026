import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/notification_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Донат-реквизиты общие для всех стран (разработчик один).
  static final Uri _supportFundUri = Uri.parse(
    'https://yoomoney.ru/fundraise/1GVT0U3CBGR.260406',
  );
  static const String _usdtTrc20 = 'THurq4CFAr7DekWAQ6a72EBPqRLWjEdTw7';

  static final Uri _telegramSupportUri = Uri.parse(
    'https://t.me/sergei_degtyarik',
  );

  /// На iOS блок доната скрыт: внешние ссылки на оплату (ЮMoney, крипто-кошелёк)
  /// нарушают правила App Store об In-App Purchase и приводят к отказу в ревью
  /// (Guideline 3.1.1 / запрос по 2.1(b)). На Android и в вебе блок остаётся.
  static bool get _donationsHidden =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Экран выбора способа доната: ЮMoney (внешняя ссылка) или USDT (адрес+QR).
  Future<void> _openSupportOptions() async {
    HapticFeedbackHelper.tap();
    if (!mounted) return;
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
                  appL10n.supportChooseMethod,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              _SupportOptionTile(
                icon: Icons.account_balance_wallet_outlined,
                label: appL10n.supportYoomoney,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _openSupportFund();
                },
              ),
              const SizedBox(height: AppDimensions.spacingS),
              _SupportOptionTile(
                icon: Icons.currency_bitcoin_rounded,
                label: appL10n.supportUsdt,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showUsdtSheet();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showThemePicker(
    AppSettings settings,
    AppSettingsController controller,
  ) async {
    HapticFeedbackHelper.tap();
    if (!mounted) return;
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

  /// Открыть сбор на ЮMoney во внешнем браузере.
  Future<void> _openSupportFund() async {
    HapticFeedbackHelper.tap();
    final ok = await launchUrl(
      _supportFundUri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appL10n.linkOpenFailed)));
    }
  }

  /// Показать bottom sheet с USDT-адресом и QR-кодом.
  Future<void> _showUsdtSheet() async {
    HapticFeedbackHelper.tap();
    if (!mounted) return;
    final colors = AppColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.cardBackground,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => const _UsdtSheetContent(address: _usdtTrc20),
    );
  }

  Future<void> _openTelegramSupport() async {
    HapticFeedbackHelper.tap();
    final ok = await launchUrl(
      _telegramSupportUri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appL10n.linkOpenFailed)));
    }
  }

  Future<void> _openPrivacyPolicy() async {
    HapticFeedbackHelper.tap();
    final ok = await launchUrl(
      Uri.parse(CountryConfig.current.privacyUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appL10n.linkOpenFailed)));
    }
  }

  /// Открыть произвольную внешнюю ссылку (источники данных на экране «О приложении»).
  Future<void> _openExternalUrl(String url) async {
    HapticFeedbackHelper.tap();
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appL10n.linkOpenFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final settings = ref.watch(appSettingsProvider);
    final settingsController = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            16,
            AppDimensions.screenPadding,
            24,
          ),
          children: [
            _buildSectionCard(
              children: [
                if (!_donationsHidden) ...[
                  _buildSettingItem(
                    icon: Icons.volunteer_activism_rounded,
                    title: appL10n.supportDeveloper,
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colors.secondaryText,
                    ),
                    onTap: _openSupportOptions,
                  ),
                  _buildDivider(),
                ],
                _buildSettingItem(
                  icon: Icons.support_agent_outlined,
                  title: appL10n.techSupport,
                  subtitle: 'Telegram: @sergei_degtyarik',
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.secondaryText,
                  ),
                  onTap: _openTelegramSupport,
                ),
              ],
            ),
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
                  onTap: _confirmReset,
                ),
              ],
            ),
            // Секция «О приложении»: источники гос-данных + дисклеймер.
            // Требование Google Play/App Store к приложениям с государственной
            // информацией. Показывается только там, где источники заданы (RS).
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
            if (CountryConfig.current.privacyUrl.isNotEmpty) ...[
              const SizedBox(height: AppDimensions.spacingXXL),
              Center(
                child: GestureDetector(
                  onTap: _openPrivacyPolicy,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spacingM,
                      vertical: AppDimensions.spacingS,
                    ),
                    child: Text(
                      appL10n.privacyPolicy,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.secondaryText,
                        decoration: TextDecoration.underline,
                        decorationColor: colors.secondaryText.withOpacity(0.4),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            // Debug-секция: только в сборке с --dart-define=NOTIF_TEST=true.
            // В прод компилятор её вырезает (условие const false). Строки
            // намеренно захардкожены — это внутренний тест, не UI для юзера.
            if (const bool.fromEnvironment('NOTIF_TEST')) ...[
              const SizedBox(height: AppDimensions.spacingXL),
              _buildSectionTitle('Debug'),
              _buildSectionCard(
                children: [
                  _buildSettingItem(
                    icon: Icons.notifications_active_outlined,
                    title: 'Показать уведомление сейчас',
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colors.secondaryText,
                    ),
                    onTap: () async {
                      HapticFeedbackHelper.select();
                      final result =
                          await StreakNotifier.instance.debugDiagnose();
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Диагностика уведомлений'),
                          content: Text(result),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  _buildDivider(),
                  _buildSettingItem(
                    icon: Icons.timer_outlined,
                    title: 'Через 5 сек (сверни, увидишь в шторке)',
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colors.secondaryText,
                    ),
                    onTap: () {
                      HapticFeedbackHelper.select();
                      unawaited(
                        StreakNotifier.instance.showTestReminder(
                          delay: const Duration(seconds: 5),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingM),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.primaryText,
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
      child: Column(children: children),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String subtitle = '',
    required Widget trailing,
    VoidCallback? onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    final colors = AppColors.of(context);
    final hasSubtitle = subtitle.isNotEmpty;
    final effectiveIconColor = iconColor ?? colors.primaryText;
    final effectiveTitleColor = titleColor ?? colors.primaryText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spacingL),
          child: Row(
            crossAxisAlignment:
                hasSubtitle ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: effectiveIconColor),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: effectiveTitleColor,
                      ),
                    ),
                    if (hasSubtitle) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required Color textColor,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildThemeBadge(AppSettings settings) {
    final colors = AppColors.of(context);
    final String label;
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
    return _buildPill(
      label: label,
      textColor: colors.accent,
      backgroundColor: colors.accentSurface10,
    );
  }

  Widget _buildTicketCategoryBadge(AppSettings settings) {
    final colors = AppColors.of(context);
    final isAb = settings.ticketCategory == TicketCategory.ab;
    return _buildPill(
      label: isAb ? 'A/B' : 'C/D',
      textColor: colors.accent,
      backgroundColor: colors.accentSurface10,
    );
  }

  Future<void> _toggleTicketCategory() async {
    HapticFeedbackHelper.select();
    final current = ref.read(appSettingsProvider).ticketCategory;
    final next =
        current == TicketCategory.ab ? TicketCategory.cd : TicketCategory.ab;
    await ref.read(appSettingsProvider.notifier).setTicketCategory(next);
    ref.invalidate(ticketsProvider);
    ref.invalidate(topicsProvider);
    ref.invalidate(statsProvider);
    ref.invalidate(ticketProgressProvider);
    ref.invalidate(favoriteQuestionsProvider);
    ref.invalidate(wrongQuestionIdsProvider);
    ref.read(appDataRefreshProvider.notifier).state++;
  }

  Widget _buildDivider() {
    final colors = AppColors.of(context);
    return Divider(height: 1, thickness: 1, color: colors.divider);
  }

  Future<void> _confirmReset() async {
    HapticFeedbackHelper.warning();
    final colors = AppColors.of(context);
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        title: Text(
          appL10n.resetStats,
          style: TextStyle(color: colors.primaryText),
        ),
        content: Text(
          appL10n.resetStatsDetail,
          style: TextStyle(color: colors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(appL10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              appL10n.reset,
              style: TextStyle(color: colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldReset != true) return;

    final dataSource = ref.read(progressDataSourceProvider);
    await dataSource.resetAllProgress();
    // Серия обнулена — снимаем возможное запланированное напоминание.
    unawaited(StreakNotifier.instance.cancelStreakReminder());
    ref.read(appDataRefreshProvider.notifier).state++;
    ref.invalidate(statsProvider);
    ref.invalidate(favoriteQuestionsProvider);

    if (!mounted) return;

    HapticFeedbackHelper.success();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appL10n.statsReset)));
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

/// Высокая кнопка выбора способа доната (в bottom sheet).
class _SupportOptionTile extends StatelessWidget {
  const _SupportOptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingM,
            vertical: 18,
          ),
          child: Row(
            children: [
              Icon(icon, color: colors.accent),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: colors.primaryText,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: colors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }
}

/// Содержимое шита USDT: QR + адрес с копированием и всплывающим
/// подтверждением «Скопировано» прямо в шите (SnackBar тут не виден —
/// его перекрывает сам bottom sheet).
class _UsdtSheetContent extends StatefulWidget {
  const _UsdtSheetContent({required this.address});

  final String address;

  @override
  State<_UsdtSheetContent> createState() => _UsdtSheetContentState();
}

class _UsdtSheetContentState extends State<_UsdtSheetContent> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    HapticFeedbackHelper.tap();
    await Clipboard.setData(ClipboardData(text: widget.address));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
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
                appL10n.supportUsdt,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.all(AppDimensions.spacingM),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
                ),
                child: QrImageView(
                  data: widget.address,
                  version: QrVersions.auto,
                  size: 180,
                  backgroundColor: AppColors.white,
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            InkWell(
              borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
              onTap: _copy,
              child: Container(
                padding: const EdgeInsets.all(AppDimensions.spacingM),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.address,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacingS),
                    Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 18,
                      color: _copied ? colors.green : colors.accent,
                    ),
                  ],
                ),
              ),
            ),
            // Всплывающее подтверждение «Скопировано» (2 сек).
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _copied
                  ? Padding(
                      padding: const EdgeInsets.only(
                        top: AppDimensions.spacingS,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 16, color: colors.green),
                          const SizedBox(width: 6),
                          Text(
                            appL10n.copiedToClipboard,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: AppDimensions.spacingM),
            Text(
              appL10n.supportUsdtWarning,
              style: TextStyle(
                fontSize: 12,
                color: colors.secondaryText,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
