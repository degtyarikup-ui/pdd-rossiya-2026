import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/auth_repository.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/screens/auth/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  static bool _detailsMentionInvalidJwt(Object? details) {
    final s = details?.toString().toLowerCase() ?? '';
    return s.contains('invalid jwt') || s.contains('invalid_token');
  }

  /// Укоротить ответ Edge Function, чтобы в SnackBar не утекали простыни JSON/стека.
  static String _sanitizeEdgeFunctionMessage(String raw) {
    var t = raw.trim();
    final nl = t.indexOf('\n');
    if (nl != -1) {
      t = t.substring(0, nl).trim();
    }
    if (t.length > 200) {
      return '${t.substring(0, 197)}…';
    }
    return t;
  }

  /// Почта для подзаголовка «Выйти из аккаунта».
  String _accountEmailForSubtitle(User? user) {
    final direct = user?.email?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final meta = user?.userMetadata;
    if (meta == null) return '';
    final fromMeta = meta['email'] as String?;
    final t = fromMeta?.trim();
    return (t != null && t.isNotEmpty) ? t : '';
  }

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
    final isGuestMode = ref.watch(guestModeProvider);
    final currentUser = ref.watch(currentUserProvider);
    final isAuthorized = !isGuestMode && currentUser != null;
    final signOutEmailSubtitle = _accountEmailForSubtitle(currentUser);

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
            ),
            const SizedBox(height: AppDimensions.spacingXL),
            _buildSectionTitle(isAuthorized ? 'Данные' : 'Аккаунт'),
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
                _buildDivider(),
                if (isAuthorized) ...[
                  _buildSettingItem(
                    icon: Icons.logout_rounded,
                    title: 'Выйти из аккаунта',
                    subtitle: signOutEmailSubtitle,
                    titleColor: AppColors.red,
                    iconColor: AppColors.red,
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.secondaryText,
                    ),
                    onTap: _confirmSignOut,
                  ),
                  _buildDivider(),
                  _buildSettingItem(
                    icon: Icons.delete_forever_outlined,
                    title: 'Удалить аккаунт',
                    titleColor: AppColors.red,
                    iconColor: AppColors.red,
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.secondaryText,
                    ),
                    onTap: _confirmDeleteAccount,
                  ),
                ] else
                  _buildSettingItem(
                    icon: Icons.login_rounded,
                    title: 'Войти или зарегистрироваться',
                    titleColor: AppColors.accent,
                    iconColor: AppColors.accent,
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.secondaryText,
                    ),
                    onTap: _openAuthScreen,
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

  Future<void> _confirmSignOut() async {
    HapticFeedbackHelper.warning();
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из аккаунта'),
        content: const Text('Вы уверены, что хотите завершить текущую сессию?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (shouldSignOut != true) return;

    await ref.read(supabaseClientProvider).auth.signOut();
    ref.read(authLoadingProvider.notifier).state = false;
    final progress = ref.read(progressDataSourceProvider);
    await progress.clearAllProgressForAccountSwitch();
    await progress.setStoredProgressOwnerId(null);
    ref.read(appDataRefreshProvider.notifier).state++;
    ref.invalidate(statsProvider);
    ref.invalidate(ticketProgressProvider);
    ref.invalidate(favoriteQuestionsProvider);
    ref.invalidate(wrongQuestionIdsProvider);
  }

  /// Удаление учётной записи через Edge Function `delete-account` (admin API на сервере).
  Future<void> _confirmDeleteAccount() async {
    HapticFeedbackHelper.warning();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аккаунт'),
        content: const Text(
          'Аккаунт и связанные данные в сервисе авторизации будут удалены без возможности восстановления. Продолжить?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    if (!ref.read(supabaseAvailableProvider)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сервис авторизации недоступен')),
      );
      return;
    }

    final client = ref.read(supabaseClientProvider);
    if (client.auth.currentSession == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сессия недействительна. Войдите снова.')),
      );
      return;
    }

    try {
      // Не передаём Authorization вручную: AuthHttpClient подставит access token
      // (и при необходимости обновит сессию). Ручной заголовок блокирует это и
      // часто приводит к «Invalid JWT» на Edge Functions при свежем входе.
      await client.functions.invoke(
        'delete-account',
        method: HttpMethod.post,
        body: const <String, dynamic>{},
      );

      await client.auth.signOut();
      ref.read(authLoadingProvider.notifier).state = false;
      final progress = ref.read(progressDataSourceProvider);
      await progress.clearAllProgressForAccountSwitch();
      await progress.setStoredProgressOwnerId(null);
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(statsProvider);
      ref.invalidate(ticketProgressProvider);
      ref.invalidate(favoriteQuestionsProvider);
      ref.invalidate(wrongQuestionIdsProvider);
      if (!mounted) return;
      HapticFeedbackHelper.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аккаунт удалён')),
      );
    } on FunctionException catch (e) {
      var message = 'Не удалось удалить аккаунт';
      if (e.status == 404) {
        message =
            'Функция delete-account не развёрнута. Выполните: supabase functions deploy delete-account';
      } else if (e.status == 401 ||
          _detailsMentionInvalidJwt(e.details)) {
        message =
            'Сессия устарела или недействительна. Выйдите из аккаунта, войдите снова и повторите удаление.';
      } else if (e.details is Map) {
        final map = e.details as Map;
        final m = map['msg'] ?? map['message'] ?? map['error'];
        if (m != null && m.toString().isNotEmpty) {
          message = _sanitizeEdgeFunctionMessage(m.toString());
        }
      } else if (e.details is String && (e.details as String).isNotEmpty) {
        message = _sanitizeEdgeFunctionMessage(e.details as String);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('Delete account unexpected error: $e');
      }
      final raw = e.toString();
      final text = raw.toLowerCase().contains('invalid jwt')
          ? 'Сессия устарела или недействительна. Выйдите из аккаунта, войдите снова и повторите удаление.'
          : 'Не удалось удалить аккаунт. Попробуйте позже.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    }
  }

  void _openAuthScreen() {
    HapticFeedbackHelper.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (loginContext) =>
            LoginScreen(onClose: () => Navigator.of(loginContext).pop()),
      ),
    );
  }
}
