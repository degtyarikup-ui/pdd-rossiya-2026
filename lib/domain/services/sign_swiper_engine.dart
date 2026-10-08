import 'dart:math';
import 'package:pdd_app/data/datasources/sign_scenarios_library.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';

/// Сервис генерации карточек для игры «Знак-Свайпер».
class SignSwiperEngine {
  final List<SignItem> allSigns;
  final Map<String, List<SignItem>> signsByCategory;
  final Random _rnd;

  SignSwiperEngine({
    required this.allSigns,
    Random? random,
  })  : _rnd = random ?? Random(),
        signsByCategory = _groupSignsByCategory(allSigns);

  static Map<String, List<SignItem>> _groupSignsByCategory(List<SignItem> signs) {
    final map = <String, List<SignItem>>{};
    for (final s in signs) {
      map.putIfAbsent(s.category, () => []).add(s);
    }
    return map;
  }

  /// Парсинг сырого словаря `signs.json` в список валидных знаков.
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

  /// Получить список всех доступных категорий.
  List<String> get availableCategories => signsByCategory.keys.toList();

  /// Генерация колоды вопросов.
  /// [categoryFilter] — фильтр по категории (null или «Все» — без фильтра).
  /// [count] — количество вопросов в колоде.
  List<SignCardQuestion> generateDeck({
    String? categoryFilter,
    int count = 25,
  }) {
    final pool = (categoryFilter == null ||
            categoryFilter.isEmpty ||
            categoryFilter == 'Все категории' ||
            !signsByCategory.containsKey(categoryFilter))
        ? allSigns
        : signsByCategory[categoryFilter]!;

    if (pool.isEmpty) return const [];

    final deck = <SignCardQuestion>[];
    final shuffledSigns = List<SignItem>.from(pool)..shuffle(_rnd);

    for (int i = 0; i < count; i++) {
      final sign = shuffledSigns[i % shuffledSigns.length];
      final isTrue = _rnd.nextBool();
      deck.add(_generateCardQuestion(sign, isTrue));
    }

    return deck;
  }

  SignCardQuestion _generateCardQuestion(SignItem sign, bool targetIsTrue) {
    final id = '${sign.number}_${DateTime.now().microsecondsSinceEpoch}_${_rnd.nextInt(10000)}';

    // 1. Попробуем найти точный сценарий конкретного знака
    final signScenarios = SignScenariosLibrary.getScenariosForSign(sign.number);
    if (signScenarios != null && signScenarios.isNotEmpty) {
      final matching = signScenarios.where((s) => s.isCorrect == targetIsTrue).toList();
      if (matching.isNotEmpty) {
        final chosen = matching[_rnd.nextInt(matching.length)];
        return SignCardQuestion(
          id: id,
          sign: sign,
          prompt: chosen.prompt,
          isCorrect: chosen.isCorrect,
          explanation: chosen.explanation,
          type: chosen.type,
        );
      } else {
        // Если нет подходящего по истинности, берем любой доступный для знака
        final chosen = signScenarios[_rnd.nextInt(signScenarios.length)];
        return SignCardQuestion(
          id: id,
          sign: sign,
          prompt: chosen.prompt,
          isCorrect: chosen.isCorrect,
          explanation: chosen.explanation,
          type: chosen.type,
        );
      }
    }

    // 2. Fallback: умный генератор дорожных ситуаций по категории знака
    final fallbackScenario = SignScenariosLibrary.generateCategoryScenario(sign, targetIsTrue, _rnd);
    return SignCardQuestion(
      id: id,
      sign: sign,
      prompt: fallbackScenario.prompt,
      isCorrect: fallbackScenario.isCorrect,
      explanation: fallbackScenario.explanation,
      type: fallbackScenario.type,
    );
  }
}
