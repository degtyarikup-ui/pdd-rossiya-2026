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
    final coreDef = extractCoreDefinition(target.description);
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

    final officialQuote = extractOfficialQuote(target.description, target.title);

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

  /// Алгоритм строгого отбора дистракторов с исключением дублирующихся названий (33 коллизии)
  /// и дублирующихся народных названий.
  List<SignItem> selectDistractors(SignItem target, {required int count}) {
    final targetTitle = _normalize(target.title);
    final targetFolk = target.folkName != null ? _normalize(target.folkName!) : null;

    bool isCandidateValid(SignItem c, List<SignItem> selected) {
      // Исключаем сам целевой знак
      if (c.number == target.number) return false;

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

  /// Формирование текста вопроса по значению/определению.
  static String formatMeaningPrompt(String coreDefinition) {
    var def = coreDefinition.trim();
    if (def.endsWith('.')) {
      def = def.substring(0, def.length - 1).trim();
    }
    return 'Какой из этих знаков означает: «$def»?';
  }

  /// Извлечение краткого смыслового определения знака из первого предложения описания.
  static String extractCoreDefinition(String rawDescription) {
    if (rawDescription.isEmpty) return '';

    var text = rawDescription
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r', '')
        .trim();

    // Отсекаем статьи КоАП и штрафы, если они в описании
    final penaltyIdx = text.indexOf('Наказание');
    if (penaltyIdx != -1) {
      text = text.substring(0, penaltyIdx).trim();
    }
    final koapIdx = text.indexOf('КоАП РФ');
    if (koapIdx != -1) {
      text = text.substring(0, koapIdx).trim();
    }

    // Берём первое предложение (заканчивающееся точкой или переводом строки)
    final match = RegExp(r'^([^.\n]+?\.)(?:\s+|$)').firstMatch(text);
    if (match != null) {
      return match.group(1)!.trim();
    }

    return text.split('\n').first.trim();
  }

  /// Извлечение официальной цитаты правил ПДД РФ о назначении знака.
  static String extractOfficialQuote(String rawDescription, String title) {
    if (rawDescription.isEmpty) return title;

    var text = rawDescription
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r', '')
        .trim();

    // 1. Отрезаем блок штрафов и наказаний КоАП РФ
    final penaltyMarker = RegExp(
      r'(?:Наказание за нарушение|Наказание:|КоАП РФ)',
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

    // 3. Если текст слишком длинный, берём основную часть с назначением знака (первые 1-2 предложения)
    final sentences = RegExp(r'[^.!?]+[.!?]').allMatches(text).map((m) => m.group(0)!.trim()).toList();
    if (sentences.isNotEmpty) {
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

  static String _normalize(String text) => text.trim().toLowerCase();
}
