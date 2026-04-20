import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/app_pill_search_field.dart';

class PddScreen extends StatefulWidget {
  const PddScreen({super.key});

  @override
  State<PddScreen> createState() => _PddScreenState();
}

class _PddScreenState extends State<PddScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  List<_PddSectionData> get _sections => const [
    _PddSectionData('1. Общие положения', _generalProvisions),
    _PddSectionData('2. Общие обязанности водителей', _driverDuties),
    _PddSectionData('3. Дорожные знаки', _roadSigns),
    _PddSectionData('4. Дорожная разметка', _roadMarkup),
    _PddSectionData('5. Расположение ТС на проезжей части', _vehiclePosition),
    _PddSectionData('6. Скорость движения', _speedLimits),
    _PddSectionData('7. Обгон, опережение, встречный разъезд', _overtaking),
    _PddSectionData('8. Остановка и стоянка', _parking),
    _PddSectionData('9. Проезд перекрестков', _intersections),
    _PddSectionData('10. Пешеходные переходы', _pedestrianCrossings),
    _PddSectionData('11. Пользование световыми приборами', _lightSignals),
    _PddSectionData('12. Движение через ж/д пути', _railwayCrossing),
    _PddSectionData('13. Перевозка людей и грузов', _cargoTransport),
    _PddSectionData('14. Учебная езда', _drivingLessons),
    _PddSectionData('15. Неисправности ТС', _vehicleMalfunctions),
    _PddSectionData('16. Оказание первой помощи', _firstAid),
    _PddSectionData('17. Ответственность водителя', _driverResponsibility),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filteredSections = _sections.where((section) {
      if (normalizedQuery.isEmpty) return true;

      return section.title.toLowerCase().contains(normalizedQuery) ||
          section.content.toLowerCase().contains(normalizedQuery);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                16,
                AppDimensions.screenPadding,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: double.infinity,
                    child: Text(
                      'ПДД',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingS),
                  AppPillSearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    hintText: 'Поиск',
                  ),
                ],
              ),
            ),
            Expanded(
              child: filteredSections.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppDimensions.screenPadding),
                        child: Text(
                          'Ничего не найдено. Попробуйте номер раздела или ключевое слово.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(
                        AppDimensions.screenPadding,
                      ),
                      children: [
                        ...filteredSections.map((section) {
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppDimensions.spacingM,
                            ),
                            child: _buildPddSection(
                              context,
                              section.title,
                              section.content,
                            ),
                          );
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPddSection(BuildContext context, String title, String content) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: () {
          HapticFeedbackHelper.tap();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PddDetailScreen(title: title, content: content),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingL,
            vertical: 20,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.secondaryText,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PddDetailScreen extends StatelessWidget {
  final String title;
  final String content;

  const PddDetailScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = content
        .split('\n\n')
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppDimensions.screenPadding),
              child: Row(
                children: [
                  AppChromeIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () {
                      HapticFeedbackHelper.tap();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: AppDimensions.spacingM),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.screenPadding,
                  0,
                  AppDimensions.screenPadding,
                  24,
                ),
                children: [
                  ...blocks.map((block) {
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: AppDimensions.spacingM,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(AppDimensions.spacingL),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.cardRadius,
                          ),
                        ),
                        child: Text(
                          block,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.65,
                            color: AppColors.primaryText,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PddSectionData {
  final String title;
  final String content;

  const _PddSectionData(this.title, this.content);
}

const String _generalProvisions = '''
1.1. Настоящие Правила дорожного движения устанавливают единый порядок дорожного движения на всей территории Российской Федерации.

1.2. В Правилах используются следующие основные понятия и термины:
"Автомагистраль" — дорога, обозначенная знаком 5.1 и имеющая для каждого направления движения проезжие части, отделенные друг от друга разделительной полосой.
"Велосипед" — транспортное средство, кроме инвалидных колясок, которое имеет по крайней мере два колеса и приводится в движение мускульной силой людей.
"Вынужденная остановка" — прекращение движения транспортного средства из-за его технической неисправности или опасности, создаваемой перевозимым грузом, состоянием водителя или пассажира.
"Главная дорога" — дорога, обозначенная знаками 2.1, 2.3.1–2.3.7 или 5.1.
"Дневные ходовые огни" — внешние световые приборы, предназначенные для улучшения видимости движущегося транспортного средства спереди в светлое время суток.

1.3. Участники дорожного движения обязаны знать и соблюдать относящиеся к ним правила.
''';

const String _driverDuties = '''
2.1. Водитель механического транспортного средства обязан:
2.1.1. Иметь при себе и по требованию сотрудников полиции передавать им для проверки документы на право управления ТС, регистрационные документы, страховой полис ОСАГО.
2.1.2. Передавать для проверки документы лицам, осуществляющим контрольные функции.
2.1.3. Предоставлять транспортное средство должностным лицам в случаях, предусмотренных законодательством.

2.2. Водителю запрещается:
- управлять ТС в состоянии опьянения;
- передавать управление лицам, находящимся в состоянии опьянения;
- передавать управление лицам, не имеющим при себе водительского удостоверения;
- пользоваться телефоном во время движения;
- превышать установленную скорость движения.
''';

const String _roadSigns = '''
Дорожные знаки подразделяются на восемь групп:
1. Предупреждающие знаки
2. Знаки приоритета
3. Запрещающие знаки
4. Предписывающие знаки
5. Знаки особых предписаний
6. Информационные знаки
7. Знаки сервиса
8. Знаки дополнительной информации (таблички)

Предупреждающие знаки информируют о приближении к опасному участку дороги.
Знаки приоритета устанавливают очередность проезда перекрестков и узких участков.
Запрещающие знаки вводят или отменяют определенные ограничения движения.
Предписывающие знаки предписывают направление движения.
Знаки особых предписаний вводят или отменяют режим движения.
Информационные знаки информируют о расположении населенных пунктов и объектов.
Знаки сервиса информируют о расположении соответствующих объектов.
Знаки дополнительной информации уточняют или ограничивают действие других знаков.
''';

const String _roadMarkup = '''
1.1 Сплошная линия — разделяет транспортные потоки противоположных направлений.
1.2 Сплошная линия (широкая) — обозначает край проезжей части.
1.3 Двойная сплошная линия — разделяет потоки противоположных направлений на дорогах с 4+ полосами.
1.4 Сплошная желтая линия — запрещает остановку ТС.
1.5 Прерывистая линия — разделяет потоки, разрешает перестроение.
1.6 Прерывистая линия (длинная) — предупреждает о приближении к сплошной.
1.10 Прерывистая желтая линия — запрещает стоянку.
1.11 Сплошная и прерывистая — обгон разрешен только со стороны прерывистой.
1.14.1, 1.14.2 Пешеходный переход — обозначает место для перехода.
1.15 Стоп-линия — указывает место остановки перед перекрестком.
1.17 Остановка маршрутных ТС — место остановки автобусов и троллейбусов.
1.18 Указывает разрешенные направления по полосам.
1.23.1 Полоса для велосипедистов.
''';

const String _vehiclePosition = '''
8.1 Перед началом движения, перестроением, поворотом и остановкой водитель обязан подавать сигналы световыми указателями поворота.
8.2 Подача сигнала не дает преимущества и не освобождает от принятия мер предосторожности.
8.3 При выезде на дорогу с прилегающей территории водитель должен уступить дорогу ТС и пешеходам.
8.4 При перестроении водитель должен уступить дорогу ТС, движущимся попутно без изменения направления.
8.5 Перед поворотом направо, налево или разворотом водитель обязан занять крайнее положение на проезжей части.
8.6 Поворот должен выполняться таким образом, чтобы при выезде с пересечения проезжих частей ТС не оказалось на стороне встречного движения.
8.7 При повороте направо ТС должно двигаться по возможности ближе к правому краю проезжей части.
''';

const String _speedLimits = '''
10.1 Водитель должен вести ТС со скоростью, не превышающей установленного ограничения.
10.2 Разрешенная максимальная скорость:
- в населенных пунктах — 60 км/ч;
- вне населенных пунктов — 90 км/ч;
- на автомагистралях — 110 км/ч;
- на дорогах, обозначенных знаком 5.17 — 110 км/ч.
10.3 При буксировке механических ТС — 50 км/ч.
10.4 Водителям мопедов — 50 км/ч.
10.5 Запрещается превышать скорость, указанную на знаке 3.24.
''';

const String _overtaking = '''
11.1 Перед началом обгона водитель должен убедиться, что полоса встречного движения свободна.
11.2 Обгон запрещен:
- на регулируемых перекрестках;
- на нерегулируемых перекрестках при движении по дороге, не являющейся главной;
- на пешеходных переходах;
- на железнодорожных переездах и ближе 100 м перед ними;
- на мостах, путепроводах, эстакадах и под ними;
- в тоннелях;
- на участках с ограниченной видимостью.
11.3 На дорогах с двусторонним движением, имеющих 4+ полосы, запрещается выезжать для обгона на встречную полосу.
11.4 На дорогах с двусторонним движением, имеющих 2-3 полосы, запрещается выезжать на встречную полосу для обгона.
''';

const String _parking = '''
12.1 Остановка и стоянка ТС разрешаются на правой стороне дороги на обочине, на тротуаре или обочине.
12.2 Ставить ТС разрешается в один ряд параллельно краю проезжей части.
12.3 Стоянка запрещена:
- на трамвайных путях;
- на железнодорожных переездах;
- в тоннелях;
- на пешеходных переходах и ближе 5 м перед ними;
- на проезжей части с опасными поворотами;
- ближе 5 м от края пересекаемой проезжей части;
- ближе 15 м от остановки маршрутных ТС.
12.4 Стоянка запрещена в местах, где расстояние между сплошной линией разметки и ТС менее 3 м.
''';

const String _intersections = '''
13.1 При повороте направо или налево водитель обязан уступить дорогу пешеходам и велосипедистам.
13.2 Запрещается выезжать на перекресток при заторе.
13.3 При запрещающем сигнале светофора водитель должен остановиться перед стоп-линией.
13.4 При повороте налево или развороте по зеленому сигналу светофора водитель обязан уступить дорогу встречным ТС.
13.5 При движении в направлении стрелки, включенной в дополнительной секции, водитель обязан уступить дорогу ТС, движущимся с других направлений.
13.6 Если сигналы светофора противоречат знакам приоритета — руководствоваться знаками.
13.7 На перекрестке равнозначных дорог водитель безрельсового ТС уступает дорогу ТС, приближающимся справа.
''';

const String _pedestrianCrossings = '''
14.1 Водитель ТС, приближающегося к пешеходному переходу, обязан уступить дорогу пешеходам.
14.2 Если перед нерегулируемым пешеходным переходом остановилось ТС, водители могут продолжать движение только убедившись, что перед остановившимся ТС нет пешеходов.
14.3 На регулируемых переходах водитель обязан руководствоваться сигналами светофора.
14.4 При приближении к остановке маршрутных ТС водитель обязан уступить дорогу пешеходам, идущим к ТС или от него.
''';

const String _lightSignals = '''
19.1 В темное время суток и в условиях недостаточной видимости на движущемся ТС должны быть включены фары.
19.2 Ближний свет фар должен быть включен:
- в темное время суток;
- в тоннелях;
- при движении в условиях недостаточной видимости;
- на всех механических ТС в светлое время суток.
19.3 Дальний свет должен быть переключен на ближний:
- при встречном разъезде на расстоянии 150 м;
- при ослеплении других водителей.
19.4 Противотуманные фары могут использоваться в условиях недостаточной видимости.
19.5 Аварийная сигнализация включается при ДТП, вынужденной остановке.
''';

const String _railwayCrossing = '''
15.1 Водитель должен подчиняться сигналам светофора, знакам и указаниям дежурного.
15.2 При приближении к переезду водитель обязан снизить скорость.
15.3 Запрещается:
- объезжать ТС, стоящие перед закрытым шлагбаумом;
- выезжать на переезд при закрытом шлагбауме;
- останавливаться на переезде;
- разворачиваться на переезде;
- двигаться задним ходом на переезде.
15.4 При вынужденной остановке на переезде водитель должен принять меры для освобождения переезда.
''';

const String _cargoTransport = '''
22.1 Перевозка людей в кузове грузового ТС допускается при наличии водителя с 3+ лет стажа.
22.2 Запрещается перевозка людей на мотоцикле без бокового прицепа.
22.3 Перевозка детей до 12 лет — в удерживающих устройствах.
22.4 Запрещается перевозка груза, выступающего более 1 м за габариты ТС без опознавательных знаков.
22.5 При перевозке опасных грузов — специальные опознавательные знаки.
''';

const String _drivingLessons = '''
21.1 Первоначальное обучение — на закрытых площадках.
21.2 Учебная езда на дорогах — с 16 лет.
21.3 Обучающий должен иметь при себе документ на право обучения.
21.4 Запрещается учебная езда на автомагистралях.
21.5 Обучающийся обязан иметь опознавательный знак "Учебное транспортное средство".
''';

const String _vehicleMalfunctions = '''
2.3.1 Запрещается движение при неисправности:
- рабочей тормозной системы;
- рулевого управления;
- сцепного устройства (в составе автопоезда);
- негорящих фар и задних габаритных огней в темное время суток;
- стеклоочистителя со стороны водителя в дождь или снег.
2.3.2 При возникновении неисправности водитель должен устранить ее или следовать к месту ремонта с соблюдением мер предосторожности.
2.3.3 Запрещается движение при неисправности тормозной системы, рулевого управления, сцепного устройства.
''';

const String _firstAid = '''
При ДТП водитель обязан:
1. Немедленно остановить ТС, включить аварийную сигнализацию.
2. Оказать первую помощь пострадавшим.
3. Вызвать скорую помощь и полицию.
4. Не перемещать предметы, имеющие отношение к ДТП.
5. Записать данные свидетелей.

Первая помощь:
- При кровотечении — наложить жгут выше раны.
- При переломе — иммобилизовать конечность.
- При ожоге — охладить место ожога водой.
- При потере сознания — уложить на бок, обеспечить приток воздуха.
- При остановке сердца — непрямой массаж сердца.
''';

const String _driverResponsibility = '''
Административная ответственность:
- Превышение скорости — штраф 500-5000 руб. или лишение прав.
- Проезд на красный сигнал — штраф 1000 руб.
- Управление ТС без прав — штраф 5000-15000 руб.
- Управление в состоянии опьянения — штраф 30000 руб. + лишение прав на 1.5-2 года.
- Нарушение правил парковки — штраф 500-3000 руб.
- Непредоставление преимущества пешеходу — штраф 1500-2500 руб.
- Разговор по телефону за рулем — штраф 1500 руб.
- Неиспользование ремней безопасности — штраф 1000 руб.
- Перевозка детей без удерживающего устройства — штраф 3000 руб.
''';
