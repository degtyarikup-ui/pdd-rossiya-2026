import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Оплата на сайте через СБП, пока платёжка не подключена: человек
/// оставляет почту (для письма о запуске и чека), сервер записывает выбор
/// тарифа — это просит банк при согласовании. Возвращает почту, если
/// выбор сохранён, иначе null.
Future<String?> showWebPaymentDialog({
  required BuildContext context,
  required PremiumTier tier,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _WebPaymentDialog(tier: tier),
  );
}

class _WebPaymentDialog extends StatefulWidget {
  const _WebPaymentDialog({required this.tier});

  final PremiumTier tier;

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _controller.text.trim();
    if (!_emailPattern.hasMatch(email) || _sending) return;
    setState(() {
      _sending = true;
      _failed = false;
    });
    final ok = await PremiumService.instance.recordPayIntent(
      tier: widget.tier,
      email: email,
    );
    if (!mounted) return;
    if (ok) {
      HapticFeedbackHelper.success();
      Navigator.of(context).pop(email);
    } else {
      HapticFeedbackHelper.error();
      setState(() {
        _sending = false;
        _failed = true;
      });
    }
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
            appL10n.webPayEmailBody,
            style: TextStyle(
              fontSize: 14,
              color: colors.secondaryText,
              height: 1.35,
            ),
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
                      ? appL10n.webPayFailed
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(appL10n.cancel),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            final canSend =
                _emailPattern.hasMatch(value.text.trim()) && !_sending;
            return TextButton(
              onPressed: canSend ? _send : null,
              child: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(appL10n.webPayNotify),
            );
          },
        ),
      ],
    );
  }
}
