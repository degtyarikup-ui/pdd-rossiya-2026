import 'dart:math';
import 'package:pdd_app/data/models/road_signs_model.dart';

/// Сервис генерации вопросов викторины «Знаки» с защитой от коллизий дистракторов.
class RoadSignsEngine {
  final List<SignItem> allSigns;
  final Map<String, List<SignItem>> signsByCategory;
  final Random _rnd;

  RoadSignsEngine({required this.allSigns, Random? random})
    : _rnd = random ?? Random(),
      signsByCategory = _groupSignsByCategory(allSigns);

  static Map<String, List<SignItem>> _groupSignsByCategory(
    List<SignItem> signs,
  ) {
    final map = <String, List<SignItem>>{};
    for (final s in signs) {
      map.putIfAbsent(s.category, () => []).add(s);
    }
    return map;
  }

  /// Парсинг словаря `signs.json` в типизированный список знаков.
  static List<SignItem> parseSignsJson(Map<String, dynamic> rawJson) {
    final list = <SignItem>[];
    for (final catEntry in rawJson.entries) {
      final category = catEntry.key.trim();
      final itemsMap = catEntry.value;
      if (itemsMap is! Map) continue;

      for (final signEntry in itemsMap.entries) {
        final number = signEntry.key.toString().trim();
        final signData = signEntry.value;
        if (signData is! Map) continue;

        final item = SignItem.fromMap(
          number: number,
          category: category,
          map: Map<String, dynamic>.from(signData),
        );
        if (item.image.isNotEmpty && item.title.isNotEmpty) {
          list.add(item);
        }
      }
    }
    return list;
  }

  /// Доступные категории знаков.
  List<String> get availableCategories => signsByCategory.keys.toList();

  /// Генерация колоды вопросов с анти-коллизией вариантов.
  List<RoadSignQuizQuestion> generateDeck({
    int count = 25,
    String? categoryFilter,
  }) {
    if (allSigns.length < 4) return const [];

    final pool =
        (categoryFilter != null &&
            categoryFilter.isNotEmpty &&
            signsByCategory.containsKey(categoryFilter))
        ? List<SignItem>.from(signsByCategory[categoryFilter]!)
        : List<SignItem>.from(allSigns);

    if (pool.isEmpty) return const [];

    pool.shuffle(_rnd);
    final deck = <RoadSignQuizQuestion>[];

    for (int i = 0; i < count; i++) {
      final target = pool[i % pool.length];
      final q = buildQuestionForSign(target);
      if (q != null) {
        deck.add(q);
      }
    }

    return deck;
  }

  /// Создание вопроса для конкретного целевого знака [target].
  RoadSignQuizQuestion? buildQuestionForSign(SignItem target) {
    // 1. Подбор 3 дистракторов без совпадения названий, номеров и народных названий.
    final distractors = selectDistractors(target, count: 3);
    if (distractors.length < 3) return null;

    final options = [target, ...distractors]..shuffle(_rnd);
    final correctIndex = options.indexOf(target);

    // 2. Определение типа вопроса и текста подсказки (prompt).
    final RoadSignQuizType type;
    final String prompt;

    final hasFolk = target.folkName != null && target.folkName!.trim().isNotEmpty;
    final coreDef = extractCoreDefinition(target.description, target: target);
    final hasMeaning = coreDef.isNotEmpty;

    final roll = _rnd.nextDouble();
    if (hasFolk && roll < 0.30) {
      type = RoadSignQuizType.folkNameMatch;
      prompt = 'Какой знак в народе называют «${target.folkName!.trim()}»?';
    } else if (hasMeaning && roll < 0.70) {
      type = RoadSignQuizType.meaningDefinition;
      prompt = formatMeaningPrompt(coreDef);
    } else {
      type = RoadSignQuizType.titleMatch;
      prompt = 'Какой из этих знаков — «${target.title.trim()}»?';
    }

    final officialQuote = extractOfficialQuote(
      target.description,
      target.title,
      signNumber: target.number,
    );

    final id =
        '${target.number}_${DateTime.now().microsecondsSinceEpoch}_${_rnd.nextInt(100000)}';

    return RoadSignQuizQuestion(
      id: id,
      correctSign: target,
      options: options,
      correctAnswerIndex: correctIndex,
      prompt: prompt,
      officialRuleQuote: officialQuote,
      type: type,
    );
  }

