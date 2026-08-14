/// Конфигурация страны. Страна выбирается на этапе сборки:
/// `--dart-define=COUNTRY=ru` (по умолчанию) или `--dart-define=COUNTRY=by`.
///
/// Правило проекта: код один для всех стран. Всё страно-зависимое —
/// правила экзамена, названия, пути контента, наличие категорий C/D —
/// живёт здесь, а не в экранах.
library;

/// Модель подсчёта результата экзамена.
/// - [mistakes] — «не больше N ошибок» (РФ/РБ; возможна доп. фаза).
/// - [points] — весовые баллы: вопрос стоит 1/2/3, сдал при наборе
///   ≥ [ExamRules.passPercent]% от максимума (Сербия). Доп. фазы нет.
enum ExamScoring { mistakes, points }

/// Правила теоретического экзамена конкретной страны.
class ExamRules {
  /// Вопросов в основном блоке билета.
  final int mainCount;

  /// Время на экзамен, секунд.
  final int totalSeconds;

  /// Максимум ошибок, при котором экзамен ещё может быть сдан.
  /// Актуально только для [ExamScoring.mistakes].
  final int maxMistakes;

  /// Сколько доп. вопросов даётся за каждую ошибку (РФ: 5; РБ: 0 — механики нет).
  final int additionalPerMistake;

  /// Добавка времени за каждый доп. блок, секунд (РФ: 5 минут за блок из 5).
  final int additionalSecondsPerBlock;

  /// Как считается результат экзамена (по ошибкам или по баллам).
  final ExamScoring scoring;

  /// Проходной процент баллов для [ExamScoring.points] (Сербия: 85).
  /// Для [ExamScoring.mistakes] не используется.
  final int passPercent;

  /// Размер тематического блока билета в вопросах (РФ: 5 — билет из 20
  /// вопросов делится на 4 блока по позиции: 1-5, 6-10, 11-15, 16-20).
  ///
  /// Ключевая деталь регламента ГИБДД: две ошибки допускаются ТОЛЬКО в разных
  /// блоках, а две ошибки внутри одного блока — немедленный провал. Без этого
  /// симулятор мягче реального экзамена и растит ложную уверенность.
  ///
  /// 0 — блочного правила нет (РБ: 10 вопросов без деления; Сербия: баллы).
  final int blockSize;

  /// Максимум ошибок внутри ОДНОГО тематического блока, после которого
  /// экзамен считается проваленным немедленно (РФ: 2).
  final int maxMistakesPerBlock;

  const ExamRules({
    required this.mainCount,
    required this.totalSeconds,
    required this.maxMistakes,
    required this.additionalPerMistake,
    required this.additionalSecondsPerBlock,
    this.scoring = ExamScoring.mistakes,
    this.passPercent = 0,
    this.blockSize = 0,
    this.maxMistakesPerBlock = 0,
  });

  /// Действует ли правило «две ошибки в одном блоке — провал».
  bool get hasBlockRule =>
      scoring == ExamScoring.mistakes &&
      blockSize > 0 &&
      maxMistakesPerBlock > 0;

  /// Номер тематического блока (0-based) для вопроса основной части.
  /// Без блочного правила все вопросы считаются одним блоком.
  int blockIndexOf(int questionIndex) =>
      hasBlockRule ? questionIndex ~/ blockSize : 0;

  /// Есть ли механика дополнительных вопросов.
  /// В балльной модели доп. фазы нет никогда.
  bool get hasAdditionalPhase =>
      scoring == ExamScoring.mistakes && additionalPerMistake > 0;

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

  /// Название экзаменующего органа («ГИБДД» / «ГАИ» / «MUP»).
  final String examOfficeName;

  /// Язык интерфейса (локаль). Фиксирован под страну, рантайм-переключателя нет.
  /// 'ru' — Россия/Беларусь, 'sr' — Сербия (латиница).
  final String language;

