import 'crossroads_translations.dart';

/// Сторона перекрестка, откуда подъезжает транспорт.
enum CrossroadsSide {
  south('Юг'),
  north('Север'),
  east('Восток'),
  west('Запад');

  const CrossroadsSide(this.title);
  final String title;

  String localizedTitle([String? lang]) => switch (lang) {
    'en' => switch (this) {
      CrossroadsSide.south => 'South',
      CrossroadsSide.north => 'North',
      CrossroadsSide.east => 'East',
      CrossroadsSide.west => 'West',
    },
    'kk' => switch (this) {
      CrossroadsSide.south => 'Оңтүстік',
      CrossroadsSide.north => 'Солтүстік',
      CrossroadsSide.east => 'Шығыс',
      CrossroadsSide.west => 'Батыс',
    },
    _ => title,
  };
}

/// Направление движения на перекрестке.
enum CrossroadsManeuver {
  straight('Прямо'),
  right('Направо'),
  left('Налево'),
  uTurn('Разворот'),
  cross('Переход дороги');

  const CrossroadsManeuver(this.label);
  final String label;

  String localizedLabel([String? lang]) => switch (lang) {
    'en' => switch (this) {
      CrossroadsManeuver.straight => 'Straight',
      CrossroadsManeuver.right => 'Right',
      CrossroadsManeuver.left => 'Left',
      CrossroadsManeuver.uTurn => 'U-turn',
      CrossroadsManeuver.cross => 'Crossing',
    },
    'kk' => switch (this) {
      CrossroadsManeuver.straight => 'Тіке',
      CrossroadsManeuver.right => 'Оңға',
      CrossroadsManeuver.left => 'Солға',
      CrossroadsManeuver.uTurn => 'Кері бұрылу',
      CrossroadsManeuver.cross => 'Жолдан өту',
    },
    _ => label,
  };
}

/// Тип транспортного средства или участника движения.
enum CrossroadsVehicleType {
  car('Легковой автомобиль'),
  tram('Трамвай'),
  emergency('Спецтранспорт с сиреной и маячком'),
  truck('Грузовой автомобиль'),
  suv('Внедорожник'),
  motorcycle('Мотоцикл'),
  bus('Автобус'),
  police('Полиция (ДПС)'),
  pedestrian('Пешеход');

  const CrossroadsVehicleType(this.label);
  final String label;

  String localizedLabel([String? lang]) => switch (lang) {
    'en' => switch (this) {
      CrossroadsVehicleType.car => 'Car',
      CrossroadsVehicleType.tram => 'Tram',
      CrossroadsVehicleType.emergency => 'Emergency vehicle with siren',
      CrossroadsVehicleType.truck => 'Truck',
      CrossroadsVehicleType.suv => 'SUV',
      CrossroadsVehicleType.motorcycle => 'Motorcycle',
      CrossroadsVehicleType.bus => 'Bus',
      CrossroadsVehicleType.police => 'Police',
      CrossroadsVehicleType.pedestrian => 'Pedestrian',
    },
    'kk' => switch (this) {
      CrossroadsVehicleType.car => 'Жеңіл автокөлік',
      CrossroadsVehicleType.tram => 'Трамвай',
      CrossroadsVehicleType.emergency => 'Сиренасы бар арнайы көлік',
      CrossroadsVehicleType.truck => 'Жүк көлігі',
      CrossroadsVehicleType.suv => 'Жол талғамайтын көлік',
      CrossroadsVehicleType.motorcycle => 'Мотоцикл',
      CrossroadsVehicleType.bus => 'Автобус',
      CrossroadsVehicleType.police => 'Полиция',
      CrossroadsVehicleType.pedestrian => 'Жаяу жүргінші',
    },
    _ => label,
  };
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

  CrossroadsActor copyWith({
    String? id,
    CrossroadsVehicleType? type,
    String? name,
    String? colorHex,
    CrossroadsSide? side,
    CrossroadsManeuver? maneuver,
    int? priorityOrder,
    String? ruleExplanation,
    bool? hasSiren,
    String? vehicleModel,
  }) => CrossroadsActor(
    id: id ?? this.id,
    type: type ?? this.type,
    name: name ?? this.name,
    colorHex: colorHex ?? this.colorHex,
    side: side ?? this.side,
    maneuver: maneuver ?? this.maneuver,
    priorityOrder: priorityOrder ?? this.priorityOrder,
    ruleExplanation: ruleExplanation ?? this.ruleExplanation,
    hasSiren: hasSiren ?? this.hasSiren,
    vehicleModel: vehicleModel ?? this.vehicleModel,
  );
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

/// Конфигурация светофора на подъезде к перекрестку.
class CrossroadsTrafficLight {
  const CrossroadsTrafficLight({
    required this.side,
    this.state = 'red',
    this.arrow,
    this.arrowActive = false,
  });

  /// Сторона перекрестка, перед которой установлен светофор.
  final CrossroadsSide side;

  /// Основной сигнал светофора: 'green', 'red', 'yellow', 'flashing_yellow'.
  final String state;

  /// Дополнительная секция: 'right', 'left', null.
  final String? arrow;

  /// Горит ли дополнительная секция в текущей фазе.
  final bool arrowActive;