  /// Алгоритм строгого отбора дистракторов с исключением дублирующихся названий (33 коллизии),
  /// дублирующихся изображений и дублирующихся народных названий.
  List<SignItem> selectDistractors(SignItem target, {required int count}) {
    final targetTitle = _normalize(target.title);
    final targetFolk = target.folkName != null ? _normalize(target.folkName!) : null;

    bool isCandidateValid(SignItem c, List<SignItem> selected) {
      // Исключаем сам целевой знак
      if (c.number == target.number) return false;

      // Исключаем одинаковое изображение SVG
      if (c.image.isNotEmpty && c.image == target.image) return false;
      if (c.image.isNotEmpty && selected.any((s) => s.image == c.image)) return false;

      final cTitle = _normalize(c.title);
      // Исключаем совпадение названия с целевым знаком
      if (cTitle == targetTitle) return false;

      // Исключаем совпадение названия с уже отобранными дистракторами
      if (selected.any((s) => _normalize(s.title) == cTitle)) return false;

      // Исключаем совпадение номера знака
      if (selected.any((s) => s.number == c.number)) return false;

      // Исключаем коллизии по народным названиям
      if (targetFolk != null && targetFolk.isNotEmpty) {
        if (c.folkName != null && _normalize(c.folkName!) == targetFolk) {
          return false;
        }
      }
      if (c.folkName != null && c.folkName!.trim().isNotEmpty) {
        final cFolk = _normalize(c.folkName!);
        if (selected.any((s) => s.folkName != null && _normalize(s.folkName!) == cFolk)) {
          return false;
        }
      }

      return true;
    }

    final selected = <SignItem>[];

    // Фаза 1: Приоритетно отбираем кандидатов из той же категории знаков для сложности
    final sameCategoryPool = List<SignItem>.from(
      signsByCategory[target.category] ?? const [],
    )..shuffle(_rnd);

    for (final candidate in sameCategoryPool) {
      if (isCandidateValid(candidate, selected)) {
        selected.add(candidate);
        if (selected.length == count) return selected;
      }
    }

    // Фаза 2: Добираем из общего пула знаков
    final generalPool = List<SignItem>.from(allSigns)..shuffle(_rnd);
    for (final candidate in generalPool) {
      if (isCandidateValid(candidate, selected)) {
        selected.add(candidate);
        if (selected.length == count) return selected;
      }
    }

    return selected;
  }

  /// Эталонные смысловые определения для ключевых дорожных знаков ПДД РФ.
  /// Формулировки выверены, кратки, однозначны и не содержат номеров знаков или подсказок.
  static const Map<String, String> _curatedMeanings = {
    // 2. Знаки приоритета
    '2.1': 'Предоставляет право преимущественного проезда нерегулируемых перекрестков',
    '2.2': 'Обозначает конец дороги с преимущественным правом проезда',
    '2.4': 'Обязывает уступить дорогу ТС на пересекаемой дороге',
    '2.5': 'Запрещает движение без обязательной остановки перед стоп-линией',
    '2.6': 'Запрещает въезд на узкий участок дороги, если это затруднит встречное движение',
    '2.7': 'Предоставляет преимущество по отношению к встречным ТС на узком участке дороги',

    // 3. Запрещающие знаки
    '3.1': 'Запрещает въезд всех транспортных средств в данном направлении',
    '3.2': 'Запрещает движение всех транспортных средств в обоих направлениях',
    '3.3': 'Запрещает движение любых механических транспортных средств',
    '3.4': 'Запрещает движение грузовиков с разрешенной максимальной массой более 3,5 т',
    '3.5': 'Запрещает движение мотоциклов любого типа',
    '3.6': 'Запрещает движение любых тракторов и самоходных машин',
    '3.7': 'Запрещает движение грузовиков и тракторов с любыми прицепами, а также буксировку',
    '3.10': 'Запрещает перемещение пешеходов, а также лиц на СИМ',
    '3.18.1': 'Запрещает поворот направо на ближайшем пересечении дорог',
    '3.18.2': 'Запрещает поворот налево на ближайшем пересечении дорог',
    '3.19': 'Запрещает только разворот (при этом поворот налево разрешен)',
    '3.20': 'Запрещает обгон транспортных средств, кроме тихоходных и двухколесных',
    '3.22': 'Запрещает грузовым авто с массой более 3,5 т обгон любых ТС',
    '3.24': 'Запрещает движение со скоростью выше числа, указанного на знаке',
    '3.27': 'Запрещает как остановку, так и стоянку любых транспортных средств',
    '3.28': 'Запрещает исключительно стоянку ТС (кратковременная остановка разрешена)',

    // 4. Предписывающие знаки
    '4.1.1': 'Предписывает двигаться только прямо',
    '4.1.2': 'Предписывает двигаться только направо',
    '4.1.3': 'Предписывает двигаться только налево или на разворот',
    '4.1.4': 'Предписывает двигаться только прямо или направо',
    '4.1.5': 'Предписывает двигаться только прямо или налево (а также на разворот)',
    '4.1.6': 'Предписывает двигаться только направо или налево (а также на разворот)',
    '4.2.1': 'Разрешает объезд препятствия только с правой стороны',
    '4.2.2': 'Разрешает объезд препятствия только с левой стороны',
    '4.2.3': 'Разрешает объезд препятствия с любой удобной стороны',
    '4.3': 'Предписывает движение по кругу в направлении стрелок',
    '4.6': 'Запрещает движение со скоростью менее указанной на знаке',

    // 5. Знаки особых предписаний
    '5.1': 'Обозначает дорогу с высшим скоростным режимом для автомобилей',
    '5.3': 'Обозначает дорогу только для автомобилей, автобусов и мотоциклов',
    '5.5': 'Обозначает дорогу с движением по всей ширине в одну сторону',
    '5.11.1': 'Обозначает дорогу с полосой для встречного маршрутного транспорта',
    '5.14.1': 'Обозначает специальную выделенную полосу для маршрутного транспорта',
    '5.19.1': 'Обозначает место организованного наземного перехода дороги',
    '5.20': 'Обозначает точные границы искусственной неровности',
    '5.21': 'Обозначает въезд на территорию с особым режимом для пешеходов',
    '5.27': 'Обозначает начало участка с запретом стоянки',
    '5.31': 'Обозначает начало участка с лимитом максимальной скорости',

    // 6. Информационные знаки и 7. Знаки сервиса
    '6.4': 'Обозначает площадку для стоянки (парковки) автомобилей',
    '6.8.1': 'Обозначает дорогу, не имеющую сквозного проезда',
    '6.16': 'Указывает место остановки перед светофором или регулировщиком',
    '8.8': 'Указывает, что услуги предоставляются исключительно за плату',
  };

