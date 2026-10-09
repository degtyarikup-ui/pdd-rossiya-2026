import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/device_region.dart';
import 'package:pdd_app/data/services/payment_mode.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/presentation/widgets/web_payment_dialog.dart';
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
  // Подключена ли оплата СБП на сервере (спрашиваем при открытии).
  bool _sbpLive = false;
  // Android: как платить — СБП или магазин. null — ещё определяем.
  PaymentMode? _androidMode;

  @override
  void initState() {
    super.initState();
    IapService.instance.addListener(_onIapChanged);
    if (!kIsWeb) IapService.instance.loadProducts();
    if (kIsWeb) {
      _loadSbpAvailability();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      _resolveAndroidMode();
    }
  }

  /// Android: СБП для российских устройств в Google Play и для всех в
  /// RuStore; остальные покупают через Play (см. payment_mode.dart).
  Future<void> _resolveAndroidMode() async {
    final store = StoreConfig.current;
    final country = store == AppStore.googlePlay
        ? await DeviceRegion.countryCode()
        : null;
    final mode = androidPaymentMode(store: store, deviceCountry: country);
    if (!mounted) return;
    setState(() => _androidMode = mode);
    if (mode == PaymentMode.sbp) _loadSbpAvailability();
  }

  void _loadSbpAvailability() {
    if (!CountryConfig.current.hasWebPayments) return;
    PremiumService.instance.webPaymentsAvailable().then((live) {
      if (mounted && live) setState(() => _sbpLive = true);
    });
  }

  /// Android платит через СБП (не через магазин).
  bool get _androidSbp =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _androidMode == PaymentMode.sbp;

  /// Способ определяется — кнопку можно нажимать (Android ждёт ответа).
  bool get _androidUnresolved =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _androidMode == null;

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
      if (!AuthService.instance.hasServerSession) {
        final signedIn = await AuthModalSheet.show(context);
        if (!mounted) return;
        if (signedIn != true) {
          setState(() => _isLoading = false);
          return;
        }
      }
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

  /// Оплата через СБП — на сайте и в Android-приложении. Нужен вход: покупка
  /// привязывается к аккаунту и работает на всех устройствах. Пока платёжка
  /// не подключена — заглушка: почта для письма о запуске оплаты.
  Future<void> _handleSbpPayment() async {
    HapticFeedbackHelper.select();
    if (!AuthService.instance.hasServerSession) {
      final signedIn = await AuthModalSheet.show(context);
      if (!mounted || signedIn != true) return;
    }
    final result = await showWebPaymentDialog(
      context: context,
      tier: _selectedTier,
      live: _sbpLive,
    );
    if (!mounted || result == null) return;
    if (result.opened) {
      // В Android страница оплаты открыта в браузере; когда человек вернётся,
      // приложение проверит заказ и покажет итог.
      if (!kIsWeb) Navigator.of(context).pop(false);
      return;
    }
    AppToast.show(
      context,
      appL10n.webPaySaved(result.email),
      type: AppToastType.success,
    );
  }

  Future<void> _handleRestore() async {
    HapticFeedbackHelper.tap();
    setState(() => _isLoading = true);
    if (!AuthService.instance.hasServerSession) {
      final signedIn = await AuthModalSheet.show(context);
      if (!mounted) return;
      if (signedIn != true) {
        setState(() => _isLoading = false);
        return;
      }
    }
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
    // Через СБП (сайт и Android) — рубли. В магазине — цена магазина
    // (валюта покупателя); пока не загрузилась — прочерк.
    if (kIsWeb || _androidSbp) {
      return tier == PremiumTier.threeMonths ? '290 ₽' : '99 ₽';
    }
    return IapService.instance.getProductPrice(tier, '—');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    // СБП: на сайте (если страна её поддерживает) и в Android-сборке, где
    // СБП выбран по стране устройства или магазину RuStore.
    final sbpPay = kIsWeb
        ? CountryConfig.current.hasWebPayments
        : _androidSbp;

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

    final store = isIOS
        ? appL10n.paywallStoreApple
        : appL10n.paywallStoreGoogle;

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
            8,
            AppDimensions.screenPadding,
            16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Icon(Icons.close_rounded, color: colors.secondaryText),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),

              // Статус: сколько бесплатных карточек осталось.
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 14, color: accentColor),
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
              const SizedBox(height: 14),

              Text(
                appL10n.paywallTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                  fontFamily: 'Onest',
                ),
              ),
              const SizedBox(height: 6),
              // Подписка не обязательна — говорим сразу (Google Play
              // Subscriptions policy: «whether a subscription is required»).
              Text(
                appL10n.paywallFreeNote,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 20),

              _buildFeature(
                Icons.all_inclusive_rounded,
                appL10n.paywallFeatureFeed,
                accentColor,
                surfaceColor,
                colors,
              ),
              _buildFeature(
                Icons.auto_awesome_rounded,
                appL10n.paywallFeatureAi,
                accentColor,
                surfaceColor,
                colors,
              ),
              _buildFeature(
                Icons.record_voice_over_rounded,
                appL10n.paywallFeatureVoice,
                accentColor,
                surfaceColor,
                colors,
              ),
              _buildFeature(
                Icons.sports_score_rounded,
                appL10n.paywallFeatureGame,
                accentColor,
                surfaceColor,
                colors,
              ),
              const SizedBox(height: 16),

              // Тарифы: цена магазина и частота списания — в самой карточке,
              // рядом с ценой, а не мелким текстом внизу.
              _buildTierCard(
                tier: PremiumTier.threeMonths,
                title: kIsWeb || _androidSbp
                    ? appL10n.webQuarter
                    : appL10n.paywallPlanQuarter,
                price: _getPrice(PremiumTier.threeMonths),
                period: kIsWeb || _androidSbp ? null : appL10n.paywallEveryQuarter,
                badge: appL10n.paywallBadgeBest,
                accentColor: accentColor,
                surfaceColor: surfaceColor,
                colors: colors,
              ),
              if (!kIsWeb || sbpPay) ...[
                const SizedBox(height: 8),
                _buildTierCard(
                  tier: PremiumTier.weekly,
                  title: kIsWeb || _androidSbp
                      ? appL10n.webWeek
                      : appL10n.paywallPlanWeek,
                  price: _getPrice(PremiumTier.weekly),
                  period: kIsWeb || _androidSbp ? null : appL10n.paywallEveryWeek,
                  accentColor: accentColor,
                  surfaceColor: surfaceColor,
                  colors: colors,
                ),
              ],
              const SizedBox(height: 16),

              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading || _androidUnresolved || (kIsWeb && !sbpPay)
                      ? null
                      : sbpPay
                      ? _handleSbpPayment
                      : _handlePurchase,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      : Text(
                          sbpPay
                              ? appL10n.webPayButton
                              : kIsWeb
                              ? appL10n.webPaymentSoon
                              : appL10n.paywallSubscribe,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                            fontFamily: 'Onest',
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),

              // Автопродление и отмена — сразу под кнопкой, читаемым цветом.
              Text(
                kIsWeb
                    ? (sbpPay ? appL10n.webPayInfo : appL10n.webPaymentInfo)
                    : (sbpPay ? appL10n.sbpPayInfoApp : appL10n.paywallRenewal(store)),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 8),

              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: _withSeparators(
                  [
                    if (sbpPay)
                      _buildLink(
                        appL10n.webPayTariffs,
                        () => _open(CountryConfig.current.tariffsUrl),
                        colors,
                      ),
                    if (CountryConfig.current.termsUrl.isNotEmpty)
                      _buildLink(
                        appL10n.paywallTerms,
                        () => _open(CountryConfig.current.termsUrl),
                        colors,
                      ),
                    if (CountryConfig.current.privacyUrl.isNotEmpty)
                      _buildLink(
                        appL10n.paywallPrivacy,
                        () => _open(CountryConfig.current.privacyUrl),
                        colors,
                      ),
                    if (!kIsWeb && !sbpPay)
                      _buildLink(
                        appL10n.paywallRestore,
                        _handleRestore,
                        colors,
                      ),
                  ],
                  Text(
                    '·',
                    style: TextStyle(color: colors.secondaryText, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  List<Widget> _withSeparators(List<Widget> items, Widget separator) => [
    for (var i = 0; i < items.length; i++) ...[if (i > 0) separator, items[i]],
  ];

  Widget _buildLink(String label, VoidCallback onTap, AppThemeColors colors) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: colors.secondaryText),
        ),
      ),
    );
  }

  Widget _buildFeature(
    IconData icon,
    String title,
    Color accentColor,
    Color surfaceColor,
    AppThemeColors colors,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accentColor, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: colors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCard({
    required PremiumTier tier,
    required String title,
    required String price,
    String? period,
    String? badge,
    required Color accentColor,
    required Color surfaceColor,
    required AppThemeColors colors,
  }) {
    final isSelected = _selectedTier == tier;

    return Semantics(
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedbackHelper.tap();
          setState(() => _selectedTier = tier);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? surfaceColor
                : colors.secondaryText.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? accentColor : Colors.transparent,
              width: 1.5,
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
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
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
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                  if (period != null)
                    Text(
                      period,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.secondaryText,
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
}
