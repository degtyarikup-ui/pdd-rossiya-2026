class DriverTip {
  final String id;
  final String title;
  final String description;
  final String category;
  final String iconKey;
  final String imagePath;

  const DriverTip({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.iconKey,
    this.imagePath = '',
  });
}

class DriverTipsData {
  static const List<DriverTip> tips = [
    DriverTip(
      id: 'tip_1',
      title: 'Держите дистанцию в 3 секунды',
      description:
          'Засеките ориентир, мимо которого проехало переднее авто. Вы должны проехать его не раньше счета «раз-два-три».',
      category: 'safety',
      iconKey: 'timer',
      imagePath: 'assets/images/tips/tip_1.webp',
    ),
    DriverTip(
      id: 'tip_2',
      title: 'Не тормозите в глубоких лужах',
      description:
          'Если авто начало «всплывать» (аквапланирование), не крутите руль и плавно отпустите газ до восстановления сцепления.',
      category: 'weather',
      iconKey: 'water',
      imagePath: 'assets/images/tips/tip_2.webp',
    ),
    DriverTip(
      id: 'tip_3',
      title: 'Настройте зеркала без слепых зон',
      description:
          'В боковых зеркалах должен быть виден лишь краешек заднего крыла своего авто, а остальное пространство — дорога.',
      category: 'mirrors',
      iconKey: 'visibility',
      imagePath: 'assets/images/tips/tip_3.webp',
    ),
    DriverTip(
      id: 'tip_4',
      title: 'Въезд на круг — с правым поворотником',
      description:
          'При въезде на перекресток с круговым движением включается только правый указатель поворота, а не левый.',
      category: 'rules',
      iconKey: 'roundabout',
      imagePath: 'assets/images/tips/tip_4.webp',
    ),
    DriverTip(
      id: 'tip_5',
      title: 'На переднем приводе при заносе — добавьте газ',
      description:
          'Если заднюю ось начало сносить, плавно прибавьте тягу и направьте руль в сторону заноса. Не жмите на тормоз!',
      category: 'winter',
      iconKey: 'car_drive',
      imagePath: 'assets/images/tips/tip_5.webp',
    ),
    DriverTip(
      id: 'tip_6',
      title: 'На заднем приводе при заносе — сбросьте газ',
      description:
          'При заносе заднеприводного авто немедленно отпустите педаль газа и мягко скорректируйте траекторию рулем.',
      category: 'winter',
      iconKey: 'car_skid',
      imagePath: 'assets/images/tips/tip_6.webp',
    ),
    DriverTip(
      id: 'tip_7',
      title: 'Остановитесь строго до знака «СТОП»',
      description:
          'Знак 6.16 «Стоп-линия» и разметка определяют границу. Наезд бампером фиксируется камерой как проезд на красный.',
      category: 'rules',
      iconKey: 'stop_sign',
      imagePath: 'assets/images/tips/tip_7.webp',
    ),
    DriverTip(
      id: 'tip_8',
      title: 'Не прижимайтесь к фуре перед обгоном',
      description:
          'Держитесь в 25–30 метрах позади грузовика, чтобы заранее хорошо просматривать встречную полосу.',
      category: 'highway',
      iconKey: 'truck',
      imagePath: 'assets/images/tips/tip_8.webp',
    ),
    DriverTip(
      id: 'tip_9',
      title: 'На уклоне уступает тот, кто едет на спуск',
      description:
          'На крутых спусках и подъемах со знаками 1.13 и 1.14 приоритет имеет автомобиль, поднимающийся в гору.',
      category: 'rules',
      iconKey: 'slope',
      imagePath: 'assets/images/tips/tip_9.webp',
    ),
    DriverTip(
      id: 'tip_10',
      title: 'Зеленый свет не гарантирует безопасность',
      description:
          'Выезжая на разрешающий сигнал, убедитесь, что все автомобили с поперечного направления завершили проезд.',
      category: 'safety',
      iconKey: 'traffic_light',
      imagePath: 'assets/images/tips/tip_10.webp',
    ),
    DriverTip(
      id: 'tip_11',
      title: 'На скользкой дороге тормозите двигателем',
      description:
          'Переходите на пониженные передачи заблаговременно. Это предотвращает блокировку колес и снос машины.',
      category: 'winter',
      iconKey: 'ice',
      imagePath: 'assets/images/tips/tip_11.webp',
    ),
    DriverTip(
      id: 'tip_12',
      title: 'Не выкручивайте колеса при повороте налево',
      description:
          'Ожидая окна во встречном потоке, держите колеса прямо. При ударе сзади авто не вылетит на встречку.',
      category: 'safety',
      iconKey: 'turn_left',
      imagePath: 'assets/images/tips/tip_12.webp',
    ),
    DriverTip(
      id: 'tip_13',
      title: 'Не видите зеркал фуры — водитель не видит вас',
      description:
          'У большегрузов огромные мертвые зоны справа и прямо под кабиной. Не задерживайтесь рядом с ними.',
      category: 'highway',
      iconKey: 'blind_spot',
      imagePath: 'assets/images/tips/tip_13.webp',
    ),
    DriverTip(
      id: 'tip_14',
      title: 'Соседний ряд притормозил — тормозите и вы',
      description:
          'Если попутная машина снижает скорость перед пешеходным переходом, за ней наверняка идет пешеход.',
      category: 'safety',
      iconKey: 'pedestrian',
      imagePath: 'assets/images/tips/tip_14.webp',
    ),
    DriverTip(
      id: 'tip_15',
      title: 'Грузовик берет левее перед правым поворотом',
      description:
          'Длинномерам нужен радиус для заноса прицепа. Никогда не пытайтесь проскочить в открывшийся карман справа.',
      category: 'maneuver',
      iconKey: 'turn_right',
      imagePath: 'assets/images/tips/tip_15.webp',
    ),
    DriverTip(
      id: 'tip_16',
      title: 'Включите кондиционер при запотевании стекол',
      description:
          'Кондиционер быстро осушает воздух в салоне. Направьте поток на лобовое стекло и отключите рециркуляцию.',
      category: 'comfort',
      iconKey: 'wind',
      imagePath: 'assets/images/tips/tip_16.webp',
    ),
    DriverTip(
      id: 'tip_17',
      title: 'На уклоне выкручивайте колеса к бордюру',
      description:
          'При парковке на спуске направьте колеса вправо (в бордюр), на подъеме с бордюром — влево от него.',
      category: 'parking',
      iconKey: 'parking_icon',
      imagePath: 'assets/images/tips/tip_17.webp',
    ),
    DriverTip(
      id: 'tip_18',
      title: 'В тумане включайте только ближний свет и ПТФ',
      description:
          'Дальний свет создает ослепляющую белую стену из капель воды. Снижайте скорость и держите дистанцию.',
      category: 'weather',
      iconKey: 'fog',
      imagePath: 'assets/images/tips/tip_18.webp',
    ),
    DriverTip(
      id: 'tip_19',
      title: 'Знак аварийной остановки: 15 м в городе, 30 м на трассе',
      description:
          'Выставляйте знак заблаговременно, чтобы у других водителей было достаточно времени для перестроения.',
      category: 'rules',
      iconKey: 'hazard_triangle',
      imagePath: 'assets/images/tips/tip_19.webp',
    ),
    DriverTip(
      id: 'tip_20',
      title: 'Делайте паузу на 15 минут каждые 2–3 часа',
      description:
          'Тяжелые веки и частая зевота — верный сигнал микросна. Остановитесь, выпейте воды и сделайте легкую разминку.',
      category: 'safety',
      iconKey: 'rest',
    ),
  ];