  /// BCP-47 локаль для озвучки (TTS). Выводится из [language]: ru → ru-RU,
  /// sr → sr-RS. Голос должен соответствовать языку контента, иначе, например,
  /// сербский текст читается русским голосом.
  String get ttsLocale {
    switch (language) {
      case 'sr':
        return 'sr-RS';
      case 'ru':
      default:
        return 'ru-RU';
    }
  }

  /// Корень контента страны в ассетах.
  final String assetsRoot;

  /// Есть ли раздельные наборы билетов A/B и C/D (РФ — да, РБ на старте — нет).
  final bool hasCdCategory;

  final ExamRules examRules;

  /// Публичный веб-адрес приложения страны (для шеринга результата и т.п.).
  final String webUrl;

  /// Страница политики конфиденциальности. App Store (Guideline 5.1.1(i))
  /// требует ссылку И в метаданных, И внутри приложения; Google Play — тоже.
  /// Пусто → пункт в настройках скрыт (BY: страницы ещё нет, страна на паузе).
  final String privacyUrl;

  /// Ссылки на официальные источники гос-данных (вопросы, закон) для секции
  /// «О приложении». Google Play/App Store требуют указывать источник для
  /// приложений с государственной информацией. Пусто → секция скрыта.
  final List<({String label, String url})> dataSources;

  /// Абзац-дисклеймер: приложение неофициальное и не связано с госорганом
  /// (на языке страны). Пусто → не показывается.
  final String notAffiliatedNote;

  /// Как в разборе вопроса выглядит ссылка на пункт правил: регулярное
  /// выражение, где группа 1 — перечисление номеров («Пункт 13.11 ПДД»,
  /// «пункты 8.1, 8.2»). По ним номера становятся кликабельными.
  ///
  /// null — ссылки не подсвечиваются. Так у Сербии: текст правил там пока
  /// авторский пересказ, а не закон, и вести человека по номеру некуда.
  final String? pddPointMarker;

  const CountryConfig({
    required this.code,
    required this.appTitle,
    required this.examOfficeName,
    required this.language,
    required this.assetsRoot,
    required this.hasCdCategory,
    required this.examRules,
    required this.webUrl,
    this.privacyUrl = '',
    this.dataSources = const [],
    this.notAffiliatedNote = '',
    this.pddPointMarker,
  });

  /// Русскоязычный маркер ссылки на пункт: «Пункт 13.11 ПДД», «пункты 8.1, 8.2»,
  /// «п. 6.2». Общий для РФ и РБ — язык интерфейса и разборов там один.
  static const String _pddPointMarkerRu =
      r'(?:[Пп]ункт(?:ы|ов|а|е|ам|ами)?|[Пп]\.)\s*((?:\d{1,2}(?:\.\d{1,2}){1,3}(?:\s*(?:,|и)\s*)?)+)';

  /// Путь к JSON вопросов категории ('ab' | 'cd').
  String questionsJson(String cat) => '$assetsRoot/questions/questions_$cat.json';

  /// Путь к JSON тем категории ('ab' | 'cd').
  String topicsJson(String cat) => '$assetsRoot/questions/topics_$cat.json';

  /// Путь к JSON знаков.
  String get signsJson => '$assetsRoot/questions/signs.json';

  /// Путь к JSON текста ПДД (разделы для вкладки «ПДД»).
  String get pddSectionsJson => '$assetsRoot/questions/pdd_sections.json';

  /// Путь к JSON дорожной разметки (страно-зависимая).
  String get markupJson => '$assetsRoot/questions/markup.json';

  /// Каталог картинок вопросов категории.
  String questionImagesDir(String cat) => '$assetsRoot/images/questions_$cat';

  /// Каталог изображений знаков.
  String get signImagesDir => '$assetsRoot/images/signs';

