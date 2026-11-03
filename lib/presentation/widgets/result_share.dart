import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/share_card_renderer.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/share_result_card.dart';

/// «Поделиться» с завершающего экрана экзамена, билета или темы: картинка
/// [ShareResultCard] и текст (share_plus: Android/iOS — нативный лист, web —
/// Web Share API, без него — копия текста в буфер).
Future<void> shareStudyResult(
  BuildContext context, {
  required bool passed,
  required String title,
  required int correct,
  required int total,
  required int wrong,
}) async {
  final config = CountryConfig.current;
  final text = appL10n.examShareText(
    title,
    correct,
    total,
    config.appTitle,
    config.webUrl,
  );
  // Готовность — тот же показатель, что на главной: доля верно решённых
  // вопросов от всей базы категории.
  final container = ProviderScope.containerOf(context, listen: false);

  // Сначала пробуем поделиться картинкой: текстом никто не делится, а
  // квадрат 1080×1080 уходит в сторис и чаты автошкол. Если рендер или
  // сохранение не удались — молча откатываемся на текстовый путь.
  final imageFile = await _buildShareImage(
    container,
    passed: passed,
    title: title,
    correct: correct,
    total: total,
    wrong: wrong,
  );
  if (imageFile != null) {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, files: [imageFile]),
      );
      if (result.status != ShareResultStatus.unavailable) return;
    } catch (_) {
      // Ниже — обычный текстовый шеринг.
    }
  }

  try {
    final result = await SharePlus.instance.share(ShareParams(text: text));
    // На web системный «Поделиться» (navigator.share) есть не везде — на
    // десктопе/без HTTPS он недоступен, и share_plus вернёт unavailable.
    // Тогда — запасной путь: копируем текст в буфер и уведомляем.
    if (result.status != ShareResultStatus.unavailable) return;
  } catch (_) {
    // navigator.share бросил (нет Web Share API) — идём в запасной путь.
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(appL10n.copiedToClipboard)));
}

/// Собирает картинку результата и кладёт во временный файл.
///
/// Возвращает null на вебе (там нет файловой системы под share_plus и
/// картинку всё равно не приложить) и при любой ошибке рендера — тогда
/// вызывающий код делится обычным текстом.
Future<XFile?> _buildShareImage(
  ProviderContainer container, {
  required bool passed,
  required String title,
  required int correct,
  required int total,
  required int wrong,
}) async {
  if (kIsWeb) return null;
  try {
    final stats = await container.read(statsProvider.future);
    final correctTotal = stats['correctAnswers'] ?? 0;
    final totalQuestions = stats['totalQuestions'] ?? 0;
    final readiness = totalQuestions > 0
        ? (correctTotal / totalQuestions * 100).round()
        : 0;

    final png = await ShareCardRenderer.renderToPng(
      size: const Size(ShareResultCard.side, ShareResultCard.side),
      widget: ShareResultCard(
        passed: passed,
        correct: correct,
        total: total,
        wrong: wrong,
        readinessPercent: readiness,
        title: title,
        // Короткие формы со склонением: на карточке подпись стоит прямо
        // под числом, и «6 ошибка» из обычного ярлыка выглядело бы
        // безграмотно — а картинку увидят посторонние люди.
        correctLabel: appL10n.shareCardCorrectWord(correct),
        wrongLabel: appL10n.shareCardWrongWord(wrong),
        readinessLabel: appL10n.examReadiness,
        siteUrl: CountryConfig.current.shareCardHost,
      ),
    );
    if (png == null) return null;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/study_result.png');
    await file.writeAsBytes(png, flush: true);
    return XFile(file.path, mimeType: 'image/png');
  } catch (_) {
    return null;
  }
}
