import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionManagementSheet extends StatefulWidget {
  const SubscriptionManagementSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedbackHelper.tap();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SubscriptionManagementSheet(),
    );
  }

  @override
  State<SubscriptionManagementSheet> createState() => _SubscriptionManagementSheetState();
}

class _SubscriptionManagementSheetState extends State<SubscriptionManagementSheet> {
  bool _isRestoring = false;

  Future<void> _openStoreSubscriptionSettings() async {
    HapticFeedbackHelper.select();
    Uri uri;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // Apple Subscriptions management deep-link
      uri = Uri.parse('https://apps.apple.com/account/subscriptions');
    } else {
      // Google Play Subscriptions management deep-link
      uri = Uri.parse('https://play.google.com/store/account/subscriptions?package=ru.pdd.pdd_app');
    }

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        // Fallback for Google Play web
        await launchUrl(
          Uri.parse('https://play.google.com/store/account/subscriptions'),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint('Failed to open subscription url: $e');
    }
  }

  Future<void> _handleRestore() async {
    setState(() => _isRestoring = true);
    HapticFeedbackHelper.select();

    try {
      final restored = await IapService.instance.restorePurchases();
      if (mounted) {
        setState(() => _isRestoring = false);
        if (restored) {
          AppToast.show(
            context,
            'Покупки успешно восстановлены',
            type: AppToastType.success,
          );
        } else {
          AppToast.show(
            context,
            'Активных покупок не найдено',
            type: AppToastType.normal,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRestoring = false);
        AppToast.show(
          context,
          'Ошибка восстановления: $e',
          type: AppToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final expiresAt = PremiumService.instance.expiresAt;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    final dateStr = expiresAt != null
        ? DateFormat('d MMMM yyyy, HH:mm', 'ru').format(expiresAt)
        : 'Бессрочно';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const greenAccent = Color(0xFF2BC280);
    final greenSurface = isDark ? const Color(0xFF162B1D) : const Color(0xFFE8F8F0);

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewPadding.bottom + 20,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Close Button
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Icon(Icons.close_rounded, color: colors.secondaryText),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 2),

              // 2. Verified Header Badge
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: greenSurface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    size: 32,
                    color: greenAccent,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 3. Title & Expiration Info
              Text(
                'Премиум-доступ активен',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                  fontFamily: 'Onest',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Действует до $dateStr',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.secondaryText,
                  fontFamily: 'Onest',
                ),
              ),
              const SizedBox(height: 20),

              // 4. Features Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colors.divider.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    _buildFeatureItem(
                      icon: Icons.all_inclusive_rounded,
                      title: 'Безлимитная умная лента',
                      description: 'Все вопросы и категории доступны без ограничений',
                      accentColor: greenAccent,
                      surfaceColor: greenSurface,
                      colors: colors,
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureItem(
                      icon: Icons.auto_awesome_rounded,
                      title: 'ИИ-разбор каждого вопроса',
                      description: 'Мгновенное объяснение правил и дорожных ситуаций',
                      accentColor: greenAccent,
                      surfaceColor: greenSurface,
                      colors: colors,
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureItem(
                      icon: Icons.record_voice_over_rounded,
                      title: 'Профессиональная озвучка',
                      description: 'Студийный диктор для вопросов и билетов',
                      accentColor: greenAccent,
                      surfaceColor: greenSurface,
                      colors: colors,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 5. How to cancel explanation
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colors.divider.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: colors.secondaryText,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isIOS
                            ? 'Вы можете отключить автопродление или изменить подписку в любой момент в настройках учетной записи Apple ID. При отмене доступ сохранится до $dateStr.'
                            : 'Вы можете отключить автопродление или изменить способ оплаты в любой момент в Google Play. При отмене подписка останется активной до $dateStr.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: colors.secondaryText,
                          fontFamily: 'Onest',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 6. Action Button: Manage in App Store / Google Play
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _openStoreSubscriptionSettings,
                  icon: Icon(
                    isIOS ? Icons.apple_rounded : Icons.shop_rounded,
                    size: 20,
                  ),
                  label: Text(
                    isIOS ? 'Управлять в App Store' : 'Управлять в Google Play',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      fontFamily: 'Onest',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: greenAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 7. Restore & Support
              Center(
                child: TextButton(
                  onPressed: _isRestoring ? null : _handleRestore,
                  child: _isRestoring
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Восстановить покупки',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.secondaryText,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required Color accentColor,
    required Color surfaceColor,
    required AppThemeColors colors,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: accentColor, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.check_circle_rounded,
          color: colors.green,
          size: 18,
        ),
      ],
    );
  }
}
