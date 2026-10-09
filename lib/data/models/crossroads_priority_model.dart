/// Сторона перекрестка, откуда подъезжает транспорт.
enum CrossroadsSide {
  south('Юг'),
  north('Север'),
  east('Восток'),
  west('Запад');

  const CrossroadsSide(this.title);
  final String title;
}

/// Направление движения на перекрестке.
enum CrossroadsManeuver {
  straight('Прямо'),
  right('Направо'),
  left('Налево'),
  uTurn('Разворот');

  const CrossroadsManeuver(this.label);
  final String label;
}

/// Тип транспортного средства.
enum CrossroadsVehicleType {
  car('Легковой автомобиль'),
  tram('Трамвай'),
  emergency('Спецтранспорт с сиреной и маячком'),
  truck('Грузовой автомобиль'),
  suv('Внедорожник'),
  motorcycle('Мотоцикл');

  const CrossroadsVehicleType(this.label);
  final String label;
}

/// Участник дорожного движения на перекрестке.
class CrossroadsActor {
  const CrossroadsActor({
    required this.id,
    required this.type,
    required this.name,
    required this.colorHex,
    required this.side,
    required this.maneuver,
    required this.priorityOrder,
    required this.ruleExplanation,
    this.hasSiren = false,
    this.vehicleModel = 'hatch',
  });

  final String id;
  final CrossroadsVehicleType type;
  final String name;
  final String colorHex;
  final CrossroadsSide side;
  final CrossroadsManeuver maneuver;

  /// Порядковый номер проезда: 1 = первый, 2 = второй, 3 = третий и т.д.
  final int priorityOrder;

  /// Обоснование приоритета по ПДД РФ.
  final String ruleExplanation;

  /// Включены ли проблесковые маячки и сирена (п. 3.2 ПДД).
  final bool hasSiren;

  /// Модель кузова из каталога PDD_VEHICLES (hatch, sedan, suv, coupe, pickup, cyber).
  final String vehicleModel;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'color': colorHex,
    'side': side.name,
    'maneuver': maneuver.name,
    'order': priorityOrder,
    'explanation': ruleExplanation,
    'hasSiren': hasSiren,
    'model': vehicleModel,
  };
}

/// Дорожный знак на перекрестке.
class CrossroadsSignPlacement {
  const CrossroadsSignPlacement({
    required this.code,
    required this.side,
    this.table8_13,
  });

  /// Код знака по ГОСТ: '2.1' (Главная), '2.4' (Уступите), '2.5' (STOP).
  final String code;

  /// Сторона дороги, перед которой установлен знак.
  final CrossroadsSide side;

  /// Направление главной дороги для знака 8.13 ('left', 'right', 'straight_left', etc.).
  final String? table8_13;

  Map<String, dynamic> toJson() => {
    'code': code,
    'side': side.name,
    if (table8_13 != null) 'table8_13': table8_13,
  };
}

/// Сценарий перекрестка.
class CrossroadsScenario {
  const CrossroadsScenario({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.pddArticle,
    required this.actors,
    this.signs = const [],
    this.isEqualCrossroad = false,
    this.trafficLightGreenSides,
  });

  final String id;
  final String title;
  final String subtitle;
  final String pddArticle;
  final List<CrossroadsActor> actors;
  final List<CrossroadsSignPlacement> signs;
  final bool isEqualCrossroad;
  final List<CrossroadsSide>? trafficLightGreenSides;

  /// Список акторов, отсортированных по правильному порядку проезда.
  List<CrossroadsActor> get orderedActors {
    final list = List<CrossroadsActor>.from(actors);
    list.sort((a, b) => a.priorityOrder.compareTo(b.priorityOrder));
    return list;
  }

