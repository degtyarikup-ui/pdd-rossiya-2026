/// Конфигурация страны. Страна выбирается на этапе сборки:
/// `--dart-define=COUNTRY=ru` (по умолчанию) или `--dart-define=COUNTRY=by`.
///
/// Правило проекта: код один для всех стран. Всё страно-зависимое —
/// правила экзамена, названия, пути контента, наличие категорий C/D —
/// живёт здесь, а не в экранах.
library;

/// Правила теоретического экзамена конкретной страны.
class ExamRules {
  /// Вопросов в основном блоке билета.
  final int mainCount;

  /// Время на экзамен, секунд.
  final int totalSeconds;

  /// Максимум ошибок, при котором экзамен ещё может быть сдан.
  final int maxMistakes;

  /// Сколько доп. вопросов даётся за каждую ошибку (РФ: 5; РБ: 0 — механики нет).
  final int additionalPerMistake;

  /// Добавка времени за каждый доп. блок, секунд (РФ: 5 минут за блок из 5).
  final int additionalSecondsPerBlock;

  const ExamRules({
    required this.mainCount,
    required this.totalSeconds,
    required this.maxMistakes,
    required this.additionalPerMistake,
    required this.additionalSecondsPerBlock,
  });

  /// Есть ли механика дополнительных вопросов.
  bool get hasAdditionalPhase => additionalPerMistake > 0;

  /// Минут на основной блок — для бейджей на главной.
  int get totalMinutes => totalSeconds ~/ 60;

  /// Минимум верных ответов, чтобы билет из [totalQuestions] считался сданным.
  int passThreshold(int totalQuestions) => totalQuestions - maxMistakes;
}

class CountryConfig {
  /// Код страны ('ru' | 'by').
  final String code;

  /// Название приложения (заголовок, About).
  final String appTitle;

  /// Название экзаменующего органа («ГИБДД» / «ГАИ»).
  final String examOfficeName;

  /// Корень контента страны в ассетах.
  final String assetsRoot;

  /// Есть ли раздельные наборы билетов A/B и C/D (РФ — да, РБ на старте — нет).
  final bool hasCdCategory;

  final ExamRules examRules;

  const CountryConfig({
    required this.code,
    required this.appTitle,
    required this.examOfficeName,
    required this.assetsRoot,
    required this.hasCdCategory,
    required this.examRules,
  });

  /// Путь к JSON вопросов категории ('ab' | 'cd').
  String questionsJson(String cat) => '$assetsRoot/questions/questions_$cat.json';

  /// Путь к JSON тем категории ('ab' | 'cd').
  String topicsJson(String cat) => '$assetsRoot/questions/topics_$cat.json';

  /// Путь к JSON знаков.
  String get signsJson => '$assetsRoot/questions/signs.json';

  /// Путь к JSON текста ПДД (разделы для вкладки «ПДД»).
  String get pddSectionsJson => '$assetsRoot/questions/pdd_sections.json';

  /// Каталог картинок вопросов категории.
  String questionImagesDir(String cat) => '$assetsRoot/images/questions_$cat';

  /// Каталог изображений знаков.
  String get signImagesDir => '$assetsRoot/images/signs';

  static const CountryConfig russia = CountryConfig(
    code: 'ru',
    appTitle: 'ПДД Россия 2026',
    examOfficeName: 'ГИБДД',
    assetsRoot: 'assets/countries/ru',
    hasCdCategory: true,
    examRules: ExamRules(
      mainCount: 20,
      totalSeconds: 20 * 60,
      maxMistakes: 2,
      additionalPerMistake: 5,
      additionalSecondsPerBlock: 5 * 60,
    ),
  );

  static const CountryConfig belarus = CountryConfig(
    code: 'by',
    appTitle: 'ПДД Беларусь 2026',
    examOfficeName: 'ГАИ',
    assetsRoot: 'assets/countries/by',
    hasCdCategory: false,
    // ГАИ РБ: 10 вопросов, 15 минут, максимум 1 ошибка, доп. вопросов нет.
    examRules: ExamRules(
      mainCount: 10,
      totalSeconds: 15 * 60,
      maxMistakes: 1,
      additionalPerMistake: 0,
      additionalSecondsPerBlock: 0,
    ),
  );

  static const String _countryCode =
      String.fromEnvironment('COUNTRY', defaultValue: 'ru');

  /// Конфигурация текущей сборки.
  static const CountryConfig current =
      _countryCode == 'by' ? belarus : russia;
}
