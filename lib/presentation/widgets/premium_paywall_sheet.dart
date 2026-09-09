import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

class PremiumPaywallSheet extends StatefulWidget {
  const PremiumPaywallSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    HapticFeedbackHelper.tap();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PremiumPaywallSheet(),
    );
  }

  @override
  State<PremiumPaywallSheet> createState() => _PremiumPaywallSheetState();
}

class _PremiumPaywallSheetState extends State<PremiumPaywallSheet> {
  PremiumTier _selectedTier = PremiumTier.threeMonths;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    IapService.instance.addListener(_onIapChanged);
    IapService.instance.loadProducts();
  }

  @override
  void dispose() {
    IapService.instance.removeListener(_onIapChanged);
    super.dispose();
  }

  void _onIapChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handlePurchase() async {
    HapticFeedbackHelper.select();
    setState(() => _isLoading = true);

    try {
      final result = await IapService.instance.buyProduct(_selectedTier);
      if (mounted) {
        setState(() => _isLoading = false);
        if (result == PurchaseResult.success) {
          HapticFeedbackHelper.success();
          Navigator.of(context).pop(true);
          AppToast.show(
            context,
            'Премиум-доступ успешно активирован',
            type: AppToastType.success,
          );
        } else if (result == PurchaseResult.canceled) {
          // Пользователь закрыл окно оплаты Apple/Google — ошибку не показываем
        } else if (result == PurchaseResult.productNotFound) {
          AppToast.show(
            context,
            'Товары магазина загружаются... Попробуйте через секунду.',
            type: AppToastType.normal,
          );
        } else {
          final errorMsg = IapService.instance.lastErrorMessage;
          AppToast.show(
            context,
            errorMsg.isNotEmpty ? errorMsg : 'Не удалось завершить покупку',
            type: AppToastType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(
          context,
          'Ошибка при оформлении: $e',
          type: AppToastType.error,
        );
      }
    }
  }

  Future<void> _handleRestore() async {
    HapticFeedbackHelper.tap();
    setState(() => _isLoading = true);
    final restored = await IapService.instance.restorePurchases();
    if (mounted) {
      setState(() => _isLoading = false);
      if (restored) {
        HapticFeedbackHelper.success();
        Navigator.of(context).pop(true);
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
  }

  String _getPrice(PremiumTier tier) {
    return IapService.instance.getProductPrice(
      tier,
      tier == PremiumTier.threeMonths ? '290 ₽' : '99 ₽',
    );
  }

  String? _getOldPrice(PremiumTier tier) {
    if (tier != PremiumTier.threeMonths) return null;
    final price = _getPrice(tier);
    if (price.contains(r'$')) {
      return r'5,90 $';
    } else if (price.contains('€')) {
      return '5,50 €';
    }
    return '490 ₽';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAuth = AuthService.instance.isAuthenticated;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    final isPremium = PremiumService.instance.isPremium;
    final remaining = PremiumService.instance.remainingFreeCards;
    final limit = PremiumService.instance.dailyFreeLimit;

    final Color accentColor;
    final Color surfaceColor;
    final String badgeText;
    final IconData badgeIcon;

    if (isPremium) {
      accentColor = const Color(0xFF2BC280);
      surfaceColor = isDark ? const Color(0xFF162B1D) : const Color(0xFFE8F8F0);
      badgeText = 'Премиум активен';
      badgeIcon = Icons.verified_rounded;
    } else if (remaining > 0) {
      accentColor = const Color(0xFFFFA53C);
      surfaceColor = isDark ? const Color(0xFF2E2215) : const Color(0xFFFFF7ED);
      badgeText = 'Осталось $remaining из $limit карточек';
      badgeIcon = Icons.auto_awesome_rounded;
    } else {
      accentColor = const Color(0xFFED4621);
      surfaceColor = isDark ? const Color(0xFF341717) : const Color(0xFFFFECE8);
      badgeText = 'Бесплатные карточки закончились';
      badgeIcon = Icons.hourglass_empty_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
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
              // 1. Close Button
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Icon(Icons.close_rounded, color: colors.secondaryText),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(height: 2),

              // 2. Clean Accent Header Badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        badgeIcon,
                        size: 14,
                        color: accentColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                          fontFamily: 'Onest',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 3. Clean Header Title
              Text(
                'Умная лента и студийная\nозвучка',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                  fontFamily: 'Onest',
                ),
              ),
              const SizedBox(height: 20),

              // 4. Feature Rows
              _buildFeatureItem(
                icon: Icons.all_inclusive_rounded,
                title: 'Безлимитная лента',
                description: 'Тренируйтесь без ограничений в любое время',
                accentColor: accentColor,
                surfaceColor: surfaceColor,
                colors: colors,
              ),
              const SizedBox(height: 12),
              _buildFeatureItem(
                icon: Icons.auto_awesome_rounded,
                title: 'Разбор от ИИ в 1 клик',
                description: 'Объяснение дорожных ситуаций и ПДД',
                accentColor: accentColor,
                surfaceColor: surfaceColor,
                colors: colors,
              ),
              const SizedBox(height: 12),
              _buildFeatureItem(
                icon: Icons.record_voice_over_rounded,
                title: 'Студийная озвучка',
                description: 'Красивый профессиональный голос для всех вопросов и билетов',
                accentColor: accentColor,
                surfaceColor: surfaceColor,
                colors: colors,
              ),
              const SizedBox(height: 20),

              // 5. Pricing Tiers
              _buildTierCard(
                tier: PremiumTier.threeMonths,
                title: '3 месяца',
                price: _getPrice(PremiumTier.threeMonths),
                oldPrice: _getOldPrice(PremiumTier.threeMonths),
                badge: 'ХИТ',
                accentColor: accentColor,
                surfaceColor: surfaceColor,
                colors: colors,
              ),
              const SizedBox(height: 8),
              _buildTierCard(
                tier: PremiumTier.weekly,
                title: '1 неделя',
                price: _getPrice(PremiumTier.weekly),
                accentColor: accentColor,
                surfaceColor: surfaceColor,
                colors: colors,
              ),
              const SizedBox(height: 20),

              // 6. Action Button (исправлено обрезание текста)
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handlePurchase,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Center(
                          child: Text(
                            'Оформить доступ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                              fontFamily: 'Onest',
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // 7. Store Compliance Disclaimer
              Text(
                isIOS
                    ? 'Подписка продлевается автоматически, пока не будет отключена в настройках Apple ID не позднее 24 часов до окончания периода.'
                    : 'Подписка продлевается автоматически, пока не будет отменена в Google Play в разделе «Платежи и подписки».',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: colors.secondaryText.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 14),

              // 8. Legal Links & Restore
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (!isAuth) ...[
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop(false);
                        AuthModalSheet.show(context);
                      },
                      child: Text(
                        'Войти в профиль',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: accentColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text('•', style: TextStyle(color: colors.secondaryText, fontSize: 10)),
                  ],
                  if (CountryConfig.current.termsUrl.isNotEmpty) ...[
                    GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse(CountryConfig.current.termsUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(
                        'Условия использования',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.secondaryText,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text('•', style: TextStyle(color: colors.secondaryText, fontSize: 10)),
                  ],
                  if (CountryConfig.current.privacyUrl.isNotEmpty) ...[
                    GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse(CountryConfig.current.privacyUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(
                        'Конфиденциальность',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.secondaryText,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text('•', style: TextStyle(color: colors.secondaryText, fontSize: 10)),
                  ],
                  GestureDetector(
                    onTap: _handleRestore,
                    child: Text(
                      'Восстановить',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.secondaryText,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: accentColor, size: 18),
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
              const SizedBox(height: 1),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTierCard({
    required PremiumTier tier,
    required String title,
    required String price,
    String? oldPrice,
    String? badge,
    required Color accentColor,
    required Color surfaceColor,
    required AppThemeColors colors,
  }) {
    final isSelected = _selectedTier == tier;

    return GestureDetector(
      onTap: () {
        HapticFeedbackHelper.tap();
        setState(() => _selectedTier = tier);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: isSelected
              ? surfaceColor
              : colors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accentColor : colors.divider.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? accentColor : colors.secondaryText,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (oldPrice != null) ...[
              Text(
                oldPrice,
                style: TextStyle(
                  fontSize: 13.5,
                  decoration: TextDecoration.lineThrough,
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              price,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isSelected ? accentColor : colors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
