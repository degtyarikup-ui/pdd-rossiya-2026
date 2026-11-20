import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/pending_payment.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

/// Оплата на сайте через СБП. Человек указывает почту для чека, сервер
/// записывает выбор тарифа (этого просит банк) и, если платёжка
/// подключена ([live]), создаёт платёж — страница уходит на форму оплаты.
/// Пока не подключена — заглушка: почта для письма о запуске оплаты.
///
/// Возвращает почту и признак [opened]: true — страница оплаты открыта
/// (в этой вкладке на вебе, в браузере на Android); false — выбор сохранён
/// в режиме заглушки. null — отмена или ошибка.
typedef WebPaymentResult = ({String email, bool opened, bool priceChanged});

Future<WebPaymentResult?> showWebPaymentDialog({
  required BuildContext context,
  required PremiumTier tier,
  required bool live,
  bool fromOnboarding = false,
  required int expectedPriceRub,
}) {
  return showDialog<WebPaymentResult>(
    context: context,
    builder: (_) => _WebPaymentDialog(
      tier: tier,
      live: live,
      fromOnboarding: fromOnboarding,
      expectedPriceRub: expectedPriceRub,
    ),
  );
}

class _WebPaymentDialog extends StatefulWidget {
  const _WebPaymentDialog({
    required this.tier,
    required this.live,
    required this.fromOnboarding,
    required this.expectedPriceRub,
  });

  final PremiumTier tier;
  final bool live;
  final bool fromOnboarding;
  final int expectedPriceRub;

  @override
  State<_WebPaymentDialog> createState() => _WebPaymentDialogState();
}

class _WebPaymentDialogState extends State<_WebPaymentDialog> {
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  late final TextEditingController _controller = TextEditingController(
    text: AuthService.instance.currentUser?.email ?? '',
  );
  bool _sending = false;
  bool _failed = false;
  bool _noConnection = false;
  String? _creationErrorCode;
  String? _creationOrder;
  String? _existingOrderSummary;
  Uri? _existingOrderUrl;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _controller.text.trim();
    if (!_emailPattern.hasMatch(email) ||
        _sending ||
        _creationErrorCode != null) {
      return;
    }
    setState(() {
      _sending = true;
      _failed = false;
    });
    final start = await PremiumService.instance.startWebPayment(
      tier: widget.tier,
      email: email,
      fromOnboarding: widget.fromOnboarding,
      expectedPriceRub: widget.expectedPriceRub,
    );
    if (!mounted) return;
    if (start?.errorCode == 'price_changed') {
      Navigator.of(
        context,
      ).pop((email: email, opened: false, priceChanged: true));
      return;
    }
    if (start?.errorCode == 'pending_order') {
      final details = await PremiumService.instance.checkWebPaymentDetails(
        order: start!.order,
      );
      if (!mounted) return;
      if (details != null &&
          details.order == start.order &&
          details.status == 'pending' &&
          details.tier != null &&
          details.amount != null &&
          details.url != null) {
        _existingOrderSummary = appL10n.premiumExistingOrder(
          details.tier == PremiumTier.weekly
              ? appL10n.webWeek
              : appL10n.webQuarter,
          '${details.amount} ₽',
        );
        _existingOrderUrl = Uri.tryParse(details.url!);
      }
    }
    if (start?.errorCode != null) {
      HapticFeedbackHelper.error();
      setState(() {
        _sending = false;
        _creationErrorCode = start!.errorCode;
        _creationOrder = start.order;
      });
      return;
    }
    final url = start?.url;
    if (url != null) {
      // Веб — та же вкладка, после оплаты Platega вернёт на /app/?pay=done.
      // Android — внешний браузер: заказ запоминаем, приложение проверит его
      // при возврате (см. PremiumService.checkPendingPayment).
      if (await _openPayment(Uri.parse(url), email)) return;
      if (!kIsWeb) {
        await PendingPayment.clear(
          ownerId: AuthService.instance.currentUser?.id,
        );
        if (!mounted) return;
      }
    }
    if (!mounted) return;
    if (start != null && url == null) {
      HapticFeedbackHelper.success();
      Navigator.of(
        context,
      ).pop((email: email, opened: false, priceChanged: false));
    } else {
      HapticFeedbackHelper.error();
      setState(() {
        _sending = false;
        _failed = true;
        // No payment link came back, so nothing could be paid.
        _noConnection = start == null;
      });
    }
  }

  Future<bool> _openPayment(Uri url, String email) async {
    var opened = false;
    try {
      opened = await launchUrl(
        url,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
      if (!opened) {
        ErrorReporter.report(
          ErrorCategory.purchase,
          'web_payment.open',
          code: 'page_not_opened',
          provider: 'platega',
        );
      }
    } catch (error) {
      ErrorReporter.report(
        ErrorCategory.purchase,
        'web_payment.open',
        error: error,
        provider: 'platega',
      );
    }
    if (!mounted) return true;
    if (opened) {
      Navigator.of(
        context,
      ).pop((email: email, opened: true, priceChanged: false));
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AlertDialog(
      backgroundColor: colors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      title: Text(
        appL10n.webPayEmailTitle,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colors.primaryText,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.live ? appL10n.webPayLiveBody : appL10n.webPayEmailBody,
            style: TextStyle(
              fontSize: 14,
              color: colors.secondaryText,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingS),
          Text(
            '${widget.tier == PremiumTier.weekly ? appL10n.webWeek : appL10n.webQuarter} · ${widget.expectedPriceRub} ₽',
          ),
          const SizedBox(height: AppDimensions.spacingL),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final text = value.text.trim();
              final invalid = text.isNotEmpty && !_emailPattern.hasMatch(text);
              return TextField(
                controller: _controller,
                autofocus: _controller.text.isEmpty,
                enabled: !_sending,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                onSubmitted: (_) => _send(),
                style: TextStyle(color: colors.primaryText),
                decoration: InputDecoration(
                  hintText: appL10n.webPayEmailHint,
                  hintStyle: TextStyle(color: colors.secondaryText),
                  errorText: invalid
                      ? appL10n.webPayEmailInvalid
                      : _failed
                      ? (_noConnection
                            ? appL10n.webPayNoConnection
                            : appL10n.webPayFailed)
                      : null,
                  filled: true,
                  fillColor: colors.searchFieldFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppDimensions.smallRadius,
                    ),
                    borderSide: BorderSide.none,
                  ),
                ),
              );
            },
          ),
          if (_creationErrorCode != null) ...[
            const SizedBox(height: AppDimensions.spacingL),
            SelectableText(
              _existingOrderSummary ??
                  (_creationErrorCode == 'payment_creation_unknown'
                      ? appL10n.webPayCreationReview(_creationOrder ?? '')
                      : appL10n.webPayCreationPending(_creationOrder ?? '')),
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(appL10n.cancel),
        ),
        if (_existingOrderUrl case final url?)
          TextButton(
            onPressed: _sending
                ? null
                : () async {
                    setState(() => _sending = true);
                    if (!await _openPayment(url, _controller.text.trim()) &&
                        mounted) {
                      setState(() {
                        _failed = true;
                        _sending = false;
                      });
                    }
                  },
            child: Text(appL10n.checkoutContinue),
          )
        else
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final canSend =
                  _emailPattern.hasMatch(value.text.trim()) &&
                  !_sending &&
                  _creationErrorCode == null;
              return TextButton(
                onPressed: canSend ? _send : null,
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.live
                            ? appL10n.webPayProceed
                            : appL10n.webPayNotify,
                      ),
              );
            },
          ),
      ],
    );
  }
}
