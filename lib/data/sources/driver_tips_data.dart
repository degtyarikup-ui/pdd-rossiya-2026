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
      title: 'Три секунды — ориентир для дистанции',
      description:
          'Выберите ориентир. После передней машины досчитайте до трёх и только потом проедьте его. В дождь и гололёд оставляйте больше места.',
      category: 'safety',
      iconKey: 'timer',
      imagePath: 'assets/images/tips/tip_1.webp',
    ),
    DriverTip(
      id: 'tip_2',
      title: 'На мокрой дороге избегайте резких движений',
      description:
          'Сбавьте скорость перед лужей. Если машину повело по воде, плавно отпустите газ и держите руль прямо до восстановления сцепления.',
      category: 'weather',
      iconKey: 'water',
      imagePath: 'assets/images/tips/tip_2.webp',
    ),
    DriverTip(
      id: 'tip_3',
      title: 'Настройте зеркала и проверяйте слепую зону',
      description:
          'Отрегулируйте зеркала на стоящем автомобиле. Перед перестроением дополнительно поверните голову и проверьте слепую зону.',
      category: 'mirrors',
      iconKey: 'visibility',
      imagePath: 'assets/images/tips/tip_3.webp',
    ),
    DriverTip(
      id: 'tip_4',
      title: 'Перед въездом на круг включите правый поворотник',
      description:
          'Заранее подайте сигнал перед въездом. Перед съездом с круга снова включите правый поворотник.',
      category: 'rules',
      iconKey: 'roundabout',
      imagePath: 'assets/images/tips/tip_4.webp',
    ),
    DriverTip(
      id: 'tip_5',
      title: 'Снижайте скорость до поворота',
      description:
          'На скользкой дороге заранее сбросьте скорость. В повороте избегайте резкого газа, торможения и движений рулём.',
      category: 'winter',
      iconKey: 'car_drive',
      imagePath: 'assets/images/tips/tip_5.webp',
    ),
    DriverTip(
      id: 'tip_6',
      title: 'При заносе не тормозите резко',
      description:
          'Смотрите туда, куда хотите ехать, и плавно корректируйте руль. Не тормозите резко и не делайте резких поворотов.',
      category: 'winter',
      iconKey: 'car_skid',
      imagePath: 'assets/images/tips/tip_6.webp',
    ),
    DriverTip(
      id: 'tip_7',
      title: 'Останавливайтесь перед стоп-линией',
      description:
          'На запрещающий сигнал остановитесь перед стоп-линией. Если её нет — перед светофором или пересекаемой проезжей частью.',
      category: 'rules',
      iconKey: 'stop_sign',
      imagePath: 'assets/images/tips/tip_7.webp',
    ),
    DriverTip(
      id: 'tip_8',
      title: 'Не начинайте обгон вплотную за грузовиком',
      description:
          'Из-за грузовика плохо видна встречная полоса. Оставьте дистанцию и начинайте обгон, только если обзор и расстояние позволяют безопасно его завершить.',
      category: 'highway',
      iconKey: 'truck',
      imagePath: 'assets/images/tips/tip_8.webp',
    ),
    DriverTip(
      id: 'tip_9',
      title: 'На крутом уклоне при разъезде уступают с горы',
      description:
          'Когда на уклоне со знаками 1.13 или 1.14 трудно разъехаться, уступает водитель, который едет вниз (п. 11.7 ПДД).',
      category: 'rules',
      iconKey: 'slope',
      imagePath: 'assets/images/tips/tip_9.webp',
    ),
    DriverTip(
      id: 'tip_10',
      title: 'На зелёный убедитесь, что путь свободен',
      description:
          'Перед въездом на перекрёсток проверьте, что он свободен. Уступите тем, кто завершает проезд (п. 13.8 ПДД).',
      category: 'safety',
      iconKey: 'traffic_light',
      imagePath: 'assets/images/tips/tip_10.webp',
    ),
    DriverTip(
      id: 'tip_11',
      title: 'На скользкой дороге тормозите плавно',
      description:
          'Снизьте скорость заранее и увеличьте дистанцию. Резкое торможение может привести к потере сцепления.',
      category: 'winter',
      iconKey: 'ice',
      imagePath: 'assets/images/tips/tip_11.webp',
    ),
    DriverTip(
      id: 'tip_12',
      title: 'При ожидании левого поворота держите колёса прямо',
      description:
          'Пока ждёте встречный поток, не выворачивайте колёса заранее. Так при ударе сзади автомобиль с меньшей вероятностью вынесет на встречную полосу.',
      category: 'safety',
      iconKey: 'turn_left',
      imagePath: 'assets/images/tips/tip_12.webp',
    ),
    DriverTip(
      id: 'tip_13',
      title: 'Не задерживайтесь рядом с грузовиком',
      description:
          'У грузовика есть зоны, в которых водителю трудно вас заметить. Не едьте долго сбоку и не рассчитывайте только на зеркала.',
      category: 'highway',
      iconKey: 'blind_spot',
      imagePath: 'assets/images/tips/tip_13.webp',
    ),
    DriverTip(
      id: 'tip_14',
      title: 'У перехода следите за соседними рядами',
      description:
          'Если соседняя машина замедлилась перед переходом, тоже сбавьте скорость: из-за неё может выйти пешеход.',
      category: 'safety',
      iconKey: 'pedestrian',
      imagePath: 'assets/images/tips/tip_14.webp',
    ),
    DriverTip(
      id: 'tip_15',
      title: 'Оставляйте грузовику место для поворота',
      description:
          'Длинный грузовик может сместиться влево перед правым поворотом. Не занимайте пространство справа от него.',
      category: 'maneuver',
      iconKey: 'turn_right',
      imagePath: 'assets/images/tips/tip_15.webp',
    ),
    DriverTip(
      id: 'tip_16',
      title: 'При запотевании направьте воздух на стекло',
      description:
          'Включите обдув лобового стекла и подачу наружного воздуха. Кондиционер поможет быстрее убрать влагу, если он есть.',
      category: 'comfort',
      iconKey: 'wind',
      imagePath: 'assets/images/tips/tip_16.webp',
    ),
    DriverTip(
      id: 'tip_17',
      title: 'На уклоне надёжно зафиксируйте автомобиль',
      description:
          'Используйте стояночный тормоз. На механике оставьте передачу, на автомате включите P; перед выходом убедитесь, что машина не катится.',
      category: 'parking',
      iconKey: 'parking_icon',
      imagePath: 'assets/images/tips/tip_17.webp',
    ),
    DriverTip(
      id: 'tip_18',
      title: 'В тумане снизьте скорость и включите ближний свет',
      description:
          'Используйте ближний свет или противотуманные фары. Дальний свет может отражаться от капель и мешать видеть дорогу.',
      category: 'weather',
      iconKey: 'fog',
      imagePath: 'assets/images/tips/tip_18.webp',
    ),
    DriverTip(
      id: 'tip_19',
      title: 'Выставляйте знак аварийной остановки по ПДД',
      description:
          'В населённом пункте — не менее 15 м от автомобиля, вне населённого пункта — не менее 30 м (п. 7.2 ПДД).',
      category: 'rules',
      iconKey: 'hazard_triangle',
      imagePath: 'assets/images/tips/tip_19.webp',
    ),
    DriverTip(
      id: 'tip_20',
      title: 'Остановитесь, если начинает клонить в сон',
      description:
          'Зевота и тяжёлые веки — повод безопасно остановиться и отдохнуть. Не пытайтесь перебороть сон за рулём.',
      category: 'safety',
      iconKey: 'rest',
      imagePath: 'assets/images/tips/tip_20.webp',
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
      title: 'Three seconds is a useful gap guide',
      description:
          'Pick a landmark. Count to three after the car ahead passes it, then pass it yourself. Leave more space in rain or on ice.',
      category: 'safety',
      iconKey: 'timer',
      imagePath: 'assets/images/tips/tip_1.webp',
    ),
    DriverTip(
      id: 'tip_2',
      title: 'Avoid sudden moves on wet roads',
      description:
          'Slow down before puddles. If the car starts to hydroplane, ease off the accelerator and hold the wheel steady until grip returns.',
      category: 'weather',
      iconKey: 'water',
      imagePath: 'assets/images/tips/tip_2.webp',
    ),
    DriverTip(
      id: 'tip_3',
      title: 'Adjust your mirrors and check blind spots',
      description:
          'Set mirrors while parked. Before changing lanes, also turn your head to check the blind spot.',
      category: 'mirrors',
      iconKey: 'visibility',
      imagePath: 'assets/images/tips/tip_3.webp',
    ),
    DriverTip(
      id: 'tip_4',
      title: 'Signal right before entering a roundabout',
      description:
          'Signal in advance before entering. Signal right again before leaving the roundabout.',
      category: 'rules',
      iconKey: 'roundabout',
      imagePath: 'assets/images/tips/tip_4.webp',
    ),
    DriverTip(
      id: 'tip_5',
      title: 'Slow down before a turn',
      description:
          'On slippery roads, reduce speed early. Avoid sudden acceleration, braking, or steering in the turn.',
      category: 'winter',
      iconKey: 'car_drive',
      imagePath: 'assets/images/tips/tip_5.webp',
    ),
    DriverTip(
      id: 'tip_6',
      title: 'If the car skids, avoid hard braking',
      description:
          'Look where you want to go and steer smoothly. Do not brake hard or make sudden turns.',
      category: 'winter',
      iconKey: 'car_skid',
      imagePath: 'assets/images/tips/tip_6.webp',
    ),
    DriverTip(
      id: 'tip_7',
      title: 'Stop before the stop line',
      description:
          'At a red light, stop before the stop line. If there is none, stop before the signal or the intersecting road.',
      category: 'rules',
      iconKey: 'stop_sign',
      imagePath: 'assets/images/tips/tip_7.webp',
    ),
    DriverTip(
      id: 'tip_8',
      title: 'Do not follow a truck too closely before overtaking',
      description:
          'A truck blocks your view of oncoming traffic. Leave space and overtake only when you can see far enough to finish safely.',
      category: 'highway',
      iconKey: 'truck',
      imagePath: 'assets/images/tips/tip_8.webp',
    ),
    DriverTip(
      id: 'tip_9',
      title: 'On a steep hill, downhill traffic may need to yield',
      description:
          'When passing is difficult on a slope marked 1.13 or 1.14, the downhill driver must yield (Russian Traffic Rules, 11.7).',
      category: 'rules',
      iconKey: 'slope',
      imagePath: 'assets/images/tips/tip_9.webp',
    ),
    DriverTip(
      id: 'tip_10',
      title: 'On green, check that the way is clear',
      description:
          'Before entering an intersection, make sure it is clear. Yield to vehicles still clearing it (Russian Traffic Rules, 13.8).',
      category: 'safety',
      iconKey: 'traffic_light',
      imagePath: 'assets/images/tips/tip_10.webp',
    ),
    DriverTip(
      id: 'tip_11',
      title: 'Brake gently on slippery roads',
      description:
          'Reduce speed early and leave more space. Sudden braking can make you lose grip.',
      category: 'winter',
      iconKey: 'ice',
      imagePath: 'assets/images/tips/tip_11.webp',
    ),
    DriverTip(
      id: 'tip_12',
      title: 'Keep the wheels straight while waiting to turn left',
      description:
          'Do not turn the wheels early while waiting for oncoming traffic. A rear impact is then less likely to push you into oncoming traffic.',
      category: 'safety',
      iconKey: 'turn_left',
      imagePath: 'assets/images/tips/tip_12.webp',
    ),
    DriverTip(
      id: 'tip_13',
      title: 'Do not linger beside a truck',
      description:
          'Trucks have areas where the driver may not see you. Avoid riding alongside and do not rely on mirrors alone.',
      category: 'highway',
      iconKey: 'blind_spot',
      imagePath: 'assets/images/tips/tip_13.webp',
    ),
    DriverTip(
      id: 'tip_14',
      title: 'Watch nearby lanes at a crosswalk',
      description:
          'If a car in another lane slows at a crosswalk, slow down too: a pedestrian may be hidden behind it.',
      category: 'safety',
      iconKey: 'pedestrian',
      imagePath: 'assets/images/tips/tip_14.webp',
    ),
    DriverTip(
      id: 'tip_15',
      title: 'Leave room for a truck to turn',
      description:
          'A long truck may swing left before turning right. Do not move into the space beside it.',
      category: 'maneuver',
      iconKey: 'turn_right',
      imagePath: 'assets/images/tips/tip_15.webp',
    ),
    DriverTip(
      id: 'tip_16',
      title: 'Clear a fogged windshield',
      description:
          'Direct airflow to the windshield and use fresh outside air. Air conditioning can clear moisture faster if available.',
      category: 'comfort',
      iconKey: 'wind',
      imagePath: 'assets/images/tips/tip_16.webp',
    ),
    DriverTip(
      id: 'tip_17',
      title: 'Secure your car on a slope',
      description:
          'Use the parking brake. Leave a gear engaged in a manual car or select P in an automatic, then make sure the car is secure.',
      category: 'parking',
      iconKey: 'parking_icon',
      imagePath: 'assets/images/tips/tip_17.webp',
    ),
    DriverTip(
      id: 'tip_18',
      title: 'Slow down and use low beams in fog',
      description:
          'Use low beams or fog lights. High beams can reflect off water droplets and make the road harder to see.',
      category: 'weather',
      iconKey: 'fog',
      imagePath: 'assets/images/tips/tip_18.webp',
    ),
    DriverTip(
      id: 'tip_19',
      title: 'Place the hazard triangle as the rules require',
      description:
          'At least 15 m from the vehicle in a built-up area and 30 m outside one (Russian Traffic Rules, 7.2).',
      category: 'rules',
      iconKey: 'hazard_triangle',
      imagePath: 'assets/images/tips/tip_19.webp',
    ),
    DriverTip(
      id: 'tip_20',
      title: 'Stop if you feel sleepy',
      description:
          'Yawning and heavy eyelids mean it is time to stop safely and rest. Do not try to fight sleep while driving.',
      category: 'safety',
      iconKey: 'rest',
      imagePath: 'assets/images/tips/tip_20.webp',
    ),
  ];

  static const List<DriverTip> _tipsKk = [
    DriverTip(
      id: 'tip_1',
      title: 'Үш секунд — арақашықтыққа арналған бағдар',
      description:
          'Бағдар таңдаңыз. Алдыңғы көлік өткен соң, үшке дейін санап барып өзіңіз өтіңіз. Жаңбырда және көктайғақта арақашықтықты ұлғайтыңыз.',
      category: 'safety',
      iconKey: 'timer',
      imagePath: 'assets/images/tips/tip_1.webp',
    ),
    DriverTip(
      id: 'tip_2',
      title: 'Ылғал жолда күрт қимыл жасамаңыз',
      description:
          'Шалшыққа дейін жылдамдықты азайтыңыз. Көлік су бетінде сырғи бастаса, газды біртіндеп босатып, ілініс қалпына келгенше рульді тұрақты ұстаңыз.',
      category: 'weather',
      iconKey: 'water',
      imagePath: 'assets/images/tips/tip_2.webp',
    ),
    DriverTip(
      id: 'tip_3',
      title: 'Айналарды реттеп, соқыр аймақты тексеріңіз',
      description:
          'Айналарды көлік тоқтап тұрғанда реттеңіз. Жолақ ауыстырмас бұрын басыңызды бұрып, соқыр аймақты да тексеріңіз.',
      category: 'mirrors',
      iconKey: 'visibility',
      imagePath: 'assets/images/tips/tip_3.webp',
    ),
    DriverTip(
      id: 'tip_4',
      title: 'Шеңберге кірерде оң жақ бұрылыс сигналын беріңіз',
      description:
          'Кірер алдында сигналды ертерек қосыңыз. Шеңберден шығар алдында оң жақ сигналды қайта қосыңыз.',
      category: 'rules',
      iconKey: 'roundabout',
      imagePath: 'assets/images/tips/tip_4.webp',
    ),
    DriverTip(
      id: 'tip_5',
      title: 'Бұрылыстың алдында жылдамдықты азайтыңыз',
      description:
          'Тайғақ жолда жылдамдықты ертерек азайтыңыз. Бұрылыс кезінде газды, тежегішті немесе рульді күрт қолданбаңыз.',
      category: 'winter',
      iconKey: 'car_drive',
      imagePath: 'assets/images/tips/tip_5.webp',
    ),
    DriverTip(
      id: 'tip_6',
      title: 'Көлік сырғыса, күрт тежемеңіз',
      description:
          'Жүргіңіз келген бағытқа қарап, рульді бірқалыпты түзетіңіз. Күрт тежемеңіз және рульді шұғыл бұрмаңыз.',
      category: 'winter',
      iconKey: 'car_skid',
      imagePath: 'assets/images/tips/tip_6.webp',
    ),
    DriverTip(
      id: 'tip_7',
      title: 'Тоқтау сызығының алдында тоқтаңыз',
      description:
          'Қызыл сигналда тоқтау сызығынан аспаңыз. Сызық болмаса, бағдаршамның немесе қиылысатын жолдың алдында тоқтаңыз.',
      category: 'rules',
      iconKey: 'stop_sign',
      imagePath: 'assets/images/tips/tip_7.webp',
    ),
    DriverTip(
      id: 'tip_8',
      title: 'Жүк көлігінің артынан тым жақын жүрмеңіз',
      description:
          'Жүк көлігі қарсы жолды көруге кедергі жасайды. Арақашықтық сақтап, тек қауіпсіз аяқтауға көрініс пен орын жеткілікті болса басып озыңыз.',
      category: 'highway',
      iconKey: 'truck',
      imagePath: 'assets/images/tips/tip_8.webp',
    ),
    DriverTip(
      id: 'tip_9',
      title: 'Тік еңісте төмен түсіп келе жатқан көлік жол беруі мүмкін',
      description:
          '1.13 немесе 1.14 белгісі бар еңісте өту қиындаса, төмен түсіп келе жатқан жүргізуші жол береді (Ресей ЖҚЕ, 11.7-т.).',
      category: 'rules',
      iconKey: 'slope',
      imagePath: 'assets/images/tips/tip_9.webp',
    ),
    DriverTip(
      id: 'tip_10',
      title: 'Жасыл жанса да, жолдың ашық екенін тексеріңіз',
      description:
          'Қиылысқа кірмес бұрын оның бос екеніне көз жеткізіңіз. Қиылыстан шығып үлгеріп жатқан көліктерге жол беріңіз (Ресей ЖҚЕ, 13.8-т.).',
      category: 'safety',
      iconKey: 'traffic_light',
      imagePath: 'assets/images/tips/tip_10.webp',
    ),
    DriverTip(
      id: 'tip_11',
      title: 'Тайғақ жолда бірқалыпты тежеңіз',
      description:
          'Жылдамдықты алдын ала азайтып, арақашықтықты ұлғайтыңыз. Күрт тежеу дөңгелектің жолмен ілінісуін жоғалтуы мүмкін.',
      category: 'winter',
      iconKey: 'ice',
      imagePath: 'assets/images/tips/tip_11.webp',
    ),
    DriverTip(
      id: 'tip_12',
      title: 'Солға бұрылуды күткенде дөңгелектерді түзу ұстаңыз',
      description:
          'Қарсы ағынды күткенде дөңгелектерді алдын ала бұрмаңыз. Арттан соққы болса, көлік қарсы жолаққа азырақ ығысады.',
      category: 'safety',
      iconKey: 'turn_left',
      imagePath: 'assets/images/tips/tip_12.webp',
    ),
    DriverTip(
      id: 'tip_13',
      title: 'Жүк көлігінің жанында ұзақ жүрмеңіз',
      description:
          'Жүк көлігінің жүргізушісі сізді байқамай қалуы мүмкін аймақтар бар. Қасында ұзақ жүрмеңіз және айнаға ғана сенбеңіз.',
      category: 'highway',
      iconKey: 'blind_spot',
      imagePath: 'assets/images/tips/tip_13.webp',
    ),
    DriverTip(
      id: 'tip_14',
      title: 'Жаяу жүргіншілер өткелінде көрші жолақтарды бақылаңыз',
      description:
          'Көрші жолақтағы көлік өткел алдында баяуласа, сіз де баяулаңыз: оның артында жаяу жүргінші болуы мүмкін.',
      category: 'safety',
      iconKey: 'pedestrian',
      imagePath: 'assets/images/tips/tip_14.webp',
    ),
    DriverTip(
      id: 'tip_15',
      title: 'Жүк көлігіне бұрылуға орын қалдырыңыз',
      description:
          'Ұзын жүк көлігі оңға бұрыларда солға қарай ығысуы мүмкін. Оның оң жағындағы бос орынға кірмеңіз.',
      category: 'maneuver',
      iconKey: 'turn_right',
      imagePath: 'assets/images/tips/tip_15.webp',
    ),
    DriverTip(
      id: 'tip_16',
      title: 'Әйнек буланса, ауаны оған бағыттаңыз',
      description:
          'Ауа ағынын алдыңғы әйнекке бағыттап, сырттан ауа кіргізіңіз. Бар болса, кондиционер ылғалды тезірек кетіреді.',
      category: 'comfort',
      iconKey: 'wind',
      imagePath: 'assets/images/tips/tip_16.webp',
    ),
    DriverTip(
      id: 'tip_17',
      title: 'Еңісте көлікті сенімді бекітіңіз',
      description:
          'Тұрақ тежегішін қолданыңыз. Механикалық беріліс қорабында берілісті қосып, автоматта P күйін таңдаңыз; көліктің қозғалмай тұрғанын тексеріңіз.',
      category: 'parking',
      iconKey: 'parking_icon',
      imagePath: 'assets/images/tips/tip_17.webp',
    ),
    DriverTip(
      id: 'tip_18',
      title: 'Тұманда жылдамдықты азайтып, жақын жарықты қосыңыз',
      description:
          'Жақын жарықты немесе тұманға қарсы шамдарды қолданыңыз. Алыс жарық су тамшыларынан шағылысып, көріністі нашарлатуы мүмкін.',
      category: 'weather',
      iconKey: 'fog',
      imagePath: 'assets/images/tips/tip_18.webp',
    ),
    DriverTip(
      id: 'tip_19',
      title: 'Апаттық тоқтау белгісін ереже бойынша қойыңыз',
      description:
          'Елді мекенде көліктен кемінде 15 м, елді мекеннен тыс жерде кемінде 30 м қашықтықта қойыңыз (Ресей ЖҚЕ, 7.2-т.).',
      category: 'rules',
      iconKey: 'hazard_triangle',
      imagePath: 'assets/images/tips/tip_19.webp',
    ),
    DriverTip(
      id: 'tip_20',
      title: 'Ұйқы қысса, қауіпсіз жерге тоқтаңыз',
      description:
          'Есінеу мен ауырлаған қабақ — демалу керек деген белгі. Рөлде отырып ұйқымен күреспеңіз.',
      category: 'safety',
      iconKey: 'rest',
      imagePath: 'assets/images/tips/tip_20.webp',
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
