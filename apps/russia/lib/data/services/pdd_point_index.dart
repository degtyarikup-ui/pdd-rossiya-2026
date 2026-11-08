import 'package:pdd_app/data/sources/questions_data_source.dart';

/// Указатель «номер пункта ПДД → раздел, в котором он лежит».
///
/// Нужен, чтобы из разбора вопроса («Пункт 13.11 ПДД») открыть текст Правил
/// ровно на этом пункте. Строится один раз за запуск: разделов два десятка,
/// разбор занимает миллисекунды, но делать его на каждый показанный
/// комментарий было бы расточительно.
class PddPointIndex {
  PddPointIndex._(this._sections, this._pointToSection);

  final List<Map<String, String>> _sections;
  final Map<String, int> _pointToSection;

  static Future<PddPointIndex>? _loading;

  /// Разобранный указатель, если он уже построен. Позволяет отрисовать
  /// ссылки сразу, без мигания обычным текстом на первом кадре.
  static PddPointIndex? cached;

  static Future<PddPointIndex> load() => _loading ??= _build();

  static Future<PddPointIndex> _build() async {
    final sections = await QuestionsDataSource().loadPddSections();

    final map = <String, int>{};
    for (var i = 0; i < sections.length; i++) {
      final content = sections[i]['content'] ?? '';
      for (final m in _pointStart.allMatches(content)) {
        // Первое вхождение выигрывает: пункт может упоминаться в соседних
        // разделах, но объявлен он ровно один раз.
        map.putIfAbsent(m.group(1)!, () => i);
      }
    }

    return cached = PddPointIndex._(sections, map);
  }

  /// Начало пункта: номер в начале строки, 2–4 уровня («13.11», «13.11.1»).
  static final RegExp _pointStart = RegExp(
    r'^(\d{1,2}(?:\.\d{1,2}){1,3})\.',
    multiLine: true,
  );

  bool contains(String point) => _pointToSection.containsKey(point);

  /// Раздел, в котором объявлен пункт. null — пункта нет в тексте Правил
  /// (например, ссылка на «Перечень неисправностей» — это отдельный документ).
  Map<String, String>? sectionOf(String point) {
    final index = _pointToSection[point];
    return index == null ? null : _sections[index];
  }
}
