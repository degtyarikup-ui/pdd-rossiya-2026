import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/question_report_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Форма «что не так с вопросом» — прямо в приложении, без почты.
///
/// Человек пишет своими словами и отправляет; данные вопроса (id, билет,
/// тема, версия) прикладываются автоматически, спрашивать их у пользователя
/// бессмысленно — он их не знает и не должен.
Future<void> showReportQuestionDialog({
  required BuildContext context,
  required String questionId,
  String? questionText,
  int? ticketNumber,
  String? topic,
  String? mode,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReportQuestionDialog(
      questionId: questionId,
      questionText: questionText,
      ticketNumber: ticketNumber,
      topic: topic,
      mode: mode,
    ),
  );
}

class _ReportQuestionDialog extends StatefulWidget {
  const _ReportQuestionDialog({
    required this.questionId,
    this.questionText,
    this.ticketNumber,
    this.topic,
    this.mode,
  });

  final String questionId;
  final String? questionText;
  final int? ticketNumber;
  final String? topic;
  final String? mode;

  @override
  State<_ReportQuestionDialog> createState() => _ReportQuestionDialogState();
}

class _ReportQuestionDialogState extends State<_ReportQuestionDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final ok = await QuestionReportService.send(
      message: text,
      questionId: widget.questionId,
      questionText: widget.questionText,
      ticketNumber: widget.ticketNumber,
      topic: widget.topic,
      mode: widget.mode,
    );
    if (!mounted) return;

    Navigator.of(context).pop();
    if (ok) {
      HapticFeedbackHelper.success();
    } else {
      HapticFeedbackHelper.error();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? appL10n.reportSent : appL10n.reportFailed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      title: Text(
        appL10n.reportQuestionTooltip,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryText,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appL10n.reportQuestionBody,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.secondaryText,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            maxLength: QuestionReportService.maxMessageLength,
            enabled: !_sending,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: appL10n.reportQuestionHint,
              filled: true,
              fillColor: AppColors.searchFieldFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(appL10n.cancel),
        ),
        // Кнопка активна только когда есть текст: отправлять пустую жалобу
        // бессмысленно, а разбираться с ней потом — тем более.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            final canSend = value.text.trim().isNotEmpty && !_sending;
            return TextButton(
              onPressed: canSend ? _send : null,
              child: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(appL10n.reportSend),
            );
          },
        ),
      ],
    );
  }
}
