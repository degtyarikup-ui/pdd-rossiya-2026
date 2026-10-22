import 'package:pdd_app/l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/payment_mode.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/presentation/widgets/web_payment_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class PremiumPlansSheet extends StatefulWidget {
  const PremiumPlansSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    HapticFeedbackHelper.tap();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Native drag dismissal calls Navigator.pop directly and bypasses
      // PopScope. The handle below permits dismissal only while idle.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth: 600,
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (_) => const PremiumPlansSheet(),
    );
  }

  @override
  State<PremiumPlansSheet> createState() => _PremiumPlansSheetState();
}

class _PremiumPlansSheetState extends State<PremiumPlansSheet> {
  PremiumTier _selectedTier = PremiumTier.threeMonths;
  bool _isLoading = false;
  // Подключена ли оплата СБП на сервере (спрашиваем при открытии).
  bool _sbpLive = false;
  // Android: как платить — СБП или магазин. null — ещё определяем.
  PaymentMode? _androidMode;
  // Способы, между которыми можно выбирать (российское устройство в Play).
  List<PaymentMode> _androidModes = const [];

  @override
  void initState() {
    super.initState();
    IapService.instance.addListener(_onIapChanged);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _loadStorePrices();
    }
    if (kIsWeb) {
      _loadSbpAvailability();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      _resolveAndroidMode();
    }
  }

  /// Android: СБП для российских устройств в Google Play и для всех в
  /// RuStore; остальные покупают через Play (см. payment_mode.dart).
  Future<void> _resolveAndroidMode() async {
    final modes = await currentAndroidPaymentModes();
    if (!mounted) return;
    setState(() {
      _androidModes = modes;
      _androidMode = modes.first;
    });
    if (modes.contains(PaymentMode.sbp)) _loadSbpAvailability();
    if (_androidMode == PaymentMode.storeBilling) {
      _loadStorePrices();
    }
  }

  // Пока магазин не отдал тарифы, тихо спрашиваем снова, пока экран открыт:
  // человек видит заглушку цены (или прошлую цену магазина), а не ошибку.
  static const _priceRetryDelay = Duration(seconds: 20);
  Timer? _priceRetry;

  void _loadStorePrices() {
    _priceRetry?.cancel();
    _priceRetry = null;
    IapService.instance
        .loadProducts(phase: ProductLoadPhase.paywall)
        .whenComplete(() {
          if (!mounted || IapService.instance.hasCompleteStoreProducts) return;
          final storeShown =
              !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  _androidMode == PaymentMode.storeBilling);
          if (storeShown) {
            _priceRetry = Timer(_priceRetryDelay, _loadStorePrices);
          }
        });
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
    _priceRetry?.cancel();
    IapService.instance.removeListener(_onIapChanged);
    super.dispose();
  }

  void _onIapChanged() {
    if (mounted) setState(() {});
  }

  /// Понятный текст при неудачной покупке. Сырой текст магазина не показываем:
  /// он бывает на чужом языке и ничего не говорит о том, что делать дальше.
  String _purchaseErrorText(PurchaseResult result) {
    final store = defaultTargetPlatform == TargetPlatform.iOS
        ? 'App Store'
        : 'Google Play';
    if (result == PurchaseResult.storeUnavailable) {
      return appL10n.payErrorStoreUnavailable(store);
    }
    return switch (IapService.instance.lastFailure) {
      PurchaseFailure.verificationPending =>
        appL10n.purchaseVerificationPending,
      PurchaseFailure.storeRefused => appL10n.payErrorStoreRefused(store),
      PurchaseFailure.legacyOwnerRequired =>
        appL10n.purchaseLegacyOwnerRequired,
      PurchaseFailure.other => appL10n.payErrorGeneric,
    };
  }

  Future<void> _handlePurchase() async {
    if (_isLoading) return;
    HapticFeedbackHelper.select();
    final tier = _selectedTier;
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
      final result = await IapService.instance.buyProduct(tier);
      if (mounted) {
        setState(() => _isLoading = false);
        if (result == PurchaseResult.success) {
          HapticFeedbackHelper.success();
          Navigator.of(context).pop(true);
          AppToast.show(
            context,
            appL10n.paySuccessActivated,
            type: AppToastType.success,
          );
        } else if (result == PurchaseResult.canceled) {
          // Пользователь закрыл окно оплаты Apple/Google — ошибку не показываем
        } else if (result == PurchaseResult.productNotFound) {
          // Тарифы уже запрошены заново (с повторами): «подождите» не поможет.
          AppToast.show(
            context,
            _purchaseErrorText(PurchaseResult.storeUnavailable),
            type: AppToastType.error,
          );
        } else {
          AppToast.show(
            context,
            _purchaseErrorText(result),
            type: AppToastType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(
          context,
          appL10n.payErrorUnexpected,
          type: AppToastType.error,
        );
      }
    }
  }

  /// Оплата через СБП — на сайте и в Android-приложении. Нужен вход: покупка
  /// привязывается к аккаунту и работает на всех устройствах. Пока платёжка
  /// не подключена — заглушка: почта для письма о запуске оплаты.
  Future<void> _handleSbpPayment() async {
    if (_isLoading || (!kIsWeb && !_androidSbp)) return;
    HapticFeedbackHelper.select();
    final tier = _selectedTier;
    setState(() => _isLoading = true);
    try {
      if (!AuthService.instance.hasServerSession) {
        final signedIn = await AuthModalSheet.show(context);
        if (!mounted || signedIn != true) return;
      }
      // The test sign-in has no server session: payment needs a real account.
      if (!AuthService.instance.hasServerSession) {
        AppToast.show(
          context,
          appL10n.webPayNeedsAccount,
          type: AppToastType.error,
        );
        return;
      }
      final result = await showWebPaymentDialog(
        context: context,
        tier: tier,
        live: _sbpLive,
      );
      if (!mounted || result == null) return;
      if (result.opened) {
        // Android checks the pending order when returning from the browser.
        if (!kIsWeb) Navigator.of(context).pop(false);
        return;
      }
      AppToast.show(
        context,
        appL10n.webPaySaved(result.email),
        type: AppToastType.success,
      );
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          appL10n.payErrorUnexpected,
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRestore() async {
    if (_isLoading) return;
    HapticFeedbackHelper.tap();
    setState(() => _isLoading = true);
    try {
      if (!AuthService.instance.hasServerSession) {
        final signedIn = await AuthModalSheet.show(context);
        if (!mounted || signedIn != true) return;
      }
      final restored = await IapService.instance.restorePurchases();
      if (!mounted) return;
      if (restored) {
        HapticFeedbackHelper.success();
        Navigator.of(context).pop(true);
        AppToast.show(
          context,
          appL10n.payRestoreSuccess,
          type: AppToastType.success,
        );
      } else {
        AppToast.show(
          context,
          IapService.instance.lastFailure == PurchaseFailure.legacyOwnerRequired
              ? appL10n.purchaseLegacyOwnerRequired
              : appL10n.payRestoreNone,
          type: AppToastType.normal,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          appL10n.payErrorUnexpected,
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _getPrice(PremiumTier tier) {
    // Через СБП (сайт и Android) — рубли. В магазине — цена магазина
    // (валюта покупателя); пока её нет — заглушка на месте цены (null).
    if (kIsWeb || _androidSbp) {
      return tier == PremiumTier.threeMonths ? '290 ₽' : '99 ₽';
    }
    return IapService.instance.storePrice(tier);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final sbpPay = kIsWeb ? CountryConfig.current.hasWebPayments : _androidSbp;
    final store = isIOS
        ? appL10n.paywallStoreApple
        : appL10n.paywallStoreGoogle;
    final detailColor = colors.primaryText.withValues(alpha: 0.7);
    final buttonLabel = _androidMode == PaymentMode.unavailable
        ? appL10n.paymentRegionUnavailable
        : sbpPay
        ? appL10n.webPayButton
        : kIsWeb
        ? appL10n.webPaymentSoon
        : appL10n.paywallSubscribe;

    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    final title = Semantics(
      header: true,
      child: Text(
        appL10n.premiumPlansTitle,
        style: TextStyle(
          fontFamily: 'Onest',
          fontSize: largeText ? 22 : 26,
          height: 1.15,
          fontWeight: FontWeight.w700,
          color: colors.primaryText,
        ),
      ),
    );
    final closeButton = IconButton(
      key: const ValueKey('premium-plans-close'),
      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      onPressed: _isLoading ? null : () => Navigator.of(context).maybePop(),
      color: colors.primaryText,
      icon: const Icon(Icons.close_rounded),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );

    return PopScope<bool>(
      canPop: !_isLoading,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Material(
          color: colors.cardBackground,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppDimensions.radiusExtraLarge),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                4,
                AppDimensions.screenPadding,
                AppDimensions.spacingXXL,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: _isLoading
                        ? null
                        : (details) {
                            if ((details.primaryVelocity ?? 0) > 250) {
                              Navigator.of(context).maybePop();
                            }
                          },
                    child: SizedBox(
                      height: 28,
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.primaryText.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (largeText) ...[
                    Align(alignment: Alignment.centerRight, child: closeButton),
                    title,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: title,
                          ),
                        ),
                        const SizedBox(width: AppDimensions.spacingS),
                        closeButton,
                      ],
                    ),
                  const SizedBox(height: AppDimensions.spacingS),
                  Text(
                    appL10n.paywallFreeNote,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: detailColor,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingXXL),
                  if (_androidModes.length > 1) ...[
                    _buildMethodSelector(colors),
                    const SizedBox(height: AppDimensions.spacingL),
                  ],
                  _buildTierCard(
                    tier: PremiumTier.threeMonths,
                    title: kIsWeb || _androidSbp
                        ? appL10n.webQuarter
                        : appL10n.paywallPlanQuarter,
                    price: _getPrice(PremiumTier.threeMonths),
                    period: kIsWeb || _androidSbp
                        ? null
                        : appL10n.paywallEveryQuarter,
                    badge: appL10n.paywallBadgeBest,
                    colors: colors,
                  ),
                  if (!kIsWeb || sbpPay) ...[
                    const SizedBox(height: AppDimensions.spacingM),
                    _buildTierCard(
                      tier: PremiumTier.weekly,
                      title: kIsWeb || _androidSbp
                          ? appL10n.webWeek
                          : appL10n.paywallPlanWeek,
                      price: _getPrice(PremiumTier.weekly),
                      period: kIsWeb || _androidSbp
                          ? null
                          : appL10n.paywallEveryWeek,
                      colors: colors,
                    ),
                  ],
                  const SizedBox(height: AppDimensions.spacingXXL),
                  ElevatedButton(
                    key: const ValueKey('premium-plans-purchase'),
                    onPressed:
                        _isLoading ||
                            _androidUnresolved ||
                            _androidMode == PaymentMode.unavailable ||
                            (kIsWeb && !sbpPay)
                        ? null
                        : sbpPay
                        ? _handleSbpPayment
                        : _handlePurchase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.spacingL,
                        vertical: AppDimensions.spacingL,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDimensions.buttonRadius,
                        ),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : Text(
                            buttonLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                  ),
                  const SizedBox(height: AppDimensions.spacingL),
                  // Renewal or a one-off payment is visible alongside the CTA.
                  Text(
                    kIsWeb
                        ? (sbpPay ? appL10n.webPayInfo : appL10n.webPaymentInfo)
                        : (sbpPay
                              ? appL10n.sbpPayInfoApp
                              : appL10n.paywallRenewal(store)),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: detailColor,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingS),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppDimensions.spacingXS,
                    children: [
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  Widget _buildLink(String label, VoidCallback onTap, AppThemeColors colors) {
    return TextButton(
      onPressed: _isLoading ? null : onTap,
      style: TextButton.styleFrom(
        foregroundColor: colors.primaryText.withValues(alpha: 0.7),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        textStyle: const TextStyle(fontFamily: 'Onest', fontSize: 13),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }

  /// Russian Google Play builds offer SBP and Play; the resolver owns eligibility.
  Widget _buildMethodSelector(AppThemeColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.gray,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final mode in _androidModes)
              Expanded(
                child: Semantics(
                  selected: _androidMode == mode,
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            HapticFeedbackHelper.tap();
                            setState(() => _androidMode = mode);
                            if (mode == PaymentMode.storeBilling) {
                              _loadStorePrices();
                            }
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: _androidMode == mode
                          ? colors.accent
                          : colors.primaryText.withValues(alpha: 0.7),
                      backgroundColor: _androidMode == mode
                          ? colors.cardBackground
                          : Colors.transparent,
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDimensions.buttonRadius,
                        ),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(
                      mode == PaymentMode.sbp
                          ? appL10n.paywallMethodSbp
                          : appL10n.paywallStoreGoogle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierCard({
    required PremiumTier tier,
    required String title,
    required String? price,
    String? period,
    String? badge,
    required AppThemeColors colors,
  }) {
    final selected = _selectedTier == tier;
    final priceStyle = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: colors.primaryText,
    );

    Widget details() => Wrap(
      spacing: AppDimensions.spacingS,
      runSpacing: AppDimensions.spacingS,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.premiumLime,
              borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                fontSize: 11,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
          ),
      ],
    );

    Widget priceLabel({required bool stacked}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: stacked
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          layoutBuilder: (current, previous) => Stack(
            alignment: stacked ? Alignment.centerLeft : Alignment.centerRight,
            children: [...previous, ?current],
          ),
          child: price == null
              ? ExcludeSemantics(
                  child: DecoratedBox(
                    key: const ValueKey('price-placeholder'),
                    decoration: BoxDecoration(
                      color: colors.primaryText.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '000,00 ₽',
                      style: priceStyle.copyWith(color: Colors.transparent),
                    ),
                  ),
                )
              : Text(
                  price,
                  key: ValueKey(price),
                  style: priceStyle,
                  textAlign: stacked ? TextAlign.start : TextAlign.end,
                ),
        ),
        if (period != null) ...[
          const SizedBox(height: 3),
          Text(
            period,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: colors.primaryText.withValues(alpha: 0.65),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      selected: selected,
      child: AnimatedContainer(
        key: ValueKey('premium-plan-${tier.name}'),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? colors.lightAccent : colors.cardBackground,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          border: Border.all(
            color: selected ? colors.accent : colors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            onTap: _isLoading
                ? null
                : () {
                    HapticFeedbackHelper.tap();
                    setState(() => _selectedTier = tier);
                  },
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.spacingL),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(16) > 20;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: selected ? colors.accent : colors.secondaryText,
                        size: 22,
                      ),
                      const SizedBox(width: AppDimensions.spacingM),
                      Expanded(
                        child: stacked
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  details(),
                                  const SizedBox(
                                    height: AppDimensions.spacingS,
                                  ),
                                  priceLabel(stacked: true),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: details()),
                                  const SizedBox(width: AppDimensions.spacingM),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: constraints.maxWidth * 0.45,
                                    ),
                                    child: priceLabel(stacked: false),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
