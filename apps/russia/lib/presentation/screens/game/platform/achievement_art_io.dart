import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Кладёт картинки наград, которые игра может вручить за этот запуск, во
/// временную папку и возвращает её путь с `/` на конце. Своего комплекта
/// значков в игре нет: так они не занимают место в сборке дважды.
Future<String> prepareAchievementArt(Iterable<String> assetKeys) async {
  final dir = Directory(
    '${(await getTemporaryDirectory()).path}/achievement_art',
  );
  // Несколько файлов по ~20 КБ — синхронная запись.
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  for (final key in assetKeys) {
    final data = await rootBundle.load(key);
    File('${dir.path}/${key.split('/').last}').writeAsBytesSync(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
  return '${dir.path}/';
}
