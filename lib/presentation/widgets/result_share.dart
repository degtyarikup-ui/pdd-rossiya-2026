import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
/// [ShareResultCard] и текст.
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
    config.shareUrl,
  );
  // Готовность — тот же показатель, что на главной: доля верно решённых
  // вопросов от всей базы категории.
  final container = ProviderScope.containerOf(context, listen: false);
  String? footer;
  try {
    final stats = await container.read(statsProvider.future);
    final correctTotal = stats['correctAnswers'] ?? 0;
    final totalQuestions = stats['totalQuestions'] ?? 0;
    final readiness = totalQuestions > 0
        ? (correctTotal / totalQuestions * 100).round()
        : 0;
    footer = '${appL10n.examReadiness} — $readiness%';
  } catch (_) {
    // Без готовности карточка просто короче.
  }
  if (!context.mounted) return;
  await shareResultCard(
    context,
    text: text,
    card: ShareResultCard(
      passed: passed,
      title: title,
      badge: '$correct/$total',
      // Короткие формы со склонением: на карточке подпись стоит прямо под
      // числом, и «6 ошибка» из обычного ярлыка выглядело бы безграмотно —
      // а картинку увидят посторонние люди.
      stats: [
        (value: '$correct', label: appL10n.shareCardCorrectWord(correct)),
        (value: '$wrong', label: appL10n.shareCardWrongWord(wrong)),
      ],
      footer: footer,
      siteUrl: config.shareCardHost,
    ),
  );
}

/// Снимок эмблемы с экрана итога (там она уже нарисована, вместе с SVG) —
/// для карточки игры. null, если снять не удалось.
Future<ui.Image?> captureEmblem(GlobalKey key) async {
  try {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) return null;
    // Эмблема на карточке — 320 px; снимаем с запасом под это.
    final ratio = 400 / boundary.size.shortestSide;
    return await boundary.toImage(pixelRatio: ratio);
  } catch (_) {
    return null;
  }
}

/// Делится картинкой [card] и [text] (share_plus: Android/iOS — нативный
/// лист, web — Web Share API, без него — копия текста в буфер).
Future<void> shareResultCard(
  BuildContext context, {
  required ShareResultCard card,
  required String text,
}) async {
  // Сначала пробуем поделиться картинкой: текстом никто не делится, а
  // квадрат 1080×1080 уходит в сторис и чаты автошкол. Если рендер или
  // сохранение не удались — молча откатываемся на текстовый путь.
  final origin = sharePositionOrigin(context);
  final imageFile = await _saveCard(card);
  if (imageFile != null) {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: [imageFile],
          sharePositionOrigin: origin,
        ),
      );
      if (result.status != ShareResultStatus.unavailable) return;
    } catch (_) {
      // Ниже — обычный текстовый шеринг.
    }
  }

  try {
    final result = await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
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

/// Точка, к которой iPad привязывает окно «Поделиться», — центр экрана
/// [context]. Без неё share_plus на iPad возвращает ошибку, и вместо окна
/// текст молча уходил в буфер. На телефонах значение не используется.
Rect? sharePositionOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return Rect.fromCenter(
    center: box.localToGlobal(box.size.center(Offset.zero)),
    width: 1,
    height: 1,
  );
}

/// Собирает картинку и кладёт во временный файл.
///
/// Возвращает null на вебе (там нет файловой системы под share_plus и
/// картинку всё равно не приложить) и при любой ошибке рендера — тогда
/// вызывающий код делится обычным текстом.
Future<XFile?> _saveCard(ShareResultCard card) async {
  if (kIsWeb) return null;
  try {
    final png = await ShareCardRenderer.renderToPng(
      size: const Size(ShareResultCard.side, ShareResultCard.side),
      widget: card,
    );
    if (png == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/result_card.png');
    await file.writeAsBytes(png, flush: true);
    return XFile(file.path, mimeType: 'image/png');
  } catch (_) {
    return null;
  }
}