  /// Формирование текста вопроса по значению/определению.
  static String formatMeaningPrompt(String coreDefinition) {
    var def = coreDefinition.trim();
    if (def.endsWith('.')) {
      def = def.substring(0, def.length - 1).trim();
    }
    return 'Какой из этих знаков означает: «$def»?';
  }

  /// Извлечение краткого смыслового определения знака.
  /// Возвращает непустую строку только если определение гарантированно краткое (до 90 символов),
  /// не раскрывает номер или название знака, не содержит регламентной шелухи ("устанавливается за 50 м")
  /// и не относится к группе знаков одновременно. При любых сомнениях возвращает пустую строку,
  /// что безопасно переводит вопрос в надежный режим `titleMatch`.
  static String extractCoreDefinition(String rawDescription, {SignItem? target}) {
    if (target != null && _curatedMeanings.containsKey(target.number)) {
      return _curatedMeanings[target.number]!;
    }

    if (rawDescription.isEmpty) return '';

    var text = rawDescription
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r', ' ')
        .trim();

    // 1. Отсекаем статьи КоАП и штрафы
    final penaltyMarker = RegExp(
      r'(?:Наказание за нарушение|Наказание:|КоАП РФ|КоАП|Штраф)',
      caseSensitive: false,
    );
    final pMatch = penaltyMarker.firstMatch(text);
    if (pMatch != null) {
      text = text.substring(0, pMatch.start).trim();
    }

    // 2. Если в тексте упоминаются несколько номеров знаков с точками (например, 8.2.1-8.2.6),
    // это составное описание группы знаков — его категорически нельзя использовать для вопроса.
    final numbersWithDots = RegExp(r'\b\d+\.\d+(?:\.\d+)?\b').allMatches(text).toList();
    if (numbersWithDots.length > 1) {
      return '';
    }

    // 3. Если в тексте есть хоть один номер знака или слово "знак" — отсекаем, чтобы не спойлерить номер знака.
    if (numbersWithDots.isNotEmpty) {
      return '';
    }
    if (RegExp(r'\bзнак[а-я]*\b', caseSensitive: false).hasMatch(text)) {
      return '';
    }

    // 4. Отсекаем описания, состоящие из правил установки, дистанций и ГОСТ-регламентов
    final badKeywords = RegExp(
      r'\b(?:устанавл|расстояни|таб\b|табличк|коап|штраф|руб|гост|пункт|стать|н\.\s*п\.|вне\s+н|разметк)\w*',
      caseSensitive: false,
    );
    if (badKeywords.hasMatch(text)) {
      return '';
    }

    // 5. Разделяем на предложения с защитой сокращений
    final sentences = _splitSentences(text);
    if (sentences.isEmpty) return '';

    var candidate = sentences.first.trim();
    while (candidate.endsWith('.') || candidate.endsWith('!') || candidate.endsWith('?')) {
      candidate = candidate.substring(0, candidate.length - 1).trim();
    }

    // 6. Проверка длины: смысловое определение для викторины должно быть от 20 до 90 символов
    if (candidate.length < 20 || candidate.length > 90) {
      return '';
    }

    // 7. Проверка на цифры (в хорошем смысловом определении знака не должно быть случайных цифр)
    if (RegExp(r'\d').hasMatch(candidate)) {
      return '';
    }

    // 8. Проверка на совпадение с названием знака (не спойлерить правильный ответ в вопросе)
    if (target != null) {
      final targetTitleNorm = _normalize(target.title);
      final candidateNorm = _normalize(candidate);
      if (candidateNorm.contains(targetTitleNorm)) {
        return '';
      }
    }

    // 9. Проверка на оборванные предложения
    if (RegExp(r'\b(?:и\s+т|в\s+н|и\s+др)$', caseSensitive: false).hasMatch(candidate)) {
      return '';
    }

    return candidate.isNotEmpty ? '${candidate[0].toUpperCase()}${candidate.substring(1)}' : '';
  }