  /// Возвращает ID автомобиля, который должен проехать следующим на заданном шаге (1-based).
  CrossroadsActor? getActorForStep(int step) {
    for (final a in actors) {
      if (a.priorityOrder == step) return a;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'pddArticle': pddArticle,
    'isEqual': isEqualCrossroad,
    'signs': signs.map((s) => s.toJson()).toList(),
    'actors': actors.map((a) => a.toJson()).toList(),
  };
}

/// Библиотека сертифицированных перекрестков по билетам ГИБДД РФ.
class CrossroadsScenariosLibrary {
  CrossroadsScenariosLibrary._();

  static final List<CrossroadsScenario> allScenarios = [
    // 1. Неравнозначный перекресток с табличкой 8.13 (главная налево, п. 13.10)
    const CrossroadsScenario(
      id: 'cross_main_turns_left',
      title: 'Главная дорога поворачивает налево (знак 8.13)',
      subtitle: 'Водители на главной разъезжаются по помехе справа, затем второстепенные.',
      pddArticle: 'Пункт 13.10 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.south, table8_13: 'left'),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.west, table8_13: 'right'),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.north, table8_13: 'left'),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east, table8_13: 'left'),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Белый седан',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Белый седан на главной дороге и для южного автомобиля является помехой справа. Проезжает первым.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий хэтчбек',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation: 'Синий автомобиль на главной дороге, уступает белому справа и проезжает вторым.',
          vehicleModel: 'hatch',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый кроссовер',
          colorHex: '#4D7768',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'Зеленый на второстепенной дороге. Среди второстепенных у него нет помехи справа от северного.',
          vehicleModel: 'suv',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Оранжевый седан',
          colorHex: '#F08A24',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 4,
          ruleExplanation: 'Оранжевый на второстепенной дороге уступает зеленому кроссоверу справа.',
          vehicleModel: 'sedan',
        ),
      ],
    ),

    // 2. Неравнозначный перекресток: прямая главная дорога (п. 13.9)
    const CrossroadsScenario(
      id: 'cross_main_straight',
      title: 'Главная дорога: прямое направление',
      subtitle: 'Транспорт на главной дороге имеет безусловный приоритет.',
      pddArticle: 'Пункт 13.9 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Синий автомобиль движется по главной дороге прямо.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый внедорожник',
          colorHex: '#4D7768',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation: 'Зеленый внедорожник на главной дороге, но при повороте налево уступает встречному синему (п. 13.12).',
          vehicleModel: 'suv',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек',
          colorHex: '#ED4621',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'Красный автомобиль находится на второстепенной дороге со знаком 2.4 «Уступите дорогу».',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 3. Равнозначный перекресток с помехой справа (п. 13.11)
    const CrossroadsScenario(
      id: 'cross_equal_3_cars',
      title: 'Равнозначный перекресток: 3 автомобиля',
      subtitle: 'При равных условиях уступают помехе справа.',
      pddArticle: 'Пункт 13.11 ПДД РФ',
      isEqualCrossroad: true,
      actors: [
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Желтый седан',
          colorHex: '#F08A24',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'У желтого автомобиля справа нет помехи. Он начинает движение первым.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Синий хэтчбек',
          colorHex: '#317ED4',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'Синий автомобиль уступает желтому справа. После его проезда освобождается.',
          vehicleModel: 'hatch',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый кроссовер',
          colorHex: '#4D7768',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'Зеленый кроссовер имеет помеху справа (синий авто) и проезжает последним.',
          vehicleModel: 'suv',
        ),
      ],
    ),

