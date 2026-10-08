import 'dart:math';
import 'package:pdd_app/data/models/sign_swiper_model.dart';

/// Модель практического дорожного сценария для знака.
class SignScenario {
  final String prompt;
  final bool isCorrect;
  final String explanation;
  final SignQuestionType type;

  const SignScenario({
    required this.prompt,
    required this.isCorrect,
    required this.explanation,
    this.type = SignQuestionType.actionPermission,
  });
}

/// Большая библиотека практических дорожных сценариев (ПДД РФ) для игры «Знак-Свайпер».
/// 100% практические вопросы: «Можно/Нельзя», «Обязан/Не обязан», зоны, исключения.
class SignScenariosLibrary {
  static final Map<String, List<SignScenario>> _scenarios = {
    // ==========================================
    // 1. ПРЕДУПРЕЖДАЮЩИЕ ЗНАКИ
    // ==========================================
    '1.1': const [
      SignScenario(
        prompt: 'Предупреждает ли знак о ж/д переезде со шлагбаумом вне города за 150–300 м?',
        isCorrect: true,
        explanation: 'Да! Предупреждающие знаки вне населённых пунктов устанавливаются на расстоянии 150–300 м до объекта.',
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: 'Разрешён ли обгон на самом ж/д переезде и ближе чем за 100 м перед ним?',
        isCorrect: false,
        explanation: 'Нельзя! ПДД 11.4 категорически запрещает обгон на переездах и ближе чем за 100 метров перед ними.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешена ли стоянка автомобиля ближе 50 метров от этого ж/д переезда?',
        isCorrect: false,
        explanation: 'Нельзя! Согласно ПДД 12.5 стоянка запрещена ближе 50 метров от железнодорожных переездов.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '1.2': const [
      SignScenario(
        prompt: 'Предупреждает ли знак о ж/д переезде, НЕ оборудованном шлагбаумом?',
        isCorrect: true,
        explanation: 'Да! Знак 1.2 предупреждает о приближении к переезду без шлагбаума.',
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: 'Разрешён ли разворот и движение задним ходом в границах ж/д переезда?',
        isCorrect: false,
        explanation: 'Нельзя! Согласно ПДД 8.11 и 8.12 разворот и движение задним ходом на ж/д переездах строго запрещены.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '1.3.1': const [
      SignScenario(
        prompt: 'Обозначает ли этот знак переезд только через один железнодорожный путь?',
        isCorrect: true,
        explanation: 'Да! Знак 1.3.1 устанавливается только перед переездами через один ж/д путь.',
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: 'Устанавливается ли этот знак за 150–300 метров до переезда?',
        isCorrect: false,
        explanation: 'Нет! Знаки 1.3.1 и 1.3.2 устанавливаются непосредственно перед железнодорожным переездом.',
        type: SignQuestionType.warningNotice,
      ),
    ],

    '1.5': const [
      SignScenario(
        prompt: 'Имеет ли трамвай преимущество при одновременном праве на движение?',
        isCorrect: true,
        explanation: 'Да! При равном праве на проезд водители трамваев имеют безусловное преимущество перед безрельсовыми ТС.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Обязан ли трамвай уступить дорогу автомобилям при выезде из депо?',
        isCorrect: true,
        explanation: 'Да! Согласно ПДД 18.1 при выезде из депо трамвай обязан уступить дорогу всем транспортным средствам.',
        type: SignQuestionType.driverObligation,
      ),
    ],

    '1.6': const [
      SignScenario(
        prompt: 'Обязан ли водитель уступить дорогу помехе справа на этом перекрёстке?',
        isCorrect: true,
        explanation: 'Да! На перекрёстке равнозначных дорог действует правило «помехи справа» (ПДД 13.11).',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Разрешён ли обгон с выездом на встречную полосу на равнозначном перекрёстке?',
        isCorrect: false,
        explanation: 'Нельзя! Согласно ПДД 11.4 обгон запрещён на нерегулируемых перекрёстках при движении по дороге, не являющейся главной.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '1.7': const [
      SignScenario(
        prompt: 'Предупреждает ли знак о приближении к перекрёстку с круговым движением?',
        isCorrect: true,
        explanation: 'Да! Знак 1.7 предупреждает о пересечении с круговым движением.',
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: 'Обязывает ли этот знак двигаться строго против часовой стрелки уже в месте установки?',
        isCorrect: false,
        explanation: 'Нет! Это предупреждающий знак за 50–100 м (или 150–300 м), а предписывает круг знак 4.3 на самом перекрёстке.',
        type: SignQuestionType.warningNotice,
      ),
    ],

    '1.11.1': const [
      SignScenario(
        prompt: 'Разрешён ли разворот в месте с видимостью дороги менее 100 метров?',
        isCorrect: false,
        explanation: 'Нельзя! Согласно ПДД 8.11 разворот запрещён в местах с видимостью дороги менее 100 метров хотя бы в одном направлении.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Обязан ли водитель снизить скорость перед крутым поворотом с ограниченной видимостью?',
        isCorrect: true,
        explanation: 'Да! ПДД 10.1 обязывает выбирать скорость с учётом видимости и профиля дороги.',
        type: SignQuestionType.driverObligation,
      ),
    ],

    '1.23': const [
      SignScenario(
        prompt: 'Обязывает ли знак повысить внимание из-за риска появления детей на дороге?',
        isCorrect: true,
        explanation: 'Да! Знак 1.23 устанавливается возле школ, детских садов и площадок.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Даёт ли этот знак детям право переходить проезжую часть в любом месте вне перехода?',
        isCorrect: false,
        explanation: 'Нет! Знак только предупреждает водителей, правила перехода проезжей части для пешеходов остаются прежними.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '1.25': const [
      SignScenario(
        prompt: 'Имеет ли этот знак на жёлтом фоне приоритет перед постоянными дорожными знаками?',
        isCorrect: true,
        explanation: 'Да! Жёлтый фон означает временный статус знака, временные знаки имеют приоритет над постоянными.',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Обязывает ли этот знак обязательно остановиться перед ним?',
        isCorrect: false,
        explanation: 'Нет! Знак 1.25 лишь предупреждает о дорожных работах и требует повышенного внимания и снижения скорости.',
        type: SignQuestionType.driverObligation,
      ),
    ],

    // ==========================================
    // 2. ЗНАКИ ПРИОРИТЕТА
    // ==========================================
    '2.1': const [
      SignScenario(
        prompt: 'Имеете ли вы преимущество перед авто со второстепенных дорог на перекрёстке?',
        isCorrect: true,
        explanation: 'Да! Знак 2.1 «Главная дорога» даёт преимущество проезда нерегулируемых перекрёстков (ПДД 13.9).',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Разрешает ли этот знак проехать перекрёсток первым при красном сигнале светофора?',
        isCorrect: false,
        explanation: 'Нельзя! Согласно ПДД 6.15 сигналы светофора отменяют действие знаков приоритета.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешена ли стоянка на проезжей части вне населённых пунктов под этим знаком?',
        isCorrect: false,
        explanation: 'Нельзя! Согласно ПДД 12.5 стоянка на проезжей части дорог, обозначенных знаком 2.1, вне населённых пунктов запрещена.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '2.2': const [
      SignScenario(
        prompt: 'Обязывает ли знак быть готовым уступить дорогу на ближайшем перекрёстке?',
        isCorrect: true,
        explanation: 'Да! Знак 2.2 отменяет статус главной дороги, впереди перекрёсток со второстепенным или равнозначным статусом.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Сохраняется ли у вас преимущество проезда перекрёстка после этого знака?',
        isCorrect: false,
        explanation: 'Нет! Знак 2.2 отменяет право преимущественного проезда.',
        type: SignQuestionType.zoneAndException,
      ),
    ],

    '2.3.1': const [
      SignScenario(
        prompt: 'Имеете ли вы преимущество перед автомобилями с примыкающих дорог?',
        isCorrect: true,
        explanation: 'Да! Вы движетесь по главной дороге, пересекаемая дорога является второстепенной.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Обязаны ли вы уступить дорогу автомобилю, приближающемуся справа по примыканию?',
        isCorrect: false,
        explanation: 'Нет! Знак 2.3.1 информирует, что примыкающие дороги второстепенные, правило помехи справа здесь не действует.',
        type: SignQuestionType.driverObligation,
      ),
    ],

    '2.4': const [
      SignScenario(
        prompt: 'Обязаны ли вы уступить дорогу транспортным средствам на пересекаемой дороге?',
        isCorrect: true,
        explanation: 'Да! Знак 2.4 обязывает уступить дорогу всем ТС, движущимся по пересекаемой главной дороге.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Обязаны ли вы обязательно остановиться, если на пересекаемой дороге нет машин?',
        isCorrect: false,
        explanation: 'Нет! В отличие от знака 2.5 (STOP), знак 2.4 не требует обязательной остановки, если вы не создаёте помех.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Имеете ли вы преимущество проезда перед встречным автомобилем, поворачивающим налево?',
        isCorrect: true,
        explanation: 'Да! При движении прямо вы оба находитесь на второстепенной дороге, и встречный поворачивающий налево обязан уступить вам (ПДД 13.12).',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '2.5': const [
      SignScenario(
        prompt: 'Обязаны ли вы остановиться перед стоп-линией, даже если на дороге никого нет?',
        isCorrect: true,
        explanation: 'Да! Знак 2.5 запрещает движение без обязательной полной остановки в любых обстоятельствах.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Разрешено ли проехать без остановки, если видимость отличная и помех нет?',
        isCorrect: false,
        explanation: 'Нельзя! Знак 2.5 категорически требует остановки транспортного средства перед стоп-линией или краем проезжей части.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '2.6': const [
      SignScenario(
        prompt: 'Обязаны ли вы уступить дорогу встречному ТС на узком участке дороги?',
        isCorrect: true,
        explanation: 'Да! Знак 2.6 запрещает въезд на узкий участок, если это затруднит встречное движение.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Имеете ли вы преимущество перед встречным автомобилем?',
        isCorrect: false,
        explanation: 'Нет! Красная стрелка в вашем направлении указывает, что преимущество у встречного транспорта.',
        type: SignQuestionType.driverObligation,
      ),
    ],

    '2.7': const [
      SignScenario(
        prompt: 'Имеете ли вы право проехать узкий участок дороги первым перед встречным авто?',
        isCorrect: true,
        explanation: 'Да! Белая стрелка на синем фоне знака 2.7 даёт преимущество перед встречным движением.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Обязаны ли вы уступить дорогу встречному автомобилю на узком участке?',
        isCorrect: false,
        explanation: 'Нет! Знак 2.7 предоставляет вам право преимущественного проезда.',
        type: SignQuestionType.driverObligation,
      ),
    ],

    // ==========================================
    // 3. ЗАПРЕЩАЮЩИЕ ЗНАКИ
    // ==========================================
    '3.1': const [
      SignScenario(
        prompt: 'Распространяется ли запрет въезда под знак на такси и каршеринг?',
        isCorrect: true,
        explanation: 'Да! Знак 3.1 («Кирпич») действует на все ТС, кроме маршрутных транспортных средств (автобусы, троллейбусы, трамваи).',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Разрешён ли въезд под этот знак водителю, проживающему в этом доме?',
        isCorrect: false,
        explanation: 'Нельзя! Знак 3.1 «Въезд запрещен» не делает исключений для проживающих граждан (в отличие от знака 3.2).',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли въезд под этот знак маршрутному автобусу, следующему по маршруту?',
        isCorrect: true,
        explanation: 'Можно! Маршрутные транспортные средства освобождены от действия знака 3.1 (ПДД Приложение 1).',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '3.2': const [
      SignScenario(
        prompt: 'Разрешён ли проезд под этот знак жителям домов, расположенных в обозначенной зоне?',
        isCorrect: true,
        explanation: 'Можно! Знак 3.2 не распространяется на ТС граждан, проживающих или работающих в зоне действия знака.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли сквозной транзитный проезд через эту зону обычным автомобилям?',
        isCorrect: false,
        explanation: 'Нельзя! Сквозное движение через зону действия знака 3.2 строго запрещено.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Распространяется ли действие знака на автомобили инвалидов I и II групп?',
        isCorrect: false,
        explanation: 'Нет! ТС с опознавательным знаком «Инвалид» (I и II группы) имеют право въезжать под знак 3.2.',
        type: SignQuestionType.zoneAndException,
      ),
    ],

    '3.4': const [
      SignScenario(
        prompt: 'Разрешено ли движение легкового автомобиля под этот знак?',
        isCorrect: true,
        explanation: 'Можно! Знак 3.4 распространяется только на грузовые автомобили с разрешённой максимальной массой более 3,5 т.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешено ли движение грузовика с разрешённой массой 5 тонн без исключений?',
        isCorrect: false,
        explanation: 'Нельзя! Если масса на знаке не указана, он запрещает движение грузовиков с РММ свыше 3,5 тонн.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '3.18.1': const [
      SignScenario(
        prompt: 'Разрешён ли разворот или поворот налево на этом перекрёстке?',
        isCorrect: true,
        explanation: 'Можно! Знак 3.18.1 запрещает исключительно поворот направо. Поворот налево, разворот и прямо разрешены.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли поворот направо на ближайшем пересечении проезжих частей?',
        isCorrect: false,
        explanation: 'Нельзя! Знак 3.18.1 прямо запрещает поворот направо на первом пересечении.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '3.18.2': const [
      SignScenario(
        prompt: 'Разрешён ли разворот на перекрёстке при установленном знаке?',
        isCorrect: true,
        explanation: 'Можно! Знак 3.18.2 запрещает только поворот налево и НЕ запрещает разворот (ПДД Приложение 1).',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли поворот налево на этом перекрёстке?',
        isCorrect: false,
        explanation: 'Нельзя! Знак 3.18.2 категорически запрещает поворот налево.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '3.19': const [
      SignScenario(
        prompt: 'Разрешён ли поворот налево на перекрёстке под этот знак?',
        isCorrect: true,
        explanation: 'Можно! Знак 3.19 запрещает только разворот. Поворот налево и движение прямо разрешены.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли разворот на этом перекрёстке?',
        isCorrect: false,
        explanation: 'Нельзя! Знак 3.19 категорически запрещает разворот.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '3.20': const [
      SignScenario(
        prompt: 'Разрешено ли обогнать тихоходное транспортное средство с треугольным знаком сзади?',
        isCorrect: true,
        explanation: 'Можно! В зоне знака 3.20 разрешён обгон тихоходных ТС, гужевых повозок, мопедов и мотоциклов без люльки.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешено ли обогнать одиночный легковой автомобиль, едущий со скоростью 25 км/ч?',
        isCorrect: false,
        explanation: 'Нельзя! Легковой автомобиль не является тихоходным ТС по паспорту, его обгон в зоне знака 3.20 запрещён.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли обгон двухколёсного мотоцикла без бокового прицепа?',
        isCorrect: true,
        explanation: 'Можно! Двухколесные мотоциклы без люльки являются официальным исключением из запрета знака 3.20.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '3.24': const [
      SignScenario(
        prompt: 'Обязан ли водитель двигаться со скоростью не выше числа, указанного на знаке?',
        isCorrect: true,
        explanation: 'Да! Знак 3.24 устанавливает максимально разрешённую скорость движения.',
        type: SignQuestionType.speedAndLane,
      ),
      SignScenario(
        prompt: 'Обязывает ли этот знак двигаться строго со скоростью на знаке или быстрее?',
        isCorrect: false,
        explanation: 'Нет! Знак ограничивает максимальную, а не минимальную скорость (минимальную предписывает синий знак 4.6).',
        type: SignQuestionType.speedAndLane,
      ),
    ],

    '3.27': const [
      SignScenario(
        prompt: 'Запрещена ли здесь даже кратковременная остановка на 1 минуту для высадки пассажира?',
        isCorrect: true,
        explanation: 'Да! Знак 3.27 запрещает как стоянку, так и любую преднамеренную остановку ТС.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешена ли остановка под этим знаком на легковом автомобиле инвалидам I и II групп?',
        isCorrect: false,
        explanation: 'Нельзя! На знак 3.27 льгота для инвалидов не действует (только при наличии специальной таблички 8.18).',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Разрешена ли стоянка автомобиля в зоне действия этого знака?',
        isCorrect: false,
        explanation: 'Нельзя! Знак 3.27 запрещает и остановку, и стоянку.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '3.28': const [
      SignScenario(
        prompt: 'Разрешена ли остановка до 5 минут для посадки или высадки пассажиров?',
        isCorrect: true,
        explanation: 'Можно! Знак 3.28 запрещает стоянку, но разрешает остановку до 5 минут (или дольше при погрузке/высадке).',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешено ли оставить автомобиль заглушенным на 20 минут без погрузки/выгрузки?',
        isCorrect: false,
        explanation: 'Нельзя! Прекращение движения на время более 5 минут без посадки/погрузки считается стоянкой и запрещено.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Распространяется ли действие знака на автомобили инвалидов I и II групп?',
        isCorrect: false,
        explanation: 'Нет! Знак 3.28 не действует на транспортные средства, управляемые инвалидами I и II групп или перевозящие их.',
        type: SignQuestionType.zoneAndException,
      ),
    ],

    '3.29': const [
      SignScenario(
        prompt: 'Разрешена ли стоянка на обеих сторонах улицы во время перестановки с 21:00 до 24:00?',
        isCorrect: true,
        explanation: 'Можно! При одновременном применении знаков 3.29 и 3.30 время перестановки с 21:00 до 24:00 разрешает стоянку на обеих сторонах.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Запрещает ли этот знак кратковременную остановку на 3 минуты для посадки пассажиров?',
        isCorrect: false,
        explanation: 'Нет! Знак запрещает только стоянку. Остановка до 5 минут разрешена в любой день месяца.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '3.31': const [
      SignScenario(
        prompt: 'Снимает ли этот знак действие ранее введённых запретов на обгон и скорость?',
        isCorrect: true,
        explanation: 'Да! Знак 3.31 отменяет действие знаков 3.16, 3.20, 3.22, 3.24, 3.26–3.30.',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Отменяет ли этот знак действие сигналов светофора и правил разметки?',
        isCorrect: false,
        explanation: 'Нет! Знак снимает ограничения только запрещающих дорожных знаков.',
        type: SignQuestionType.zoneAndException,
      ),
    ],

    // ==========================================
    // 4. ПРЕДПИСЫВАЮЩИЕ ЗНАКИ
    // ==========================================
    '4.1.1': const [
      SignScenario(
        prompt: 'Разрешён ли поворот направо во двор, если знак установлен в начале участка дороги?',
        isCorrect: true,
        explanation: 'Можно! Установленный в начале участка дороги знак 4.1.1 разрешает поворот направо во дворы и прилегающие территории.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли поворот налево или разворот на перекрёстке, перед которым стоит знак?',
        isCorrect: false,
        explanation: 'Нельзя! Знак 4.1.1 перед перекрёстком разрешает движение исключительно прямо.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '4.1.2': const [
      SignScenario(
        prompt: 'Обязывает ли знак повернуть направо на ближайшем пересечении проезжих частей?',
        isCorrect: true,
        explanation: 'Да! Предписывающий знак 4.1.2 разрешает движение только направо.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Разрешено ли продолжить движение прямо через перекрёсток?',
        isCorrect: false,
        explanation: 'Нельзя! Движение прямо запрещено, разрешён только правый поворот.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '4.1.3': const [
      SignScenario(
        prompt: 'Разрешает ли этот знак выполнить разворот на перекрёстке?',
        isCorrect: true,
        explanation: 'Можно! Знак 4.1.3 разрешает поворот налево, а любой знак, разрешающий поворот налево, разрешает и разворот.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешено ли движение прямо через перекрёсток?',
        isCorrect: false,
        explanation: 'Нельзя! Знак 4.1.3 разрешает движение только налево и в обратном направлении (разворот).',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '4.1.4': const [
      SignScenario(
        prompt: 'Разрешено ли продолжить движение прямо или повернуть направо?',
        isCorrect: true,
        explanation: 'Можно! Знак 4.1.4 предписывает движение только прямо или направо.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли разворот на этом перекрёстке?',
        isCorrect: false,
        explanation: 'Нельзя! Разрешены только направления прямо и направо, левый поворот и разворот запрещены.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '4.1.5': const [
      SignScenario(
        prompt: 'Разрешён ли разворот из крайней левой полосы при таком знаке?',
        isCorrect: true,
        explanation: 'Можно! Знак разрешает прямо и налево, а разрешение поворота налево всегда допускает разворот.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли поворот направо на этом перекрёстке?',
        isCorrect: false,
        explanation: 'Нельзя! Знак 4.1.5 разрешает движение только прямо, налево и в обратном направлении.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '4.2.1': const [
      SignScenario(
        prompt: 'Обязывает ли знак объезжать препятствие только справа?',
        isCorrect: true,
        explanation: 'Да! Стрелка знака 4.2.1 строго предписывает объезд препятствия с правой стороны.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Разрешено ли объехать препятствие слева при отсутствии встречных машин?',
        isCorrect: false,
        explanation: 'Нельзя! Знак строго указывает обязательную сторону объезда.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '4.3': const [
      SignScenario(
        prompt: 'Обязывает ли знак двигаться по перекрёстку только в направлении стрелок (против часовой)?',
        isCorrect: true,
        explanation: 'Да! Знак 4.3 предписывает круговое движение в указанном направлении.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Разрешён ли поворот налево непосредственно при въезде на круговой перекрёсток?',
        isCorrect: false,
        explanation: 'Нельзя! Въезд на круговой перекрёсток осуществляется только по направлению кругового движения (направо).',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '4.6': const [
      SignScenario(
        prompt: 'Обязан ли водитель двигаться со скоростью не менее указанной на знаке?',
        isCorrect: true,
        explanation: 'Да! Знак 4.6 предписывает минимально разрешённую скорость движения.',
        type: SignQuestionType.speedAndLane,
      ),
      SignScenario(
        prompt: 'Разрешено ли двигаться со скоростью 30 км/ч, если на знаке указано 50 (при отсутствии заторов)?',
        isCorrect: false,
        explanation: 'Нельзя! Движение со скоростью ниже 50 км/ч на этом участке запрещено.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    // ==========================================
    // 5. ЗНАКИ ОСОБЫХ ПРЕДПИСАНИЙ
    // ==========================================
    '5.1': const [
      SignScenario(
        prompt: 'Разрешена ли максимальная скорость легковых автомобилей до 110 км/ч (при отсутствии иных знаков)?',
        isCorrect: true,
        explanation: 'Да! На автомагистралях для легковых автомобилей установлен скоростной режим 110 км/ч (ПДД 10.3).',
        type: SignQuestionType.speedAndLane,
      ),
      SignScenario(
        prompt: 'Разрешено ли движение задним ходом или разворот в технологических разрывах?',
        isCorrect: false,
        explanation: 'Нельзя! Согласно ПДД 16.1 разворот и движение задним ходом на автомагистралях категорически запрещены.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешено ли движение мопедов и ТС со скоростью менее 40 км/ч по автомагистрали?',
        isCorrect: false,
        explanation: 'Нельзя! Согласно ПДД 16.1 запрещено движение пешеходов, мопедов, велосипедов и ТС со скоростью менее 40 км/ч.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '5.3': const [
      SignScenario(
        prompt: 'Действуют ли на этой дороге запреты на разворот в разрывах и движение задним ходом?',
        isCorrect: true,
        explanation: 'Да! На дорогах для автомобилей действуют правила раздела 16 ПДД (правила движения по автомагистралям).',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Разрешена ли остановка на обочине дороги для автомобилей вне специальных площадок?',
        isCorrect: false,
        explanation: 'Нельзя! Остановка разрешена только на специальных площадках для стоянки (знаки 6.4 или 7.11).',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '5.5': const [
      SignScenario(
        prompt: 'Разрешено ли движение задним ходом по дороге с односторонним движением (при отсутствии перекрёстков)?',
        isCorrect: true,
        explanation: 'Можно! Движение задним ходом на односторонней дороге разрешено, если это безопасно и не на перекрёстке (ПДД 8.12).',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли разворот для движения в обратном направлении?',
        isCorrect: false,
        explanation: 'Нельзя! Разворот приведёт к движению во встречном направлении по односторонней дороге (лишение прав по КоАП 12.16 ч.3).',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешена ли стоянка легкового авто на левой стороне дороги в населённом пункте?',
        isCorrect: true,
        explanation: 'Можно! В населённых пунктах на дорогах с односторонним движением остановка и стоянка на левой стороне разрешены (ПДД 12.1).',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '5.14.1': const [
      SignScenario(
        prompt: 'Разрешено ли легковым такси и школьным автобусам двигаться по этой выделенной полосе?',
        isCorrect: true,
        explanation: 'Можно! По полосе для маршрутных ТС разрешено движение легковых такси, школьных автобусов и велосипедистов (ПДД 18.2).',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешено ли обычным легковушкам ехать по этой полосе в будний день (без таблички выходных дней)?',
        isCorrect: false,
        explanation: 'Нельзя! Движение обычных автомобилей по выделенной полосе без разрешающих табличек строго запрещено.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '5.15.1': const [
      SignScenario(
        prompt: 'Разрешает ли крайняя левая полоса с разрешённым поворотом налево также выполнить разворот?',
        isCorrect: true,
        explanation: 'Можно! Знак, разрешающий поворот налево из крайней левой полосы, разрешает и разворот из этой полосы.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешено ли повернуть налево из средней полосы, если на ней стрелка только прямо?',
        isCorrect: false,
        explanation: 'Нельзя! Движение по полосам должно строго соответствовать указаниям стрелок знака 5.15.1.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '5.19.1': const [
      SignScenario(
        prompt: 'Обязан ли водитель уступить дорогу пешеходам, переходящим проезжую часть?',
        isCorrect: true,
        explanation: 'Да! Согласно ПДД 14.1 водитель обязан уступить дорогу пешеходам, переходящим дорогу или вступившим на неё.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Разрешён ли разворот и движение задним ходом в границах пешеходного перехода?',
        isCorrect: false,
        explanation: 'Нельзя! На пешеходных переходах разворот и движение задним ходом категорически запрещены (ПДД 8.11, 8.12).',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешена ли остановка ближе 5 метров перед пешеходным переходом?',
        isCorrect: false,
        explanation: 'Нельзя! Согласно ПДД 12.4 остановка запрещается на пешеходных переходах и ближе 5 м перед ними.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '5.20': const [
      SignScenario(
        prompt: 'Обозначает ли знак границы искусственной неровности непосредственно на дороге?',
        isCorrect: true,
        explanation: 'Да! Знак 5.20 устанавливается на ближайшей границе искусственной неровности.',
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: 'Обязывает ли знак полностью остановиться перед неровностью?',
        isCorrect: false,
        explanation: 'Нет! Остановка не требуется, знак обозначает неровность, перед которой необходимо лишь снизить скорость.',
        type: SignQuestionType.driverObligation,
      ),
    ],

    '5.21': const [
      SignScenario(
        prompt: 'Имеют ли пешеходы преимущество на всей ширине проезжей части в жилой зоне?',
        isCorrect: true,
        explanation: 'Да! В жилой зоне пешеходы могут двигаться как по тротуарам, так и по проезжей части и имеют преимущество (ПДД 17.1).',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Разрешена ли в жилой зоне скорость движения более 20 км/ч?',
        isCorrect: false,
        explanation: 'Нельзя! В жилой зоне и на дворовых территориях скорость движения ограничена 20 км/ч (ПДД 10.2).',
        type: SignQuestionType.speedAndLane,
      ),
      SignScenario(
        prompt: 'Разрешена ли в жилой зоне стоянка с работающим двигателем или сквозной проезд?',
        isCorrect: false,
        explanation: 'Нельзя! В жилой зоне запрещены сквозное движение, учебная езда и стоянка с работающим двигателем (ПДД 17.2).',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '5.23.1': const [
      SignScenario(
        prompt: 'Действует ли после этого знака общее городское ограничение скорости 60 км/ч?',
        isCorrect: true,
        explanation: 'Да! Белый фон знака означает начало населённого пункта, где действуют требования ПДД для города (в т.ч. 60 км/ч).',
        type: SignQuestionType.speedAndLane,
      ),
      SignScenario(
        prompt: 'Разрешено ли продолжить движение со скоростью 90 км/ч сразу после въезда под знак?',
        isCorrect: false,
        explanation: 'Нельзя! Въезд в населённый пункт на белом фоне ограничивает скорость до 60 км/ч.',
        type: SignQuestionType.speedAndLane,
      ),
    ],

    '5.25': const [
      SignScenario(
        prompt: 'Разрешено ли легковому авто продолжать движение со скоростью 90 км/ч после этого знака?',
        isCorrect: true,
        explanation: 'Можно! Синий фон означает, что на данной дороге требования ПДД для населённых пунктов НЕ действуют.',
        type: SignQuestionType.speedAndLane,
      ),
      SignScenario(
        prompt: 'Обязывает ли синий знак населённого пункта обязательно снизить скорость до 60 км/ч?',
        isCorrect: false,
        explanation: 'Нет! На дороге, обозначенной знаком на синем фоне, сохраняется загородный скоростной режим 90 км/ч.',
        type: SignQuestionType.speedAndLane,
      ),
    ],

    // ==========================================
    // 6. ИНФОРМАЦИОННЫЕ ЗНАКИ
    // ==========================================
    '6.2': const [
      SignScenario(
        prompt: 'Является ли указанная скорость рекомендованной, а не строго обязательной?',
        isCorrect: true,
        explanation: 'Да! Знак 6.2 рекомендует скорость движения на данном участке дороги, но не обязывает ехать строго с ней.',
        type: SignQuestionType.speedAndLane,
      ),
      SignScenario(
        prompt: 'Обязывает ли этот знак двигаться строго с указанной скоростью под угрозой штрафа?',
        isCorrect: false,
        explanation: 'Нет! Знак носит рекомендательный характер.',
        type: SignQuestionType.speedAndLane,
      ),
    ],

    '6.3.1': const [
      SignScenario(
        prompt: 'Разрешён ли разворот в месте установки этого знака?',
        isCorrect: true,
        explanation: 'Можно! Знак 6.3.1 указывает место для выполнения разворота.',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Разрешён ли поворот налево во двор или проезд под этот знак?',
        isCorrect: false,
        explanation: 'Нельзя! Знак 6.3.1 разрешает только разворот. Поворот налево категорически запрещён!',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '6.4': const [
      SignScenario(
        prompt: 'Разрешена ли стоянка транспортных средств в зоне действия этого знака?',
        isCorrect: true,
        explanation: 'Можно! Знак 6.4 обозначает парковку (парковочное место).',
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: 'Обязывает ли знак всех водителей обязательно свернуть на парковку?',
        isCorrect: false,
        explanation: 'Нет! Знак является информационным и указывает на место для стоянки.',
        type: SignQuestionType.driverObligation,
      ),
    ],

    '6.16': const [
      SignScenario(
        prompt: 'Указывает ли знак место остановки при запрещающем сигнале светофора?',
        isCorrect: true,
        explanation: 'Да! Знак 6.16 «Стоп-линия» показывает место обязательной остановки при красном сигнале светофора или жесте регулировщика.',
        type: SignQuestionType.driverObligation,
      ),
      SignScenario(
        prompt: 'Обязан ли водитель остановиться перед знаком 6.16 при горящем зелёном сигнале светофора?',
        isCorrect: false,
        explanation: 'Нет! При разрешающем сигнале светофора остановка перед знаком 6.16 не требуется.',
        type: SignQuestionType.driverObligation,
      ),
    ],

    // ==========================================
    // 7. ЗНАКИ СЕРВИСА
    // ==========================================
    '7.1': const [
      SignScenario(
        prompt: 'Информирует ли знак о расположении пункта первой медицинской помощи?',
        isCorrect: true,
        explanation: 'Да! Знак 7.1 информирует водителей и пассажиров о пункте первой медпомощи.',
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: 'Обязывает ли этот знак снизить скорость до 20 км/ч или остановиться?',
        isCorrect: false,
        explanation: 'Нет! Знаки сервиса не вводят скоростных ограничений и не обязывают останавливаться.',
        type: SignQuestionType.driverObligation,
      ),
    ],

    '7.3': const [
      SignScenario(
        prompt: 'Информирует ли знак о приближении к автозаправочной станции (АЗС)?',
        isCorrect: true,
        explanation: 'Да! Знак 7.3 обозначает автозаправочную станцию.',
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: 'Даёт ли этот знак преимущество при выезде с территории АЗС на главную дорогу?',
        isCorrect: false,
        explanation: 'Нет! При выезде с прилегающей территории (АЗС) водитель обязан уступить дорогу всем ТС (ПДД 8.3).',
        type: SignQuestionType.actionPermission,
      ),
    ],

    // ==========================================
    // 8. ТАБЛИЧКИ ДОПОЛНИТЕЛЬНОЙ ИНФОРМАЦИИ
    // ==========================================
    '8.1.1': const [
      SignScenario(
        prompt: 'Указывает ли табличка расстояние от знака до начала опасного участка или объекта?',
        isCorrect: true,
        explanation: 'Да! Табличка 8.1.1 указывает расстояние от знака до места, с которого начинается его действие.',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Обозначает ли эта табличка протяжённость опасной зоны со стрелками по бокам?',
        isCorrect: false,
        explanation: 'Нет! Протяжённость зоны указывают таблички со стрелками (8.2.1 «Зона действия»).',
        type: SignQuestionType.zoneAndException,
      ),
    ],

    '8.2.1': const [
      SignScenario(
        prompt: 'Обозначает ли табличка протяжённость опасного участка или зоны действия знака?',
        isCorrect: true,
        explanation: 'Да! Стрелки по бокам числа указывают протяжённость зоны действия знака.',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Означает ли табличка, что знак начнёт действовать только через это расстояние?',
        isCorrect: false,
        explanation: 'Нет! Табличка 8.2.1 обозначает длину зоны, а расстояние до объекта обозначается без стрелок (8.1.1).',
        type: SignQuestionType.zoneAndException,
      ),
    ],

    '8.2.3': const [
      SignScenario(
        prompt: 'Означает ли стрелка вниз конец зоны действия знака запрета остановки или стоянки?',
        isCorrect: true,
        explanation: 'Да! Табличка 8.2.3 со стрелкой вниз указывает конец зоны действия знаков 3.27–3.30.',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Запрещена ли стоянка сразу за местом установки знака с этой табличкой?',
        isCorrect: false,
        explanation: 'Нет! Табличка указывает конец зоны запрета, сразу за знаком стоянка разрешена.',
        type: SignQuestionType.actionPermission,
      ),
    ],

    '8.4.1': const [
      SignScenario(
        prompt: 'Распространяет ли табличка действие знака только на грузовики с РММ свыше 3,5 тонн?',
        isCorrect: true,
        explanation: 'Да! Силуэт грузовика на табличке 8.4.1 означает грузовые автомобили с разрешённой массой более 3,5 т.',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Распространяется ли действие знака с этой табличкой на легковые автомобили?',
        isCorrect: false,
        explanation: 'Нет! Табличка 8.4.1 указывает, что знак распространяется исключительно на грузовики более 3,5 т.',
        type: SignQuestionType.zoneAndException,
      ),
    ],

    '8.4.3': const [
      SignScenario(
        prompt: 'Распространяется ли действие знака на легковые авто и небольшие грузовики до 3,5 тонн?',
        isCorrect: true,
        explanation: 'Да! Табличка 8.4.3 распространяет действие знака на легковые авто, а также грузовые с РММ до 3,5 т.',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Распространяется ли действие знака на автобусы и грузовые автомобили массой 12 тонн?',
        isCorrect: false,
        explanation: 'Нет! На тяжёлые грузовики и автобусы табличка 8.4.3 не распространяется.',
        type: SignQuestionType.zoneAndException,
      ),
    ],

    '8.17': const [
      SignScenario(
        prompt: 'Указывает ли табличка, что парковка разрешена только автомобилям со знаком «Инвалид»?',
        isCorrect: true,
        explanation: 'Да! Табличка 8.17 «Инвалиды» резервирует парковочные места только для ТС инвалидов I и II групп или перевозящих их.',
        type: SignQuestionType.zoneAndException,
      ),
      SignScenario(
        prompt: 'Разрешена ли парковка на этом месте обычному водителю без знака «Инвалид» на 10 минут?',
        isCorrect: false,
        explanation: 'Нельзя! Стоянка на местах для инвалидов без опознавательного знака строго запрещена (штраф 5000 руб и эвакуация).',
        type: SignQuestionType.actionPermission,
      ),
    ],
  };

  /// Получить доступные сценарии для конкретного знака.
  static List<SignScenario>? getScenariosForSign(String signNumber) {
    return _scenarios[signNumber];
  }

  /// Умная генерация практического дорожного сценария по категории знака (fallback для остальных знаков).
  static SignScenario generateCategoryScenario(SignItem sign, bool targetIsTrue, Random rnd) {
    final cat = sign.category;

    if (cat.contains('Предупреждающие')) {
      if (targetIsTrue) {
        final options = [
          SignScenario(
            prompt: 'Предупреждает ли этот знак водителя о приближении к опасному участку дороги?',
            isCorrect: true,
            explanation: 'Верно! Знак ${sign.number} «${sign.title}» относится к предупреждающим и информирует о приближении к опасному участку дороги.',
            type: SignQuestionType.warningNotice,
          ),
          SignScenario(
            prompt: 'Устанавливается ли этот знак в населённом пункте обычно за 50–100 метров до объекта?',
            isCorrect: true,
            explanation: 'Верно! По правилам ПДД РФ предупреждающие знаки в населённых пунктах устанавливаются за 50–100 метров до опасного участка.',
            type: SignQuestionType.warningNotice,
          ),
          SignScenario(
            prompt: 'Обязывает ли появление этого знака повысить внимание и подготовиться к снижению скорости?',
            isCorrect: true,
            explanation: 'Верно! Предупреждающий знак сигнализирует об изменении дорожных условий и требует повышенной концентрации.',
            type: SignQuestionType.driverObligation,
          ),
        ];
        return options[rnd.nextInt(options.length)];
      } else {
        final options = [
          SignScenario(
            prompt: 'Обязывает ли этот знак немедленно совершить полную остановку транспортного средства?',
            isCorrect: false,
            explanation: 'Неверно! Знак ${sign.number} является предупреждающим. Обязательную остановку он не предписывает (в отличие от знака 2.5 STOP).',
            type: SignQuestionType.driverObligation,
          ),
          SignScenario(
            prompt: 'Разрешает ли этот знак увеличить скорость выше разрешённой на этом участке?',
            isCorrect: false,
            explanation: 'Нельзя! Предупреждающие знаки не дают права превышать установленный скоростной режим, а напротив, требуют аккуратности.',
            type: SignQuestionType.actionPermission,
          ),
          SignScenario(
            prompt: 'Предоставляет ли этот предупреждающий знак приоритет перед встречными автомобилями?',
            isCorrect: false,
            explanation: 'Неверно! Предупреждающие знаки не устанавливают очерёдность проезда и не дают преимущественного права движения.',
            type: SignQuestionType.driverObligation,
          ),
        ];
        return options[rnd.nextInt(options.length)];
      }
    }

    if (cat.contains('приоритета')) {
      if (targetIsTrue) {
        final options = [
          SignScenario(
            prompt: 'Определяет ли этот знак очерёдность проезда перекрёстков или узких участков дорог?',
            isCorrect: true,
            explanation: 'Верно! Знаки приоритета определяют порядок разъезда транспортных средств на перекрёстках и узких участках.',
            type: SignQuestionType.driverObligation,
          ),
          SignScenario(
            prompt: 'Обязан ли водитель руководствоваться этим знаком при отсутствии работающего светофора?',
            isCorrect: true,
            explanation: 'Верно! На нерегулируемых перекрёстках очерёдность проезда определяется именно знаками приоритета.',
            type: SignQuestionType.driverObligation,
          ),
        ];
        return options[rnd.nextInt(options.length)];
      } else {
        final options = [
          SignScenario(
            prompt: 'Имеют ли требования этого знака приоритет перед работающим исправным светофором?',
            isCorrect: false,
            explanation: 'Неверно! Согласно ПДД 6.15 работающий светофор отменяет действие знаков приоритета.',
            type: SignQuestionType.driverObligation,
          ),
          SignScenario(
            prompt: 'Разрешено ли игнорировать сигналы регулировщика, если установлен этот знак приоритета?',
            isCorrect: false,
            explanation: 'Нельзя! Сигналы регулировщика имеют высший приоритет над всеми знаками и светофорами (ПДД 6.15).',
            type: SignQuestionType.actionPermission,
          ),
        ];
        return options[rnd.nextInt(options.length)];
      }
    }

    if (cat.contains('Запрещающие')) {
      if (targetIsTrue) {
        final options = [
          SignScenario(
            prompt: 'Вводит ли этот знак запрет или строгое ограничение для движения транспортных средств?',
            isCorrect: true,
            explanation: 'Верно! Запрещающие знаки вводят определённые ограничения движения, обязательные для исполнения.',
            type: SignQuestionType.zoneAndException,
          ),
          SignScenario(
            prompt: 'Действует ли запрет знака до ближайшего по ходу движения перекрёстка (при отсутствии иных знаков)?',
            isCorrect: true,
            explanation: 'Верно! Зона действия большинства запрещающих знаков распространяется до ближайшего перекрёстка или конца населённого пункта.',
            type: SignQuestionType.zoneAndException,
          ),
        ];
        return options[rnd.nextInt(options.length)];
      } else {
        final options = [
          SignScenario(
            prompt: 'Разрешено ли нарушать требование этого запрещающего знака в ночное время, если дорога пуста?',
            isCorrect: false,
            explanation: 'Нельзя! Требования запрещающих знаков действуют круглосуточно независимо от загруженности трассы.',
            type: SignQuestionType.actionPermission,
          ),
          SignScenario(
            prompt: 'Предоставляет ли этот знак преимущество движения перед другими транспортными средствами?',
            isCorrect: false,
            explanation: 'Неверно! Запрещающие знаки ограничивают действия водителей и не предоставляют преимущества.',
            type: SignQuestionType.driverObligation,
          ),
        ];
        return options[rnd.nextInt(options.length)];
      }
    }

    if (cat.contains('Предписывающие')) {
      if (targetIsTrue) {
        final options = [
          SignScenario(
            prompt: 'Обязывает ли этот знак двигаться строго в соответствии с предписанием?',
            isCorrect: true,
            explanation: 'Верно! Предписывающие знаки строго регламентируют направление движения, минимальную скорость или категорию ТС.',
            type: SignQuestionType.driverObligation,
          ),
          SignScenario(
            prompt: 'Является ли исполнение предписания этого знака обязательным для всех обычных водителей?',
            isCorrect: true,
            explanation: 'Верно! Требования предписывающих знаков обязательны для выполнения водителями.',
            type: SignQuestionType.driverObligation,
          ),
        ];
        return options[rnd.nextInt(options.length)];
      } else {
        final options = [
          SignScenario(
            prompt: 'Носит ли этот предписывающий знак лишь рекомендательный характер?',
            isCorrect: false,
            explanation: 'Неверно! В отличие от информационных рекомендаций, предписывающие знаки обязательны для соблюдения под угрозой штрафа.',
            type: SignQuestionType.driverObligation,
          ),
          SignScenario(
            prompt: 'Разрешено ли водителю отступать от предписания знака, если на перекрёстке нет других машин?',
            isCorrect: false,
            explanation: 'Нельзя! ПДД РФ требуют неукоснительного исполнения требований предписывающих знаков в любой дорожной ситуации.',
            type: SignQuestionType.actionPermission,
          ),
        ];
        return options[rnd.nextInt(options.length)];
      }
    }

    if (cat.contains('особых предписаний')) {
      if (targetIsTrue) {
        final options = [
          SignScenario(
            prompt: 'Вводит или отменяет ли этот знак специальный режим движения на данном участке дороги?',
            isCorrect: true,
            explanation: 'Верно! Знаки особых предписаний вводят или отменяют особые режимы движения (магистрали, полосы, зоны, переходы).',
            type: SignQuestionType.zoneAndException,
          ),
          SignScenario(
            prompt: 'Обязан ли водитель строго соблюдать установленный этим знаком режим движения?',
            isCorrect: true,
            explanation: 'Верно! Режимы движения, установленные знаками особых предписаний, обязательны для исполнения всеми участниками движения.',
            type: SignQuestionType.driverObligation,
          ),
        ];
        return options[rnd.nextInt(options.length)];
      } else {
        final options = [
          SignScenario(
            prompt: 'Разрешено ли водителю обычного авто игнорировать этот специальный режим без спецсигналов?',
            isCorrect: false,
            explanation: 'Нельзя! Отступать от требований знаков особых предписаний имеют право только ТС со включёнными спецсигналами.',
            type: SignQuestionType.actionPermission,
          ),
        ];
        return options[rnd.nextInt(options.length)];
      }
    }

    if (cat.contains('Информационные')) {
      if (targetIsTrue) {
        return const SignScenario(
          prompt: 'Информирует ли этот знак о схемах движения, рекомендованной скорости или расположении объектов?',
          isCorrect: true,
          explanation: 'Верно! Информационные знаки информируют о расположении населённых пунктов и других объектов, а также об установленных или о рекомендуемых режимах движения.',
          type: SignQuestionType.warningNotice,
        );
      } else {
        return const SignScenario(
          prompt: 'Является ли этот знак категорически запрещающим дальнейшее движение всех транспортных средств?',
          isCorrect: false,
          explanation: 'Неверно! Информационные знаки не запрещают движение, а сообщают полезную дорожную информацию.',
          type: SignQuestionType.actionPermission,
        );
      }
    }

    if (cat.contains('сервиса')) {
      if (targetIsTrue) {
        return const SignScenario(
          prompt: 'Информирует ли этот знак о расположении соответствующего объекта дорожного сервиса?',
          isCorrect: true,
          explanation: 'Верно! Знаки сервиса информируют о наличии объектов инфраструктуры (АЗС, больницы, гостиницы, СТО и др.).',
          type: SignQuestionType.warningNotice,
        );
      } else {
        return const SignScenario(
          prompt: 'Обязывает ли знак сервиса каждого водителя обязательно остановиться у данного объекта?',
          isCorrect: false,
          explanation: 'Неверно! Знаки сервиса носят ознакомительный характер, посещение объектов сервиса добровольное.',
          type: SignQuestionType.driverObligation,
        );
      }
    }

    // Дополнительной информации (таблички) и общее
    if (targetIsTrue) {
      return const SignScenario(
        prompt: 'Уточняет или ограничивает ли эта табличка действие дорожного знака, с которым она установлена?',
        isCorrect: true,
        explanation: 'Верно! Знаки дополнительной информации (таблички) уточняют или ограничивают действие знаков, с которыми они применены.',
        type: SignQuestionType.zoneAndException,
      );
    } else {
      return const SignScenario(
        prompt: 'Применяется ли эта табличка на дороге самостоятельно без основного дорожного знака?',
        isCorrect: false,
        explanation: 'Неверно! Таблички дополнительной информации всегда используются только в сочетании с основными дорожными знаками.',
        type: SignQuestionType.zoneAndException,
      );
    }
  }
}
