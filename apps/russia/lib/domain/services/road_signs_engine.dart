import 'dart:math';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Сервис генерации вопросов викторины «Знаки» с защитой от коллизий дистракторов.
class RoadSignsEngine {
  final List<SignItem> allSigns;
  final Map<String, List<SignItem>> signsByCategory;
  final Random _rnd;
  final AppLocalizations l10n;

  RoadSignsEngine({
    required this.allSigns,
    Random? random,
    AppLocalizations? l10n,
  }) : _rnd = random ?? Random(),
       l10n = l10n ?? appL10n,
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

    final hasFolk =
        target.folkName != null && target.folkName!.trim().isNotEmpty;
    final coreDef = extractCoreDefinition(
      target.description,
      target: target,
      l10n: l10n,
    );
    final hasMeaning = coreDef.isNotEmpty;

    final roll = _rnd.nextDouble();
    if (hasFolk && roll < 0.30) {
      type = RoadSignQuizType.folkNameMatch;
      prompt = l10n.roadSignsFolkPrompt(target.folkName!.trim());
    } else if (hasMeaning && roll < 0.70) {
      type = RoadSignQuizType.meaningDefinition;
      prompt = formatMeaningPrompt(coreDef, l10n: l10n);
    } else {
      type = RoadSignQuizType.titleMatch;
      prompt = l10n.roadSignsTitlePrompt(target.title.trim());
    }

