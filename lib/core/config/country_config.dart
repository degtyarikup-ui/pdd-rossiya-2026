/// Конфигурация приложения: правила экзамена, названия, пути контента,
/// адреса сайта. Приложение одно — российское; всё, что зависит от
/// регламента и контента, живёт здесь, а не в экранах.
library;

/// Правила теоретического экзамена.
class ExamRules {
  /// Вопросов в основном блоке билета.
  final int mainCount;

  /// Время на экзамен, секунд.
  final int totalSeconds;

  /// Максимум ошибок, при котором экзамен ещё может быть сдан.
  final int maxMistakes;

  /// Сколько доп. вопросов даётся за каждую ошибку (РФ: 5; 0 — механики нет).
  final int additionalPerMistake;

  /// Добавка времени за каждый доп. блок, секунд (РФ: 5 минут за блок из 5).
  final int additionalSecondsPerBlock;

  /// Размер тематического блока билета в вопросах (РФ: 5 — билет из 20
  /// вопросов делится на 4 блока по позиции: 1-5, 6-10, 11-15, 16-20).
  ///
  /// Ключевая деталь регламента ГИБДД: две ошибки допускаются ТОЛЬКО в разных
  /// блоках, а две ошибки внутри одного блока — немедленный провал. Без этого
  /// симулятор мягче реального экзамена и растит ложную уверенность.
  ///
  /// 0 — блочного правила нет.
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
    this.blockSize = 0,
    this.maxMistakesPerBlock = 0,
  });

  /// Действует ли правило «две ошибки в одном блоке — провал».
  bool get hasBlockRule => blockSize > 0 && maxMistakesPerBlock > 0;

  /// Номер тематического блока (0-based) для вопроса основной части.
  /// Без блочного правила все вопросы считаются одним блоком.
  int blockIndexOf(int questionIndex) =>
      hasBlockRule ? questionIndex ~/ blockSize : 0;

  /// Есть ли механика дополнительных вопросов.
  bool get hasAdditionalPhase => additionalPerMistake > 0;

  /// Минут на основной блок — для бейджей на главной.
  int get totalMinutes => totalSeconds ~/ 60;

  /// Минимум верных ответов, чтобы билет из [totalQuestions] считался сданным.
  int passThreshold(int totalQuestions) => totalQuestions - maxMistakes;
}

class CountryConfig {
  /// Код страны ('ru'). Сверяется с полем `country` сцен игры.
  final String code;

  /// Название приложения (заголовок, About).
  final String appTitle;

  /// Название экзаменующего органа («ГИБДД»).
  final String examOfficeName;

  /// Язык интерфейса (локаль), рантайм-переключателя нет.
  final String language;

  /// BCP-47 локаль для озвучки (TTS).
  String get ttsLocale => 'ru-RU';

  /// Корень контента страны в ассетах.
  final String assetsRoot;

  /// Есть ли раздельные наборы билетов A/B и C/D.
  final bool hasCdCategory;

  final ExamRules examRules;

  /// Публичный веб-адрес приложения страны (для шеринга результата и т.п.).
  final String webUrl;

  /// Страница политики конфиденциальности. App Store (Guideline 5.1.1(i))
  /// требует ссылку И в метаданных, И внутри приложения; Google Play — тоже.
  /// Пусто → пункт в настройках скрыт.
  final String privacyUrl;

  /// Страница пользовательского соглашения (Terms of Use / EULA).
  /// Требуется Apple (Guideline 3.1.2) и Google Play для платных подписок.
  final String termsUrl;

  /// Страница тарифов оплаты на сайте (что и за сколько покупает клиент —
  /// требование банка). Пусто → оплаты на сайте нет, веб-пейвол
  /// показывает только «оплата скоро». РФ: СБП через агрегатора.
  final String tariffsUrl;

  /// Оплата премиума на сайте (веб-версия). Только веб: в приложениях из
  /// App Store / Google Play — покупки стора.
  bool get hasWebPayments => tariffsUrl.isNotEmpty;

  /// Как в разборе вопроса выглядит ссылка на пункт правил: регулярное
  /// выражение, где группа 1 — перечисление номеров («Пункт 13.11 ПДД»,
  /// «пункты 8.1, 8.2»). По ним номера становятся кликабельными.
  ///
  /// null — ссылки не подсвечиваются.
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
    this.termsUrl = '',
    this.tariffsUrl = '',
    this.pddPointMarker,
  });

  /// Русскоязычный маркер ссылки на пункт: «Пункт 13.11 ПДД», «пункты 8.1, 8.2»,
  /// «п. 6.2».
  static const String _pddPointMarkerRu =
      r'(?:[Пп]ункт(?:ы|ов|а|е|ам|ами)?|[Пп]\.)\s*((?:\d{1,2}(?:\.\d{1,2}){1,3}(?:\s*(?:,|и)\s*)?)+)';

  /// BCP-47 локаль для озвучки (TTS) с учётом текущего языка.
  String ttsLocaleFor([String? lang]) {
    switch (lang) {
      case 'en':
        return 'en-US';
      case 'kk':
        return 'kk-KZ';
      case 'ru':
      default:
        return 'ru-RU';
    }
  }

  /// Путь к JSON вопросов категории ('ab' | 'cd') с учётом языка.
  String questionsJson(String cat, [String? lang]) {
    if (lang != null && lang != 'ru' && (lang == 'en' || lang == 'kk')) {
      return '$assetsRoot/questions/questions_${cat}_$lang.json';
    }
    return '$assetsRoot/questions/questions_$cat.json';
  }

  /// Путь к JSON тем категории ('ab' | 'cd') с учётом языка.
  String topicsJson(String cat, [String? lang]) {
    if (lang != null && lang != 'ru' && (lang == 'en' || lang == 'kk')) {
      return '$assetsRoot/questions/topics_${cat}_$lang.json';
    }
    return '$assetsRoot/questions/topics_$cat.json';
  }

  /// Путь к JSON знаков с учётом языка.
  String signsJson([String? lang]) {
    if (lang != null && lang != 'ru' && (lang == 'en' || lang == 'kk')) {
      return '$assetsRoot/questions/signs_$lang.json';
    }
    return '$assetsRoot/questions/signs.json';
  }

  /// Путь к JSON манифеста ленты знаков с учётом языка.
  String signsFeedManifestJson([String? lang]) {
    if (lang != null && lang != 'ru' && (lang == 'en' || lang == 'kk')) {
      return '$assetsRoot/questions/signs_feed_manifest_$lang.json';
    }
    return '$assetsRoot/questions/signs_feed_manifest.json';
  }

  /// Путь к JSON текста ПДД (разделы для вкладки «ПДД») с учётом языка.
  String pddSectionsJson([String? lang]) {
    if (lang != null && lang != 'ru' && (lang == 'en' || lang == 'kk')) {
      return '$assetsRoot/questions/pdd_sections_$lang.json';
    }
    return '$assetsRoot/questions/pdd_sections.json';
  }

  /// Путь к JSON дорожной разметки с учётом языка.
  String markupJson([String? lang]) {
    if (lang != null && lang != 'ru' && (lang == 'en' || lang == 'kk')) {
      return '$assetsRoot/questions/markup_$lang.json';
    }
    return '$assetsRoot/questions/markup.json';
  }

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
    termsUrl: 'https://pdd-drive.ru/terms.html',
    tariffsUrl: 'https://pdd-drive.ru/tarify/',
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

  /// Конфигурация текущей сборки. Страна одна, `--dart-define=COUNTRY`
  /// других значений не принимает.
  static const CountryConfig current = russia;
}
