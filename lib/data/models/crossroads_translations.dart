// Generated file by tools/l10n/translate_crossroads.py. Do not edit manually.

class LocalizedScenarioText {
  const LocalizedScenarioText({
    required this.title,
    required this.subtitle,
    required this.pddArticle,
    required this.actors,
  });

  final String title;
  final String subtitle;
  final String pddArticle;
  final Map<String, LocalizedActorText> actors;
}

class LocalizedActorText {
  const LocalizedActorText({
    required this.name,
    required this.ruleExplanation,
  });

  final String name;
  final String ruleExplanation;
}

class CrossroadsTranslations {
  CrossroadsTranslations._();

  static const Map<String, Map<String, LocalizedScenarioText>> localizedScenarios = {
    'en': {
      'cross_main_turns_left': LocalizedScenarioText(
        title: 'The main road turns left (sign 8.13)',
        subtitle: 'Drivers on the main one pass through the obstacle on the right, then the secondary ones.',
        pddArticle: 'Clause 13.10 of the Russian Traffic Regulations',
        actors: {
          'car_west': LocalizedActorText(
            name: 'White sedan',
            ruleExplanation: 'The white sedan is on the main road and for the southern car is an obstacle on the right. Passes first.',
          ),
          'car_south': LocalizedActorText(
            name: 'Blue hatchback',
            ruleExplanation: 'The blue car is on the main road, giving way to the white one on the right and passing second.',
          ),
          'car_east': LocalizedActorText(
            name: 'Green crossover',
            ruleExplanation: 'Green on a secondary road. Among the minors, he has no interference to the right of the north.',
          ),
          'car_north': LocalizedActorText(
            name: 'Orange sedan',
            ruleExplanation: 'The orange one on the secondary road gives way to the green crossover on the right.',
          ),
        },
      ),
      'cross_main_straight': LocalizedScenarioText(
        title: 'Main road: direct direction',
        subtitle: 'Transport on the main road has absolute priority.',
        pddArticle: 'Clause 13.9 of the Russian Traffic Regulations',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Blue sedan',
            ruleExplanation: 'The blue car is moving straight along the main road.',
          ),
          'car_north': LocalizedActorText(
            name: 'Green SUV',
            ruleExplanation: 'A green SUV is on the main road, but when turning left it gives way to the oncoming blue one (section 13.12).',
          ),
          'car_east': LocalizedActorText(
            name: 'Red hatchback',
            ruleExplanation: 'The red car is on a secondary road with a sign 2.4 “Give way”.',
          ),
        },
      ),
      'cross_equal_3_cars': LocalizedScenarioText(
        title: 'Equivalent intersection: 3 cars',
        subtitle: 'Under equal conditions, they yield to interference on the right.',
        pddArticle: 'Clause 13.11 of the Russian Traffic Regulations',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Yellow sedan',
            ruleExplanation: 'The yellow car on the right has no obstacle. He starts moving first.',
          ),
          'car_north': LocalizedActorText(
            name: 'Blue hatchback',
            ruleExplanation: 'The blue car is inferior to the yellow one on the right. After his passage it is released.',
          ),
          'car_west': LocalizedActorText(
            name: 'Green crossover',
            ruleExplanation: 'The green crossover has an obstacle on the right (blue car) and passes last.',
          ),
        },
      ),
      'cross_equal_tram': LocalizedScenarioText(
        title: 'Equivalent intersection with tram',
        subtitle: 'On an equivalent road, the tram always has priority.',
        pddArticle: 'Clause 13.11 of the Russian Traffic Regulations',
        actors: {
          'tram_north': LocalizedActorText(
            name: 'Red tram',
            ruleExplanation: 'At the intersection of equivalent roads, a tram has an advantage over trackless vehicles, regardless of direction.',
          ),
          'car_west': LocalizedActorText(
            name: 'Blue sedan',
            ruleExplanation: 'After the tram, the blue car is free of obstacles on the right and passes second.',
          ),
          'car_south': LocalizedActorText(
            name: 'Gray hatchback',
            ruleExplanation: 'The gray car gives way to the tram and the obstacle on the right (the blue car).',
          ),
        },
      ),
      'cross_emergency_priority': LocalizedScenarioText(
        title: 'Special transport: ambulance with siren',
        subtitle: 'A beacon and a special sound signal give unconditional priority.',
        pddArticle: 'Clause 3.2 of the Russian Traffic Regulations',
        actors: {
          'ambulance_east': LocalizedActorText(
            name: 'Ambulance (siren)',
            ruleExplanation: 'A car with a flashing light and a special sound signal on has priority regardless of the signs!',
          ),
          'car_south': LocalizedActorText(
            name: 'Blue sedan (Home)',
            ruleExplanation: 'After the ambulance, the blue car on the main road passes second.',
          ),
          'car_west': LocalizedActorText(
            name: 'Red hatchback (Minor)',
            ruleExplanation: 'The red hatchback in the secondary with the 2.4 sign is inferior to everyone.',
          ),
        },
      ),
      'cross_tram_on_secondary': LocalizedScenarioText(
        title: 'Tram on a secondary road',
        subtitle: 'The tram on the secondary road is inferior to the cars on the main road!',
        pddArticle: 'Clause 13.9 of the Russian Traffic Regulations',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Blue sedan (Home)',
            ruleExplanation: 'The blue car moves on the main road and has priority over the tram on the secondary road.',
          ),
          'tram_east': LocalizedActorText(
            name: 'Red Tram (Minor)',
            ruleExplanation: 'The tram on the secondary road is inferior to the main one, but has an advantage over the yellow car on the same secondary road.',
          ),
          'car_west': LocalizedActorText(
            name: 'Yellow Sedan (Minor)',
            ruleExplanation: 'The yellow car on the secondary road gives way to the main road and tram.',
          ),
        },
      ),
      'cross_stop_sign': LocalizedScenarioText(
        title: 'Sign 2.5 “Driving without stopping is prohibited”',
        subtitle: 'Mandatory stop and yield to traffic on the main road being crossed.',
        pddArticle: 'Sign 2.5 and clause 13.9 of the Russian Traffic Regulations',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Green SUV',
            ruleExplanation: 'The green car is moving straight along the main road.',
          ),
          'car_north': LocalizedActorText(
            name: 'White sedan',
            ruleExplanation: 'The white sedan on the secondary lane passes before the southern car, taking into account the obstacle on the right.',
          ),
          'car_south': LocalizedActorText(
            name: 'Red hatchback (STOP sign)',
            ruleExplanation: 'The red car is inferior to all participants on the road being crossed.',
          ),
        },
      ),
      'cross_uturn_equal': LocalizedScenarioText(
        title: 'U-turn at an intersection',
        subtitle: 'When turning, an oncoming car becomes an obstacle on the right.',
        pddArticle: 'Clause 13.12 of the Russian Traffic Regulations',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Blue sedan',
            ruleExplanation: 'The blue car is moving straight. The northern sedan must yield to him when turning.',
          ),
          'car_north': LocalizedActorText(
            name: 'Red hatchback (U-turn)',
            ruleExplanation: 'A turning car yields to oncoming traffic.',
          ),
        },
      ),
      'cross_main_turns_right': LocalizedScenarioText(
        title: 'The main road turns right (sign 8.13)',
        subtitle: 'Transport on the main one moves away according to the right-hand rule, then the secondary ones.',
        pddArticle: 'Clause 13.10 of the Russian Traffic Regulations',
        actors: {
          'bus_south': LocalizedActorText(
            name: 'Regular bus',
            ruleExplanation: 'The bus moves along the main road and turns right. He has no interference on the right.',
          ),
          'car_east': LocalizedActorText(
            name: 'Blue sedan',
            ruleExplanation: 'The blue sedan on the main road gives way to the bus on the right and passes second.',
          ),
          'truck_west': LocalizedActorText(
            name: 'White truck',
            ruleExplanation: 'The truck on the secondary road is clear of obstacles on the right and passes before the northern vehicle.',
          ),
          'car_north': LocalizedActorText(
            name: 'Red hatchback',
            ruleExplanation: 'A red hatchback on a minor road gives way to a white truck on the right.',
          ),
        },
      ),
      'cross_roundabout_priority': LocalizedScenarioText(
        title: 'Roundabout (sign 4.3)',
        subtitle: 'When entering a circle with sign 4.3, the driver is obliged to give way to those moving in the circle.',
        pddArticle: 'Clause 13.11.1 Traffic Regulations of the Russian Federation',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Green crossover (circle)',
            ruleExplanation: 'The green SUV is already at the roundabout and is taking advantage.',
          ),
          'car_south': LocalizedActorText(
            name: 'Yellow sedan (entrance to the circle)',
            ruleExplanation: 'The driver of a yellow sedan, when entering a roundabout, is obliged to give way to vehicles on the circle (clause 13.11.1).',
          ),
        },
      ),
      'cross_police_vs_tram': LocalizedScenarioText(
        title: 'Traffic police patrol with special signals and tram',
        subtitle: 'An emergency service vehicle with a beacon and siren has an advantage even over a tram.',
        pddArticle: 'Clauses 3.2 and 13.11 of the Russian Traffic Regulations',
        actors: {
          'police_south': LocalizedActorText(
            name: 'DPS patrol (siren)',
            ruleExplanation: 'A car with flashing lights and a siren on has priority over all participants, including a tram (clause 3.2).',
          ),
          'tram_east': LocalizedActorText(
            name: 'Red tram',
            ruleExplanation: 'At an equivalent intersection, the tram has priority over ordinary cars and goes second.',
          ),
          'car_north': LocalizedActorText(
            name: 'Blue hatchback',
            ruleExplanation: 'The blue car is inferior to traffic police special vehicles and trams.',
          ),
        },
      ),
      'cross_junction_2_3_1': LocalizedScenarioText(
        title: 'Intersection with a minor road (sign 2.3.1)',
        subtitle: 'Sign 2.3.1 gives priority to vehicles on the secondary road being crossed.',
        pddArticle: 'Sign 2.3.1 and clause 13.12 of the Russian Traffic Regulations',
        actors: {
          'moto_south': LocalizedActorText(
            name: 'Sports motorcycle',
            ruleExplanation: 'The motorcycle moves straight along the main road and has priority over all participants.',
          ),
          'car_north': LocalizedActorText(
            name: 'Blue sedan',
            ruleExplanation: 'The sedan on the main road turns left and gives way to the oncoming motorcycle (section 13.12).',
          ),
          'truck_west': LocalizedActorText(
            name: 'Gray truck',
            ruleExplanation: 'The truck is on a secondary road with sign 2.4 and allows traffic on the main road to pass.',
          ),
        },
      ),
      'cross_junction_right_2_3_2': LocalizedScenarioText(
        title: 'Junction of a secondary road on the right (sign 2.3.2)',
        subtitle: 'The main road continues straight, the adjacent one on the right gives way.',
        pddArticle: 'Sign 2.3.2 and clause 13.9 of the Russian Traffic Regulations',
        actors: {
          'suv_south': LocalizedActorText(
            name: 'Green crossover (Home)',
            ruleExplanation: 'The crossover moves along the main road straight according to sign 2.3.2.',
          ),
          'truck_east': LocalizedActorText(
            name: 'Flatbed truck (Adjacency)',
            ruleExplanation: 'The truck leaves the secondary road with a 2.4 sign and gives way to the crossover.',
          ),
        },
      ),
      'cross_end_of_main_2_2': LocalizedScenarioText(
        title: 'End of main road (signs 2.2 and 2.4)',
        subtitle: 'Sign 2.2, together with 2.4, cancels priority over the road being crossed.',
        pddArticle: 'Signs 2.2, 2.4 and clause 13.9 of the Russian Traffic Regulations',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Black SUV (Home)',
            ruleExplanation: 'The SUV is moving straight along the intersecting main road (sign 2.1).',
          ),
          'car_west': LocalizedActorText(
            name: 'Blue coupe (Home)',
            ruleExplanation: 'A coupe on the main road gives way to an oncoming SUV when turning left (section 13.12).',
          ),
          'bus_south': LocalizedActorText(
            name: 'City bus (End of main)',
            ruleExplanation: 'The bus meets sign 2.2 “End of the main road” with sign 2.4 and gives way to both vehicles on the main road.',
          ),
        },
      ),
      'cross_mandatory_4_1_1': LocalizedScenarioText(
        title: 'Mandatory sign 4.1.1 “Move straight ahead”',
        subtitle: 'Sign 4.1.1 allows driving only straight ahead at the intersection of unequal roads.',
        pddArticle: 'Sign 4.1.1 and clause 13.9 of the Russian Traffic Regulations',
        actors: {
          'bus_south': LocalizedActorText(
            name: 'Bus (Main Direct)',
            ruleExplanation: 'The bus moves along the main road straight according to sign 4.1.1.',
          ),
          'truck_north': LocalizedActorText(
            name: 'White Truck (Home)',
            ruleExplanation: 'The truck is moving straight along the main road in the opposite direction.',
          ),
          'car_east': LocalizedActorText(
            name: 'Red hatchback (Minor)',
            ruleExplanation: 'A red hatchback with a 2.4 sign gives way to both vehicles on the main road.',
          ),
        },
      ),
      'cross_junction_left_2_3_3': LocalizedScenarioText(
        title: 'Junction of secondary road on the left (sign 2.3.3)',
        subtitle: 'The main road continues straight, with traffic on the left giving way.',
        pddArticle: 'Sign 2.3.3 and clause 13.9 of the Russian Traffic Regulations',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Yellow sedan (Home)',
            ruleExplanation: 'The sedan is moving straight along the main road (sign 2.3.3).',
          ),
          'truck_west': LocalizedActorText(
            name: 'Cargo van (Adjacent)',
            ruleExplanation: 'The truck exits the secondary road on the left with a 2.4 sign and yields to the sedan.',
          ),
        },
      ),
      'cross_truck_left_turn': LocalizedScenarioText(
        title: 'Turn left: passing oncoming traffic',
        subtitle: 'When turning left, the driver must yield to an oncoming vehicle moving straight ahead.',
        pddArticle: 'Clause 13.12 of the Russian Traffic Regulations',
        actors: {
          'moto_north': LocalizedActorText(
            name: 'Red motorcycle',
            ruleExplanation: 'The motorcycle is moving straight from the opposite direction and there is no obstacle on the right.',
          ),
          'truck_south': LocalizedActorText(
            name: 'Orange dump truck',
            ruleExplanation: 'The dump truck turns left and is obliged to give way to an oncoming motorcycle (clause 13.12).',
          ),
        },
      ),
      'cross_two_trams_and_cars': LocalizedScenarioText(
        title: 'Two trams and cars at an equivalent intersection',
        subtitle: 'Trams have an advantage over trackless vehicles.',
        pddArticle: 'Clause 13.11 of the Russian Traffic Regulations',
        actors: {
          'tram_north': LocalizedActorText(
            name: 'Tram No. 1 (North)',
            ruleExplanation: 'The tram has an advantage over trackless vehicles regardless of the direction of travel.',
          ),
          'tram_south': LocalizedActorText(
            name: 'Tram No. 2 (South)',
            ruleExplanation: 'The second tram also has unconditional priority over trackless vehicles.',
          ),
          'car_east': LocalizedActorText(
            name: 'White sedan',
            ruleExplanation: 'After the trams pass, the white sedan is free of obstacles on the right and passes third.',
          ),
          'car_west': LocalizedActorText(
            name: 'Green crossover',
            ruleExplanation: 'The green crossover is inferior to the white sedan according to the rule of interference on the right and passes last.',
          ),
        },
      ),
    },
    'kk': {
      'cross_main_turns_left': LocalizedScenarioText(
        title: 'Негізгі жол солға бұрылады (8.13 белгісі)',
        subtitle: 'Негізгі жүргізушілер оң жақтағы кедергіден өтеді, содан кейін қосалқылар.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.10 тармағы',
        actors: {
          'car_west': LocalizedActorText(
            name: 'Ақ седан',
            ruleExplanation: 'Ақ седан негізгі жолда, ал оңтүстік көлік үшін оң жақта кедергі. Бірінші өтеді.',
          ),
          'car_south': LocalizedActorText(
            name: 'Көк хэтчбек',
            ruleExplanation: 'Көк көлік үлкен жолда, оң жақтағы ақ көлікке жол беріп, екінші өтіп бара жатыр.',
          ),
          'car_east': LocalizedActorText(
            name: 'Жасыл кроссовер',
            ruleExplanation: 'Қосымша жолда жасыл. Кәмелетке толмағандар арасында солтүстіктің оң жаққа араласуы жоқ.',
          ),
          'car_north': LocalizedActorText(
            name: 'Қызғылт сары седан',
            ruleExplanation: 'Екінші жолдағы қызғылт сары оң жақтағы жасыл кроссоверге жол береді.',
          ),
        },
      ),
      'cross_main_straight': LocalizedScenarioText(
        title: 'Негізгі жол: тікелей бағыт',
        subtitle: 'Негізгі жолдағы көлік абсолютті басымдыққа ие.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.9-тармағы',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Көк седан',
            ruleExplanation: 'Көгілдір көлік үлкен жолдың бойымен тура келе жатыр.',
          ),
          'car_north': LocalizedActorText(
            name: 'Жасыл жол талғамайтын көлік',
            ruleExplanation: 'Жасыл жол талғамайтын көлік негізгі жолда келе жатыр, бірақ солға бұрылғанда келе жатқан көкке жол береді (13.12-бөлім).',
          ),
          'car_east': LocalizedActorText(
            name: 'Қызыл хэтчбек',
            ruleExplanation: 'Қызыл көлік 2.4 «Жол бер» белгісі бар қосалқы жолда.',
          ),
        },
      ),
      'cross_equal_3_cars': LocalizedScenarioText(
        title: 'Баламалы қиылысу: 3 көлік',
        subtitle: 'Тең жағдайда олар оң жақтағы араласуға көнеді.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.11 тармағы',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Сары седан',
            ruleExplanation: 'Оң жақтағы сары көлікке еш кедергі жоқ. Ол бірінші қозғала бастайды.',
          ),
          'car_north': LocalizedActorText(
            name: 'Көк хэтчбек',
            ruleExplanation: 'Көк көлік оң жақтағы сарыдан төмен. Оның өтуінен кейін ол босатылады.',
          ),
          'car_west': LocalizedActorText(
            name: 'Жасыл кроссовер',
            ruleExplanation: 'Жасыл кроссовердің оң жағында (көк көлік) кедергісі бар және ең соңғы өтеді.',
          ),
        },
      ),
      'cross_equal_tram': LocalizedScenarioText(
        title: 'Трамваймен баламалы қиылысу',
        subtitle: 'Баламалы жолда трамвай әрқашан басымдыққа ие.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.11 тармағы',
        actors: {
          'tram_north': LocalizedActorText(
            name: 'Қызыл трамвай',
            ruleExplanation: 'Баламалы жолдардың қиылысында трамвай бағытына қарамастан рельссіз көліктерге қарағанда артықшылығы бар.',
          ),
          'car_west': LocalizedActorText(
            name: 'Көк седан',
            ruleExplanation: 'Трамвайдан кейін көгілдір көлік оң жақтағы кедергілерден босатылып, екінші болып өтеді.',
          ),
          'car_south': LocalizedActorText(
            name: 'Серый хэтчбек',
            ruleExplanation: 'Сұр көлік трамвайға және оң жақтағы кедергіге жол береді (көк көлік).',
          ),
        },
      ),
      'cross_emergency_priority': LocalizedScenarioText(
        title: 'Арнайы көлік: сиренасы бар жедел жәрдем',
        subtitle: 'Маяк және арнайы дыбыстық сигнал сөзсіз басымдық береді.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 3.2-тармағы',
        actors: {
          'ambulance_east': LocalizedActorText(
            name: 'Жедел жәрдем (сирена)',
            ruleExplanation: 'Жыпылықтайтын шамы және арнайы дыбыстық сигналы қосылған көлік белгілеріне қарамастан басымдыққа ие!',
          ),
          'car_south': LocalizedActorText(
            name: 'Көк седан (Үй)',
            ruleExplanation: 'Жедел жәрдемнен кейін үлкен жолдағы көк көлік екінші болып өтеді.',
          ),
          'car_west': LocalizedActorText(
            name: 'Қызыл хэтчбек (кіші)',
            ruleExplanation: '2.4 белгісі бар екінші сатыдағы қызыл хэтчбек бәрінен де төмен.',
          ),
        },
      ),
      'cross_tram_on_secondary': LocalizedScenarioText(
        title: 'Екінші жолдағы трамвай',
        subtitle: 'Екінші жолдағы трамвай негізгі жолдағы көліктерден төмен!',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.9-тармағы',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Көк седан (Үй)',
            ruleExplanation: 'Көгілдір көлік негізгі жолда қозғалады және қосалқы жолда трамвайға қарағанда басымдыққа ие.',
          ),
          'tram_east': LocalizedActorText(
            name: 'Қызыл трамвай (кіші)',
            ruleExplanation: 'Қосалқы жолдағы трамвай негізгі жолдан төмен, бірақ сол қосалқы жолдағы сары көліктен артықшылығы бар.',
          ),
          'car_west': LocalizedActorText(
            name: 'Сары седан (кіші)',
            ruleExplanation: 'Екінші жолдағы сары көлік негізгі жол мен трамвайға жол береді.',
          ),
        },
      ),
      'cross_stop_sign': LocalizedScenarioText(
        title: '2.5 белгісі «Тоқтамай жүруге тыйым салынады»',
        subtitle: 'Міндетті түрде тоқтау және кесіп өтетін негізгі жолдағы көлік қозғалысына рұқсат беру.',
        pddArticle: 'Ресейлік Жол қозғалысы ережелерінің 2.5 және 13.9-тармағына қол қойыңыз',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Жасыл жол талғамайтын көлік',
            ruleExplanation: 'Жасыл көлік үлкен жолдың бойымен тура келе жатыр.',
          ),
          'car_north': LocalizedActorText(
            name: 'Ақ седан',
            ruleExplanation: 'Екінші жолақтағы ақ седан оң жақтағы кедергіні ескере отырып, оңтүстік көліктен бұрын өтеді.',
          ),
          'car_south': LocalizedActorText(
            name: 'Қызыл хэтчбек (ТОҚТАТУ белгісі)',
            ruleExplanation: 'Қызыл көлік өтіп бара жатқан жолда барлық қатысушылардан төмен.',
          ),
        },
      ),
      'cross_uturn_equal': LocalizedScenarioText(
        title: 'Қиылыста бұрылу',
        subtitle: 'Бұрылыс кезінде қарсы келе жатқан көлік оң жақтағы кедергіге айналады.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.12 тармағы',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Көк седан',
            ruleExplanation: 'Көгілдір көлік түзу келе жатыр. Бұрылыс кезінде солтүстік седан оған көнуі керек.',
          ),
          'car_north': LocalizedActorText(
            name: 'Қызыл хэтчбек (Бұрылыс)',
            ruleExplanation: 'Айналып келе жатқан көлік қарсы келе жатқан көлікке итермелейді.',
          ),
        },
      ),
      'cross_main_turns_right': LocalizedScenarioText(
        title: 'Негізгі жол оңға бұрылады (8.13 белгісі)',
        subtitle: 'Негізгі көлік оң қол ережесіне сәйкес, содан кейін екінші реттік көлікпен қозғалады.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.10 тармағы',
        actors: {
          'bus_south': LocalizedActorText(
            name: 'Кәдімгі автобус',
            ruleExplanation: 'Автобус негізгі жолмен жүріп, оңға бұрылады. Оның оң жағында ешқандай араласу жоқ.',
          ),
          'car_east': LocalizedActorText(
            name: 'Көк седан',
            ruleExplanation: 'Негізгі жолдағы көк седан оң жақтағы автобусқа жол беріп, екінші өтеді.',
          ),
          'truck_west': LocalizedActorText(
            name: 'Ақ жүк көлігі',
            ruleExplanation: 'Қосалқы жолдағы жүк көлігі оң жақтағы кедергілерден өтіп, солтүстік көліктің алдынан өтеді.',
          ),
          'car_north': LocalizedActorText(
            name: 'Қызыл хэтчбек',
            ruleExplanation: 'Кіші жолда қызыл хэтчбек оң жақтағы ақ жүк көлігіне жол береді.',
          ),
        },
      ),
      'cross_roundabout_priority': LocalizedScenarioText(
        title: 'Айналмалы жол (4.3 белгісі)',
        subtitle: '4.3 белгісі бар шеңберге кірген кезде жүргізуші шеңбер бойымен қозғалатындарға жол беруге міндетті.',
        pddArticle: '13.11.1 Ресей Федерациясының жол қозғалысы ережелері',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Жасыл кроссовер (шеңбер)',
            ruleExplanation: 'Жасыл жол талғамайтын көлік айналма жолдың қиылысында және артықшылығын пайдаланып жатыр.',
          ),
          'car_south': LocalizedActorText(
            name: 'Сары седан (шеңберге кіру)',
            ruleExplanation: 'Сары седанның жүргізушісі айналма жолға шыққан кезде шеңбердегі көліктерге жол беруге міндетті (13.11.1-тармақ).',
          ),
        },
      ),
      'cross_police_vs_tram': LocalizedScenarioText(
        title: 'Арнайы сигналдармен және трамваймен жол-патрульдік полициясы',
        subtitle: 'Маяк пен сиренасы бар жедел қызмет көлігінің трамвайдан да артықшылығы бар.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 3.2 және 13.11 тармақтары',
        actors: {
          'police_south': LocalizedActorText(
            name: 'DPS патруль (сирена)',
            ruleExplanation: 'Жыпылықтайтын шамдары мен сиренасы бар автомобиль барлық қатысушылардан, соның ішінде трамвайдан да басымдылыққа ие (3.2-тармақ).',
          ),
          'tram_east': LocalizedActorText(
            name: 'Қызыл трамвай',
            ruleExplanation: 'Баламалы қиылыста трамвай қарапайым вагондарға қарағанда басымдыққа ие және екінші орынға шығады.',
          ),
          'car_north': LocalizedActorText(
            name: 'Көк хэтчбек',
            ruleExplanation: 'Көгілдір көлік жол полициясының арнайы көліктері мен трамвайларынан да төмен.',
          ),
        },
      ),
      'cross_junction_2_3_1': LocalizedScenarioText(
        title: 'Кіші жолдың қиылысы (2.3.1 белгісі)',
        subtitle: '2.3.1 белгісі кесіп өтетін қосалқы жолдағы көліктерге басымдық береді.',
        pddArticle: 'Ресейлік Жол қозғалысы ережелерінің 2.3.1 белгісі және 13.12 тармағы',
        actors: {
          'moto_south': LocalizedActorText(
            name: 'Спорттық мотоцикл',
            ruleExplanation: 'Мотоцикл негізгі жол бойымен тікелей қозғалады және барлық қатысушылардан басымдыққа ие.',
          ),
          'car_north': LocalizedActorText(
            name: 'Көк седан',
            ruleExplanation: 'Негізгі жолдағы седан солға бұрылып, қарсы келе жатқан мотоциклге жол береді (13.12-бөлім).',
          ),
          'truck_west': LocalizedActorText(
            name: 'Сұр жүк көлігі',
            ruleExplanation: 'Жүк көлігі 2.4 белгісі бар қосалқы жолда және негізгі жолдағы көлік қозғалысына мүмкіндік береді.',
          ),
        },
      ),
      'cross_junction_right_2_3_2': LocalizedScenarioText(
        title: 'Оң жақтағы қосалқы жолдың торабы (2.3.2 белгісі)',
        subtitle: 'Негізгі жол түзу жалғасады, оң жақтағы көрші жол береді.',
        pddArticle: 'Ресейлік Жол қозғалысы ережелерінің 2.3.2 және 13.9-тармағына қол қою',
        actors: {
          'suv_south': LocalizedActorText(
            name: 'Жасыл кроссовер (Үй)',
            ruleExplanation: 'Кроссовер негізгі жол бойымен 2.3.2 белгісі бойынша түзу қозғалады.',
          ),
          'truck_east': LocalizedActorText(
            name: 'Пластикалық жүк көлігі (іргелес)',
            ruleExplanation: 'Жүк көлігі 2.4 белгісімен қосалқы жолдан шығып, кроссоверге жол береді.',
          ),
        },
      ),
      'cross_end_of_main_2_2': LocalizedScenarioText(
        title: 'Негізгі жолдың соңы (2.2 және 2.4 белгілері)',
        subtitle: '2.2 белгісі 2.4 белгісімен бірге өтетін жолға басымдықты жояды.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 2.2, 2.4 және 13.9 тармағының белгілері',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Қара жол талғамайтын көлік (үй)',
            ruleExplanation: 'Жол талғамайтын көлік қиылысатын негізгі жол бойымен түзу қозғалады (2.1 белгісі).',
          ),
          'car_west': LocalizedActorText(
            name: 'Көк купе (Үй)',
            ruleExplanation: 'Негізгі жолдағы купе солға бұрылған кезде келе жатқан жол талғамайтын көлікке жол береді (13.12-бөлім).',
          ),
          'bus_south': LocalizedActorText(
            name: 'Қалалық автобус (негізгі жолдың соңы)',
            ruleExplanation: 'Автобус 2.4 белгісі бар «Басты жолдың соңы» 2.2 белгісімен кездесіп, негізгі жолда екі көлікке де жол береді.',
          ),
        },
      ),
      'cross_mandatory_4_1_1': LocalizedScenarioText(
        title: 'Міндетті белгі 4.1.1 «Тура алға»',
        subtitle: '4.1.1 белгісі тең емес жолдардың қиылысында тек тура алға жүруге мүмкіндік береді.',
        pddArticle: 'Ресей Жол қозғалысы ережелерінің 4.1.1 және 13.9-тармағына қол қою',
        actors: {
          'bus_south': LocalizedActorText(
            name: 'Автобус (негізгі тікелей)',
            ruleExplanation: 'Автобус 4.1.1 белгісіне сәйкес негізгі жол бойымен түзу жүреді.',
          ),
          'truck_north': LocalizedActorText(
            name: 'Ақ жүк көлігі (үй)',
            ruleExplanation: 'Жүк көлігі негізгі жолдың бойымен қарама-қарсы бағытта тура келе жатыр.',
          ),
          'car_east': LocalizedActorText(
            name: 'Қызыл хэтчбек (кіші)',
            ruleExplanation: '2.4 белгісі бар қызыл хэтчбек негізгі жолда екі көлікке де жол береді.',
          ),
        },
      ),
      'cross_junction_left_2_3_3': LocalizedScenarioText(
        title: 'Сол жақтағы қосалқы жол айрығы (2.3.3 белгісі)',
        subtitle: 'Негізгі жол түзу жалғасады, сол жақтағы қозғалыс жол береді.',
        pddArticle: 'Ресейлік Жол қозғалысы ережелерінің 2.3.3 және 13.9-тармағына қол қою',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Сары седан (Үй)',
            ruleExplanation: 'Седан негізгі жолдың бойымен түзу қозғалады (2.3.3 белгісі).',
          ),
          'truck_west': LocalizedActorText(
            name: 'Жүк фургоны (іргелес)',
            ruleExplanation: 'Жүк көлігі 2.4 белгісімен сол жақтағы қосалқы жолдан шығып, седанға қарай бет алды.',
          ),
        },
      ),
      'cross_truck_left_turn': LocalizedScenarioText(
        title: 'Солға бұрылыңыз: қарсы келе жатқан көлікті өту',
        subtitle: 'Солға бұрылу кезінде жүргізуші тікелей алға қарай келе жатқан көлікке көнуі керек.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.12 тармағы',
        actors: {
          'moto_north': LocalizedActorText(
            name: 'Қызыл мотоцикл',
            ruleExplanation: 'Мотоцикл қарама-қарсы жақтан түзу келе жатыр, оң жақта ешқандай кедергі жоқ.',
          ),
          'truck_south': LocalizedActorText(
            name: 'Қызғылт сары самосвал',
            ruleExplanation: 'Самосвал солға бұрылып, қарсы келе жатқан мотоциклге жол беруге міндетті (13.12-тармақ).',
          ),
        },
      ),
      'cross_two_trams_and_cars': LocalizedScenarioText(
        title: 'Баламалы қиылыста екі трамвай мен көлік',
        subtitle: 'Трамвайлардың жолсыз көліктерден артықшылығы бар.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.11 тармағы',
        actors: {
          'tram_north': LocalizedActorText(
            name: '№1 трамвай (солтүстік)',
            ruleExplanation: 'Трамвайдың жүру бағытына қарамастан жолсыз көліктерден артықшылығы бар.',
          ),
          'tram_south': LocalizedActorText(
            name: '№2 трамвай (Оңтүстік)',
            ruleExplanation: 'Екінші трамвай жолсыз көліктерге қарағанда сөзсіз басымдыққа ие.',
          ),
          'car_east': LocalizedActorText(
            name: 'Ақ седан',
            ruleExplanation: 'Трамвайлар өткеннен кейін ақ седан оң жақтағы кедергілерден босатылып, үшіншіден өтеді.',
          ),
          'car_west': LocalizedActorText(
            name: 'Жасыл кроссовер',
            ruleExplanation: 'Жасыл кроссовер оң жақтағы кедергі ережесі бойынша ақ седаннан төмен және соңғы болып өтеді.',
          ),
        },
      ),
    },
  };
}
