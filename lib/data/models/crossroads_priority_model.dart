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
  uTurn('Разворот');

  const CrossroadsManeuver(this.label);
  final String label;

  String localizedLabel([String? lang]) => switch (lang) {
    'en' => switch (this) {
      CrossroadsManeuver.straight => 'Straight',
      CrossroadsManeuver.right => 'Right',
      CrossroadsManeuver.left => 'Left',
      CrossroadsManeuver.uTurn => 'U-turn',
    },
    'kk' => switch (this) {
      CrossroadsManeuver.straight => 'Тіке',
      CrossroadsManeuver.right => 'Оңға',
      CrossroadsManeuver.left => 'Солға',
      CrossroadsManeuver.uTurn => 'Кері бұрылу',
    },
    _ => label,
  };
}

/// Тип транспортного средства.
enum CrossroadsVehicleType {
  car('Легковой автомобиль'),
  tram('Трамвай'),
  emergency('Спецтранспорт с сиреной и маячком'),
  truck('Грузовой автомобиль'),
  suv('Внедорожник'),
  motorcycle('Мотоцикл'),
  bus('Автобус'),
  police('Полиция (ДПС)');

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

  CrossroadsScenario copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? pddArticle,
    List<CrossroadsActor>? actors,
    List<CrossroadsSignPlacement>? signs,
    bool? isEqualCrossroad,
    List<CrossroadsSide>? trafficLightGreenSides,
  }) => CrossroadsScenario(
    id: id ?? this.id,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    pddArticle: pddArticle ?? this.pddArticle,
    actors: actors ?? this.actors,
    signs: signs ?? this.signs,
    isEqualCrossroad: isEqualCrossroad ?? this.isEqualCrossroad,
    trafficLightGreenSides: trafficLightGreenSides ?? this.trafficLightGreenSides,
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
      subtitle: 'Водители на главной разъезжаются по помехе справа, затем второстепенные.',
      pddArticle: 'Пункт 13.10 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.south, table8_13: 'bottom_left'),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.west, table8_13: 'bottom_right'),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.north, table8_13: 'top_right'),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east, table8_13: 'left_top'),
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

    // 9. Неравнозначный перекресток: главная поворачивает направо (п. 13.10)
    const CrossroadsScenario(
      id: 'cross_main_turns_right',
      title: 'Главная дорога поворачивает направо (знак 8.13)',
      subtitle: 'Транспорт на главной разъезжается по правилу правой руки, затем второстепенные.',
      pddArticle: 'Пункт 13.10 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.south, table8_13: 'bottom_right'),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.east, table8_13: 'bottom_left'),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.north, table8_13: 'left_top'),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west, table8_13: 'top_right'),
      ],
      actors: [
        CrossroadsActor(
          id: 'bus_south',
          type: CrossroadsVehicleType.bus,
          name: 'Рейсовый автобус',
          colorHex: '#F08A24',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.right,
          priorityOrder: 1,
          ruleExplanation: 'Автобус движется по главной дороге и поворачивает направо. У него нет помехи справа.',
          vehicleModel: 'bus',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Синий седан',
          colorHex: '#317ED4',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'Синий седан на главной дороге уступает автобусу справа и проезжает вторым.',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'truck_west',
          type: CrossroadsVehicleType.truck,
          name: 'Белый грузовик',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'Грузовик на второстепенной дороге свободен от помехи справа и проезжает раньше северного авто.',
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
          ruleExplanation: 'Красный хэтчбек на второстепенной дороге уступает белому грузовику справа.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 10. Круговое движение со знаком 4.3 (п. 13.11.1)
    const CrossroadsScenario(
      id: 'cross_roundabout_priority',
      title: 'Круговое движение (знак 4.3)',
      subtitle: 'При въезде на круг со знаком 4.3 водитель обязан уступить дорогу движущимся по кругу.',
      pddArticle: 'Пункт 13.11.1 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '4.3', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '4.3', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый кроссовер (по кругу)',
          colorHex: '#4D7768',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Зеленый кроссовер уже находится на перекрестке с круговым движением и пользуется преимуществом.',
          vehicleModel: 'suv',
        ),
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Желтый седан (въезд на круг)',
          colorHex: '#E8C547',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'Водитель желтого седана при въезде на круговой перекресток обязан уступить дорогу ТС на круге (п. 13.11.1).',
          vehicleModel: 'sedan',
        ),
      ],
    ),

    // 11. ДПС со спецсигналами и трамвай (п. 3.2 и 13.11)
    const CrossroadsScenario(
      id: 'cross_police_vs_tram',
      title: 'Патруль ДПС со спецсигналами и трамвай',
      subtitle: 'Автомобиль оперативной службы с маячком и сиреной имеет преимущество даже перед трамваем.',
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
          ruleExplanation: 'Автомобиль со включенными проблесковыми маячками и сиреной пользуется преимуществом перед всеми участниками, включая трамвай (п. 3.2).',
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
          ruleExplanation: 'На равнозначном перекрестке трамвай имеет преимущество перед обычными автомобилями и едет вторым.',
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
          ruleExplanation: 'Синий автомобиль уступает спецтранспорту ДПС и трамваю.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 12. Пересечение со второстепенной дорогой (знак 2.3.1 и п. 13.12)
    const CrossroadsScenario(
      id: 'cross_junction_2_3_1',
      title: 'Пересечение со второстепенной дорогой (знак 2.3.1)',
      subtitle: 'Знак 2.3.1 предоставляет приоритет перед ТС на пересекаемой второстепенной дороге.',
      pddArticle: 'Знак 2.3.1 и п. 13.12 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.3.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.3.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west),
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
          ruleExplanation: 'Мотоцикл движется по главной дороге прямо и имеет приоритет перед всеми участниками.',
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
          ruleExplanation: 'Седан на главной дороге поворачивает налево и уступает встречному мотоциклу (п. 13.12).',
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
          ruleExplanation: 'Грузовик находится на второстепенной дороге со знаком 2.4 и пропускает транспорт главной дороги.',
          vehicleModel: 'truck',
        ),
      ],
    ),

    // 13. Примыкание второстепенной дороги справа (знак 2.3.2)
    const CrossroadsScenario(
      id: 'cross_junction_right_2_3_2',
      title: 'Примыкание второстепенной дороги справа (знак 2.3.2)',
      subtitle: 'Главная дорога продолжается прямо, примыкающий справа уступает.',
      pddArticle: 'Знак 2.3.2 и п. 13.9 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.3.2', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
      ],
      actors: [
        CrossroadsActor(
          id: 'suv_south',
          type: CrossroadsVehicleType.suv,
          name: 'Зеленый кроссовер (Главная)',
          colorHex: '#4D7768',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Кроссовер движется по главной дороге прямо согласно знаку 2.3.2.',
          vehicleModel: 'suv',
        ),
        CrossroadsActor(
          id: 'truck_east',
          type: CrossroadsVehicleType.truck,
          name: 'Бортовой грузовик (Примыкание)',
          colorHex: '#D7AA60',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'Грузовик выезжает со второстепенной дороги со знаком 2.4 и уступает кроссоверу.',
          vehicleModel: 'truck',
        ),
      ],
    ),

    // 14. Конец главной дороги (знаки 2.2 и 2.4)
    const CrossroadsScenario(
      id: 'cross_end_of_main_2_2',
      title: 'Конец главной дороги (знаки 2.2 и 2.4)',
      subtitle: 'Знак 2.2 совместно с 2.4 отменяет приоритет перед пересекаемой дорогой.',
      pddArticle: 'Знаки 2.2, 2.4 и п. 13.9 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.2', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.east),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.suv,
          name: 'Черный внедорожник (Главная)',
          colorHex: '#2B2F36',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Внедорожник движется по пересекаемой главной дороге прямо (знак 2.1).',
          vehicleModel: 'suv',
        ),
        CrossroadsActor(
          id: 'car_west',
          type: CrossroadsVehicleType.car,
          name: 'Синее купе (Главная)',
          colorHex: '#317ED4',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.left,
          priorityOrder: 2,
          ruleExplanation: 'Купе на главной дороге при повороте налево уступает встречному внедорожнику (п. 13.12).',
          vehicleModel: 'coupe',
        ),
        CrossroadsActor(
          id: 'bus_south',
          type: CrossroadsVehicleType.bus,
          name: 'Городской автобус (Конец главной)',
          colorHex: '#F08A24',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'Автобус встречает знак 2.2 «Конец главной дороги» со знаком 2.4 и уступает обоим ТС на главной дороге.',
          vehicleModel: 'bus',
        ),
      ],
    ),

    // 15. Предписывающий знак 4.1.1 «Движение прямо»
    const CrossroadsScenario(
      id: 'cross_mandatory_4_1_1',
      title: 'Предписывающий знак 4.1.1 «Движение прямо»',
      subtitle: 'Знак 4.1.1 разрешает движение только прямо, на перекрестке неравнозначных дорог.',
      pddArticle: 'Знак 4.1.1 и п. 13.9 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '4.1.1', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.1', side: CrossroadsSide.north),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.east),
      ],
      actors: [
        CrossroadsActor(
          id: 'bus_south',
          type: CrossroadsVehicleType.bus,
          name: 'Автобус (Главная прямо)',
          colorHex: '#317ED4',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Автобус движется по главной дороге прямо согласно знаку 4.1.1.',
          vehicleModel: 'bus',
        ),
        CrossroadsActor(
          id: 'truck_north',
          type: CrossroadsVehicleType.truck,
          name: 'Белый грузовик (Главная)',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'Грузовик движется по главной дороге во встречном направлении прямо.',
          vehicleModel: 'truck',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Красный хэтчбек (Второстепенная)',
          colorHex: '#ED4621',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'Красный хэтчбек со знаком 2.4 уступает дорогу обоим ТС на главной дороге.',
          vehicleModel: 'hatch',
        ),
      ],
    ),

    // 16. Примыкание второстепенной дороги слева (знак 2.3.3)
    const CrossroadsScenario(
      id: 'cross_junction_left_2_3_3',
      title: 'Примыкание второстепенной дороги слева (знак 2.3.3)',
      subtitle: 'Главная дорога продолжается прямо, транспорт слева уступает.',
      pddArticle: 'Знак 2.3.3 и п. 13.9 ПДД РФ',
      signs: [
        CrossroadsSignPlacement(code: '2.3.3', side: CrossroadsSide.south),
        CrossroadsSignPlacement(code: '2.4', side: CrossroadsSide.west),
      ],
      actors: [
        CrossroadsActor(
          id: 'car_south',
          type: CrossroadsVehicleType.car,
          name: 'Желтый седан (Главная)',
          colorHex: '#E8C547',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Седан движется по главной дороге прямо (знак 2.3.3).',
          vehicleModel: 'sedan',
        ),
        CrossroadsActor(
          id: 'truck_west',
          type: CrossroadsVehicleType.truck,
          name: 'Грузовой фургон (Примыкание)',
          colorHex: '#2B2F36',
          side: CrossroadsSide.west,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'Грузовик выезжает со второстепенной дороги слева со знаком 2.4 и уступает седану.',
          vehicleModel: 'truck',
        ),
      ],
    ),

    // 17. Поворот налево: встречный разъезд (п. 13.12)
    const CrossroadsScenario(
      id: 'cross_truck_left_turn',
      title: 'Поворот налево: разъезд со встречным транспортом',
      subtitle: 'При повороте налево водитель обязан уступить встречному ТС, движущемуся прямо.',
      pddArticle: 'Пункт 13.12 ПДД РФ',
      isEqualCrossroad: true,
      actors: [
        CrossroadsActor(
          id: 'moto_north',
          type: CrossroadsVehicleType.motorcycle,
          name: 'Красный мотоцикл',
          colorHex: '#ED4621',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Мотоцикл движется со встречного направления прямо и не имеет помехи справа.',
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
          ruleExplanation: 'Самосвал поворачивает налево и обязан уступить дорогу встречному мотоциклу (п. 13.12).',
          vehicleModel: 'truck',
        ),
      ],
    ),

    // 18. Два трамвая и автомобили на равнозначном перекрестке (п. 13.11)
    const CrossroadsScenario(
      id: 'cross_two_trams_and_cars',
      title: 'Два трамвая и автомобили на равнозначном перекрестке',
      subtitle: 'Трамваи пользуются преимуществом перед безрельсовыми ТС.',
      pddArticle: 'Пункт 13.11 ПДД РФ',
      isEqualCrossroad: true,
      actors: [
        CrossroadsActor(
          id: 'tram_north',
          type: CrossroadsVehicleType.tram,
          name: 'Трамвай №1 (Север)',
          colorHex: '#ED4621',
          side: CrossroadsSide.north,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 1,
          ruleExplanation: 'Трамвай пользуется преимуществом перед безрельсовыми транспортными средствами независимо от направления движения.',
          vehicleModel: 'tram',
        ),
        CrossroadsActor(
          id: 'tram_south',
          type: CrossroadsVehicleType.tram,
          name: 'Трамвай №2 (Юг)',
          colorHex: '#ED4621',
          side: CrossroadsSide.south,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 2,
          ruleExplanation: 'Второй трамвай также имеет безусловный приоритет перед безрельсовыми автомобилями.',
          vehicleModel: 'tram',
        ),
        CrossroadsActor(
          id: 'car_east',
          type: CrossroadsVehicleType.car,
          name: 'Белый седан',
          colorHex: '#F2F3F5',
          side: CrossroadsSide.east,
          maneuver: CrossroadsManeuver.straight,
          priorityOrder: 3,
          ruleExplanation: 'После проезда трамваев белый седан свободен от помехи справа и проезжает третьим.',
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
          ruleExplanation: 'Зеленый кроссовер уступает белому седану по правилу помехи справа и проезжает последним.',
          vehicleModel: 'suv',
        ),
      ],
    ),
  ];
}