  /// Извлечение официальной цитаты правил ПДД РФ о назначении знака.
  static String extractOfficialQuote(
    String rawDescription,
    String title, {
    String? signNumber,
  }) {
    if (rawDescription.isEmpty) return title;

    var text = rawDescription
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r', ' ')
        .trim();

    // 1. Отрезаем блок штрафов и наказаний КоАП РФ
    final penaltyMarker = RegExp(
      r'(?:Наказание за нарушение|Наказание:|КоАП РФ|КоАП)',
      caseSensitive: false,
    );
    final match = penaltyMarker.firstMatch(text);
    if (match != null) {
      text = text.substring(0, match.start).trim();
    }

    // 2. Исправляем склеенные предложения
    text = text.replaceAllMapped(
      RegExp(r'(\))\.(?=\p{Lu})', unicode: true),
      (m) => '). ',
    );
    text = text.replaceAllMapped(
      RegExp(r'(?<=[\p{Ll}\w])\.(?=\p{Lu})', unicode: true),
      (m) => '. ',
    );

    // 3. Аккуратное разделение на предложения без разрыва по точкам внутри номеров (8.2.1, 3.27)
    final sentences = _splitSentences(text);
    if (sentences.isNotEmpty) {
      // Если для группы знаков (например, 8.2.1-8.2.6) передан конкретный номер знака,
      // ищем предложение, относящееся именно к нему.
      if (signNumber != null && signNumber.isNotEmpty) {
        final specific = sentences.firstWhere(
          (s) => s.contains(signNumber),
          orElse: () => '',
        );
        if (specific.isNotEmpty && specific.length <= 320) {
          return specific;
        }
      }

      if (sentences.length == 1) {
        return sentences.first;
      }
      // Первые 2 предложения обычно содержат назначение и ключевую зону действия
      final firstTwo = '${sentences[0]} ${sentences[1]}'.trim();
      if (firstTwo.length <= 260) {
        return firstTwo;
      }
      return sentences.first;
    }

    return text.isNotEmpty ? text : title;
  }

  /// Безопасное разделение текста на предложения с защитой десятичных точек в номерах знаков и сокращениях.
  static List<String> _splitSentences(String text) {
    if (text.isEmpty) return const [];

    // Защищаем точки в номерах знаков (например, 8.2.1 -> 8§2§1)
    var protected = text.replaceAllMapped(
      RegExp(r'(?<=\d)\.(?=\d)'),
      (m) => '§',
    );

    // Защищаем распространенные сокращения
    const abbrevs = [
      'н. п.',
      'н.п.',
      'т. е.',
      'т.е.',
      'т. д.',
      'т.д.',
      'т. п.',
      'т.п.',
      'таб.',
      'рис.',
      'см.',
      'г.',
      'руб.',
      'м.',
    ];
    for (final ab in abbrevs) {
      protected = protected.replaceAll(ab, ab.replaceAll('.', '§'));
    }

    final rawSentences = RegExp(r'[^.!?]+[.!?]').allMatches(protected).map((m) => m.group(0)!.trim()).toList();

    return rawSentences
        .map((s) => s.replaceAll('§', '.').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static String _normalize(String text) => text.trim().toLowerCase();
}
