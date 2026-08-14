import 'package:pdd_app/core/config/country_config.dart';

/// Ссылка на пункт Правил внутри текста разбора.
class PddPointRef {
  const PddPointRef({
    required this.point,
    required this.start,
    required this.end,
  });

  /// Номер пункта, как он написан в тексте: «13.11», «9.1.1».
  final String point;

  /// Границы номера в исходной строке — по ним строятся кликабельные куски.
  final int start;
  final int end;
}

/// Находит в комментарии к вопросу ссылки на пункты ПДД.
///
/// Ловим только номера после слова «пункт» («Пункт 13.11 ПДД», «пункты 8.1,
/// 8.2»). Голые числа брать нельзя: в разборах полно номеров знаков и
/// разметки («знак 3.1», «разметка 1.1»), и они выглядят точно так же —
/// линковать их на текст Правил значило бы уводить человека не туда.
List<PddPointRef> findPddPointRefs(String text) {
  final pattern = CountryConfig.current.pddPointMarker;
  if (pattern == null || text.isEmpty) return const [];

  final refs = <PddPointRef>[];
  for (final marker in RegExp(pattern).allMatches(text)) {
    // Группа с номерами идёт следом за словом-маркером; внутри может быть
    // перечисление через запятую или «и».
    final tail = marker.group(1);
    if (tail == null) continue;
    final tailStart = marker.start + marker.group(0)!.indexOf(tail);
    for (final n in _number.allMatches(tail)) {
      refs.add(
        PddPointRef(
          point: n.group(0)!,
          start: tailStart + n.start,
          end: tailStart + n.end,
        ),
      );
    }
  }
  return refs;
}

final RegExp _number = RegExp(r'\d{1,2}(?:\.\d{1,2}){1,3}');
