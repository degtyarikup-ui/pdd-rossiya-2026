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
      description: 'Засеките ориентир, мимо которого проехало переднее авто. Вы должны проехать его не раньше счета «раз-два-три».',
      category: 'safety',
      iconKey: 'timer',
      imagePath: 'assets/images/tips/tip_1.png',
    ),
    DriverTip(
      id: 'tip_2',
      title: 'Не тормозите в глубоких лужах',
      description: 'Если авто начало «всплывать» (аквапланирование), не крутите руль и плавно отпустите газ до восстановления сцепления.',
      category: 'weather',
      iconKey: 'water',
      imagePath: 'assets/images/tips/tip_2.png',
    ),
    DriverTip(
      id: 'tip_3',
      title: 'Настройте зеркала без слепых зон',
      description: 'В боковых зеркалах должен быть виден лишь краешек заднего крыла своего авто, а остальное пространство — дорога.',
      category: 'mirrors',
      iconKey: 'visibility',
      imagePath: 'assets/images/tips/tip_3.png',
    ),
    DriverTip(
      id: 'tip_4',
      title: 'Въезд на круг — с правым поворотником',
      description: 'При въезде на перекресток с круговым движением включается только правый указатель поворота, а не левый.',
      category: 'rules',
      iconKey: 'roundabout',
      imagePath: 'assets/images/tips/tip_4.png',
    ),
    DriverTip(
      id: 'tip_5',
      title: 'На переднем приводе при заносе — добавьте газ',
      description: 'Если заднюю ось начало сносить, плавно прибавьте тягу и направьте руль в сторону заноса. Не жмите на тормоз!',
      category: 'winter',
      iconKey: 'car_drive',
      imagePath: 'assets/images/tips/tip_5.png',
    ),
    DriverTip(
      id: 'tip_6',
      title: 'На заднем приводе при заносе — сбросьте газ',
      description: 'При заносе заднеприводного авто немедленно отпустите педаль газа и мягко скорректируйте траекторию рулем.',
      category: 'winter',
      iconKey: 'car_skid',
      imagePath: 'assets/images/tips/tip_6.png',
    ),
    DriverTip(
      id: 'tip_7',
      title: 'Остановитесь строго до знака «СТОП»',
      description: 'Знак 6.16 «Стоп-линия» и разметка определяют границу. Наезд бампером фиксируется камерой как проезд на красный.',
      category: 'rules',
      iconKey: 'stop_sign',
      imagePath: 'assets/images/tips/tip_7.png',
    ),
    DriverTip(
      id: 'tip_8',
      title: 'Не прижимайтесь к фуре перед обгоном',
      description: 'Держитесь в 25–30 метрах позади грузовика, чтобы заранее хорошо просматривать встречную полосу.',
      category: 'highway',
      iconKey: 'truck',
      imagePath: 'assets/images/tips/tip_8.png',
    ),
    DriverTip(
      id: 'tip_9',
      title: 'На уклоне уступает тот, кто едет на спуск',
      description: 'На крутых спусках и подъемах со знаками 1.13 и 1.14 приоритет имеет автомобиль, поднимающийся в гору.',
      category: 'rules',
      iconKey: 'slope',
      imagePath: 'assets/images/tips/tip_9.png',
    ),
    DriverTip(
      id: 'tip_10',
      title: 'Зеленый свет не гарантирует безопасность',
      description: 'Выезжая на разрешающий сигнал, убедитесь, что все автомобили с поперечного направления завершили проезд.',
      category: 'safety',
      iconKey: 'traffic_light',
      imagePath: 'assets/images/tips/tip_10.png',
    ),
    DriverTip(
      id: 'tip_11',
      title: 'На скользкой дороге тормозите двигателем',
      description: 'Переходите на пониженные передачи заблаговременно. Это предотвращает блокировку колес и снос машины.',
      category: 'winter',
      iconKey: 'ice',
      imagePath: 'assets/images/tips/tip_11.png',
    ),
    DriverTip(
      id: 'tip_12',
      title: 'Не выкручивайте колеса при повороте налево',
      description: 'Ожидая окна во встречном потоке, держите колеса прямо. При ударе сзади авто не вылетит на встречку.',
      category: 'safety',
      iconKey: 'turn_left',
      imagePath: 'assets/images/tips/tip_12.png',
    ),
    DriverTip(
      id: 'tip_13',
      title: 'Не видите зеркал фуры — водитель не видит вас',
      description: 'У большегрузов огромные мертвые зоны справа и прямо под кабиной. Не задерживайтесь рядом с ними.',
      category: 'highway',
      iconKey: 'blind_spot',
      imagePath: 'assets/images/tips/tip_13.png',
    ),
    DriverTip(
      id: 'tip_14',
      title: 'Соседний ряд притормозил — тормозите и вы',
      description: 'Если попутная машина снижает скорость перед пешеходным переходом, за ней наверняка идет пешеход.',
      category: 'safety',
      iconKey: 'pedestrian',
      imagePath: 'assets/images/tips/tip_14.png',
    ),
    DriverTip(
      id: 'tip_15',
      title: 'Грузовик берет левее перед правым поворотом',
      description: 'Длинномерам нужен радиус для заноса прицепа. Никогда не пытайтесь проскочить в открывшийся карман справа.',
      category: 'maneuver',
      iconKey: 'turn_right',
      imagePath: 'assets/images/tips/tip_15.png',
    ),
    DriverTip(
      id: 'tip_16',
      title: 'Включите кондиционер при запотевании стекол',
      description: 'Кондиционер быстро осушает воздух в салоне. Направьте поток на лобовое стекло и отключите рециркуляцию.',
      category: 'comfort',
      iconKey: 'wind',
      imagePath: 'assets/images/tips/tip_16.png',
    ),
    DriverTip(
      id: 'tip_17',
      title: 'На уклоне выкручивайте колеса к бордюру',
      description: 'При парковке на спуске направьте колеса вправо (в бордюр), на подъеме с бордюром — влево от него.',
      category: 'parking',
      iconKey: 'parking_icon',
      imagePath: 'assets/images/tips/tip_17.png',
    ),
    DriverTip(
      id: 'tip_18',
      title: 'В тумане включайте только ближний свет и ПТФ',
      description: 'Дальний свет создает ослепляющую белую стену из капель воды. Снижайте скорость и держите дистанцию.',
      category: 'weather',
      iconKey: 'fog',
      imagePath: 'assets/images/tips/tip_18.png',
    ),
    DriverTip(
      id: 'tip_19',
      title: 'Знак аварийной остановки: 15 м в городе, 30 м на трассе',
      description: 'Выставляйте знак заблаговременно, чтобы у других водителей было достаточно времени для перестроения.',
      category: 'rules',
      iconKey: 'hazard_triangle',
      imagePath: 'assets/images/tips/tip_19.png',
    ),
    DriverTip(
      id: 'tip_20',
      title: 'Делайте паузу на 15 минут каждые 2–3 часа',
      description: 'Тяжелые веки и частая зевота — верный сигнал микросна. Остановитесь, выпейте воды и сделайте легкую разминку.',
      category: 'safety',
      iconKey: 'rest',
    ),
  ];

  static String resolveCategoryTitle(String category) {
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
      case 'fuel':
        return 'Экономия';
      default:
        return 'Советы';
    }
  }
}