  Map<String, dynamic> toJson() => {
    'side': side.name,
    'state': state,
    if (arrow != null) 'arrow': arrow,
    if (arrowActive) 'arrowActive': arrowActive,
  };
}

/// Категория перекрестка для фильтрации.
enum CrossroadsCategory {
  all('Все'),
  prioritySigns('Знаки приоритета'),
  trafficLights('Светофоры'),
  hardSituations('Сложные ситуации');

  const CrossroadsCategory(this.title);
  final String title;
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
    this.trafficLights,
    this.trafficLightGreenSides,
    this.closedSide,
    this.isHardSituation = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String pddArticle;
  final List<CrossroadsActor> actors;
  final List<CrossroadsSignPlacement> signs;
  final bool isEqualCrossroad;
  final List<CrossroadsTrafficLight>? trafficLights;
  final List<CrossroadsSide>? trafficLightGreenSides;

  /// Т-образный перекрёсток: этой стороны нет (знаки 2.3.2, 2.3.3).
  final CrossroadsSide? closedSide;

  /// Является ли ситуация сложной (повышенные очки 3×, пешеходы/комплексный разъезд).
  final bool isHardSituation;

  /// Регулируемый ли перекрёсток со светофорами.
  bool get isRegulated => trafficLights != null && trafficLights!.isNotEmpty;

  /// Категория перекрестка.
  CrossroadsCategory get category {
    if (isHardSituation) return CrossroadsCategory.hardSituations;
    return isRegulated
        ? CrossroadsCategory.trafficLights
        : CrossroadsCategory.prioritySigns;
  }

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
    'isHard': isHardSituation,
    if (closedSide != null) 'closedSide': closedSide!.name,
    'signs': signs.map((s) => s.toJson()).toList(),
    'actors': actors.map((a) => a.toJson()).toList(),
    if (trafficLights != null)
      'trafficLights': trafficLights!.map((t) => t.toJson()).toList(),
  };

  CrossroadsScenario copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? pddArticle,
    List<CrossroadsActor>? actors,
    List<CrossroadsSignPlacement>? signs,
    bool? isEqualCrossroad,
    List<CrossroadsTrafficLight>? trafficLights,
    List<CrossroadsSide>? trafficLightGreenSides,
    CrossroadsSide? closedSide,
    bool? isHardSituation,
  }) => CrossroadsScenario(
    id: id ?? this.id,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    pddArticle: pddArticle ?? this.pddArticle,
    actors: actors ?? this.actors,
    signs: signs ?? this.signs,
    isEqualCrossroad: isEqualCrossroad ?? this.isEqualCrossroad,
    trafficLights: trafficLights ?? this.trafficLights,
    trafficLightGreenSides:
        trafficLightGreenSides ?? this.trafficLightGreenSides,
    closedSide: closedSide ?? this.closedSide,
    isHardSituation: isHardSituation ?? this.isHardSituation,
  );
}

/// Библиотека сертифицированных перекрестков по билетам ГИБДД РФ.
class CrossroadsScenariosLibrary {
  CrossroadsScenariosLibrary._();

  static List<CrossroadsScenario> getScenarios([String? lang]) {
    if (lang == null || lang == 'ru') return allScenarios;
    final localizedMap = CrossroadsTranslations.localizedScenarios[lang];
    if (localizedMap == null) return allScenarios;
    return allScenarios.map((sc) {
      final locSc = localizedMap[sc.id];
      if (locSc == null) return sc;
      final newActors = sc.actors.map((actor) {
        final locActor = locSc.actors[actor.id];
        if (locActor == null) return actor;
        return actor.copyWith(
          name: locActor.name,
          ruleExplanation: locActor.ruleExplanation,
        );
      }).toList();
      return sc.copyWith(
        title: locSc.title,
        subtitle: locSc.subtitle,
        pddArticle: locSc.pddArticle,
        actors: newActors,
      );
    }).toList();
  }

  static final List<CrossroadsScenario> allScenarios = [
    // 1. Неравнозначный перекресток с табличкой 8.13 (главная налево, п. 13.10)
    const CrossroadsScenario(
      id: 'cross_main_turns_left',
      title: 'Главная дорога поворачивает налево (знак 8.13)',
      subtitle:
          'Сначала проезжают машины на главной, между собой — по помехе справа. Затем второстепенные.',
      pddArticle: 'Пункт 13.10 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(
          code: '2.1',
          side: CrossroadsSide.south,
          table8_13: 'bottom_left',
        ),
        CrossroadsSignPlacement(
          code: '2.1',
          side: CrossroadsSide.west,
          table8_13: 'bottom_right',
        ),
        CrossroadsSignPlacement(
          code: '2.4',
          side: CrossroadsSide.north,
          table8_13: 'top_right',
        ),
        CrossroadsSignPlacement(
          code: '2.4',
          side: CrossroadsSide.east,
          table8_13: 'left_top',
        ),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий хэтчбек',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 1,
          ruleExplanation:
              'Синий на главной дороге. Для белого седана он помеха справа, поэтому проезжает первым.',
          vehicleModel: 'hatch',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Белый седан',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation:
              'Белый тоже на главной, но справа от него синий хэтчбек. Уступает ему и проезжает вторым.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Оранжевый седан',
          colorHex: '#F08A24',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'Оранжевый на второстепенной: пропускает главную. Справа от него никого — едет третьим.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый кроссовер',
          colorHex: '#4D7768',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 4,
          ruleExplanation:
              'Зеленый на второстепенной, и справа от него оранжевый седан. Проезжает последним.',
          vehicleModel: 'suv',
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
        CrossroadsSignPlacement(code: '4.1.4', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.east),
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
          ruleExplanation:
              'Зеленый внедорожник на главной дороге, но при повороте налево уступает встречному синему (п. 13.12).',
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
          ruleExplanation:
              'Красный автомобиль находится на второстепенной дороге со знаком 2.4 «Уступите дорогу».',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 3. Равнозначный перекресток с помехой справа (п. 13.11)
    const CrossroadsScenario(
      id: 'cross_equal_3_cars',
      title: 'Равнозначный перекресток: 3 автомобиля',
      subtitle: 'Знаков нет: каждый уступает тому, кто приближается справа.',
      pddArticle: 'Пункт 13.11 ПДД РФ',
      isEqualCrossroad: true,
      actors: [
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый кроссовер',
          colorHex: '#4D7768',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Справа от зеленого кроссовера никого нет — он проезжает первым.',
          vehicleModel: 'suv',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Синий хэтчбек',
          colorHex: '#317ED4',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation:
              'Справа от синего был зеленый кроссовер. Когда тот проехал, синий свободен.',
          vehicleModel: 'hatch',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Желтый седан',
          colorHex: '#F08A24',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'Справа от желтого — синий хэтчбек. Желтый уступает и проезжает последним.',
          vehicleModel: 'sedan',
        ),
      ],
    ),

