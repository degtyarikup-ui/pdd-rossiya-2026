import 'dart:math';
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

    // 1. Проверим, есть ли специальный сценарий ПДД для ключевых знаков
    final ruleQuestion = _tryGenerateRuleQuestion(sign, targetIsTrue, id);
    if (ruleQuestion != null && _rnd.nextDouble() < 0.35) {
      return ruleQuestion;
    }

    // 2. Если есть народное название — иногда спрашиваем его
    if (sign.folkName != null && _rnd.nextDouble() < 0.25) {
      return _generateFolkNameQuestion(sign, targetIsTrue, id);
    }

    // 3. Либо соответствие категории (25% случаев)
    if (_rnd.nextDouble() < 0.25 && signsByCategory.keys.length > 1) {
      return _generateCategoryQuestion(sign, targetIsTrue, id);
    }

    // 4. По умолчанию — соответствие названию знака
    return _generateNameQuestion(sign, targetIsTrue, id);
  }

  SignCardQuestion _generateNameQuestion(SignItem sign, bool isTrue, String id) {
    if (isTrue) {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Этот знак называется «${sign.title}»?',
        isCorrect: true,
        explanation: 'Верно! Это знак ${sign.number} «${sign.title}».',
        type: SignQuestionType.nameMatch,
      );
    } else {
      // Ищем дистрактор — желательно из той же категории
      final categoryPool = signsByCategory[sign.category] ?? allSigns;
      final candidates = categoryPool.where((s) => s.number != sign.number && s.title != sign.title).toList();
      final distractor = candidates.isNotEmpty
          ? candidates[_rnd.nextInt(candidates.length)]
          : allSigns[_rnd.nextInt(allSigns.length)];

      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Этот знак называется «${distractor.title}»?',
        isCorrect: false,
        explanation: 'Неверно. На самом деле это знак ${sign.number} «${sign.title}».',
        type: SignQuestionType.nameMatch,
      );
    }
  }

  SignCardQuestion _generateCategoryQuestion(SignItem sign, bool isTrue, String id) {
    if (isTrue) {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Относится ли этот знак к категории «${sign.category}»?',
        isCorrect: true,
        explanation: 'Верно! Знак ${sign.number} «${sign.title}» входит в категорию «${sign.category}».',
        type: SignQuestionType.categoryMatch,
      );
    } else {
      final otherCats = signsByCategory.keys.where((c) => c != sign.category).toList();
      final wrongCat = otherCats.isNotEmpty ? otherCats[_rnd.nextInt(otherCats.length)] : 'Знаки сервиса';

      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Относится ли этот знак к категории «$wrongCat»?',
        isCorrect: false,
        explanation: 'Неверно. Знак ${sign.number} «${sign.title}» относится к категории «${sign.category}».',
        type: SignQuestionType.categoryMatch,
      );
    }
  }

  SignCardQuestion _generateFolkNameQuestion(SignItem sign, bool isTrue, String id) {
    if (isTrue) {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'В народе этот знак называют «${sign.folkName}»?',
        isCorrect: true,
        explanation: 'Точно так! Знак ${sign.number} «${sign.title}» в обиходе часто называют «${sign.folkName}».',
        type: SignQuestionType.folkNameMatch,
      );
    } else {
      final signsWithFolk = allSigns.where((s) => s.folkName != null && s.folkName != sign.folkName).toList();
      final otherFolk = signsWithFolk.isNotEmpty
          ? signsWithFolk[_rnd.nextInt(signsWithFolk.length)].folkName!
          : 'Кирпич';

      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'В народе этот знак называют «$otherFolk»?',
        isCorrect: false,
        explanation: 'Нет. В народе его называют «${sign.folkName}», а официальное название — «${sign.title}».',
        type: SignQuestionType.folkNameMatch,
      );
    }
  }

  SignCardQuestion? _tryGenerateRuleQuestion(SignItem sign, bool isTrue, String id) {
    final num = sign.number;

    // Знак 2.1 «Главная дорога»
    if (num == '2.1') {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Имеете ли вы преимущество проезда при этом знаке?',
        isCorrect: true,
        explanation: 'Да! Знак 2.1 «Главная дорога» даёт право преимущественного проезда нерегулируемых перекрёстков.',
        type: SignQuestionType.ruleScenario,
      );
    }

    // Знак 2.4 «Уступите дорогу»
    if (num == '2.4') {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Имеете ли вы преимущество проезда при этом знаке?',
        isCorrect: false,
        explanation: 'Нет! Знак 2.4 обязывает уступить дорогу транспортным средствам, движущимся по пересекаемой дороге.',
        type: SignQuestionType.ruleScenario,
      );
    }

    // Знак 2.5 «Движение без остановки запрещено»
    if (num == '2.5') {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Обязаны ли вы остановиться перед знаком или стоп-линией?',
        isCorrect: true,
        explanation: 'Да! Знак 2.5 запрещает движение без обязательной остановки перед стоп-линией или краем проезжей части.',
        type: SignQuestionType.ruleScenario,
      );
    }

    // Знак 3.1 «Въезд запрещен»
    if (num == '3.1') {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Разрешён ли въезд под этот знак?',
        isCorrect: false,
        explanation: 'Нет! Знак 3.1 «Въезд запрещен» («Кирпич») категорически запрещает въезд всех транспортных средств в данном направлении.',
        type: SignQuestionType.ruleScenario,
      );
    }

    // Знак 3.20 «Обгон запрещен»
    if (num == '3.20') {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Разрешён ли обгон всех транспортных средств?',
        isCorrect: false,
        explanation: 'Нет! Знак 3.20 запрещает обгон всех ТС (кроме тихоходных, гужевых повозок, мопедов и двухколёсных мотоциклов).',
        type: SignQuestionType.ruleScenario,
      );
    }

    // Знак 3.27 «Остановка запрещена»
    if (num == '3.27') {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Разрешена ли остановка под этот знак?',
        isCorrect: false,
        explanation: 'Нет! Знак 3.27 запрещает как стоянку, так и любую остановку транспортных средств.',
        type: SignQuestionType.ruleScenario,
      );
    }

    // Знак 3.28 «Стоянка запрещена»
    if (num == '3.28') {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Разрешена ли кратковременная остановка (до 5 мин для посадки)?',
        isCorrect: true,
        explanation: 'Да! Знак 3.28 запрещает стоянку, но разрешает преднамеренную остановку до 5 минут или для посадки/высадки.',
        type: SignQuestionType.ruleScenario,
      );
    }

    // Знак 4.1.1 «Движение прямо»
    if (num == '4.1.1') {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Разрешён ли поворот направо на ближайшем пересечении?',
        isCorrect: false,
        explanation: 'Нет! Предписывающий знак 4.1.1 разрешает движение только прямо.',
        type: SignQuestionType.ruleScenario,
      );
    }

    // Знак 5.1 «Автомагистраль»
    if (num == '5.1') {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Разрешено ли движение пешеходов и тихоходных ТС (<40 км/ч)?',
        isCorrect: false,
        explanation: 'Нет! На автомагистрали запрещено движение пешеходов, велосипедистов и ТС со скоростью менее 40 км/ч.',
        type: SignQuestionType.ruleScenario,
      );
    }

    // Знак 6.4 «Парковка»
    if (num == '6.4') {
      return SignCardQuestion(
        id: id,
        sign: sign,
        prompt: 'Разрешена ли стоянка транспортных средств?',
        isCorrect: true,
        explanation: 'Да! Знак 6.4 обозначает парковочное место (стоянку транспортных средств).',
        type: SignQuestionType.ruleScenario,
      );
    }

    return null;
  }
}
