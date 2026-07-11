import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static final Uri _supportFundUri = Uri.parse(
    'https://yoomoney.ru/fundraise/1GVT0U3CBGR.260406',
  );

  static final Uri _telegramSupportUri = Uri.parse(
    'https://t.me/sergei_degtyarik',
  );

  Future<void> _openSupportFund() async {
    HapticFeedbackHelper.tap();
    final ok = await launchUrl(
      _supportFundUri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }

  Future<void> _openTelegramSupport() async {
    HapticFeedbackHelper.tap();
    final ok = await launchUrl(
      _telegramSupportUri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть Telegram')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final settingsController = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
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
                _buildSettingItem(
                  icon: Icons.volunteer_activism_rounded,
                  title: 'Поддержать разработчика',
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.secondaryText,
                  ),
                  onTap: _openSupportFund,
                ),
                _buildDivider(),
                _buildSettingItem(
                  icon: Icons.support_agent_outlined,
                  title: 'Тех. поддержка',
                  subtitle: 'Telegram: @sergei_degtyarik',
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.secondaryText,
                  ),
                  onTap: _openTelegramSupport,
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingXL),
            _buildSectionTitle('Подготовка'),
            _buildSectionCard(
              children: [
                _buildSettingItem(
                  icon: Icons.check_circle_outline,
                  title: 'Подтверждать ответ',
                  subtitle:
                      'Ответ сначала выбирается, а затем подтверждается кнопкой.',
                  trailing: Switch(
                    value: settings.confirmAnswerEnabled,
                    onChanged: (value) {
                      HapticFeedbackHelper.select();
                      settingsController.setConfirmAnswerEnabled(value);
                    },
                  ),
                ),
                _buildDivider(),
                _buildSettingItem(
                  icon: Icons.vibration_rounded,
                  title: 'Тактильный отклик',
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
                  icon: Icons.record_voice_over_outlined,
                  title: 'Озвучка вопросов',
                  trailing: Switch(
                    value: settings.voiceEnabled,
                    onChanged: (value) {
                      HapticFeedbackHelper.select();
                      settingsController.setVoiceEnabled(value);
                    },
                  ),
                ),
                if (CountryConfig.current.hasCdCategory) ...[
                  _buildDivider(),
                  _buildSettingItem(
                    icon: Icons.badge_outlined,
                    title: 'Категория билетов',
                    subtitle:
                        'A/B – легковые и мото, C/D – грузовые и автобусы',
                    trailing: _buildTicketCategoryBadge(settings),
                    onTap: _toggleTicketCategory,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppDimensions.spacingXL),
            _buildSectionTitle('Данные'),
            _buildSectionCard(
              children: [
                _buildSettingItem(
                  icon: Icons.restart_alt_rounded,
                  title: 'Сбросить статистику',
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.secondaryText,
                  ),
                  onTap: _confirmReset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingM),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryText,
        ),
      ),
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
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
    Color iconColor = AppColors.primaryText,
    Color titleColor = AppColors.primaryText,
  }) {
    final hasSubtitle = subtitle.isNotEmpty;
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
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor),
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
                        color: titleColor,
                      ),
                    ),
                    if (hasSubtitle) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppColors.secondaryText,
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

  Widget _buildTicketCategoryBadge(AppSettings settings) {
    final isAb = settings.ticketCategory == TicketCategory.ab;
    return _buildPill(
      label: isAb ? 'A/B' : 'C/D',
      textColor: AppColors.accent,
      backgroundColor: AppColors.lightAccent,
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
    return const Divider(height: 1, thickness: 1, color: AppColors.divider);
  }

  Future<void> _confirmReset() async {
    HapticFeedbackHelper.warning();
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить статистику'),
        content: const Text(
          'Будут очищены прогресс по вопросам, результаты экзаменов и избранные вопросы.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Сбросить',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldReset != true) return;

    final dataSource = ref.read(progressDataSourceProvider);
    await dataSource.resetAllProgress();
    ref.read(appDataRefreshProvider.notifier).state++;
    ref.invalidate(statsProvider);
    ref.invalidate(favoriteQuestionsProvider);

    if (!mounted) return;

    HapticFeedbackHelper.success();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Статистика сброшена')));
  }
}