  static const CountryConfig russia = CountryConfig(
    code: 'ru',
    appTitle: 'ПДД Россия 2026',
    examOfficeName: 'ГИБДД',
    language: 'ru',
    assetsRoot: 'assets/countries/ru',
    hasCdCategory: true,
    webUrl: 'https://pdd-drive.ru',
    privacyUrl: 'https://pdd-drive.ru/privacy.html',
    pddPointMarker: _pddPointMarkerRu,
    // Регламент ГИБДД (пост. Правительства РФ № 1097, приказ МВД № 80):
    // 20 вопросов / 20 минут, 4 тематических блока по 5 вопросов.
    // Не более 2 ошибок И ТОЛЬКО В РАЗНЫХ блоках — две ошибки внутри одного
    // блока означают провал сразу. За каждую ошибку +5 вопросов и +5 минут;
    // любая ошибка в доп. блоке — не сдан.
    examRules: ExamRules(
      mainCount: 20,
      totalSeconds: 20 * 60,
      maxMistakes: 2,
      additionalPerMistake: 5,
      additionalSecondsPerBlock: 5 * 60,
      blockSize: 5,
      maxMistakesPerBlock: 2,
    ),
  );

  static const CountryConfig belarus = CountryConfig(
    code: 'by',
    appTitle: 'ПДД Беларусь 2026',
    examOfficeName: 'ГАИ',
    language: 'ru',
    assetsRoot: 'assets/countries/by',
    hasCdCategory: false,
    webUrl: 'https://pdd-drive.online',
    pddPointMarker: _pddPointMarkerRu,
    // ГАИ РБ: 10 вопросов, 15 минут, максимум 1 ошибка, доп. вопросов нет.
    examRules: ExamRules(
      mainCount: 10,
      totalSeconds: 15 * 60,
      maxMistakes: 1,
      additionalPerMistake: 0,
      additionalSecondsPerBlock: 0,
    ),
  );

  static const CountryConfig serbia = CountryConfig(
    code: 'rs',
    appTitle: 'Auto testovi Srbija 2026',
    examOfficeName: 'MUP',
    // Сербский, латиница. Первая страна на не-русском языке.
    language: 'sr',
    assetsRoot: 'assets/countries/rs',
    // Старт — только A/B (41 вопрос на экзамене).
    hasCdCategory: false,
    webUrl: 'https://rs.pdd-drive.online',
    privacyUrl: 'https://rs.pdd-drive.online/privacy.html',
    dataSources: [
      (
        label: 'Ispitna pitanja — MUP Republike Srbije',
        url:
            'https://www.mup.gov.rs/wps/portal/sr/gradjani/dokumenta/vozacka+dozvola/ispitna+pitanja+i+ostala+dokumenta+za+osposobljavanje+kandidata',
      ),
      (
        label: 'Zakon o bezbednosti saobraćaja — MGSI Republike Srbije',
        url:
            'https://www.mgsi.gov.rs/lat/dokumenti/zakon-o-bezbednosti-saobracaja-na-putevima',
      ),
    ],
    notAffiliatedNote:
        'Nezvanična aplikacija napravljena u obrazovne svrhe. Nije povezana '
        'sa Ministarstvom unutrašnjih poslova Republike Srbije niti bilo kojim '
        'državnim organom, i ne izdaje niti zamenjuje zvanične dokumente. '
        'Opisi znakova su objašnjenja autora radi lakšeg učenja; merodavni su '
        'zvanični izvori navedeni iznad.',
    // MUP: 41 вопрос, 45 минут, балльная модель (вопрос 1/2/3),
    // сдал при наборе ≥ 85% от максимума. Доп. вопросов нет.
    examRules: ExamRules(
      mainCount: 41,
      totalSeconds: 45 * 60,
      maxMistakes: 0,
      additionalPerMistake: 0,
      additionalSecondsPerBlock: 0,
      scoring: ExamScoring.points,
      passPercent: 85,
    ),
  );

  static const String _countryCode =
      String.fromEnvironment('COUNTRY', defaultValue: 'ru');

  /// Конфигурация текущей сборки.
  static const CountryConfig current = _countryCode == 'by'
      ? belarus
      : _countryCode == 'rs'
          ? serbia
          : russia;
}