    // 4. Равнозначный перекресток с трамваем (п. 13.11)
    const CrossroadsScenario(
      id: 'cross_equal_tram',
      title: 'Равнозначный перекресток с трамваем',
      subtitle:
          'На равнозначном перекрестке трамвай проезжает раньше автомобилей.',
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
          ruleExplanation:
              'На перекрестке равнозначных дорог трамвай имеет преимущество перед безрельсовыми ТС независимо от направления.',
          vehicleModel: 'tram',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Серый хэтчбек',
          colorHex: '#B9C0C7',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation:
              'Серый поворачивает налево и пропускает трамвай. Справа от него никого — он второй.',
          vehicleModel: 'hatch',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'Справа от синего седана — серый хэтчбек. Синий уступает ему и проезжает последним.',
          vehicleModel: 'sedan',
        ),
      ],
    ),

    // 5. Спецтранспорт со спецсигналами (п. 3.2 ПДД)
    const CrossroadsScenario(
      id: 'cross_emergency_priority',
      title: 'Спецтранспорт: скорая помощь с сиреной',
      subtitle:
          'Маячок и специальный звуковой сигнал дают безоговорочный приоритет.',
      pddArticle: 'Пункт 3.2 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '5.15.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.north),
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
          ruleExplanation:
              'Автомобиль с включенными проблесковым маячком и специальным звуковым сигналом пользуется преимуществом независимо от знаков!',
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
          ruleExplanation:
              'После скорой синий автомобиль на главной дороге проезжает вторым.',
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
          ruleExplanation:
              'Красный хэтчбек на второстепенной со знаком 2.4 уступает всем.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 6. Неравнозначный перекресток с трамваем на второстепенной дороге (п. 13.9)
    const CrossroadsScenario(
      id: 'cross_tram_on_secondary',
      title: 'Трамвай на второстепенной дороге',
      subtitle: 'Трамвай на второстепенной уступает автомобилям на главной.',
      pddArticle: 'Пункты 13.9 и 13.12 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан (главная)',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Синий автомобиль на главной дороге — он проезжает раньше трамвая на второстепенной.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'tram_east',
          type: CrossroadsVehicleType.tram,
          name: 'Красный трамвай (второстепенная)',
          colorHex: '#ED4621',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation:
              'Трамвай на второстепенной пропускает главную. Встречный желтый поворачивает налево и уступает трамваю.',
          vehicleModel: 'tram',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Желтый седан (второстепенная)',
          colorHex: '#F08A24',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 3,
          ruleExplanation:
              'Желтый на второстепенной, а поворачивая налево, уступает и встречному трамваю.',
          vehicleModel: 'sedan',
        ),
      ],
    ),

    // 7. Знак 2.5 «STOP» (п. 2.5 Приложения 1 к ПДД и п. 13.9)
    const CrossroadsScenario(
      id: 'cross_stop_sign',
      title: 'Знак 2.5 «Движение без остановки запрещено»',
      subtitle:
          'Перед знаком STOP нужно остановиться и уступить транспорту на пересекаемой дороге.',
      pddArticle: 'Знак 2.5, пункты 13.9 и 13.12 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '5.15.2', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.west),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.west),
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
          ruleExplanation: 'Зеленый внедорожник едет по главной дороге прямо.',
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
          ruleExplanation:
              'Белый седан на второстепенной пропускает главную и едет прямо.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек (знак STOP)',
          colorHex: '#ED4621',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 3,
          ruleExplanation:
              'Красный остановился у знака STOP, пропускает главную, а при повороте налево — встречный белый седан.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 8. Разворот на равнозначном перекрестке (п. 13.11 и 13.12)
    const CrossroadsScenario(
      id: 'cross_uturn_equal',
      title: 'Разворот на перекрестке',
      subtitle:
          'При развороте водитель уступает встречным машинам, которые едут прямо или направо.',
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
          ruleExplanation:
              'Синий автомобиль движется прямо. Северный седан при развороте обязан уступить ему.',
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
          ruleExplanation:
              'Разворачивающийся автомобиль уступает встречному транспорту.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 9. Неравнозначный перекресток: главная поворачивает направо (п. 13.10)
    const CrossroadsScenario(
      id: 'cross_main_turns_right',
      title: 'Главная дорога поворачивает направо (знак 8.13)',
      subtitle:
          'Сначала проезжают машины на главной, между собой — по помехе справа. Затем второстепенные.',
      pddArticle: 'Пункт 13.10 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(
          code: '2.1',
          side: CrossroadsSide.south,
          table8_13: 'bottom_right',
        ),
        CrossroadsSignPlacement(
          code: '2.1',
          side: CrossroadsSide.east,
          table8_13: 'bottom_left',
        ),
        CrossroadsSignPlacement(
          code: '2.4',
          side: CrossroadsSide.north,
          table8_13: 'left_top',
        ),
        CrossroadsSignPlacement(
          code: '2.4',
          side: CrossroadsSide.west,
          table8_13: 'top_right',
        ),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 1,
          ruleExplanation:
              'Синий на главной поворачивает налево, вдоль главной. Для автобуса он помеха справа — едет первым.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'bus_south',
          type: CrossroadsVehicleType.bus,
          name: 'Рейсовый автобус',
          colorHex: '#F08A24',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation:
              'Автобус тоже на главной, но справа от него синий седан. Уступает и проезжает вторым.',
          vehicleModel: 'bus',
        ),
        CrossroadsActor(
          id: 'truck_west',
          type: CrossroadsVehicleType.truck,
          name: 'Белый грузовик',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'Грузовик на второстепенной пропускает главную. Справа от него уже никого — он третий.',
          vehicleModel: 'truck',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек',
          colorHex: '#ED4621',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 4,
          ruleExplanation:
              'Красный на второстепенной, и справа от него белый грузовик. Проезжает последним.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 11. ДПС со спецсигналами и трамвай (п. 3.2 и 13.11)
    const CrossroadsScenario(
      id: 'cross_police_vs_tram',
      title: 'Патруль ДПС со спецсигналами и трамвай',
      subtitle:
          'Автомобиль оперативной службы с маячком и сиреной имеет преимущество даже перед трамваем.',
      pddArticle: 'Пункты 3.2 и 13.11 ПДД РФ',
      isEqualCrossroad: true,
      actors: [
        CrossroadsActor(
          id: 'police_south',
          type: CrossroadsVehicleType.police,
          name: 'Патруль ДПС (сирена)',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Автомобиль со включенными проблесковыми маячками и сиреной пользуется преимуществом перед всеми участниками, включая трамвай (п. 3.2).',
          hasSiren: true,
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'tram_east',
          type: CrossroadsVehicleType.tram,
          name: 'Красный трамвай',
          colorHex: '#ED4621',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation:
              'На равнозначном перекрестке трамвай имеет преимущество перед обычными автомобилями и едет вторым.',
          vehicleModel: 'tram',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Синий хэтчбек',
          colorHex: '#317ED4',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'Синий автомобиль уступает спецтранспорту ДПС и трамваю.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 12. Пересечение со второстепенной дорогой (знак 2.3.1 и п. 13.12)
    const CrossroadsScenario(
      id: 'cross_junction_2_3_1',
      title: 'Пересечение со второстепенной дорогой (знак 2.3.1)',
      subtitle:
          'Главная асфальтированная дорога пересекается с сельской грунтовой (знак 2.3.1).',
      pddArticle: 'Знак 2.3.1, пп. 1.2, 13.9, 13.12 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.3.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '5.15.2', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.3.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'moto_south',
          type: CrossroadsVehicleType.motorcycle,
          name: 'Спортивный мотоцикл',
          colorHex: '#ED4621',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Мотоцикл движется прямо по главной дороге и имеет приоритет (знак 2.3.1, п. 1.2).',
          vehicleModel: 'motorcycle',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation:
              'Седан на главной дороге поворачивает налево и уступает встречному мотоциклу (п. 13.12).',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'truck_west',
          type: CrossroadsVehicleType.truck,
          name: 'Серый грузовик',
          colorHex: '#8C929A',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'Грузовик на сельской грунтовой дороге со знаком 2.4 пропускает транспорт главной дороги (пп. 1.2, 13.9).',
          vehicleModel: 'truck',
        ),
      ],
    ),

    // 13. Примыкание второстепенной дороги справа (знак 2.3.2)
    const CrossroadsScenario(
      id: 'cross_junction_right_2_3_2',
      title: 'Примыкание второстепенной дороги справа (знак 2.3.2)',
      subtitle:
          'Главная асфальтированная дорога идет прямо, справа примыкает сельская грунтовая (знак 2.3.2).',
      pddArticle: 'Знак 2.3.2, пп. 1.2, 13.9 ПДД РФ',
      closedSide: CrossroadsSide.west,
      signs: [
        CrossroadsSignPlacement(code: '2.3.2', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.3.3', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
      ],
      actors: [
        CrossroadsActor(
          id: 'suv_south',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый кроссовер (главная)',
          colorHex: '#4D7768',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Кроссовер едет по главной асфальтированной дороге прямо (знак 2.3.2, п. 1.2).',
          vehicleModel: 'suv',
        ),
        CrossroadsActor(
          id: 'truck_east',
          type: CrossroadsVehicleType.truck,
          name: 'Бортовой грузовик (грунтовка)',
          colorHex: '#D7AA60',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation:
              'Грузовик выезжает с грунтовой сельской дороги (знак 2.4) и пропускает кроссовер на главной (пп. 1.2, 13.9).',
          vehicleModel: 'truck',
        ),
      ],
    ),

    // 14. Конец главной дороги (знаки 2.2 и 2.4)
    const CrossroadsScenario(
      id: 'cross_end_of_main_2_2',
      title: 'Конец главной дороги (знаки 2.2 и 2.4)',
      subtitle:
          'После знака 2.2 главная кончилась: на перекрестке со знаком 2.4 нужно уступить.',
      pddArticle: 'Знаки 2.2, 2.4 и пункт 13.9 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.2', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.suv,
          name: 'Черный внедорожник (главная)',
          colorHex: '#2B2F36',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Внедорожник едет по главной дороге прямо (знак 2.1).',
          vehicleModel: 'suv',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Синее купе (главная)',
          colorHex: '#317ED4',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation:
              'Купе на главной при повороте налево уступает встречному внедорожнику (п. 13.12).',
          vehicleModel: 'coupe',
        ),
        CrossroadsActor(
          id: 'bus_south',
          type: CrossroadsVehicleType.bus,
          name: 'Городской автобус',
          colorHex: '#F08A24',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'Для автобуса главная кончилась (знак 2.2), перед перекрестком знак 2.4 — он уступает обоим.',
          vehicleModel: 'bus',
        ),
      ],
    ),

    // 15. Предписывающий знак 4.1.1 «Движение прямо»
    const CrossroadsScenario(
      id: 'cross_mandatory_4_1_1',
      title: 'Предписывающий знак 4.1.1 «Движение прямо»',
      subtitle:
          'С южной стороны можно ехать только прямо. Порядок — по знакам приоритета.',
      pddArticle: 'Знак 4.1.1, пункты 13.9 и 13.12 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'bus_south',
          type: CrossroadsVehicleType.bus,
          name: 'Автобус (главная, прямо)',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Автобус на главной едет прямо, как велит знак 4.1.1.',
          vehicleModel: 'bus',
        ),
        CrossroadsActor(
          id: 'truck_north',
          type: CrossroadsVehicleType.truck,
          name: 'Белый грузовик (главная)',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation:
              'Грузовик на главной поворачивает налево и уступает встречному автобусу (п. 13.12).',
          vehicleModel: 'truck',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек (второстепенная)',
          colorHex: '#ED4621',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'Красный хэтчбек со знаком 2.4 пропускает обоих на главной.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 16. Примыкание второстепенной дороги слева (знак 2.3.3)
    const CrossroadsScenario(
      id: 'cross_junction_left_2_3_3',
      title: 'Примыкание второстепенной дороги слева (знак 2.3.3)',
      subtitle:
          'Главная асфальтированная дорога идет прямо, слева примыкает сельская грунтовая (знак 2.3.3).',
      pddArticle: 'Знак 2.3.3, пп. 1.2, 13.9 ПДД РФ',
      closedSide: CrossroadsSide.east,
      signs: [
        CrossroadsSignPlacement(code: '2.3.3', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.3.2', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Желтый седан (главная)',
          colorHex: '#E8C547',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Седан едет прямо по главной асфальтированной дороге (знак 2.3.3, п. 1.2).',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'truck_west',
          type: CrossroadsVehicleType.truck,
          name: 'Грузовой фургон (грунтовка)',
          colorHex: '#2B2F36',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation:
              'Фургон выезжает с грунтовой сельской дороги (знак 2.4) и пропускает транспорт на главной (пп. 1.2, 13.9).',
          vehicleModel: 'truck',
        ),
      ],
    ),

    // 17. Поворот налево: встречный разъезд (п. 13.12)
    const CrossroadsScenario(
      id: 'cross_truck_left_turn',
      title: 'Поворот налево: разъезд со встречным транспортом',
      subtitle:
          'При повороте налево водитель обязан уступить встречному ТС, движущемуся прямо.',
      pddArticle: 'Пункт 13.12 ПДД РФ',
      isEqualCrossroad: true,
      signs: [
        CrossroadsSignPlacement(code: '1.6', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '1.6', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.north),
      ],
      actors: [
        CrossroadsActor(
          id: 'moto_north',
          type: CrossroadsVehicleType.motorcycle,
          name: 'Красный мотоцикл',
          colorHex: '#ED4621',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Мотоцикл движется со встречного направления прямо и не имеет помехи справа.',
          vehicleModel: 'motorcycle',
        ),
        CrossroadsActor(
          id: 'truck_south',
          type: CrossroadsVehicleType.truck,
          name: 'Оранжевый самосвал',
          colorHex: '#F08A24',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation:
              'Самосвал поворачивает налево и обязан уступить дорогу встречному мотоциклу (п. 13.12).',
          vehicleModel: 'truck',
        ),
      ],
    ),

    // 18. Два трамвая и автомобили на равнозначном перекрестке (п. 13.11)
    const CrossroadsScenario(
      id: 'cross_two_trams_and_cars',
      title: 'Два трамвая и автомобили на равнозначном перекрестке',
      subtitle:
          'Трамваи проезжают раньше автомобилей, между собой — по помехе справа.',
      pddArticle: 'Пункт 13.11 ПДД РФ',
      isEqualCrossroad: true,
      actors: [
        CrossroadsActor(
          id: 'tram_north',
          type: CrossroadsVehicleType.tram,
          name: 'Трамвай №1 (север)',
          colorHex: '#ED4621',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Трамваи проезжают раньше автомобилей. Справа от трамвая №1 никого — он первый.',
          vehicleModel: 'tram',
        ),
        CrossroadsActor(
          id: 'tram_east',
          type: CrossroadsVehicleType.tram,
          name: 'Трамвай №2 (восток)',
          colorHex: '#ED4621',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation:
              'Справа от трамвая №2 — трамвай №1. Он уступает ему и проезжает вторым.',
          vehicleModel: 'tram',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Белый седан',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'После трамваев у белого седана справа никого — он третий.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый кроссовер',
          colorHex: '#4D7768',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 4,
          ruleExplanation:
              'Справа от зеленого кроссовера — белый седан. Проезжает последним.',
          vehicleModel: 'suv',
        ),
      ],
    ),

    // 18. Дополнительная секция со стрелкой направо при красном сигнале (п. 13.5 ПДД РФ)
    const CrossroadsScenario(
      id: 'cross_tl_arrow_vs_main_13_5',
      title: 'Зелёная стрелка с красным сигналом (п. 13.5)',
      subtitle:
          'Движущийся по стрелке при красном сигнале обязан уступить тем, кто едет с других направлений.',
      pddArticle: 'Пункт 13.5 ПДД РФ',
      trafficLights: [
        CrossroadsTrafficLight(side: CrossroadsSide.north, state: 'green'),
        CrossroadsTrafficLight(side: CrossroadsSide.south, state: 'green'),
        CrossroadsTrafficLight(
          side: CrossroadsSide.west,
          state: 'red',
          arrow: 'right',
          arrowActive: true,
        ),
        CrossroadsTrafficLight(side: CrossroadsSide.east, state: 'red'),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Синий седан едет на основной зелёный сигнал светофора и имеет полное преимущество.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Белый хэтчбек',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.right,
          priorityOrder: 2,
          ruleExplanation:
              'Белый хэтчбек поворачивает по стрелке при красном сигнале и обязан уступить синему седану (п. 13.5).',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 19. Трамвай по стрелке при красном сигнале уступает автомобилю на зелёный (п. 13.6 ПДД РФ)
    const CrossroadsScenario(
      id: 'cross_tl_tram_on_arrow_13_6',
      title: 'Трамвай на стрелку с красным сигналом (п. 13.6)',
      subtitle:
          'Трамвай на стрелку при красном сигнале уступает безрельсовому транспорту на основной зелёный.',
      pddArticle: 'Пункт 13.6 ПДД РФ',
      trafficLights: [
        CrossroadsTrafficLight(side: CrossroadsSide.south, state: 'green'),
        CrossroadsTrafficLight(side: CrossroadsSide.north, state: 'green'),
        CrossroadsTrafficLight(
          side: CrossroadsSide.east,
          state: 'red',
          arrow: 'right',
          arrowActive: true,
        ),
        CrossroadsTrafficLight(side: CrossroadsSide.west, state: 'red'),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий хэтчбек',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Синий хэтчбек едет на основной зелёный сигнал светофора прямо и проезжает первым.',
          vehicleModel: 'hatch',
        ),
        CrossroadsActor(
          id: 'tram_east',
          type: CrossroadsVehicleType.tram,
          name: 'Трамвай',
          colorHex: '#ED4621',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.right,
          priorityOrder: 2,
          ruleExplanation:
              'Трамвай движется по стрелке при красном сигнале и обязан уступить автомобилю на основной зелёный (п. 13.6).',
          vehicleModel: 'tram',
        ),
      ],
    ),

    // 20. Поворот налево на регулируемом перекрестке (п. 13.4 ПДД РФ)
    const CrossroadsScenario(
      id: 'cross_tl_left_turn_13_4',
      title: 'Поворот налево на зелёный сигнал (п. 13.4)',
      subtitle:
          'При повороте налево на зелёный водитель обязан уступить встречным, едущим прямо или направо.',
      pddArticle: 'Пункт 13.4 ПДД РФ',
      trafficLights: [
        CrossroadsTrafficLight(side: CrossroadsSide.north, state: 'green'),
        CrossroadsTrafficLight(side: CrossroadsSide.south, state: 'green'),
        CrossroadsTrafficLight(side: CrossroadsSide.east, state: 'red'),
        CrossroadsTrafficLight(side: CrossroadsSide.west, state: 'red'),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Белый седан',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Белый седан движется на зелёный сигнал прямо со встречного направления и имеет преимущество.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Оранжевый седан',
          colorHex: '#F08A24',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation:
              'Оранжевый поворачивает налево по зелёному сигналу и уступает встречному прямо (п. 13.4).',
          vehicleModel: 'sedan',
        ),
      ],
    ),

    // 21. Светофор и знаки приоритета (п. 13.3, 6.15 ПДД РФ)
    const CrossroadsScenario(
      id: 'cross_tl_vs_priority_signs_13_3',
      title: 'Светофор и знаки приоритета (п. 13.3, 6.15)',
      subtitle:
          'Работающий светофор отменяет действие знаков приоритета. Водители руководствуются только светофором.',
      pddArticle: 'Пункты 13.3 и 6.15 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.west),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.east),
      ],
      trafficLights: [
        CrossroadsTrafficLight(side: CrossroadsSide.south, state: 'green'),
        CrossroadsTrafficLight(side: CrossroadsSide.north, state: 'green'),
        CrossroadsTrafficLight(side: CrossroadsSide.west, state: 'red'),
        CrossroadsTrafficLight(side: CrossroadsSide.east, state: 'red'),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий хэтчбек',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Горит зелёный сигнал светофора — знак "Уступите дорогу" не действует (п. 6.15). Синий едет прямо первым.',
          vehicleModel: 'hatch',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый кроссовер',
          colorHex: '#4D7768',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation:
              'Зелёный кроссовер поворачивает налево на свой зелёный и уступает встречному синему (п. 13.4).',
          vehicleModel: 'suv',
        ),
      ],
    ),

    // 22. Спецтранспорт со спецсигналами на регулируемом перекрестке (п. 3.2 ПДД РФ)
    const CrossroadsScenario(
      id: 'cross_tl_emergency_on_red_3_2',
      title: 'Спецтранспорт на регулируемом перекрёстке (п. 3.2)',
      subtitle:
          'Автомобили со включённым синим маячком и сиреной пользуются приоритетом независимо от сигналов светофора.',
      pddArticle: 'Пункт 3.2 ПДД РФ',
      trafficLights: [
        CrossroadsTrafficLight(side: CrossroadsSide.south, state: 'green'),
        CrossroadsTrafficLight(side: CrossroadsSide.north, state: 'green'),
        CrossroadsTrafficLight(side: CrossroadsSide.east, state: 'red'),
        CrossroadsTrafficLight(side: CrossroadsSide.west, state: 'red'),
      ],
      actors: [
        CrossroadsActor(
          id: 'ambulance_east',
          type: CrossroadsVehicleType.emergency,
          name: 'Скорая помощь',
          colorHex: '#FFFFFF',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Скорая помощь с включёнными маячками и сиреной пользуется приоритетом независимо от сигнала светофора (п. 3.2).',
          hasSiren: true,
          vehicleModel: 'ambulance',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий хэтчбек',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation:
              'Синий хэтчбек уступает скорой помощи (п. 3.2), после чего проезжает прямо на свой зелёный сигнал.',
          vehicleModel: 'hatch',
        ),
        CrossroadsActor(
          id: 'car_north',
          type: CrossroadsVehicleType.car,
          name: 'Белый седан',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 3,
          ruleExplanation:
              'Белый седан уступает скорой помощи и встречному синему автомобилю при повороте налево (п. 13.4).',
          vehicleModel: 'sedan',
        ),
      ],
    ),
    // --- Сложные ситуации со специальными условиями и пешеходами ---
    const CrossroadsScenario(
      id: 'hard_traffic_light_arrow_pedestrian',
      title: 'Стрелка светофора и пешеходный переход',
      subtitle:
          'Поворот на стрелку с основным красным и обязанность уступить пешеходу.',
      pddArticle: 'Пункты 13.1 и 13.5 ПДД РФ',
      isHardSituation: true,
      trafficLights: [
        CrossroadsTrafficLight(side: CrossroadsSide.west, state: 'green'),
        CrossroadsTrafficLight(
          side: CrossroadsSide.south,
          state: 'red',
          arrow: 'right',
          arrowActive: true,
        ),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Синий седан движется на основной зеленый сигнал светофора и имеет приоритет перед ТС на стрелку (п. 13.5).',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'pedestrian_east',
          type: CrossroadsVehicleType.pedestrian,
          name: 'Пешеход',
          colorHex: '#2E5B88',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.cross,
          priorityOrder: 2,
          ruleExplanation:
              'Пешеход переходит проезжую часть на разрешающий сигнал. Поворачивающий водитель обязан уступить ему дорогу (п. 13.1).',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Белый хэтчбек',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.right,
          priorityOrder: 3,
          ruleExplanation:
              'Белый хэтчбек поворачивает по стрелке при красном основном сигнале. Он обязан уступить синему седану (п. 13.5) и пешеходу (п. 13.1).',
          vehicleModel: 'hatch',
        ),
      ],
    ),
    const CrossroadsScenario(
      id: 'hard_equal_4way_3cars_pedestrian',
      title: 'Равнозначный перекресток с пешеходом',
      subtitle:
          'Помеха справа между автомобилями и приоритет пешехода на переходе.',
      pddArticle: 'Пункты 13.1, 13.11 и 14.1 ПДД РФ',
      isEqualCrossroad: true,
      isHardSituation: true,
      signs: [
        CrossroadsSignPlacement(code: '4.1.2', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.west),
        CrossroadsSignPlacement(code: '1.6', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '1.6', side: CrossroadsSide.east),
      ],
      actors: [
        CrossroadsActor(
          id: 'pedestrian_east',
          type: CrossroadsVehicleType.pedestrian,
          name: 'Пешеход',
          colorHex: '#2E5B88',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.cross,
          priorityOrder: 1,
          ruleExplanation:
              'Пешеход переходит проезжую часть по нерегулируемому переходу. Водитель при повороте направо обязан уступить ему дорогу (п. 13.1).',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.right,
          priorityOrder: 2,
          ruleExplanation:
              'После пропуска пешехода синий седан завершает поворот направо. Для него справа нет помех (п. 13.11).',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Белый седан',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'Для белого седана синий был помехой справа. После его проезда белый седан может двигаться прямо (п. 13.11).',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек',
          colorHex: '#D33D38',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 4,
          ruleExplanation:
              'Красный хэтчбек поворачивает налево и уступает дорогу встречному белому седану (п. 13.12).',
          vehicleModel: 'hatch',
        ),
      ],
    ),
    const CrossroadsScenario(
      id: 'hard_priority_t_tram_pedestrian',
      title: 'Т-образный перекресток: трамвай и пешеход',
      subtitle:
          'Приоритет трамвая на главной дороге и пропуск пешехода при выезде со второстепенной.',
      pddArticle: 'Пункты 13.1, 13.9 и 14.1 ПДД РФ',
      closedSide: CrossroadsSide.north,
      isHardSituation: true,
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.west),
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.west),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.south),
      ],
      actors: [
        CrossroadsActor(
          id: 'pedestrian_east',
          type: CrossroadsVehicleType.pedestrian,
          name: 'Пешеход',
          colorHex: '#2E5B88',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.cross,
          priorityOrder: 1,
          ruleExplanation:
              'Пешеход переходит проезжую часть по нерегулируемому переходу (п. 14.1). Все водители обязаны уступить ему дорогу.',
        ),
        CrossroadsActor(
          id: 'tram_west',
          type: CrossroadsVehicleType.tram,
          name: 'Трамвай',
          colorHex: '#D33D38',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation:
              'Трамвай на главной дороге имеет безусловное преимущество перед безрельсовыми ТС (п. 13.9, 13.11).',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Белый седан',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 3,
          ruleExplanation:
              'Белый седан на главной дороге поворачивает налево после проезда встречного трамвая (п. 13.9, 13.12).',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Синий хэтчбек',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 4,
          ruleExplanation:
              'Синий хэтчбек со второстепенной дороги со знаком 2.4 поворачивает налево и уступает дорогу транспорту на главной (п. 13.9).',
          vehicleModel: 'hatch',
        ),
      ],
    ),
    const CrossroadsScenario(
      id: 'hard_emergency_priority_pedestrian',
      title: 'Скорая помощь со спецсигналами и пешеход',
      subtitle:
          'Безусловный приоритет машины экстренных служб с сиреной и маячками.',
      pddArticle: 'Пункты 3.2 и 13.1 ПДД РФ',
      isHardSituation: true,
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'ambulance_north',
          type: CrossroadsVehicleType.emergency,
          name: 'Скорая помощь',
          colorHex: '#FFFFFF',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation:
              'Автомобиль скорой помощи с включенными маячками и сиреной пользуется приоритетом перед всеми участниками (п. 3.2).',
          hasSiren: true,
          vehicleModel: 'ambulance',
        ),
        CrossroadsActor(
          id: 'pedestrian_west',
          type: CrossroadsVehicleType.pedestrian,
          name: 'Пешеход',
          colorHex: '#2E5B88',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.cross,
          priorityOrder: 2,
          ruleExplanation:
              'Пешеход переходит западную улицу. Поворачивающий автомобиль обязан уступить ему дорогу (п. 13.1).',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Желтый седан',
          colorHex: '#F6B400',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 3,
          ruleExplanation:
              'Желтый седан на главной дороге уступает скорой помощи (п. 3.2), пропускает пешехода при повороте (п. 13.1) и завершает маневр.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек',
          colorHex: '#D33D38',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 4,
          ruleExplanation:
              'Красный хэтчбек находится на второстепенной дороге со знаком 2.4 и уступает дорогу транспорту на главной (п. 13.9).',
          vehicleModel: 'hatch',
        ),
      ],
    ),
    const CrossroadsScenario(
      id: 'hard_priority_main_turns_right_pedestrian',
      title: 'Главная дорога поворачивает направо и пешеход',
      subtitle: 'Разъезд на главной дороге со знаком 8.13 и пропуск пешехода.',
      pddArticle: 'Пункты 13.1, 13.10 и 13.11 ПДД РФ',
      isHardSituation: true,
      signs: [
        CrossroadsSignPlacement(
          code: '2.1',
          side: CrossroadsSide.south,
          table8_13: 'bottom_right',
        ),
        CrossroadsSignPlacement(
          code: '2.1',
          side: CrossroadsSide.east,
          table8_13: 'bottom_left',
        ),
        CrossroadsSignPlacement(
          code: '2.4',
          side: CrossroadsSide.north,
          table8_13: 'left_top',
        ),
        CrossroadsSignPlacement(
          code: '2.4',
          side: CrossroadsSide.west,
          table8_13: 'top_right',
        ),
      ],
      actors: [
        CrossroadsActor(
          id: 'pedestrian_south',
          type: CrossroadsVehicleType.pedestrian,
          name: 'Пешеход',
          colorHex: '#2E5B88',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.cross,
          priorityOrder: 1,
          ruleExplanation:
              'Пешеход переходит дорогу по переходу. Водители обязаны уступить ему дорогу (п. 13.1, 14.1).',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation:
              'Синий седан на главной дороге поворачивает по ней. Для него справа никого нет (п. 13.10, 13.11).',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Белый седан',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation:
              'Белый седан на главной дороге уступает синему седану как помехе справа (п. 13.10, 13.11).',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек',
          colorHex: '#D33D38',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 4,
          ruleExplanation:
              'Красный хэтчбек со второстепенной дороги уступает всем ТС на главной (п. 13.9).',
          vehicleModel: 'hatch',
        ),
      ],
    ),
  ];
}