    final officialQuote = extractOfficialQuote(
      target.description,
      target.title,
      signNumber: target.number,
      lang: l10n.localeName,
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
    final targetFolk = target.folkName != null
        ? _normalize(target.folkName!)
        : null;

    bool isCandidateValid(SignItem c, List<SignItem> selected) {
      // Исключаем сам целевой знак
      if (c.number == target.number) return false;

      // Исключаем одинаковое изображение SVG
      if (c.image.isNotEmpty && c.image == target.image) return false;
      if (c.image.isNotEmpty && selected.any((s) => s.image == c.image)) {
        return false;
      }

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
        if (selected.any(
          (s) => s.folkName != null && _normalize(s.folkName!) == cFolk,
        )) {
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
  static Map<String, String> _curatedMeanings(AppLocalizations l10n) => {
    '2.1': l10n.roadSignsMeaning2_1,
    '2.2': l10n.roadSignsMeaning2_2,
    '2.4': l10n.roadSignsMeaning2_4,
    '2.5': l10n.roadSignsMeaning2_5,
    '2.6': l10n.roadSignsMeaning2_6,
    '2.7': l10n.roadSignsMeaning2_7,
    '3.1': l10n.roadSignsMeaning3_1,
    '3.2': l10n.roadSignsMeaning3_2,
    '3.3': l10n.roadSignsMeaning3_3,
    '3.4': l10n.roadSignsMeaning3_4,
    '3.5': l10n.roadSignsMeaning3_5,
    '3.6': l10n.roadSignsMeaning3_6,
    '3.7': l10n.roadSignsMeaning3_7,
    '3.10': l10n.roadSignsMeaning3_10,
    '3.18.1': l10n.roadSignsMeaning3_18_1,
    '3.18.2': l10n.roadSignsMeaning3_18_2,
    '3.19': l10n.roadSignsMeaning3_19,
    '3.20': l10n.roadSignsMeaning3_20,
    '3.22': l10n.roadSignsMeaning3_22,
    '3.24': l10n.roadSignsMeaning3_24,
    '3.27': l10n.roadSignsMeaning3_27,
    '3.28': l10n.roadSignsMeaning3_28,
    '4.1.1': l10n.roadSignsMeaning4_1_1,
    '4.1.2': l10n.roadSignsMeaning4_1_2,
    '4.1.3': l10n.roadSignsMeaning4_1_3,
    '4.1.4': l10n.roadSignsMeaning4_1_4,
    '4.1.5': l10n.roadSignsMeaning4_1_5,
    '4.1.6': l10n.roadSignsMeaning4_1_6,
    '4.2.1': l10n.roadSignsMeaning4_2_1,
    '4.2.2': l10n.roadSignsMeaning4_2_2,
    '4.2.3': l10n.roadSignsMeaning4_2_3,
    '4.3': l10n.roadSignsMeaning4_3,
    '4.6': l10n.roadSignsMeaning4_6,
    '5.1': l10n.roadSignsMeaning5_1,
    '5.3': l10n.roadSignsMeaning5_3,
    '5.5': l10n.roadSignsMeaning5_5,
    '5.11.1': l10n.roadSignsMeaning5_11_1,
    '5.14.1': l10n.roadSignsMeaning5_14_1,
    '5.19.1': l10n.roadSignsMeaning5_19_1,
    '5.20': l10n.roadSignsMeaning5_20,
    '5.21': l10n.roadSignsMeaning5_21,
    '5.27': l10n.roadSignsMeaning5_27,
    '5.31': l10n.roadSignsMeaning5_31,
    '6.4': l10n.roadSignsMeaning6_4,
    '6.8.1': l10n.roadSignsMeaning6_8_1,
    '6.16': l10n.roadSignsMeaning6_16,
    '8.8': l10n.roadSignsMeaning8_8,
  };

  /// Формирование текста вопроса по значению/определению.
  static String formatMeaningPrompt(
    String coreDefinition, {
    AppLocalizations? l10n,
  }) {
    var def = coreDefinition.trim();
    if (def.endsWith('.')) {
      def = def.substring(0, def.length - 1).trim();
    }
    return (l10n ?? appL10n).roadSignsMeaningPrompt(def);
  }

  /// Извлечение краткого смыслового определения знака.
  /// Возвращает непустую строку только если определение гарантированно краткое (до 90 символов),
  /// не раскрывает номер или название знака, не содержит регламентной шелухи ("устанавливается за 50 м")
  /// и не относится к группе знаков одновременно. При любых сомнениях возвращает пустую строку,
  /// что безопасно переводит вопрос в надежный режим `titleMatch`.
  static String extractCoreDefinition(
    String rawDescription, {
    SignItem? target,
    AppLocalizations? l10n,
  }) {
    final strings = l10n ?? appL10n;
    final meanings = _curatedMeanings(strings);
    if (target != null && meanings.containsKey(target.number)) {
      return meanings[target.number]!;
    }

    // Russian heuristics cannot safely infer a short definition from another
    // language. Use reviewed meanings above or the localized sign title.
    if (strings.localeName != 'ru') return '';

    if (rawDescription.isEmpty) return '';

    var text = rawDescription
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r', ' ')
        .trim();

    // 1. Отсекаем статьи КоАП и штрафы
    final penaltyMarker = _penaltyMarker('ru');
    final pMatch = penaltyMarker.firstMatch(text);
    if (pMatch != null) {
      text = text.substring(0, pMatch.start).trim();
    }

    // 2. Если в тексте упоминаются несколько номеров знаков с точками (например, 8.2.1-8.2.6),
    // это составное описание группы знаков — его категорически нельзя использовать для вопроса.
    final numbersWithDots = RegExp(
      r'\b\d+\.\d+(?:\.\d+)?\b',
    ).allMatches(text).toList();
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
    while (candidate.endsWith('.') ||
        candidate.endsWith('!') ||
        candidate.endsWith('?')) {
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
    if (RegExp(
      r'\b(?:и\s+т|в\s+н|и\s+др)$',
      caseSensitive: false,
    ).hasMatch(candidate)) {
      return '';
    }

    return candidate.isNotEmpty
        ? '${candidate[0].toUpperCase()}${candidate.substring(1)}'
        : '';
  }

  /// Извлечение официальной цитаты правил ПДД РФ о назначении знака.
  static String extractOfficialQuote(
    String rawDescription,
    String title, {
    String? signNumber,
    String lang = 'ru',
  }) {
    if (rawDescription.isEmpty) return title;

    var text = rawDescription
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r', ' ')
        .trim();

    // 1. Отрезаем блок штрафов и наказаний КоАП РФ
    final penaltyMarker = _penaltyMarker(lang);
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

  static RegExp _penaltyMarker(String lang) => RegExp(switch (lang) {
    'en' =>
      r'(?:Punishment for violat|Penalty for violat|Code of Administrative Offen[cs]es)',
    'kk' =>
      r'(?:Белгінің талаптарын бұзғаны үшін жаза|Белгі талаптарын бұзғаны үшін жаза|Ресей Федерациясының Әкімшілік құқық бұзушылық туралы кодексі)',
    _ => r'(?:Наказание за нарушение|Наказание:|КоАП РФ|КоАП|Штраф)',
  }, caseSensitive: false);

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
      'e.g.',
      'i.e.',
      'etc.',
      'т.б.',
      'т. б.',
      'т.с.с.',
    ];
    for (final ab in abbrevs) {
      protected = protected.replaceAll(ab, ab.replaceAll('.', '§'));
    }

    final rawSentences = RegExp(
      r'[^.!?]+(?:[.!?]+|$)',
    ).allMatches(protected).map((m) => m.group(0)!.trim()).toList();

    return rawSentences
        .map((s) => s.replaceAll('§', '.').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static String _normalize(String text) => text.trim().toLowerCase();
}