  static List<DriverTip> getTips([String? lang]) {
    switch (lang) {
      case 'en':
        return _tipsEn;
      case 'kk':
        return _tipsKk;
      case 'ru':
      default:
        return tips;
    }
  }

  static const List<DriverTip> _tipsEn = [
    DriverTip(
      id: 'tip_1',
      title: 'Keep a 3-second distance',
      description:
          'Spot a landmark passed by the car ahead. You should reach it no sooner than counting one-two-three.',
      category: 'safety',
      iconKey: 'timer',
      imagePath: 'assets/images/tips/tip_1.webp',
    ),
    DriverTip(
      id: 'tip_2',
      title: 'Do not brake in deep puddles',
      description:
          'If the car starts hydroplaning, do not turn the wheel and smoothly release throttle until grip is restored.',
      category: 'weather',
      iconKey: 'water',
      imagePath: 'assets/images/tips/tip_2.webp',
    ),
    DriverTip(
      id: 'tip_3',
      title: 'Adjust mirrors with no blind spots',
      description:
          'Side mirrors should show only the edge of your car rear wing, with the rest showing the road.',
      category: 'mirrors',
      iconKey: 'visibility',
      imagePath: 'assets/images/tips/tip_3.webp',
    ),
    DriverTip(
      id: 'tip_4',
      title: 'Enter roundabout with right turn signal',
      description:
          'When entering a roundabout, turn on only the right indicator, not the left.',
      category: 'rules',
      iconKey: 'roundabout',
      imagePath: 'assets/images/tips/tip_4.webp',
    ),
    DriverTip(
      id: 'tip_5',
      title: 'In FWD skid — gently accelerate',
      description:
          'If the rear axle starts sliding, smoothly add throttle and steer into the skid. Do not hit the brakes!',
      category: 'winter',
      iconKey: 'car_drive',
      imagePath: 'assets/images/tips/tip_5.webp',
    ),
    DriverTip(
      id: 'tip_6',
      title: 'In RWD skid — release accelerator',
      description:
          'In a rear-wheel drive skid, immediately release the accelerator and gently correct trajectory with the wheel.',
      category: 'winter',
      iconKey: 'car_skid',
      imagePath: 'assets/images/tips/tip_6.webp',
    ),
    DriverTip(
      id: 'tip_7',
      title: 'Stop strictly before the STOP sign',
      description:
          'Sign 6.16 "Stop line" and marking define the boundary. Crossing with the bumper is recorded as running a red light.',
      category: 'rules',
      iconKey: 'stop_sign',
      imagePath: 'assets/images/tips/tip_7.webp',
    ),
    DriverTip(
      id: 'tip_8',
      title: 'Do not tailgate a truck before passing',
      description:
          'Stay 25–30 meters behind the truck to have a clear advance view of the oncoming lane.',
      category: 'highway',
      iconKey: 'truck',
      imagePath: 'assets/images/tips/tip_8.webp',
    ),
    DriverTip(
      id: 'tip_9',
      title: 'On a slope, descending traffic yields',
      description:
          'On steep slopes with signs 1.13 and 1.14, the vehicle moving uphill has priority.',
      category: 'rules',
      iconKey: 'slope',
      imagePath: 'assets/images/tips/tip_9.webp',
    ),
    DriverTip(
      id: 'tip_10',
      title: 'Green light does not guarantee safety',
      description:
          'Proceeding on green, ensure all vehicles from the cross street have cleared the intersection.',
      category: 'safety',
      iconKey: 'traffic_light',
      imagePath: 'assets/images/tips/tip_10.webp',
    ),
    DriverTip(
      id: 'tip_11',
      title: 'Engine-brake on slippery roads',
      description:
          'Downshift early. This prevents wheel lockup and car skidding.',
      category: 'winter',
      iconKey: 'ice',
      imagePath: 'assets/images/tips/tip_11.webp',
    ),
    DriverTip(
      id: 'tip_12',
      title: 'Do not turn wheels while waiting to turn left',
      description:
          'Waiting for a gap in oncoming traffic, keep wheels straight. A rear-end hit will not push you into oncoming cars.',
      category: 'safety',
      iconKey: 'turn_left',
      imagePath: 'assets/images/tips/tip_12.webp',
    ),
    DriverTip(
      id: 'tip_13',
      title: 'Cannot see truck mirrors? Driver cannot see you',
      description:
          'Large trucks have huge blind spots on the right and directly under the cab. Do not linger beside them.',
      category: 'highway',
      iconKey: 'blind_spot',
      imagePath: 'assets/images/tips/tip_13.webp',
    ),
    DriverTip(
      id: 'tip_14',
      title: 'Adjacent lane slows down — you brake too',
      description:
          'If a car in the neighboring lane slows down before a crosswalk, someone is likely crossing.',
      category: 'safety',
      iconKey: 'pedestrian',
      imagePath: 'assets/images/tips/tip_14.webp',
    ),
    DriverTip(
      id: 'tip_15',
      title: 'Truck swings left before a right turn',
      description:
          'Long trucks need clearance for trailer off-tracking. Never try to squeeze into the open pocket on the right.',
      category: 'maneuver',
      iconKey: 'turn_right',
      imagePath: 'assets/images/tips/tip_15.webp',
    ),
    DriverTip(
      id: 'tip_16',
      title: 'Turn on AC when windows fog up',
      description:
          'Air conditioning quickly dehumidifies cabin air. Direct airflow to windshield and turn off recirculation.',
      category: 'comfort',
      iconKey: 'wind',
      imagePath: 'assets/images/tips/tip_16.webp',
    ),
    DriverTip(
      id: 'tip_17',
      title: 'On a slope, turn wheels into the curb',
      description:
          'Parking downhill, turn wheels right (into curb); uphill with curb, turn wheels left.',
      category: 'parking',
      iconKey: 'parking_icon',
      imagePath: 'assets/images/tips/tip_17.webp',
    ),
    DriverTip(
      id: 'tip_18',
      title: 'Use low beams and fog lights in fog',
      description:
          'High beams create a blinding white wall of water droplets. Reduce speed and keep your distance.',
      category: 'weather',
      iconKey: 'fog',
      imagePath: 'assets/images/tips/tip_18.webp',
    ),
    DriverTip(
      id: 'tip_19',
      title: 'Hazard triangle: 15 m in city, 30 m on highway',
      description:
          'Place the sign well in advance so other drivers have time to change lanes safely.',
      category: 'rules',
      iconKey: 'hazard_triangle',
      imagePath: 'assets/images/tips/tip_19.webp',
    ),
    DriverTip(
      id: 'tip_20',
      title: 'Take a 15-minute break every 2–3 hours',
      description:
          'Heavy eyelids and frequent yawning signal microsleep. Pull over, drink water, and do light stretching.',
      category: 'safety',
      iconKey: 'rest',
    ),
  ];

