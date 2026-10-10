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
  const LocalizedActorText({required this.name, required this.ruleExplanation});

  final String name;
  final String ruleExplanation;
}

class CrossroadsTranslations {
  CrossroadsTranslations._();

  static const Map<String, Map<String, LocalizedScenarioText>>
  localizedScenarios = {
    'en': {
      'cross_main_turns_left': LocalizedScenarioText(
        title: 'The main road turns left (sign 8.13)',
        subtitle:
            'Vehicles on the main road go first, giving way to the one on their right. Then the secondary road.',
        pddArticle: 'Clause 13.10 of the Russian Traffic Regulations',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Blue hatchback',
            ruleExplanation:
                'The blue car is on the main road and is on the right of the white sedan, so it goes first.',
          ),
          'car_west': LocalizedActorText(
            name: 'White sedan',
            ruleExplanation:
                'The white sedan is also on the main road, but the blue hatchback is on its right. It gives way and goes second.',
          ),
          'car_north': LocalizedActorText(
            name: 'Orange sedan',
            ruleExplanation:
                'The orange car is on the secondary road and lets the main road pass. Nobody is on its right, so it goes third.',
          ),
          'car_east': LocalizedActorText(
            name: 'Green crossover',
            ruleExplanation:
                'The green car is on the secondary road with the orange sedan on its right. It goes last.',
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
            ruleExplanation:
                'The blue car is moving straight along the main road.',
          ),
          'car_north': LocalizedActorText(
            name: 'Green SUV',
            ruleExplanation:
                'A green SUV is on the main road, but when turning left it gives way to the oncoming blue one (section 13.12).',
          ),
          'car_east': LocalizedActorText(
            name: 'Red hatchback',
            ruleExplanation:
                'The red car is on a secondary road with a sign 2.4 “Give way”.',
          ),
        },
      ),
      'cross_equal_3_cars': LocalizedScenarioText(
        title: 'Equal intersection: 3 cars',
        subtitle:
            'No signs: everyone gives way to the vehicle approaching from the right.',
        pddArticle: 'Clause 13.11 of the Russian Traffic Regulations',
        actors: {
          'car_west': LocalizedActorText(
            name: 'Green crossover',
            ruleExplanation:
                'Nobody is on the right of the green crossover, so it goes first.',
          ),
          'car_north': LocalizedActorText(
            name: 'Blue hatchback',
            ruleExplanation:
                'The green crossover was on the right of the blue car. Once it has passed, the blue car is free to go.',
          ),
          'car_east': LocalizedActorText(
            name: 'Yellow sedan',
            ruleExplanation:
                'The blue hatchback is on the right of the yellow car. It gives way and goes last.',
          ),
        },
      ),
      'cross_equal_tram': LocalizedScenarioText(
        title: 'Equal intersection with a tram',
        subtitle: 'At an equal intersection the tram goes before cars.',
        pddArticle: 'Clause 13.11 of the Russian Traffic Regulations',
        actors: {
          'tram_north': LocalizedActorText(
            name: 'Red tram',
            ruleExplanation:
                'At an intersection of equal roads a tram has priority over trackless vehicles whatever its direction.',
          ),
          'car_south': LocalizedActorText(
            name: 'Grey hatchback',
            ruleExplanation:
                'The grey hatchback turns left and lets the tram pass. Nobody is on its right, so it goes second.',
          ),
          'car_west': LocalizedActorText(
            name: 'Blue sedan',
            ruleExplanation:
                'The grey hatchback is on the right of the blue sedan. It gives way and goes last.',
          ),
        },
      ),
      'cross_emergency_priority': LocalizedScenarioText(
        title: 'Special transport: ambulance with siren',
        subtitle:
            'A beacon and a special sound signal give unconditional priority.',
        pddArticle: 'Clause 3.2 of the Russian Traffic Regulations',
        actors: {
          'ambulance_east': LocalizedActorText(
            name: 'Ambulance (siren)',
            ruleExplanation:
                'A car with a flashing light and a special sound signal on has priority regardless of the signs!',
          ),
          'car_south': LocalizedActorText(
            name: 'Blue sedan (Main road)',
            ruleExplanation:
                'After the ambulance, the blue car on the main road passes second.',
          ),
          'car_west': LocalizedActorText(
            name: 'Red hatchback (Secondary road)',
            ruleExplanation:
                'The red hatchback on the secondary road with the 2.4 sign gives way to everyone.',
          ),
        },
      ),
      'cross_tram_on_secondary': LocalizedScenarioText(
        title: 'Tram on the secondary road',
        subtitle:
            'A tram on the secondary road gives way to cars on the main road.',
        pddArticle: 'Clauses 13.9 and 13.12 of the Russian Traffic Regulations',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Blue sedan (main road)',
            ruleExplanation:
                'The blue car is on the main road and goes before the tram on the secondary road.',
          ),
          'tram_east': LocalizedActorText(
            name: 'Red tram (secondary road)',
            ruleExplanation:
                'The tram on the secondary road lets the main road pass. The oncoming yellow car turns left and gives way to it.',
          ),
          'car_west': LocalizedActorText(
            name: 'Yellow sedan (secondary road)',
            ruleExplanation:
                'The yellow car is on the secondary road and, turning left, also gives way to the oncoming tram.',
          ),
        },
      ),
      'cross_stop_sign': LocalizedScenarioText(
        title: 'Sign 2.5 "Driving without stopping is prohibited"',
        subtitle:
            'At the STOP sign you stop and give way to traffic on the road you are crossing.',
        pddArticle:
            'Sign 2.5, clauses 13.9 and 13.12 of the Russian Traffic Regulations',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Green SUV',
            ruleExplanation:
                'The green SUV drives straight along the main road.',
          ),
          'car_north': LocalizedActorText(
            name: 'White sedan',
            ruleExplanation:
                'The white sedan on the secondary road lets the main road pass and drives straight.',
          ),
          'car_south': LocalizedActorText(
            name: 'Red hatchback (STOP sign)',
            ruleExplanation:
                'The red car stops at the STOP sign, lets the main road pass and, turning left, the oncoming white sedan too.',
          ),
        },
      ),
      'cross_uturn_equal': LocalizedScenarioText(
        title: 'U-turn at an intersection',
        subtitle:
            'When making a U-turn the driver gives way to oncoming vehicles going straight or turning right.',
        pddArticle: 'Clause 13.12 of the Russian Traffic Regulations',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Blue sedan',
            ruleExplanation:
                'The blue car is moving straight. The northern sedan must yield to him when turning.',
          ),
          'car_north': LocalizedActorText(
            name: 'Red hatchback (U-turn)',
            ruleExplanation: 'A turning car yields to oncoming traffic.',
          ),
        },
      ),
      'cross_main_turns_right': LocalizedScenarioText(
        title: 'The main road turns right (sign 8.13)',
        subtitle:
            'Vehicles on the main road go first, giving way to the one on their right. Then the secondary road.',
        pddArticle: 'Clause 13.10 of the Russian Traffic Regulations',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Blue sedan',
            ruleExplanation:
                'The blue car on the main road turns left along it. It is on the right of the bus, so it goes first.',
          ),
          'bus_south': LocalizedActorText(
            name: 'Route bus',
            ruleExplanation:
                'The bus is also on the main road, but the blue sedan is on its right. It gives way and goes second.',
          ),
          'truck_west': LocalizedActorText(
            name: 'White truck',
            ruleExplanation:
                'The truck on the secondary road lets the main road pass. Nobody is on its right any more, so it goes third.',
          ),
          'car_north': LocalizedActorText(
            name: 'Red hatchback',
            ruleExplanation:
                'The red car is on the secondary road with the white truck on its right. It goes last.',
          ),
        },
      ),
      'cross_police_vs_tram': LocalizedScenarioText(
        title: 'Traffic police patrol with special signals and tram',
        subtitle:
            'An emergency service vehicle with a beacon and siren has an advantage even over a tram.',
        pddArticle: 'Clauses 3.2 and 13.11 of the Russian Traffic Regulations',
        actors: {
          'police_south': LocalizedActorText(
            name: 'Traffic police patrol (siren)',
            ruleExplanation:
                'A car with flashing lights and a siren on has priority over all participants, including a tram (clause 3.2).',
          ),
          'tram_east': LocalizedActorText(
            name: 'Red tram',
            ruleExplanation:
                'At an equivalent intersection, the tram has priority over ordinary cars and goes second.',
          ),
          'car_north': LocalizedActorText(
            name: 'Blue hatchback',
            ruleExplanation:
                'The blue car gives way to traffic police special vehicles and trams.',
          ),
        },
      ),
      'cross_junction_2_3_1': LocalizedScenarioText(
        title: 'Intersection with a minor road (sign 2.3.1)',
        subtitle:
            'Sign 2.3.1 gives priority to vehicles on the secondary road being crossed.',
        pddArticle:
            'Sign 2.3.1 and clause 13.12 of the Russian Traffic Regulations',
        actors: {
          'moto_south': LocalizedActorText(
            name: 'Sports motorcycle',
            ruleExplanation:
                'The motorcycle moves straight along the main road and has priority over all participants.',
          ),
          'car_north': LocalizedActorText(
            name: 'Blue sedan',
            ruleExplanation:
                'The sedan on the main road turns left and gives way to the oncoming motorcycle (section 13.12).',
          ),
          'truck_west': LocalizedActorText(
            name: 'Gray truck',
            ruleExplanation:
                'The truck is on a secondary road with sign 2.4 and allows traffic on the main road to pass.',
          ),
        },
      ),
      'cross_junction_right_2_3_2': LocalizedScenarioText(
        title: 'Secondary road joining from the right (sign 2.3.2)',
        subtitle:
            'The main road goes straight on; a secondary road joins from the right.',
        pddArticle:
            'Sign 2.3.2 and clause 13.9 of the Russian Traffic Regulations',
        actors: {
          'suv_south': LocalizedActorText(
            name: 'Green crossover (main road)',
            ruleExplanation:
                'The crossover drives straight along the main road (sign 2.3.2).',
          ),
          'truck_east': LocalizedActorText(
            name: 'Flatbed truck (joining road)',
            ruleExplanation:
                'The truck leaves the joining road (sign 2.4) and lets the crossover on the main road pass.',
          ),
        },
      ),
      'cross_end_of_main_2_2': LocalizedScenarioText(
        title: 'End of the main road (signs 2.2 and 2.4)',
        subtitle:
            'After sign 2.2 the main road has ended: at the intersection with sign 2.4 you give way.',
        pddArticle:
            'Signs 2.2, 2.4 and clause 13.9 of the Russian Traffic Regulations',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Black SUV (main road)',
            ruleExplanation:
                'The SUV drives straight along the main road (sign 2.1).',
          ),
          'car_west': LocalizedActorText(
            name: 'Blue coupe (main road)',
            ruleExplanation:
                'Turning left on the main road, the coupe gives way to the oncoming SUV (clause 13.12).',
          ),
          'bus_south': LocalizedActorText(
            name: 'City bus',
            ruleExplanation:
                'For the bus the main road has ended (sign 2.2) and there is sign 2.4 before the intersection: it gives way to both.',
          ),
        },
      ),
      'cross_mandatory_4_1_1': LocalizedScenarioText(
        title: 'Mandatory sign 4.1.1 "Straight ahead"',
        subtitle:
            'From the south you may only go straight on. The order follows the priority signs.',
        pddArticle:
            'Sign 4.1.1, clauses 13.9 and 13.12 of the Russian Traffic Regulations',
        actors: {
          'bus_south': LocalizedActorText(
            name: 'Bus (main road, straight)',
            ruleExplanation:
                'The bus on the main road goes straight, as sign 4.1.1 requires.',
          ),
          'truck_north': LocalizedActorText(
            name: 'White truck (main road)',
            ruleExplanation:
                'The truck on the main road turns left and gives way to the oncoming bus (clause 13.12).',
          ),
          'car_east': LocalizedActorText(
            name: 'Red hatchback (secondary road)',
            ruleExplanation:
                'The red hatchback with sign 2.4 lets both vehicles on the main road pass.',
          ),
        },
      ),
      'cross_junction_left_2_3_3': LocalizedScenarioText(
        title: 'Secondary road joining from the left (sign 2.3.3)',
        subtitle:
            'The main road goes straight on; a secondary road joins from the left.',
        pddArticle:
            'Sign 2.3.3 and clause 13.9 of the Russian Traffic Regulations',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Yellow sedan (main road)',
            ruleExplanation:
                'The sedan drives straight along the main road (sign 2.3.3).',
          ),
          'truck_west': LocalizedActorText(
            name: 'Van (joining road)',
            ruleExplanation:
                'The van leaves the joining road (sign 2.4) and lets the sedan on the main road pass.',
          ),
        },
      ),
      'cross_truck_left_turn': LocalizedScenarioText(
        title: 'Turn left: passing oncoming traffic',
        subtitle:
            'When turning left, the driver must yield to an oncoming vehicle moving straight ahead.',
        pddArticle: 'Clause 13.12 of the Russian Traffic Regulations',
        actors: {
          'moto_north': LocalizedActorText(
            name: 'Red motorcycle',
            ruleExplanation:
                'The motorcycle is moving straight from the opposite direction and there is no obstacle on the right.',
          ),
          'truck_south': LocalizedActorText(
            name: 'Orange dump truck',
            ruleExplanation:
                'The dump truck turns left and is obliged to give way to an oncoming motorcycle (clause 13.12).',
          ),
        },
      ),
      'cross_two_trams_and_cars': LocalizedScenarioText(
        title: 'Two trams and cars at an equal intersection',
        subtitle:
            'Trams go before cars; between themselves they give way to the one on the right.',
        pddArticle: 'Clause 13.11 of the Russian Traffic Regulations',
        actors: {
          'tram_north': LocalizedActorText(
            name: 'Tram No. 1 (north)',
            ruleExplanation:
                'Trams go before cars. Nobody is on the right of tram No. 1, so it goes first.',
          ),
          'tram_east': LocalizedActorText(
            name: 'Tram No. 2 (east)',
            ruleExplanation:
                'Tram No. 1 is on the right of tram No. 2. It gives way and goes second.',
          ),
          'car_south': LocalizedActorText(
            name: 'White sedan',
            ruleExplanation:
                'After the trams nobody is on the right of the white sedan, so it goes third.',
          ),
          'car_west': LocalizedActorText(
            name: 'Green crossover',
            ruleExplanation:
                'The white sedan is on the right of the green crossover. It goes last.',
          ),
        },
      ),
    },
    'kk': {
      'cross_main_turns_left': LocalizedScenarioText(
        title: 'Басты жол солға бұрылады (8.13 белгісі)',
        subtitle:
            'Алдымен басты жолдағылар өтеді, өзара — оң жақтағы кедергіге жол береді. Содан кейін қосалқы жолдағылар.',
        pddArticle: 'ЖЖЕ 13.10-тармағы',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Көк хэтчбек',
            ruleExplanation:
                'Көк көлік басты жолда және ақ седанның оң жағында, сондықтан бірінші өтеді.',
          ),
          'car_west': LocalizedActorText(
            name: 'Ақ седан',
            ruleExplanation:
                'Ақ седан да басты жолда, бірақ оң жағында көк хэтчбек. Жол беріп, екінші өтеді.',
          ),
          'car_north': LocalizedActorText(
            name: 'Қызғылт сары седан',
            ruleExplanation:
                'Қызғылт сары көлік қосалқы жолда, басты жолды өткізеді. Оң жағында ешкім жоқ — үшінші өтеді.',
          ),
          'car_east': LocalizedActorText(
            name: 'Жасыл кроссовер',
            ruleExplanation:
                'Жасыл көлік қосалқы жолда, оң жағында қызғылт сары седан. Соңғы өтеді.',
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
            ruleExplanation:
                'Көгілдір көлік үлкен жолдың бойымен тура келе жатыр.',
          ),
          'car_north': LocalizedActorText(
            name: 'Жасыл жол талғамайтын көлік',
            ruleExplanation:
                'Жасыл жол талғамайтын көлік негізгі жолда келе жатыр, бірақ солға бұрылғанда келе жатқан көкке жол береді (13.12-бөлім).',
          ),
          'car_east': LocalizedActorText(
            name: 'Қызыл хэтчбек',
            ruleExplanation:
                'Қызыл көлік 2.4 «Жол бер» белгісі бар қосалқы жолда.',
          ),
        },
      ),
      'cross_equal_3_cars': LocalizedScenarioText(
        title: 'Тең маңызды қиылыс: 3 көлік',
        subtitle: 'Белгі жоқ: әркім оң жақтан жақындаған көлікке жол береді.',
        pddArticle: 'ЖЖЕ 13.11-тармағы',
        actors: {
          'car_west': LocalizedActorText(
            name: 'Жасыл кроссовер',
            ruleExplanation:
                'Жасыл кроссовердің оң жағында ешкім жоқ — ол бірінші өтеді.',
          ),
          'car_north': LocalizedActorText(
            name: 'Көк хэтчбек',
            ruleExplanation:
                'Көктің оң жағында жасыл кроссовер болды. Ол өткен соң көк жол еркін.',
          ),
          'car_east': LocalizedActorText(
            name: 'Сары седан',
            ruleExplanation:
                'Сарының оң жағында көк хэтчбек. Жол беріп, соңғы өтеді.',
          ),
        },
      ),
      'cross_equal_tram': LocalizedScenarioText(
        title: 'Трамвайы бар тең маңызды қиылыс',
        subtitle: 'Тең маңызды қиылыста трамвай автомобильдерден бұрын өтеді.',
        pddArticle: 'ЖЖЕ 13.11-тармағы',
        actors: {
          'tram_north': LocalizedActorText(
            name: 'Қызыл трамвай',
            ruleExplanation:
                'Тең маңызды жолдар қиылысында трамвай бағытына қарамастан рельссіз көліктерден басым.',
          ),
          'car_south': LocalizedActorText(
            name: 'Сұр хэтчбек',
            ruleExplanation:
                'Сұр хэтчбек солға бұрылып, трамвайды өткізеді. Оң жағында ешкім жоқ — ол екінші.',
          ),
          'car_west': LocalizedActorText(
            name: 'Көк седан',
            ruleExplanation:
                'Көк седанның оң жағында сұр хэтчбек. Жол беріп, соңғы өтеді.',
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
            ruleExplanation:
                'Жыпылықтайтын шамы және арнайы дыбыстық сигналы қосылған көлік белгілеріне қарамастан басымдыққа ие!',
          ),
          'car_south': LocalizedActorText(
            name: 'Көк седан (Үй)',
            ruleExplanation:
                'Жедел жәрдемнен кейін үлкен жолдағы көк көлік екінші болып өтеді.',
          ),
          'car_west': LocalizedActorText(
            name: 'Қызыл хэтчбек (кіші)',
            ruleExplanation:
                '2.4 белгісі бар екінші сатыдағы қызыл хэтчбек бәрінен де төмен.',
          ),
        },
      ),
      'cross_tram_on_secondary': LocalizedScenarioText(
        title: 'Қосалқы жолдағы трамвай',
        subtitle:
            'Қосалқы жолдағы трамвай басты жолдағы көліктерге жол береді.',
        pddArticle: 'ЖЖЕ 13.9 және 13.12-тармақтары',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Көк седан (басты жол)',
            ruleExplanation:
                'Көк көлік басты жолда, қосалқы жолдағы трамвайдан бұрын өтеді.',
          ),
          'tram_east': LocalizedActorText(
            name: 'Қызыл трамвай (қосалқы жол)',
            ruleExplanation:
                'Трамвай басты жолды өткізеді. Қарсы келе жатқан сары көлік солға бұрылып, трамвайға жол береді.',
          ),
          'car_west': LocalizedActorText(
            name: 'Сары седан (қосалқы жол)',
            ruleExplanation:
                'Сары көлік қосалқы жолда, солға бұрылғанда қарсы келе жатқан трамвайға да жол береді.',
          ),
        },
      ),
      'cross_stop_sign': LocalizedScenarioText(
        title: '2.5 белгісі «Тоқтамай жүруге тыйым салынады»',
        subtitle:
            'STOP белгісінде тоқтап, қиылысатын жолдағы көліктерге жол беру керек.',
        pddArticle: '2.5 белгісі, ЖЖЕ 13.9 және 13.12-тармақтары',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Жасыл жол талғамайтын көлік',
            ruleExplanation: 'Жасыл көлік басты жолмен тура жүреді.',
          ),
          'car_north': LocalizedActorText(
            name: 'Ақ седан',
            ruleExplanation:
                'Ақ седан қосалқы жолда, басты жолды өткізіп, тура жүреді.',
          ),
          'car_south': LocalizedActorText(
            name: 'Қызыл хэтчбек (STOP белгісі)',
            ruleExplanation:
                'Қызыл көлік STOP белгісінде тоқтайды, басты жолды, ал солға бұрылғанда қарсы келе жатқан ақ седанды да өткізеді.',
          ),
        },
      ),
      'cross_uturn_equal': LocalizedScenarioText(
        title: 'Қиылыста бұрылу',
        subtitle:
            'Кері бұрылғанда жүргізуші тура немесе оңға жүріп келе жатқан қарсы көліктерге жол береді.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.12 тармағы',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Көк седан',
            ruleExplanation:
                'Көгілдір көлік түзу келе жатыр. Бұрылыс кезінде солтүстік седан оған жол беруі керек.',
          ),
          'car_north': LocalizedActorText(
            name: 'Қызыл хэтчбек (Бұрылыс)',
            ruleExplanation:
                'Кері бұрылып келе жатқан көлік қарсы келе жатқан көлікке жол беруі керек.',
          ),
        },
      ),
      'cross_main_turns_right': LocalizedScenarioText(
        title: 'Басты жол оңға бұрылады (8.13 белгісі)',
        subtitle:
            'Алдымен басты жолдағылар өтеді, өзара — оң жақтағы кедергіге жол береді. Содан кейін қосалқы жолдағылар.',
        pddArticle: 'ЖЖЕ 13.10-тармағы',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Көк седан',
            ruleExplanation:
                'Көк көлік басты жолмен солға бұрылады. Ол автобустың оң жағында — бірінші өтеді.',
          ),
          'bus_south': LocalizedActorText(
            name: 'Маршруттық автобус',
            ruleExplanation:
                'Автобус та басты жолда, бірақ оң жағында көк седан. Жол беріп, екінші өтеді.',
          ),
          'truck_west': LocalizedActorText(
            name: 'Ақ жүк көлігі',
            ruleExplanation:
                'Жүк көлігі қосалқы жолда, басты жолды өткізеді. Оң жағында енді ешкім жоқ — үшінші.',
          ),
          'car_north': LocalizedActorText(
            name: 'Қызыл хэтчбек',
            ruleExplanation:
                'Қызыл қосалқы жолда, оң жағында ақ жүк көлігі. Соңғы өтеді.',
          ),
        },
      ),
      'cross_police_vs_tram': LocalizedScenarioText(
        title: 'Арнайы сигналдармен және трамваймен жол-патрульдік полициясы',
        subtitle:
            'Маяк пен сиренасы бар жедел қызмет көлігінің трамвайдан да артықшылығы бар.',
        pddArticle:
            'Ресейдің жол қозғалысы ережелерінің 3.2 және 13.11 тармақтары',
        actors: {
          'police_south': LocalizedActorText(
            name: 'Жол полициясы патрулі (сирена)',
            ruleExplanation:
                'Жыпылықтайтын шамдары мен сиренасы бар автомобиль барлық қатысушылардан, соның ішінде трамвайдан да басымдылыққа ие (3.2-тармақ).',
          ),
          'tram_east': LocalizedActorText(
            name: 'Қызыл трамвай',
            ruleExplanation:
                'Тең құқықты қиылыста трамвай қарапайым көліктерге қарағанда басымдыққа ие және екінші орынға шығады.',
          ),
          'car_north': LocalizedActorText(
            name: 'Көк хэтчбек',
            ruleExplanation:
                'Көгілдір көлік жол полициясының арнайы көліктері мен трамвайларынан да төмен.',
          ),
        },
      ),
      'cross_junction_2_3_1': LocalizedScenarioText(
        title: 'Кіші жолдың қиылысы (2.3.1 белгісі)',
        subtitle:
            '2.3.1 белгісі кесіп өтетін қосалқы жолдағы көліктерге басымдық береді.',
        pddArticle:
            'Ресейлік Жол қозғалысы ережелерінің 2.3.1 белгісі және 13.12 тармағы',
        actors: {
          'moto_south': LocalizedActorText(
            name: 'Спорттық мотоцикл',
            ruleExplanation:
                'Мотоцикл негізгі жол бойымен тікелей қозғалады және барлық қатысушылардан басымдыққа ие.',
          ),
          'car_north': LocalizedActorText(
            name: 'Көк седан',
            ruleExplanation:
                'Негізгі жолдағы седан солға бұрылып, қарсы келе жатқан мотоциклге жол береді (13.12-бөлім).',
          ),
          'truck_west': LocalizedActorText(
            name: 'Сұр жүк көлігі',
            ruleExplanation:
                'Жүк көлігі 2.4 белгісі бар қосалқы жолда және негізгі жолдағы көлік қозғалысына мүмкіндік береді.',
          ),
        },
      ),
      'cross_junction_right_2_3_2': LocalizedScenarioText(
        title: 'Оң жақтан қосалқы жолдың қосылуы (2.3.2 белгісі)',
        subtitle: 'Басты жол тура жалғасады, оң жақтан қосалқы жол қосылады.',
        pddArticle: '2.3.2 белгісі және ЖЖЕ 13.9-тармағы',
        actors: {
          'suv_south': LocalizedActorText(
            name: 'Жасыл кроссовер (басты жол)',
            ruleExplanation:
                'Кроссовер басты жолмен тура жүреді (2.3.2 белгісі).',
          ),
          'truck_east': LocalizedActorText(
            name: 'Жүк көлігі (қосылатын жол)',
            ruleExplanation:
                'Жүк көлігі қосылатын жолдан шығады (2.4 белгісі) және басты жолдағы кроссоверді өткізеді.',
          ),
        },
      ),
      'cross_end_of_main_2_2': LocalizedScenarioText(
        title: 'Басты жолдың соңы (2.2 және 2.4 белгілері)',
        subtitle:
            '2.2 белгісінен кейін басты жол аяқталды: 2.4 белгісі бар қиылыста жол беру керек.',
        pddArticle: '2.2, 2.4 белгілері және ЖЖЕ 13.9-тармағы',
        actors: {
          'car_east': LocalizedActorText(
            name: 'Қара жол талғамайтын көлік (басты жол)',
            ruleExplanation: 'Көлік басты жолмен тура жүреді (2.1 белгісі).',
          ),
          'car_west': LocalizedActorText(
            name: 'Көк купе (басты жол)',
            ruleExplanation:
                'Купе басты жолда солға бұрылғанда қарсы келе жатқан көлікке жол береді (13.12-т.).',
          ),
          'bus_south': LocalizedActorText(
            name: 'Қалалық автобус',
            ruleExplanation:
                'Автобус үшін басты жол аяқталды (2.2 белгісі), қиылыс алдында 2.4 белгісі — екеуіне де жол береді.',
          ),
        },
      ),
      'cross_mandatory_4_1_1': LocalizedScenarioText(
        title: '4.1.1 нұсқау белгісі «Тура жүру»',
        subtitle:
            'Оңтүстіктен тек тура жүруге болады. Кезек — басымдық белгілері бойынша.',
        pddArticle: '4.1.1 белгісі, ЖЖЕ 13.9 және 13.12-тармақтары',
        actors: {
          'bus_south': LocalizedActorText(
            name: 'Автобус (басты жол, тура)',
            ruleExplanation:
                'Автобус басты жолда 4.1.1 белгісі бойынша тура жүреді.',
          ),
          'truck_north': LocalizedActorText(
            name: 'Ақ жүк көлігі (басты жол)',
            ruleExplanation:
                'Жүк көлігі басты жолда солға бұрылып, қарсы келе жатқан автобусқа жол береді (13.12-т.).',
          ),
          'car_east': LocalizedActorText(
            name: 'Қызыл хэтчбек (қосалқы жол)',
            ruleExplanation:
                '2.4 белгісі бар қызыл хэтчбек басты жолдағы екеуін де өткізеді.',
          ),
        },
      ),
      'cross_junction_left_2_3_3': LocalizedScenarioText(
        title: 'Сол жақтан қосалқы жолдың қосылуы (2.3.3 белгісі)',
        subtitle: 'Басты жол тура жалғасады, сол жақтан қосалқы жол қосылады.',
        pddArticle: '2.3.3 белгісі және ЖЖЕ 13.9-тармағы',
        actors: {
          'car_south': LocalizedActorText(
            name: 'Сары седан (басты жол)',
            ruleExplanation: 'Седан басты жолмен тура жүреді (2.3.3 белгісі).',
          ),
          'truck_west': LocalizedActorText(
            name: 'Жүк фургоны (қосылатын жол)',
            ruleExplanation:
                'Фургон қосылатын жолдан шығады (2.4 белгісі) және басты жолдағы седанды өткізеді.',
          ),
        },
      ),
      'cross_truck_left_turn': LocalizedScenarioText(
        title: 'Солға бұрылыңыз: қарсы келе жатқан көлікке жол беру',
        subtitle:
            'Солға бұрылу кезінде жүргізуші тікелей алға қарай келе жатқан көлікке жол беруі керек.',
        pddArticle: 'Ресейдің жол қозғалысы ережелерінің 13.12 тармағы',
        actors: {
          'moto_north': LocalizedActorText(
            name: 'Қызыл мотоцикл',
            ruleExplanation:
                'Мотоцикл қарама-қарсы жақтан түзу келе жатыр, оң жақта ешқандай кедергі жоқ.',
          ),
          'truck_south': LocalizedActorText(
            name: 'Қызғылт сары самосвал',
            ruleExplanation:
                'Самосвал солға бұрылып, қарсы келе жатқан мотоциклге жол беруге міндетті (13.12-тармақ).',
          ),
        },
      ),
      'cross_two_trams_and_cars': LocalizedScenarioText(
        title: 'Тең маңызды қиылыстағы екі трамвай мен автомобильдер',
        subtitle:
            'Трамвайлар автомобильдерден бұрын өтеді, өзара — оң жақтағыға жол береді.',
        pddArticle: 'ЖЖЕ 13.11-тармағы',
        actors: {
          'tram_north': LocalizedActorText(
            name: '№1 трамвай (солтүстік)',
            ruleExplanation:
                'Трамвайлар автомобильдерден бұрын өтеді. №1 трамвайдың оң жағында ешкім жоқ — ол бірінші.',
          ),
          'tram_east': LocalizedActorText(
            name: '№2 трамвай (шығыс)',
            ruleExplanation:
                '№2 трамвайдың оң жағында №1 трамвай. Жол беріп, екінші өтеді.',
          ),
          'car_south': LocalizedActorText(
            name: 'Ақ седан',
            ruleExplanation:
                'Трамвайлардан кейін ақ седанның оң жағында ешкім жоқ — ол үшінші.',
          ),
          'car_west': LocalizedActorText(
            name: 'Жасыл кроссовер',
            ruleExplanation:
                'Жасыл кроссовердің оң жағында ақ седан. Соңғы өтеді.',
          ),
        },
      ),
    },
  };
}
