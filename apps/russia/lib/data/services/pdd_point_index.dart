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

  static final Map<String, Future<PddPointIndex>> _loading = {};

  /// Разобранный указатель, если он уже построен. Позволяет отрисовать
  /// ссылки сразу, без мигания обычным текстом на первом кадре.
  static final Map<String, PddPointIndex> _cached = {};
  static PddPointIndex? get cached => cachedFor('ru');
  static PddPointIndex? cachedFor(String lang) => _cached[lang];

  static Future<PddPointIndex> load([String lang = 'ru']) =>
      _loading.putIfAbsent(lang, () => _build(lang));

  static Future<PddPointIndex> _build(String lang) async {
    final sections = await QuestionsDataSource().loadPddSections(lang);

    final map = <String, int>{};
    for (var i = 0; i < sections.length; i++) {
      final content = sections[i]['content'] ?? '';
      for (final m in _pointStart.allMatches(content)) {
        // Первое вхождение выигрывает: пункт может упоминаться в соседних
        // разделах, но объявлен он ровно один раз.
        map.putIfAbsent(m.group(1)!, () => i);
      }
    }

    return _cached[lang] = PddPointIndex._(sections, map);
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