  static const List<DriverTip> _tipsKk = [
    DriverTip(
      id: 'tip_1',
      title: '3 секундтық арақашықтықты сақтаңыз',
      description:
          'Алдыңғы көлік өткен бағдарды белгілеңіз. Сіз оған «бір-екі-үш» санағаннан ерте жетпеуіңіз керек.',
      category: 'safety',
      iconKey: 'timer',
      imagePath: 'assets/images/tips/tip_1.webp',
    ),
    DriverTip(
      id: 'tip_2',
      title: 'Терең шалшықтарда тежемеңіз',
      description:
          'Егер көлік «қалқи» бастаса (аквапланирлеу), рульді бұрмаңыз және ілініс қалпына келгенше газды ақырын босатыңыз.',
      category: 'weather',
      iconKey: 'water',
      imagePath: 'assets/images/tips/tip_2.webp',
    ),
    DriverTip(
      id: 'tip_3',
      title: 'Айналарды соқыр аймақсыз реттеңіз',
      description:
          'Бүйірлік айналарда тек өз көлігіңіздің артқы қанатының шеті ғана көрінуі керек, қалған кеңістік — жол.',
      category: 'mirrors',
      iconKey: 'visibility',
      imagePath: 'assets/images/tips/tip_3.webp',
    ),
    DriverTip(
      id: 'tip_4',
      title: 'Шеңберге кіру — оң жақ бұрылыс сигналымен',
      description:
          'Айналмалы қозғалысы бар қиылысқа кіргенде тек оң жақ бұрылыс көрсеткіші қосылады, сол емес.',
      category: 'rules',
      iconKey: 'roundabout',
      imagePath: 'assets/images/tips/tip_4.webp',
    ),
    DriverTip(
      id: 'tip_5',
      title: 'Алдыңғы жетекті көлік сырғығанда — газ қосыңыз',
      description:
          'Егер артқы ось тая бастаса, тартуды ақырын арттырып, рульді сырғу бағытына бұрыңыз. Тежегішті баспаңыз!',
      category: 'winter',
      iconKey: 'car_drive',
      imagePath: 'assets/images/tips/tip_5.webp',
    ),
    DriverTip(
      id: 'tip_6',
      title: 'Артқы жетекті көлік сырғығанда — газды босатыңыз',
      description:
          'Артқы жетекті көлік сырғыған кезде дереу газ педалін босатыңыз және траекторияны рульмен жұмсақ түзетіңіз.',
      category: 'winter',
      iconKey: 'car_skid',
      imagePath: 'assets/images/tips/tip_6.webp',
    ),
    DriverTip(
      id: 'tip_7',
      title: '«СТОП» белгісінің алдында қатаң тоқтаңыз',
      description:
          '6.16 «Тоқтау сызығы» белгісі мен таңба шекараны анықтайды. Бампермен өту камерамен қызылға өту ретінде тіркеледі.',
      category: 'rules',
      iconKey: 'stop_sign',
      imagePath: 'assets/images/tips/tip_7.webp',
    ),
    DriverTip(
      id: 'tip_8',
      title: 'Басып озу алдында жүк көлігіне тым жақындамаңыз',
      description:
          'Қарсы келе жатқан жолақты алдын ала жақсы көру үшін жүк көлігінен 25–30 метр артта жүріңіз.',
      category: 'highway',
      iconKey: 'truck',
      imagePath: 'assets/images/tips/tip_8.webp',
    ),
    DriverTip(
      id: 'tip_9',
      title: 'Еңісте төмен түсіп келе жатқан көлік жол береді',
      description:
          '1.13 және 1.14 белгілері бар тік еңістер мен өрлерде тауға көтеріліп келе жатқан көлік басымдыққа ие.',
      category: 'rules',
      iconKey: 'slope',
      imagePath: 'assets/images/tips/tip_9.webp',
    ),
    DriverTip(
      id: 'tip_10',
      title: 'Жасыл түс қауіпсіздікке кепілдік бермейді',
      description:
          'Рұқсат беретін белгіге шыққан кезде, көлденең бағыттағы барлық көліктер өтуді аяқтағанына көз жеткізіңіз.',
      category: 'safety',
      iconKey: 'traffic_light',
      imagePath: 'assets/images/tips/tip_10.webp',
    ),
    DriverTip(
      id: 'tip_11',
      title: 'Тайғақ жолда қозғалтқышпен тежеңіз',
      description:
          'Төменгі берілістерге алдын ала ауысыңыз. Бұл доңғалақтардың бұғатталуын және көліктің тайып кетуін болдырмайды.',
      category: 'winter',
      iconKey: 'ice',
      imagePath: 'assets/images/tips/tip_11.webp',
    ),
    DriverTip(
      id: 'tip_12',
      title: 'Солға бұрылғанда доңғалақтарды алдын ала бұрмаңыз',
      description:
          'Қарсы ағындағы бос орынды күткенде доңғалақтарды түзу ұстаңыз. Арттан соққы тигенде көлік қарсы бетке ұшып кетпейді.',
      category: 'safety',
      iconKey: 'turn_left',
      imagePath: 'assets/images/tips/tip_12.webp',
    ),
    DriverTip(
      id: 'tip_13',
      title: 'Жүк көлігінің айнасын көрмесеңіз — жүргізуші де сізді көрмейді',
      description:
          'Ауыр жүк көліктерінің оң жағында және кабинаның дәл астында үлкен соқыр аймақтары бар. Олардың жанында бөгелмеңіз.',
      category: 'highway',
      iconKey: 'blind_spot',
      imagePath: 'assets/images/tips/tip_13.webp',
    ),
    DriverTip(
      id: 'tip_14',
      title: 'Көрші қатар баяуласа — сіз де тежеңіз',
      description:
          'Егер қатардағы көлік жаяу жүргіншілер өткелінің алдында жылдамдықты азайтса, оның артында міндетті түрде жаяу жүргінші бар.',
      category: 'safety',
      iconKey: 'pedestrian',
      imagePath: 'assets/images/tips/tip_14.webp',
    ),
    DriverTip(
      id: 'tip_15',
      title: 'Жүк көлігі оңға бұрылар алдында солға қарай алады',
      description:
          'Ұзын көліктерге тіркеменің бұрылуы үшін радиус қажет. Оң жақта ашылған қалтаға ешқашан сыналап кірмеңіз.',
      category: 'maneuver',
      iconKey: 'turn_right',
      imagePath: 'assets/images/tips/tip_15.webp',
    ),
    DriverTip(
      id: 'tip_16',
      title: 'Әйнектер терлегенде кондиционерді қосыңыз',
      description:
          'Кондиционер салондағы ауаны тез құрғатады. Ауа ағынын маңдайша әйнекке бағыттаңыз және рециркуляцияны өшіріңіз.',
      category: 'comfort',
      iconKey: 'wind',
      imagePath: 'assets/images/tips/tip_16.webp',
    ),
    DriverTip(
      id: 'tip_17',
      title: 'Еңісте доңғалақтарды жиектасқа қарай бұрыңыз',
      description:
          'Еңісте тұрақтағанда доңғалақтарды оңға (жиектасқа), ал жиектасы бар өрде — одан солға бағыттаңыз.',
      category: 'parking',
      iconKey: 'parking_icon',
      imagePath: 'assets/images/tips/tip_17.webp',
    ),
    DriverTip(
      id: 'tip_18',
      title: 'Тұманда тек жақын жарықты және тұманға қарсы шамдарды қосыңыз',
      description:
          'Алыс жарық су тамшыларынан соқыр ететін ақ қабырға жасайды. Жылдамдықты азайтып, қашықтықты сақтаңыз.',
      category: 'weather',
      iconKey: 'fog',
      imagePath: 'assets/images/tips/tip_18.webp',
    ),
    DriverTip(
      id: 'tip_19',
      title: 'Авариялық тоқтау белгісі: қалада 15 м, тас жолда 30 м',
      description:
          'Басқа жүргізушілердің жолақ ауыстыруға уақыты болуы үшін белгіні алдын ала қойыңыз.',
      category: 'rules',
      iconKey: 'hazard_triangle',
      imagePath: 'assets/images/tips/tip_19.webp',
    ),
    DriverTip(
      id: 'tip_20',
      title: 'Әр 2–3 сағат сайын 15 минут демалыңыз',
      description:
          'Ауыр қабақ пен жиі есінеу — микроұйқының айқын белгісі. Тоқтаңыз, су ішіңіз және жеңіл сергіту жасаңыз.',
      category: 'safety',
      iconKey: 'rest',
    ),
  ];