    // 4. Равнозначный перекресток с трамваем (п. 13.11)
    const CrossroadsScenario(
      id: 'cross_equal_tram',
      title: 'Равнозначный перекресток с трамваем',
      subtitle: 'На равнозначной дороге трамвай всегда имеет преимущество.',
      pddArticle: 'Пункт 13.11 ПДД РФ',
      isEqualCrossroad: true,
      actors: [
        CrossroadsActor(
          id: 'tram_north',
          type: CrossroadsVehicleType.tram,
          name: 'Красный трамвай',
          colorHex: '#ED4621',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'На перекрестке равнозначных дорог трамвай имеет преимущество перед безрельсовыми ТС независимо от направления.',
          vehicleModel: 'tram',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'После трамвая синий автомобиль свободен от помехи справа и проезжает вторым.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Серый хэтчбек',
          colorHex: '#B9C0C7',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'Серый автомобиль уступает трамваю и помехе справа (синему авто).',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 5. Спецтранспорт со спецсигналами (п. 3.2 ПДД)
    const CrossroadsScenario(
      id: 'cross_emergency_priority',
      title: 'Спецтранспорт: скорая помощь с сиреной',
      subtitle: 'Маячок и специальный звуковой сигнал дают безоговорочный приоритет.',
      pddArticle: 'Пункт 3.2 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'ambulance_east',
          type: CrossroadsVehicleType.emergency,
          name: 'Скорая помощь (сирена)',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Автомобиль с включенными проблесковым маячком и специальным звуковым сигналом пользуется преимуществом независимо от знаков!',
          hasSiren: true,
          vehicleModel: 'suv',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан (Главная)',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'После скорой синий автомобиль на главной дороге проезжает вторым.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек (Второстепенная)',
          colorHex: '#ED4621',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'Красный хэтчбек на второстепенной со знаком 2.4 уступает всем.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 6. Неравнозначный перекресток с трамваем на второстепенной дороге (п. 13.9)
    const CrossroadsScenario(
      id: 'cross_tram_on_secondary',
      title: 'Трамвай на второстепенной дороге',
      subtitle: 'Трамвай на второстепенной уступает автомобилям на главной!',
      pddArticle: 'Пункт 13.9 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан (Главная)',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Синий автомобиль движется по главной дороге и имеет приоритет перед трамваем на второстепенной.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'tram_east',
          type: CrossroadsVehicleType.tram,
          name: 'Красный трамвай (Второстепенная)',
          colorHex: '#ED4621',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'Трамвай на второстепенной уступает главной, но имеет преимущество перед желтым автомобилем на той же второстепенной дороге.',
          vehicleModel: 'tram',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Желтый седан (Второстепенная)',
          colorHex: '#F08A24',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'Желтый автомобиль на второстепенной уступает главной дороге и трамваю.',
          vehicleModel: 'sedan',
        ),
      ],
    ),

    // 7. Знак 2.5 «STOP» (п. 2.5 Приложения 1 к ПДД и п. 13.9)
    const CrossroadsScenario(
      id: 'cross_stop_sign',
      title: 'Знак 2.5 «Движение без остановки запрещено»',
      subtitle: 'Обязательная остановка и уступка транспорту по пересекаемой главной дороге.',
      pddArticle: 'Знак 2.5 и п. 13.9 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.west),
        CrossroadsSignPlacement(code: '2.5', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.north),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый внедорожник',
          colorHex: '#4D7768',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Зеленый автомобиль движется по главной дороге прямо.',
          vehicleModel: 'suv',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Белый седан',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'Белый седан на второстепенной проезжает раньше южного авто с учетом помехи справа.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек (Знак STOP)',
          colorHex: '#ED4621',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'Красный автомобиль уступает всем участникам на пересекаемой дороге.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 8. Разворот на равнозначном перекрестке (п. 13.11 и 13.12)
    const CrossroadsScenario(
      id: 'cross_uturn_equal',
      title: 'Разворот на перекрестке',
      subtitle: 'При развороте встречный автомобиль становится помехой справа.',
      pddArticle: 'Пункт 13.12 ПДД РФ',
      isEqualCrossroad: true,
      actors: [
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Синий автомобиль движется прямо. Северный седан при развороте обязан уступить ему.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек (Разворот)',
          colorHex: '#ED4621',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.uTurn,
          priorityOrder: 2,
          ruleExplanation: 'Разворачивающийся автомобиль уступает встречному транспорту.',
          vehicleModel: 'hatch',
        ),
      ],
    ),
  ];
}