  static String resolveCategoryTitle(String category, [String? lang]) {
    switch (lang) {
      case 'en':
        switch (category.toLowerCase()) {
          case 'safety':
            return 'Safety';
          case 'weather':
            return 'Weather';
          case 'winter':
            return 'Winter driving';
          case 'rules':
            return 'Traffic Rules';
          case 'highway':
            return 'Highway';
          case 'maneuver':
            return 'Maneuvers';
          case 'parking':
            return 'Parking';
          case 'comfort':
            return 'Comfort';
          case 'fuel':
            return 'Economy';
          default:
            return 'Tips';
        }
      case 'kk':
        switch (category.toLowerCase()) {
          case 'safety':
            return 'Қауіпсіздік';
          case 'weather':
            return 'Ауа райы';
          case 'winter':
            return 'Қысқы жүргізу';
          case 'rules':
            return 'ЖҚЕ';
          case 'highway':
            return 'Тас жол';
          case 'maneuver':
            return 'Манёврлер';
          case 'parking':
            return 'Тұрақ';
          case 'comfort':
            return 'Жайлылық';
          case 'fuel':
            return 'Үнемдеу';
          default:
            return 'Кеңестер';
        }
      case 'ru':
      default:
        switch (category.toLowerCase()) {
          case 'safety':
            return 'Безопасность';
          case 'weather':
            return 'Погода';
          case 'winter':
            return 'Зимняя езда';
          case 'rules':
            return 'ПДД';
          case 'highway':
            return 'Трасса';
          case 'maneuver':
            return 'Маневры';
          case 'parking':
            return 'Парковка';
          case 'comfort':
            return 'Комфорт';
          case 'fuel':
            return 'Экономия';
          default:
            return 'Советы';
        }
    }
  }
}
