// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kazakh (`kk`).
class AppLocalizationsKk extends AppLocalizations {
  AppLocalizationsKk([String locale = 'kk']) : super(locale);

  @override
  String get exam => 'Емтихан';

  @override
  String get topics => 'Тақырыптар';

  @override
  String get tickets => 'Билеттер';

  @override
  String get passedQuestions => 'сұрақтар өтті';

  @override
  String get passedTickets => 'билеттер өтті';

  @override
  String get examReadiness => 'Емтиханға дайындық';

  @override
  String get training => 'Жаттығу';

  @override
  String get pdd => 'Жол жүрісі қағидалары';

  @override
  String get signs => 'Жол белгілері';

  @override
  String get video => 'Таспа';

  @override
  String get rules => 'Ережелер';

  @override
  String get signsAndMarkup => 'Белгілер мен таңбалау';

  @override
  String get settings => 'Баптаулар';

  @override
  String get showHint => 'Кеңесті көрсету';

  @override
  String get comment => 'Түсініктеме';

  @override
  String get pddPoints => 'Жол қозғалысы ережелері';

  @override
  String get myAnswers => 'Менің жауаптарым';

  @override
  String get favorites => 'Таңдаулы';

  @override
  String get questionAddedToFavorites => 'Сұрақ Таңдаулыларға қосылды';

  @override
  String get correctAnswer => 'Дұрыс жауап';

  @override
  String get yourAnswer => 'Сіздің жауабыңыз';

  @override
  String get ticket => 'билет';

  @override
  String get question => 'сұрақ';

  @override
  String get goalText =>
      'Сіз үйренген сайын, үлгеріміңіз толтырылады. Сіздің мақсатыңыз барлық билеттерді толтыру!';

  @override
  String get goalTextTopics =>
      'Сіз үйренген сайын сіздің үлгеріміңіз толтырылады. Сіздің мақсатыңыз - барлық тақырыптарды аяқтау!';

  @override
  String get confirmAnswer => 'Жауап беру';

  @override
  String get nextQuestion => 'Келесі сұрақ';

  @override
  String get resetStats => 'Статистиканы нөлдеу';

  @override
  String get resetStatsConfirm =>
      'Барлық статистиканы қалпына келтіргіңіз келетініне сенімдісіз бе?';

  @override
  String get yes => 'Иә';

  @override
  String get no => 'Жоқ';

  @override
  String get cancel => 'Болдырмау';

  @override
  String get back => 'Артқа';

  @override
  String get category => 'Санат';

  @override
  String get categoryAB => 'AB';

  @override
  String get categoryCD => 'CD';

  @override
  String get sound => 'Дыбыс';

  @override
  String get examPassed => 'Емтихан өтті!';

  @override
  String get examFailed => 'Емтихан сәтсіз аяқталды';

  @override
  String get continueSession => 'Жалғастыру';

  @override
  String continueSessionSubtitle(String title, int index, int total) {
    return '$title · $index / $total сұрақ';
  }

  @override
  String get continueSessionDismiss => 'Жою';

  @override
  String get reportQuestionTooltip => 'Қате туралы хабарлау';

  @override
  String get reportQuestionBody =>
      'Бұл сұрақта не дұрыс емес? Қате, қате жауап, қате сурет - өз сөзіңізбен жазыңыз.';

  @override
  String get reportQuestionHint => 'Мысалы: В жауабында қате бар';

  @override
  String get reportSend => 'Жіберу';

  @override
  String get reportSent => 'Рахмет! Хабар жіберілді';

  @override
  String get reportFailed =>
      'Жіберілмеді. Интернетті тексеріп, әрекетті қайталаңыз';

  @override
  String get correctAnswers => 'Дұрыс жауаптар';

  @override
  String get wrongAnswers => 'Дұрыс емес жауаптар';

  @override
  String shareCardCorrectWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'дұрыс',
      one: 'дұрыс',
    );
    return '$_temp0';
  }

  @override
  String shareCardWrongWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'қате',
      one: 'қате',
    );
    return '$_temp0';
  }

  @override
  String get timeLeft => 'Уақыт қалды';

  @override
  String get minutes => 'мин';

  @override
  String get search => 'Іздеу';

  @override
  String get noImage => 'Сурет жоқ';

  @override
  String get mistakes => 'Қателермен жұмыс';

  @override
  String progressRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Емтиханға дейін $count сұрақ қалды',
      one: 'Емтиханға дейін $count сұрақ қалды',
    );
    return '$_temp0';
  }

  @override
  String get progressDone => 'өтті';

  @override
  String get progressCorrect => 'дұрыс';

  @override
  String get progressWrong => 'қателер';

  @override
  String get progressTickets => 'билеттер';

  @override
  String progressStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count күн',
      one: '$count күн',
    );
    return '$_temp0';
  }

  @override
  String progressRecord(int count) {
    return 'Жазба $count';
  }

  @override
  String get progressAllDone => 'Барлық сұрақтар дұрыс өтті';

  @override
  String get homePassedQuestions => 'Өтілген сұрақтар';

  @override
  String get homeCorrectSolved => 'Дұрыс шешті';

  @override
  String get homePassedTickets => 'Тапсырылған билеттер';

  @override
  String examQuestionsBadge(int count) {
    return '$count сұрақтар';
  }

  @override
  String examMinutesBadge(int count) {
    return '$count минут';
  }

  @override
  String examReadinessPercent(int percent) {
    return '$percent% Емтиханға дайындық';
  }

  @override
  String get streakStart => 'Серияны бастаңыз';

  @override
  String get streakStartHint => 'Бүгін сұраққа жауап беріңіз - жарық жанады';

  @override
  String streakDaysWord(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'күн қатарынан',
      one: 'күн қатарынан',
    );
    return '$_temp0';
  }

  @override
  String get continueButton => 'Жалғастыру';

  @override
  String get streakBarrierLabel => 'Сериялар';

  @override
  String get personalRecord => 'Жеке ең жақсы';

  @override
  String get streakTitle => 'Күндер сериясы';

  @override
  String get streakToday => 'Бүгін есептелді';

  @override
  String get streakTodayPending =>
      'Бүгін әлі жаттықпадыңыз — серияны жалғастыру үшін сұраққа жауап беріңіз';

  @override
  String get streakNewRecord => 'Жаңа рекорд';

  @override
  String streakNextGoal(int count, int goal) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$goal күнге дейін тағы $count күн',
      one: '$goal күнге дейін тағы $count күн',
    );
    return '$_temp0';
  }

  @override
  String get streakGoalReached => 'Барлық мақсат орындалды — қарқынды сақтаңыз';

  @override
  String get weekdayMon => 'Дс';

  @override
  String get weekdayTue => 'Сс';

  @override
  String get weekdayWed => 'Ср';

  @override
  String get weekdayThu => 'Бс';

  @override
  String get weekdayFri => 'Жм';

  @override
  String get weekdaySat => 'Сн';

  @override
  String get weekdaySun => 'Жс';

  @override
  String get linkOpenFailed => 'Сілтемені ашу мүмкін болмады';

  @override
  String get telegramOpenFailed => 'Telegram ашылмады';

  @override
  String get supportDeveloper => 'Әзірлеушіге қолдау көрсету';

  @override
  String get techSupport => 'Техникалық қолдау';

  @override
  String get termsOfUse => 'Пайдалану шарттары';

  @override
  String get privacyPolicy => 'Құпиялылық саясаты';

  @override
  String get preparation => 'Дайындық';

  @override
  String get feedbackSection => 'Кері байланыс және дыбыстар';

  @override
  String get confirmAnswerSetting => 'Жауапты растау';

  @override
  String get confirmAnswerHint =>
      'Жауап алдымен таңдалады, содан кейін түйме арқылы расталады.';

  @override
  String get hapticFeedback => 'Діріл';

  @override
  String get soundEffects => 'Дыбыстық әсерлер';

  @override
  String get voiceOverQuestions => 'Сұрақтарды дауыстап оқу';

  @override
  String get ticketCategorySetting => 'Санат';

  @override
  String get ticketCategoryHint =>
      'A/B – жеңіл автомобильдер мен мотоциклдер, C/D – жүк көліктері мен автобустар';

  @override
  String get dataSection => 'Деректер';

  @override
  String get resetStatsDetail =>
      'Сұрақ барысы, емтихан нәтижелері және таңдаулы сұрақтар жойылады.';

  @override
  String get reset => 'Қалпына келтіру';

  @override
  String get statsReset => 'Статистиканы қалпына келтіру';

  @override
  String get searchByQuestionOrTopic => 'Сұрақ немесе тақырып бойынша іздеу';

  @override
  String get emptyHere => 'Әзірге бұл жерде бос';

  @override
  String get favoritesEmptyHint =>
      'Күрделі сұрақтарды жұлдызшамен белгілеңіз, олар жылдам қарап шығу үшін бір жерде жиналады.';

  @override
  String get favoritesSearchEmpty =>
      'Бұл сұрау үшін ештеңе табылмады. Сұрақтың бір бөлігін немесе тақырыптың атауын қолданып көріңіз.';

  @override
  String get favoritesSubtitle => 'Жеке қиын сұрақтар';

  @override
  String favoritesCountHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сұрақ',
      one: '$count сұрақ',
    );
    return 'Қазір таңдаулыда $_temp0 бар. Бұл режимді емтихан алдында жеке жинақ ретінде пайдаланыңыз.';
  }

  @override
  String get practiceAllFavorites => 'Барлық таңдаулылар арқылы өтіңіз';

  @override
  String get noTopic => 'Тақырып жоқ';

  @override
  String get favoriteQuestion => 'Таңдаулы сұрақ';

  @override
  String ticketNumber(Object number) {
    return '$number-билет';
  }

  @override
  String get mistakesTitle => 'Қателермен жұмыс';

  @override
  String get noMistakesYet => 'Әлі қателер жоқ';

  @override
  String get mistakesEmptyHint =>
      'Дұрыс емес жауаптар пайда болған кезде, мұнда тек әлсіз сұрақтарды тез қайталауға болады.';

  @override
  String get repeatAllMistakes => 'Барлық қателерді қайталаңыз';

  @override
  String get mistakeReview => 'Қатені талдау';

  @override
  String get mistakeLabel => 'Қате';

  @override
  String get nothingFoundTryAnother =>
      'Ештеңе табылмады. Басқа сөзді қолданып көріңіз.';

  @override
  String get pddSearchEmpty =>
      'Ештеңе табылмады. Бөлім нөмірін немесе кілт сөзді қолданып көріңіз.';

  @override
  String get onboardingTitle => 'Сіз немен жүруді жоспарлап отырсыз?';

  @override
  String get categoryABDesc => 'автомобиль, мотоцикл';

  @override
  String get categoryCDDesc => 'жүк көлігі, автобус';

  @override
  String get ttsAnswerOptions => 'Жауап опциялары';

  @override
  String get ttsAnswer => 'Жауап';

  @override
  String get noQuestions => 'Сұрақтар жоқ';

  @override
  String get hint => 'Кеңес';

  @override
  String questionOfTotal(int current, int total) {
    return '$current / $total сұрақ';
  }

  @override
  String get finishButton => 'Аяқталды';

  @override
  String get hideHint => 'Кеңесті жасыру';

  @override
  String get confirmAnswerButton => 'Жауапты растау';

  @override
  String get myMistakes => 'Менің қателіктерім';

  @override
  String get noQuestionsToReview => 'Қарап шығуға сұрақтар жоқ';

  @override
  String get examReview => 'Емтиханды талдау';

  @override
  String get zoomIn => 'Үлкейту';

  @override
  String get trainingResultPerfect => 'Бірде-бір қате емес - оны жалғастырыңыз';

  @override
  String get trainingResultWithMistakes =>
      'Қате жіберген сұрақтарды қайталаңыз';

  @override
  String get trainingRepeatMistakes => 'Қателерді қайталаңыз';

  @override
  String get done => 'Дайын';

  @override
  String get close => 'Жабу';

  @override
  String get next => 'Келесі';

  @override
  String get notAnsweredThisQuestion => 'Сіз бұл сұраққа жауап бермедіңіз';

  @override
  String get description => 'Сипаттама';

  @override
  String get folkNameLabel => 'Танымал есім';

  @override
  String get examAdditionalTitle => 'Қосымша сұрақтар';

  @override
  String examAdditionalQuestionOfTotal(int current, int total) {
    return 'Қосымша $current / $total сұрақ';
  }

  @override
  String get examResultTimeout =>
      'Уақыт бітті. Жай қарқынмен қайталап көріңіз.';

  @override
  String get examResultPassed =>
      'Өте жақсы нәтиже. Оны билеттермен бекітуге болады.';

  @override
  String get examResultFailed => 'Қателерді шешіп, әлсіз жерлерін қайталаңыз.';

  @override
  String valueOfTotal(int value, int total) {
    return '$value / $total';
  }

  @override
  String examFailedByBlock(int count) {
    return 'Билет әрқайсысы 5 сұрақтан тұратын 4 тақырыптық блоктан тұрады. Жол полициясы ережелеріне сәйкес, бір блоктағы $count қателері жалпы екі қатеден көп болмаса да, емтиханнан өтпегенін білдіреді.';
  }

  @override
  String get examAdditionalBlock => 'Қосымша блок';

  @override
  String examAdditionalBlockValue(int count, int errors) {
    return '$count сұрақтар, қателер: $errors';
  }

  @override
  String get examTimeSpent => 'Өткізілген уақыт';

  @override
  String get examMainBlockErrors => 'Негізгі блоктағы қателер';

  @override
  String get backToTraining => 'Жаттығу дегенге қайта келу';

  @override
  String get share => 'Бөлісу';

  @override
  String get copiedToClipboard => 'Буферге көшірілді';

  @override
  String examShareText(
    String result,
    int correct,
    int total,
    String title,
    String url,
  ) {
    return '$result\nДұрыс жауаптар: $correct / $total\n\n$title\n$url';
  }

  @override
  String get supportChooseMethod => 'Әдісті таңдаңыз';

  @override
  String get supportYoomoney => 'YuMoney (карта, әмиян)';

  @override
  String get supportUsdt => 'USDT · TRC-20 желісі (TRON)';

  @override
  String get supportUsdtWarning =>
      'TRC-20 (TRON) желісі арқылы тек USDT жіберіңіз. Басқа желі арқылы аудару қаражаттың жоғалуына әкеледі.';

  @override
  String get copyAddress => 'Мекенжайды көшіру';

  @override
  String get notifStreakTitle1 => 'Серия қауіп төніп тұр';

  @override
  String get notifStreakBody1 => 'Жаттығу жасаңыз және жарқырауды сақтаңыз 🔥';

  @override
  String get notifStreakTitle2 => 'Сіз бас тартуға тым жақынсыз';

  @override
  String get notifStreakBody2 => 'Әр күн сізді емтиханға жақындатады';

  @override
  String get notifStreakTitle3 => '🔥 Жарық сөнгелі жатыр';

  @override
  String get notifStreakBody3 =>
      'Кіріңіз және бірнеше сұрақтарға жауап беріңіз';

  @override
  String get notifStreakTitle4 => 'Күн бітуге жақын';

  @override
  String get notifStreakBody4 => 'Бүгін жаттығу болған жоқ';

  @override
  String get notifStreakTitle5 => 'Сіздің жазбаңызға қауіп төніп тұр';

  @override
  String get notifStreakBody5 => 'Оны бір әрекетте сақтаңыз';

  @override
  String get notifStreakTitle6 => 'Емтихан көрінгеннен де жақын';

  @override
  String get notifStreakBody6 => 'Бүгін жаттығу';

  @override
  String get notifChannelName => 'Серия туралы еске салғыштар';

  @override
  String get notifChannelDesc => 'Жаттығулар сериясын жоғалтпау үшін';

  @override
  String get dataLoadError =>
      'Деректерді жүктеу мүмкін болмады. Байланысты тексеріп, әрекетті қайталаңыз.';

  @override
  String get themeSetting => 'Тақырып';

  @override
  String get themeSystem => 'Жүйелік';

  @override
  String get themeLight => 'Ашық';

  @override
  String get themeDark => 'Күңгірт';

  @override
  String get themeChoose => 'Тақырып';

  @override
  String get notificationsSetting => 'Күнделікті еске салғыш';

  @override
  String get notificationsHint => 'Серия жабылмаса күн сайын 20:00';

  @override
  String get game => 'Ойын';

  @override
  String get gameSimulator => '3D симуляторы';

  @override
  String get gameLeaderboard => 'Көшбасшылар тақтасы';

  @override
  String get gameScore => 'Ұпай';

  @override
  String get gameDistance => 'Қашықтық';

  @override
  String get gameOver => 'Жарыс аяқталды';

  @override
  String get gameRestart => 'Қайталап көріңіз';

  @override
  String get gameExit => 'Шығу';

  @override
  String get gameLeft => 'Солға';

  @override
  String get gameRight => 'Оңға';

  @override
  String get gameGas => 'ГАЗ';

  @override
  String get gameSpeedUnit => 'км/сағ';

  @override
  String get gameMeters => 'м';

  @override
  String get gameKilometers => 'км';

  @override
  String get gameSeconds => 'с';

  @override
  String get gameMistake => 'Қате';

  @override
  String get gameCorrect => 'Дұрыс!';

  @override
  String get gameContinue => 'Жүруді жалғастыру';

  @override
  String get gameResolving => 'Газ — жүру · көрсеткілер — бұру';

  @override
  String get gameGarage => 'Көлік таңдау';

  @override
  String get gameCarHatch => 'Хэтчбек';

  @override
  String get gameCarSedan => 'Седан';

  @override
  String get gameCarSuv => 'Жол талғамайтын көлік';

  @override
  String get gameCarPickup => 'Пикап';

  @override
  String get gameCarCoupe => 'Купе';

  @override
  String get gameCarWagon => 'Универсал';

  @override
  String get gameCarCyber => 'Кибертранспорт';

  @override
  String get gamePaintRed => 'қызыл';

  @override
  String get gamePaintBlue => 'көк';

  @override
  String get gamePaintGreen => 'жасыл';

  @override
  String get gamePaintSand => 'құмды';

  @override
  String get gamePaintWhite => 'ақ';

  @override
  String get gamePaintBlack => 'қара';

  @override
  String get gamePaintSilver => 'күміс';

  @override
  String get gamePaintOrange => 'апельсин';

  @override
  String get gamePaintPurple => 'күлгін';

  @override
  String get gamePaintTeal => 'көгілдір';

  @override
  String get gamePaintYellow => 'сары';

  @override
  String get gamePaintWine => 'бургундия';

  @override
  String get gamePaintGold => 'алтын';

  @override
  String gameGarageNextCar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Келесі көлік $count дұрыс жауаптан кейін',
      one: 'Келесі көлік $count дұрыс жауаптан кейін',
    );
    return '$_temp0';
  }

  @override
  String get gameGaragePremiumCar =>
      'Премиум барлық көліктер мен барлық түстердің құлпын ашады';

  @override
  String get gameRevealTitle => 'Жаңа көлік!';

  @override
  String get gameRevealTap => 'Қақпаны басыңыз';

  @override
  String get gameRevealChoose => 'таңдаңыз';

  @override
  String get gameRevealClose => 'Жабу';

  @override
  String get feedLockedTitle => 'Арна жүйеге кіргеннен кейін ашылады';

  @override
  String get feedLockedBody =>
      'Күнделікті ережелер, белгілер және кеңестер бар қысқа карталар. Жүйеге кірсеңіз, арнаңыз, әрекеттер сериясы және орындалу барысы кез келген құрылғыда сізбен бірге болады.';

  @override
  String get feedSignIn => 'Жүйеге кіру';

  @override
  String get gameSceneTitle => 'Ауа-райы және маусым';

  @override
  String get gameSceneWeather => 'ауа райы';

  @override
  String get gameSceneSeason => 'Жыл мезгілі';

  @override
  String get gameSceneAuto => 'Авто';

  @override
  String get gameSceneClear => 'Таза';

  @override
  String get gameSceneOvercast => 'Бұлтты';

  @override
  String get gameScenePrecip => 'Жауын-шашын';

  @override
  String get gameSceneCalendar => 'Күнтізбе бойынша';

  @override
  String get gameDebugUnlimitedFuel => 'Шексіз жарыстар';

  @override
  String get gameDebugUnlimitedFuelHint => 'Жазбалар жұмсалмайды';

  @override
  String get gameSceneSummer => 'Жаз';

  @override
  String get gameSceneAutumn => 'Күз';

  @override
  String get gameSceneWinter => 'Қыс';

  @override
  String get gameCollision => 'Соқтығыс';

  @override
  String get gameOffroad => 'Бордюр · жолға қарай бұрылу';

  @override
  String get gamePriorityViolation => 'Сіз жол бермедіңіз';

  @override
  String get gameWrongManeuver => 'Маневр тапсырмаға сәйкес келмейді';

  @override
  String get gameOncoming => 'Келе жатқан жолақ! Оңға оралыңыз';

  @override
  String get gameOneWayAgainst =>
      'Бір жақты қозғалыс! Сіз ағынға қарсы жүресіз';

  @override
  String get gameRoadworksHit => 'Сіз жол жұмысы аймағына кірдіңіз';

  @override
  String get gameCorrectAnswers => 'Дұрыс жауаптар';

  @override
  String gameAnswersOf(int correct, int total) {
    return '$correct / $total';
  }

  @override
  String get gameNoViolations => 'Бұзушылықтар жоқ';

  @override
  String get gameYourCar => 'Сіздің көлігіңіз';

  @override
  String get gameSpeeding => 'Жылдамдықты асыру';

  @override
  String get gameOvertakingProhibited => 'Мұнда басып озуға тыйым салынады';

  @override
  String get gameStopViolation => 'Сіз дұрыс жерде тоқтаған жоқсыз';

  @override
  String get gameRedLightViolation => 'Тыйым салу сигналы арқылы жүру';

  @override
  String get gameRailwayViolation =>
      'Өткел жабық - айналып өтуге және кетуге болмайды';

  @override
  String get gamePedestrianYield => 'Жаяу жүргіншіге жол беріңіз';

  @override
  String gameSpeedLimitLabel(int limit) {
    return 'Шектеу $limit км/сағ';
  }

  @override
  String get gameBrake => 'Тоқтаған кезде кері тежеңіз';

  @override
  String get gameNewRecord => 'Жаңа рекорд!';

  @override
  String gameBestScore(int score) {
    return 'Жазба $score';
  }

  @override
  String get gameGasHint => 'Басып ұстап тұрыңыз - бұл газ';

  @override
  String get gameWeeklyRating => 'Апта рейтингі';

  @override
  String get gameLobbyStart => 'Жарысты бастаңыз';

  @override
  String get gameLobbyContinue => 'Жүруді жалғастырыңыз';

  @override
  String get gameLobbyNewRun => 'Жаңа сапар';

  @override
  String get gameLobbyNewRunTitle => 'Жаңа сапарды бастау керек пе?';

  @override
  String get gameLobbyNewRunBody =>
      'Ағымдағы сапар аяқталады, жаңасы бірінші сұрақтан басталады.';

  @override
  String get gameLobbyNewRunConfirm => 'Қайта бастау';

  @override
  String get gameLobbyChangeCar => 'Өзгерту';

  @override
  String get gameLobbyRecord => 'Жазба';

  @override
  String get gameLobbyColour => 'Түс';

  @override
  String get gameLobbyRating => 'Рейтинг';

  @override
  String get gameLobbyColoursHint =>
      'Ойында дұрыс жауаптар үшін жаңа түстер ашылады';

  @override
  String get gameRatingHint =>
      'Аптадағы барлық жарыстардың ұпайлары. Кестеде ең жақсы 100 көрсетілген.';

  @override
  String get gameRatingEmpty =>
      'Бұл аптада әлі ешкім өткен жоқ. Бірінші болыңыз!';

  @override
  String get gameRatingUnavailable =>
      'Рейтинг жүктелмеді. Интернетті тексеріңіз.';

  @override
  String get gameRatingYou => 'Сіз';

  @override
  String gameRatingRuns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count жарыс',
      one: '$count жарыс',
    );
    return '$_temp0';
  }

  @override
  String gameRatingEndsIn(int days) {
    return 'Аптаның соңына дейін: $days күн.';
  }

  @override
  String get gameAuthRequired => 'Ойын жүйеге кіргеннен кейін қол жетімді';

  @override
  String get gameAuthRequiredHint =>
      'Ұпай жинау және апта сайынғы рейтингтерге қатысу үшін жүйеге кіріңіз.';

  @override
  String get gameSignIn => 'Жүйеге кіріңіз және өтіңіз';

  @override
  String gamePenaltyHint(int points) {
    return 'Бұзушылық: −$points ұпай';
  }

  @override
  String get pddSettingsItem => 'Ережелер, белгілер және таңбалау';

  @override
  String get gameLockedTitle => 'Рульге отыруға дайынсыз ба?';

  @override
  String get gameLockedHint =>
      'Тірі қала, жолдағы жол полициясының билеттері және аптаның рейтингі. Жүйеге кіріңіз, кеттік.';

  @override
  String get gameFuel => 'Жарыстар';

  @override
  String get gameFuelUnlimited => 'Шексіз жарыстар';

  @override
  String get gameFuelEmptyTitle => 'Жарыстар аяқталды';

  @override
  String gameFuelRefillIn(String time) {
    return '$time арқылы жаңа келу';
  }

  @override
  String get gameFuelPremiumPitch => 'Жарыстар жазылумен аяқталмайды';

  @override
  String get gameFuelBuyPremium => 'Премиумды қосыңыз';

  @override
  String get gameFuelWait => 'Күте тұрыңыз';

  @override
  String get gameViolations => 'Бұзушылықтар';

  @override
  String get gameOverDescription =>
      'Жарыстағы барлық сұрақтар аяқталды. Қате жауаптар «Қателерде» бар - оларды талдап, әрекетті қайталаңыз.';

  @override
  String get gameYou => 'Сіз';

  @override
  String get gameStop => 'ТОҚТАТУ';

  @override
  String get gameLoading => 'Ойын жүктелуде';

  @override
  String get gameLoadError =>
      'Жарысты жалғастыру мүмкін болмады. Құрылғыны қайта іске қосыңыз немесе мәзірге оралыңыз.';

  @override
  String get authSuccess => 'Жүйеге кіру сәтті';

  @override
  String get authFailed => 'Кіру орындалмады. Қайталап көріңіз.';

  @override
  String get authErrorCancelled =>
      'Кіру аяқталмады. Есептік жазбаны қайта таңдаңыз.';

  @override
  String get authErrorProvider =>
      'Таңдалған қызмет арқылы кіру мүмкін болмады. Қайталап көріңіз немесе басқа жолмен кіріңіз.';

  @override
  String get authErrorNetwork =>
      'Интернет байланысы жоқ. Байланысты тексеріп, қайталап көріңіз.';

  @override
  String get authErrorTimeout =>
      'Жауап алу мүмкін болмады. Интернетті тексеріңіз немесе басқа желіні (Wi‑Fi немесе мобильді интернет) байқап көріңіз. Билеттер мен емтихан кірмей де қолжетімді.';

  @override
  String get authErrorAppKey =>
      'Қолданбаның бұл нұсқасы ескірген. Оны дүкенде жаңартып, қайта кіріңіз.';

  @override
  String get authErrorCredential =>
      'Кіруді растау мүмкін болмады. Қайталап көріңіз немесе басқа жолмен кіріңіз.';

  @override
  String get authErrorServer =>
      'Біздің тарапта бір нәрсе дұрыс болмады. Бірнеше минуттан кейін қайталап көріңіз.';

  @override
  String get authErrorResponse =>
      'Кіру аяқталмады. Қолданбаны қайта іске қосып, қайталап көріңіз. Көмектеспесе, телефондағы күн мен уақытты тексеріңіз.';

  @override
  String get paySuccessActivated => 'Премиум қосылды. Рақмет!';

  @override
  String get payRestoreSuccess => 'Сатып алулар қалпына келтірілді.';

  @override
  String get payRestoreNone =>
      'Сатып алулар табылмады. Төлеген дүкен есептік жазбасына кіріңіз.';

  @override
  String get payErrorPricesLoading =>
      'Бағалар әлі жүктелуде. Бір секунд күтіп, қайта басыңыз.';

  @override
  String payErrorStoreUnavailable(String store) {
    return 'Дүкен қазір қолжетімсіз. Интернетті және $store есептік жазбасына кіруді тексеріп, қайталап көріңіз.';
  }

  @override
  String payErrorStoreRefused(String store) {
    return 'Дүкен төлемді өткізе алмады. $store ішіндегі төлем әдісін тексеріп, қайталап көріңіз.';
  }

  @override
  String get payErrorGeneric =>
      'Сатып алу аяқталмады. Қайталап көріңіз. Ақша алынған болса, «Қалпына келтіру» түймесін басыңыз — қолжетімділік қайтады.';

  @override
  String get payErrorUnexpected => 'Бірдеңе дұрыс болмады. Қайталап көріңіз.';

  @override
  String get authSessionTemporary =>
      'Жүйеге кіру аяқталды. Телефон сеансты сақтай алмады: қайта іске қосқаннан кейін жүйеге қайта кіру керек.';

  @override
  String authDiagnosticCode(String code) {
    return 'Қолдау коды: $code';
  }

  @override
  String get authTitle => 'Жүйеге кіру';

  @override
  String get authDescription =>
      'Құрылғыны өзгерту немесе қайта орнату кезінде премиум қолжетімділікті және статистиканы сақтаңыз';

  @override
  String get authAppleSafariHint =>
      'Деректерді енгізбей Face ID арқылы кіру үшін шолғыш мәзірі арқылы сайтты Safari жүйесінде ашыңыз. Кірістірілген шолғыш Apple электрондық поштаңыз бен құпия сөзіңізді сұрауы мүмкін.';

  @override
  String get authApple => 'Apple ID арқылы жалғастырыңыз';

  @override
  String get authGoogle => 'Google арқылы жалғастырыңыз';

  @override
  String get authYandex => 'Яндекс идентификаторымен жалғастырыңыз';

  @override
  String get authDebug => 'Сынақ енгізу (отлад құрастыру)';

  @override
  String get accountDeleted => 'Есептік жазба мен деректер жойылды';

  @override
  String get accountDeleteFailed =>
      'Есептік жазба жойылмады. Байланысты тексеріп, әрекетті қайталаңыз.';

  @override
  String get gameControlsTitle => 'Басқару';

  @override
  String get gameControlsSimple => 'Қарапайым басқару элементтері';

  @override
  String get gameControlsSimpleHint =>
      'Көрсеткілер - жолақ өзгереді және бұрылады, машина өзі жүреді';

  @override
  String get gameControlsFree => 'Еркін бақылау';

  @override
  String get gameControlsFreeHint =>
      'Көрсеткілер руль дөңгелегін сіз ұстап тұрғанда айналдырады';

  @override
  String get gameTipGas =>
      'Газ педальын ұстаңыз - машина қозғалады. Жіберіңіз - ол біркелкі тоқтайды';

  @override
  String get gameTipSteer =>
      'Көрсеткіні ұстаңыз - машина айналады. Егер сіз жіберсеңіз, ол жолақпен тураланады';

  @override
  String get gameTipTurn =>
      'Қиылыста көлік бұрылып жатқанда көрсеткіні ұстаңыз, содан кейін жіберіңіз - ол өздігінен түзетіледі';

  @override
  String get gameTipNext => 'Келесі';

  @override
  String get gameTipDone => 'кеттік';

  @override
  String get gamePause => 'Кідірту';

  @override
  String get gameLobbyControls => 'Басқару';

  @override
  String gameRunProgress(int n, int total) {
    return '$n / $total сұрақ';
  }

  @override
  String get gameCorrectAnswer => 'Дұрыс жауап';

  @override
  String get gameTimeUp => 'Уақыт бітті';

  @override
  String gamePenaltyPoints(int points) {
    String _temp0 = intl.Intl.pluralLogic(
      points,
      locale: localeName,
      other: '−$points ұпай',
      one: '−$points ұпай',
    );
    return '$_temp0';
  }

  @override
  String gameRunMistakes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Жарыста $count қате',
      one: 'Жарыста $count қате',
    );
    return '$_temp0';
  }

  @override
  String get gameReviewMistakes => 'Қателерді талдау';

  @override
  String get notifGameRunTitle => 'Жаңа жарыс дайын';

  @override
  String get notifGameRunBody =>
      'Рульге отырыңыз: емтихан билеттерінің қиылыстары күтіп тұр.';

  @override
  String get notifGameChannelName => 'Ойын';

  @override
  String get notifGameChannelDesc => 'Ойында жарыс қалпына келгенде';

  @override
  String gameRunMistakesButton(int count) {
    return 'Қателер $count';
  }

  @override
  String get gameCorrectShort => 'Бұл дұрыс';

  @override
  String gameRunsPill(int runs, int max) {
    return '$runs / $max жарыс';
  }

  @override
  String get gameRunsUnlimitedPill => 'Жарыстар ∞';

  @override
  String get gameRunsTitle => 'Жарыстар';

  @override
  String gameRunsExplain(int questions, int max, int minutes) {
    return 'Жарыс — бұл жолда $questions сұрақ. $max жарысқа дейін қор бар, әрбір жұмсалған жарыс $minutes минуттан кейін қайтарылады.';
  }

  @override
  String gameRunsNextIn(String time) {
    return '$time арқылы келесі келу';
  }

  @override
  String get gameRunsFull => 'Қор толы - сіз бара аласыз';

  @override
  String get gameRunsPremium => 'Премиум сапарларымен шектеусіз';

  @override
  String get gameRunsGetPremium => 'Премиум арқылы шектеусіз';

  @override
  String gameLobbyRunLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сұрақ',
      one: '$count сұрақ',
    );
    return '$_temp0';
  }

  @override
  String gameLobbyProgress(int n, int total) {
    return '$n / $total өтті';
  }

  @override
  String get gameLobbyNewCar => 'ЖАҢА';

  @override
  String get gameRunsReady => 'Дайын';

  @override
  String get gameRunsUntil => 'келгенге дейін';

  @override
  String get gameUturn => 'Кері бұрылу';

  @override
  String get purchaseVerificationPending =>
      'Төлем өтті, бірақ қолжетімділік әлі расталмады. Қайта төлемеңіз: интернет қосулы кезде «Қалпына келтіру» түймесін басыңыз.';

  @override
  String get notifAdminChannelName => 'Қолданба хабарламалары';

  @override
  String get noticeAcknowledge => 'Мен көремін';

  @override
  String get noticeOpen => 'Ашық';

  @override
  String get pushMessagesSetting => 'Қолданба жаңалықтары';

  @override
  String get pushMessagesHint =>
      'Жаңартулар мен маңызды оқиғалар туралы хабарландыруларды жіберіңіз';

  @override
  String get gameKeyboardHint =>
      '↑ / W - газ ↓ / S / кеңістік - тежегіш ← → / A D - бұрылыстар';

  @override
  String get webQuarter => '3 ай';

  @override
  String get webPaymentSoon => 'Төлем жақында келеді';

  @override
  String get webPaymentInfo =>
      'Автоматты жаңартусыз 3 айға қол жеткізу. Сайттағы төлем әлі қосылмаған.';

  @override
  String get webWeek => '1 апта';

  @override
  String get webPayButton => 'SBP арқылы төлеңіз';

  @override
  String get webPayInfo =>
      'Автоматты жаңартусыз бір реттік төлем. Премиум телефондағы қолданбада да ашылады - оған сол есептік жазбамен кіріңіз.';

  @override
  String get sbpPayInfoApp =>
      'Автоматты жаңартусыз бір реттік төлем. Премиум төлемнен кейін бірден іске қосылады және осы есептік жазба арқылы барлық құрылғыларда жұмыс істейді.';

  @override
  String get webPayTariffs => 'Тарифтер';

  @override
  String get webPayEmailTitle => 'СБП арқылы төлеу';

  @override
  String get webPayEmailBody =>
      'Біз жақын күндері СБП арқылы төлемді қосамыз. Электрондық поштаңызды қалдырыңыз, ол жұмыс істеп тұрған кезде сізге жазамыз. Оған чек келеді.';

  @override
  String get webPayEmailHint => 'Электрондық пошта';

  @override
  String get webPayEmailInvalid =>
      'Электрондық пошта мекенжайыңызды тексеріңіз';

  @override
  String get webPayNotify => 'Маған хабарлаңыз';

  @override
  String get webPayFailed =>
      'Төлемді ашу мүмкін болмады. Интернетті тексеріп, қайталап көріңіз.';

  @override
  String get webPayNeedsAccount =>
      'Төлеу үшін Google, Yandex немесе Apple арқылы кіріңіз: сынақ логин төлемді қабылдамайды.';

  @override
  String get webPayLiveBody =>
      'Тексеру үшін электрондық пошта мекенжайыңызды көрсетіңіз. Содан кейін төлем QR кодын пайдалану арқылы немесе банктің қосымшасында СБП арқылы ашылады. Премиум төлемнен кейін бірден іске қосылады.';

  @override
  String get webPayProceed => 'Төлемді жалғастырыңыз';

  @override
  String get webPaySuccess => 'Төлем аяқталды - Премиум кіреді. Рақмет сізге!';

  @override
  String get webPayPending =>
      'Төлем өңделуде. Премиум бірнеше минутта өзі қосылады — қайта төлеудің қажеті жоқ.';

  @override
  String get webPayCanceled => 'Төлем аяқталмады. Ақша алынған жоқ.';

  @override
  String webPaySaved(String email) {
    return 'Рахмет! Төлем жұмыс істей бастағанда біз $email нөміріне жазамыз';
  }

  @override
  String premiumOneTimeInfo(String date) {
    return 'Қол жеткізу $date дейін жарамды және автоматты түрде жаңартылмайды.';
  }

  @override
  String get appUpdateTitle => 'Жаңарту шығарылды';

  @override
  String get appUpdateBody =>
      'Жаңа нұсқада жақсартулар мен түзетулер бар. Оларды пайдалану үшін қолданбаны жаңартыңыз.';

  @override
  String appUpdateVersion(String version) {
    return '$version нұсқасы';
  }

  @override
  String get appUpdateAction => 'Жаңарту';

  @override
  String get appUpdateLater => 'Кейінірек';

  @override
  String get appUpdateReadyTitle => 'Жаңарту дайын';

  @override
  String get appUpdateReadyBody =>
      'Жаңа нұсқа әлдеқашан жүктеп алынған. Оны орнату үшін қолданбаны қайта іске қосыңыз.';

  @override
  String get appUpdateRestart => 'Қайта іске қосыңыз';

  @override
  String get appUpdateOpenFailed =>
      'Жаңартуды ашу мүмкін болмады. Тағы жасауды сәл кейінірек көріңізді өтінеміз.';

  @override
  String get profile => 'Профиль';

  @override
  String get signInCardTitle => 'Есептік жазбаға кіріңіз';

  @override
  String get signInCardSubtitle => 'Прогресс пен премиумды сақтаңыз';

  @override
  String get achievements => 'Жетістіктер';

  @override
  String achievementsEarnedCount(int count, int total) {
    return '$count / $total';
  }

  @override
  String achievementLevelFormat(int level, int total) {
    return 'Дең. $level / $total';
  }

  @override
  String achievementSemanticsLabel(String title, int level, int total) {
    return '$title, $level деңгейі, барлығы $total';
  }

  @override
  String achievementProgressFormat(int current, int target) {
    return '$current / $target';
  }

  @override
  String get achievementTitleStreak => 'Үзіліссіз';

  @override
  String get achievementTitleCoverage => 'Эрудит';

  @override
  String get achievementTitleTickets => 'Билет арқылы билет';

  @override
  String get achievementTitleAttempts => 'Шаршамайтын';

  @override
  String get achievementTitleExams => 'Емтихан';

  @override
  String get achievementTitleFlawless => 'Бір қатесіз';

  @override
  String get achievementTitleMistakes => 'Қателермен жұмыс';

  @override
  String get achievementTitleGame => 'Жарысшы';

  @override
  String get achievementDescStreak =>
      'Әрекеттермен қатар күндердің ең жақсы сызығы';

  @override
  String get achievementDescCoverage => 'Базадағы әртүрлі сұрақтарды шешті';

  @override
  String get achievementDescTickets => '«Өтті» деп шешілген билеттер';

  @override
  String get achievementDescAttempts =>
      'Көшірмелерді қоса алғанда, жалпы жауаптар';

  @override
  String get achievementDescExams => 'Сынақ емтихандары өтті';

  @override
  String get achievementDescFlawless => 'Емтихандар қатесіз өтті';

  @override
  String get achievementDescMistakes =>
      'Мен қателескен, содан кейін дұрыс жауап берген сұрақтар';

  @override
  String get achievementDescGame =>
      '«Жанды қалада» бір жүрісте 200, 400, 700 және 950 ұпай жинаңыз.';

  @override
  String get achievementTitleRank => 'Рейтинг жеңімпазы';

  @override
  String get achievementDescRank =>
      'Ойынның апталық рейтингіндегі ең жақсы орын';

  @override
  String achievementRankTop(int count) {
    return 'Топ-$count';
  }

  @override
  String get achievementRankFirst => '1 орын';

  @override
  String get paywallSubscribe => 'Жазылу';

  @override
  String get paywallStoreGoogle => 'Google Play';

  @override
  String get paywallPayMethod => 'Төлем әдісі';

  @override
  String get paywallMethodSbp => 'СБП';

  @override
  String get paywallStoreApple => 'Apple ID параметрлері';

  @override
  String get paywallTitle => 'Шектеусіз дайындалыңыз';

  @override
  String get paywallFreeNote =>
      'Билеттер, емтихан және жол жүру ережелері тегін қалады';

  @override
  String get paywallFeatureFeed => 'Шексіз сұрақтар арнасы';

  @override
  String get paywallFeatureAi => 'AI қателерін талдау';

  @override
  String get paywallFeatureVoice =>
      'Билеттерге арналған студиялық дауыс актісі';

  @override
  String get paywallFeatureGame => 'Ойында шектеусіз жарыстар';

  @override
  String get paywallPlanQuarter => '3 ай';

  @override
  String get paywallPlanWeek => '1 апта';

  @override
  String get paywallEveryQuarter => 'әр 3 ай сайын';

  @override
  String get paywallEveryWeek => 'апта сайын';

  @override
  String get paywallBadgeBest => 'Пайдалы';

  @override
  String paywallRenewal(String store) {
    return 'Автоматты түрде жаңартылады. $store ішінде кез келген уақытта бас тарта аласыз.';
  }

  @override
  String get paywallTerms => 'Шарттар';

  @override
  String get paywallPrivacy => 'Құпиялық';

  @override
  String get paywallRestore => 'Қалпына келтіру';

  @override
  String get gameSourceImage => 'Түпнұсқа сұрақ суреті';

  @override
  String get gameSourceImageUnavailable => 'Бұл сұрақта сурет жоқ';

  @override
  String get navGames => 'Ойындар';

  @override
  String get gameTrafficControllerTitle => 'Жол диспетчері';

  @override
  String get gameBestScoreLabel => 'Жазба';

  @override
  String get gameComboLabel => 'Макс. комбо';

  @override
  String get gameSolvedLabel => 'Шешілді';

  @override
  String get gameCombo => 'Комбо';

  @override
  String get gameLives => 'Өмір';

  @override
  String get gameActionStraight => 'Тіке';

  @override
  String get gameActionRight => 'Оңға';

  @override
  String get gameActionLeft => 'Солға';

  @override
  String get gameActionUTurn => 'Кері бұрылу';

  @override
  String get gameActionStand => 'тұру';

  @override
  String get gameVehicleCar => 'Автокөлік';

  @override
  String get gameVehicleTram => 'Трамвай';

  @override
  String get gameCameraOverview => 'Қарау';

  @override
  String get gameCameraDriver => 'Көлік жүргізу';

  @override
  String get gameOverTitle => 'Ойын аяқталды';

  @override
  String get gameOverNewRecord => 'Жаңа рекорд!';

  @override
  String get gamePlayAgain => 'Қайта ойнаңыз';

  @override
  String get gameWrong => 'Бұзушылық!';

  @override
  String get gameWhistleNote =>
      'Инспектордың ысқырығы: осы бағытта қозғалыс диспетчерінің сигналымен тыйым салынады.';

  @override
  String get gameSignSwiperTitle => 'Белгі-свайпер';

  @override
  String get gameSwipedLabel => 'Сырғытулар';

  @override
  String get gameSignSwiperNext => 'Келесі белгі';

  @override
  String get gameSignSwiperCategoryAll => 'Барлық санаттар';

  @override
  String get gameMistakesReview => 'Қателерді талдау';

  @override
  String get gameNoMistakes => 'Керемет жұмыс! Бір қате емес.';

  @override
  String get gameAccuracyLabel => 'Дәлдік';

  @override
  String gameQuestionCategory(String category) {
    return 'Бұл белгі \"$category\" ретінде жіктеледі ме?';
  }

  @override
  String gameQuestionName(String name) {
    return 'Бұл белгі \"$name\" деп аталады ма?';
  }

  @override
  String gameQuestionFolkName(String name) {
    return 'Бұл белгі халық арасында «$name» деп аталады ма?';
  }

  @override
  String get gameQuestionPriorityAdvantage =>
      'Бұл белгіде сіздің жол құқығыңыз бар ма?';

  @override
  String get gameQuestionProhibitsEntry =>
      'Бұл белгінің астында кіруге рұқсат етілген бе?';

  @override
  String get gameQuestionProhibitsOvertaking =>
      'Барлық көліктерді басып озуға рұқсат етілген бе?';

  @override
  String get gameQuestionProhibitsParking =>
      'Бұл белгінің астында тұрақ қоюға болады ма?';

  @override
  String get gameQuestionProhibitsStopping =>
      'Бұл белгінің астында тоқтауға рұқсат етілген бе?';

  @override
  String gameComboStreak(int combo) {
    return 'КОМБО х$combo!';
  }

  @override
  String get gameSoonBadge => 'Жақында';

  @override
  String get gameRoundaboutTitle => 'Айналмалы қозғалыс 3D';

  @override
  String get gameCrossroadsPriorityTitle => 'Қиылысты реттеңіз';

  @override
  String get gameCrossroadsPromptWhoGoesFirst => 'Кім бірінші өтеді?';

  @override
  String gameCrossroadsPromptWhoGoesNext(int step) {
    return 'Келесі ($step-ші) кім өтеді?';
  }

  @override
  String gameCrossroadsStepOf(int current, int total) {
    return '$current / $total қадам';
  }

  @override
  String get gameCrossroadsCollision => 'Жол апаты! Кезеңді бұзу';

  @override
  String gameCrossroadsShouldGo(String name) {
    return 'Қазір өтетін: $name';
  }

  @override
  String get gameCrossroadsHowTo =>
      'Көліктерді кезекпен қойыңыз: дәл қазір өтетінін басыңыз.';

  @override
  String get gameCrossroadsTapHint =>
      'Көлікті немесе оның үстіндегі белгіні басыңыз. Сахнаны саусақпен бұруға, екі саусақпен жақындатуға болады.';

  @override
  String get gameCrossroadsResetCamera => 'Камераны қайтару';

  @override
  String get gameCrossroadsNextCrossroad => 'Келесі қиылысу';

  @override
  String get gameCrossroadsRepeatCrossroad => 'Қайталап көріңіз';

  @override
  String get gameCrossroadsModeArcade => 'Аркада';

  @override
  String get gameCrossroadsModeTraining => 'Тренинг';

  @override
  String gameCrossroadsSolvedCount(int count) {
    return 'Шешілген: $count';
  }

  @override
  String get gameCrossroadsExplanationTitle =>
      'Ресей Федерациясының жол қозғалысы ережелеріне сәйкес жағдайды талдау';

  @override
  String get gameCrossroadsCompleteTitle => 'Қиылыс тазартылды!';

  @override
  String get gameGestureRightArm => 'Қол алға';

  @override
  String get gameGestureHandsSides => 'Қолдар жағына';

  @override
  String get gameGestureArmUp => 'Қол көтеріңіз';

  @override
  String get gameApproachLeft => 'Сол жағы';

  @override
  String get gameApproachFront => 'Кеуде';

  @override
  String get gameApproachRight => 'Оң жақ';

  @override
  String get gameApproachBack => 'артқа';

  @override
  String gameSecondsLeft(int seconds) {
    return '$seconds с';
  }

  @override
  String get gameSignsLoadError => 'Белгілер жүктелмеді';

  @override
  String get gameRetry => 'Қайталау';

  @override
  String get gameRestartRound => 'Қайтадан бастаңыз';

  @override
  String get gameSignYes => 'ИӘ';

  @override
  String get gameSignNo => 'ЖОҚ';

  @override
  String get gameSignCan => 'МҮМКІН';

  @override
  String get gameSignCannot => 'МҮМКІН ЕМЕС';

  @override
  String get gameUnderstood => 'Мен көремін';

  @override
  String get gamePddOfficialText =>
      'Ресей Федерациясының жол қозғалысы ережелері:';

  @override
  String get gamePromptWhereCanGo => 'Қайда баруға болады?';

  @override
  String get gameCaptionGesture => 'Қимыл';

  @override
  String get gameCaptionApproach => 'Сізге қарай бұрылған';

  @override
  String get gameAnswerWrong => 'Дұрыс емес';

  @override
  String get achievementTitleTrafficController => 'Сигнал шебері';

  @override
  String get achievementDescTrafficController =>
      '«Реттеуші» ойынында бір раундта 150, 300, 600 және 900 ұпай жинаңыз.';

  @override
  String get achievementTitleSignSwiper => 'Белгілер білгірі';

  @override
  String get achievementDescSignSwiper =>
      '«Белгі-свайпер» ойынында бір раундта 100, 200, 300 және 450 ұпай жинаңыз.';

  @override
  String get gameSignQuestionScope => 'Басқа белгілер мен тыйымдар жоқ';

  @override
  String get gameTrafficSignalQuestion => 'Сигнал нені рұқсат етеді?';

  @override
  String get gameTrafficHintButton => 'Кеңес';

  @override
  String get gameTrafficHintTitle => 'Қалай есте сақтау керек';

  @override
  String get gameTrafficHintPaused => 'Уақыт үзілісте';

  @override
  String get gameTrafficHintScope =>
      'Жолақты, белгілерді және белгілерді қарастырыңыз.';

  @override
  String get gameTrafficHintArmUp =>
      'Таяқ жоғары қаратылған - ол барлығына тұруды айтады.';

  @override
  String get gameTrafficHintForwardFront =>
      'Егер таяқ аузыңызға қараса, оңға бұрылыңыз.';

  @override
  String get gameTrafficHintForwardRight =>
      'Егер таяқ оң жаққа қараса, сіз мінуге құқығыңыз жоқ.';

  @override
  String get gameTrafficHintForwardLeft =>
      'Егер таяқ солға қараса, патшайым сияқты мініңіз.';

  @override
  String get gameTrafficHintBack => 'Артқы жағы қабырға.';

  @override
  String get gameTrafficHintWall => 'Кеуде мен арқа жүргізуші үшін қабырға.';

  @override
  String get gameTrafficHintSide =>
      'Жол диспетчері бүйірде тұрды - жол түзу және оңға ашық болды.';

  @override
  String get gameTrafficHintTramLeft =>
      'Трамвай қолдан қолға - тек солға қарай жүреді.';

  @override
  String get gameTrafficHintTramStraight =>
      'Трамвай қолынан қолға өтеді - тек түзу.';

  @override
  String get gameTrafficHintForbidden => 'Сигнал қозғалысқа тыйым салады.';

  @override
  String gameTrafficHintAllowed(String directions) {
    return 'Сигнал мүмкіндік береді: $directions.';
  }

  @override
  String get gameSignScenario1_1_0Prompt =>
      'Шлагбаумы бар өткел туралы ескерту белгісі?';

  @override
  String get gameSignScenario1_1_0Explanation =>
      'Иә. Алда шлагбаумы бар темір жол өткелі.';

  @override
  String get gameSignScenario1_1_1Prompt =>
      'Өтпей тұрып 80 м басып озуға болады ма?';

  @override
  String get gameSignScenario1_1_1Explanation =>
      'Жоқ. Өткелде және оған 100 м қалғанда басып озуға тыйым салынады (11.4 тармақ).';

  @override
  String get gameSignScenario1_1_2Prompt =>
      'Мен көлігімді өткелден 30 метр қалдыра аламын ба?';

  @override
  String get gameSignScenario1_1_2Explanation =>
      'Жоқ. Өткелден 50 м жақын жерде тұрақ қоюға тыйым салынады (12.5 тармақ).';

  @override
  String get gameSignScenario1_2_0Prompt => 'Алда бөгетсіз өткел бар ма?';

  @override
  String get gameSignScenario1_2_0Explanation =>
      'Иә. Белгі тосқауылсыз өту туралы ескертеді.';

  @override
  String get gameSignScenario1_2_1Prompt => 'Мен өткелде бұрыла аламын ба?';

  @override
  String get gameSignScenario1_2_1Explanation =>
      'Жоқ. Өткелде бұрылуға және кері бұруға тыйым салынады (8.11–8.12-тармақтар).';

  @override
  String get gameSignScenario1_3_1_0Prompt =>
      'Өткелде бір ғана темір жол бар ма?';

  @override
  String get gameSignScenario1_3_1_0Explanation =>
      'Иә. Бұл белгі бір жолды, тосқауылсыз өтуді білдіреді.';

  @override
  String get gameSignScenario1_3_1_1Prompt =>
      'Бұл белгі өткелден 150–300 м бұрын қойылған ба?';

  @override
  String get gameSignScenario1_3_1_1Explanation =>
      'Жоқ. 1.3.1 белгісі өткелдің алдында тікелей қойылады.';

  @override
  String get gameSignScenario1_5_0Prompt =>
      'Трамвай деподан емес, қиылыстан тыс жолды кесіп өтеді. Мен жол беруім керек пе?';

  @override
  String get gameSignScenario1_5_0Explanation =>
      'Иә. Қиылыстан тыс жерде трамвай деподан шығуды қоспағанда, басымдыққа ие (18.1 тармақ).';

  @override
  String get gameSignScenario1_5_1Prompt =>
      'Трамвай деподан шығады. Ол көліктерге жол беруі керек пе?';

  @override
  String get gameSignScenario1_5_1Explanation =>
      'Иә. Деподан шыққан кезде трамвай басқа көліктерге жол береді (18.1-тармақ).';

  @override
  String get gameSignScenario1_6_0Prompt =>
      'Бағдаршамсыз, тең құқықты қиылыста оң жақтағы көлікке жол беру керек пе?';

  @override
  String get gameSignScenario1_6_0Explanation =>
      'Иә. Маңыздылығы бірдей бақыланбайтын қиылыста оң жақтағы көліктерге жол беріңіз (13.11-тармақ).';

  @override
  String get gameSignScenario1_6_1Prompt =>
      'Бағдаршамсыз тең құқықты қиылыста басып озуға бола ма?';

  @override
  String get gameSignScenario1_6_1Explanation =>
      'Жоқ. Бақыланбайтын қиылыста басып озуға тек негізгі жолда жүргенде ғана рұқсат етіледі (11.4-тармақ).';

  @override
  String get gameSignScenario1_7_0Prompt => 'Алда айналма жол бар ма?';

  @override
  String get gameSignScenario1_7_0Explanation =>
      'Иә. Айналмалы жолға жақындағанда белгі ескертеді.';

  @override
  String get gameSignScenario1_7_1Prompt =>
      'Айналмалы жол дәл осы белгіден басталады ма?';

  @override
  String get gameSignScenario1_7_1Explanation =>
      'Жоқ. Бұл ескерту. Шеңбердегі қозғалыс бағыты 4.3 белгісімен белгіленеді.';

  @override
  String get gameSignScenario1_11_1_0Prompt =>
      'Жол тек 70 м жерде көрінсе, бұрылуға бола ма?';

  @override
  String get gameSignScenario1_11_1_0Explanation =>
      'Жоқ. Бұрылу үшін көріну әр бағытта кемінде 100 м болуы керек (8.11-тармақ).';

  @override
  String get gameSignScenario1_11_1_1Prompt =>
      'Қауіпті бұрылыс жасамас бұрын қауіпсіз жылдамдықты таңдау керек пе?';

  @override
  String get gameSignScenario1_11_1_1Explanation =>
      'Иә. Жылдамдық жолдың бұрылысы мен көріну мүмкіндігін ескере отырып таңдалады (10.1-тармақ).';

  @override
  String get gameSignScenario1_23_0Prompt =>
      'Балалар бұл жерде кенеттен жолға шығып кетуі мүмкін бе?';

  @override
  String get gameSignScenario1_23_0Explanation =>
      'Иә. Белгі жолда балалар пайда болуы мүмкін аймақ туралы ескертеді.';

  @override
  String get gameSignScenario1_23_1Prompt =>
      'Бұл белгі балаларға кез келген жерден жолды кесіп өтуге рұқсат ете ме?';

  @override
  String get gameSignScenario1_23_1Explanation =>
      'Жоқ. Белгі жүргізушілерге ескертеді, бірақ жолды кесіп өту ережелерін өзгертпейді.';

  @override
  String get gameSignScenario1_25_0Prompt =>
      'Сары фонда уақытша белгі, егер олар қайшы келсе, тұрақты белгіден маңыздырақ па?';

  @override
  String get gameSignScenario1_25_0Explanation =>
      'Иә. Уақытша және тұрақты белгілердің арасында қайшылық болса, уақытша талап орындалады.';

  @override
  String get gameSignScenario1_25_1Prompt =>
      'Жол жұмысы белгісіне тоқтау керек пе?';

  @override
  String get gameSignScenario1_25_1Explanation =>
      'Жоқ. Белгінің өзі тоқтауды қажет етпейді. Жол жұмыстарын ескеріп, қауіпсіз жылдамдықты таңдау керек.';

  @override
  String get gameSignScenario2_1_0Prompt =>
      'Бағдаршамсыз сізде екінші реттегі көліктің үстінен өту құқығыңыз бар ма?';

  @override
  String get gameSignScenario2_1_0Explanation =>
      'Иә. Бақыланбайтын қиылыста негізгі жол екінші жолға артықшылық береді (13.9-тармақ).';

  @override
  String get gameSignScenario2_1_1Prompt =>
      'Егер сіз үлкен жолда жүрсеңіз, қызыл жарықпен жүруге бола ма?';

  @override
  String get gameSignScenario2_1_1Explanation =>
      'Жоқ. Сигналды қиылыста сіз бағдаршам бойынша жүруіңіз керек (6.15-тармақ).';

  @override
  String get gameSignScenario2_1_2Prompt =>
      'Көлігімді елді мекеннен тыс басты жолға қоя аламын ба?';

  @override
  String get gameSignScenario2_1_2Explanation =>
      'Жоқ. Мұндай жолдарда елді мекеннен тыс жолдың бөлігінде көлікті қоюға тыйым салынады (12.5-тармақ).';

  @override
  String get gameSignScenario2_2_0Prompt =>
      'Белгі негізгі жолдың соңын белгілей ме?';

  @override
  String get gameSignScenario2_2_0Explanation =>
      'Иә. «Басты жол» белгісінің артықшылығы аяқталады.';

  @override
  String get gameSignScenario2_2_1Prompt =>
      'Бұл белгінің өзі сізді тоқтатуды талап ете ме?';

  @override
  String get gameSignScenario2_2_1Explanation =>
      'Жоқ. Бұл негізгі жол мәртебесін жояды. Жол жүру тәртібі басқа белгілермен және ережелермен белгіленеді.';

  @override
  String get gameSignScenario2_3_1_0Prompt =>
      'Бағдаршамсыз сіз өтіп бара жатқан жолдан көлік сізге жол беруі керек пе?';

  @override
  String get gameSignScenario2_3_1_0Explanation =>
      'Иә. Белгі негізгі жолдың қосалқы жолмен қиылысын көрсетеді (13.9-тармақ).';

  @override
  String get gameSignScenario2_3_1_1Prompt =>
      'Бағдаршам жоқ болса, қосалқы жолдан оң жақтағы көлікке жол беру керек пе?';

  @override
  String get gameSignScenario2_3_1_1Explanation =>
      'Жоқ. Сізде артықшылық бар: сіз негізгі жолдасыз. Мұнда «оң жақтан араласу» ережесі қолданылмайды.';

  @override
  String get gameSignScenario2_4_0Prompt =>
      'Бағдаршамсыз өтіп бара жатқан жолда көліктерге жол беру керек пе?';

  @override
  String get gameSignScenario2_4_0Explanation =>
      'Иә. Бұл белгі сізден өтіп бара жатқан жолда көліктерге жол беруді талап етеді. 8.13 белгісінде - негізгі жолда автомобильдер.';

  @override
  String get gameSignScenario2_4_1Prompt =>
      'Жол ашық. Сізге әлі де осы белгіде тоқтау керек пе?';

  @override
  String get gameSignScenario2_4_1Explanation =>
      'Жоқ. Ешкімге кедергі жасамасаңыз, міндетті аялдама болмайды.';

  @override
  String get gameSignScenario2_4_2Prompt =>
      'Екеуі де қосалқы жолақта: сіз түзусіз, қарсы қозғалыс сол жақта. Ол берілу керек пе?';

  @override
  String get gameSignScenario2_4_2Explanation =>
      'Иә. Бірдей басымдылықпен қарсы келе жатқан көлік солға бұрылып, тура келе жатқанға жол береді (13.12-тармақ).';

  @override
  String get gameSignScenario2_5_0Prompt =>
      'Жол ашық болса да, ТОҚТАУ алдында тоқтау керек пе?';

  @override
  String get gameSignScenario2_5_0Explanation =>
      'Иә. Аялдама сызығының алдына, ал егер жоқ болса, сіз өтіп бара жатқан жолдың шетіне тоқтаңыз. Тоқтау сызығы жоқ өткелде – белгінің алдында.';

  @override
  String get gameSignScenario2_5_1Prompt =>
      'Барлығы анық көрініп тұрса, ТОҚТАТУ-ды тоқтатпай жүргізуге бола ма?';

  @override
  String get gameSignScenario2_5_1Explanation =>
      'Жоқ. Белгі жол ашық болса да толық тоқтауды талап етеді.';

  @override
  String get gameSignScenario2_6_0Prompt =>
      'Кіру қарсы келе жатқан көліктерге кедергі жасайды. Мен жол беруім керек пе?';

  @override
  String get gameSignScenario2_6_0Explanation =>
      'Иә. Қарсы көлік қозғалысына кедергі келтіретін болса, тар аумаққа кіруге болмайды.';

  @override
  String get gameSignScenario2_6_1Prompt =>
      'Бұл белгі сізге кездескен адамдардан артықшылық береді ме?';

  @override
  String get gameSignScenario2_6_1Explanation =>
      'Жоқ. Қарсы келе жатқан көліктің жүру құқығы бар.';

  @override
  String get gameSignScenario2_7_0Prompt =>
      'Тар аймақта артықшылығыңыз бар ма?';

  @override
  String get gameSignScenario2_7_0Explanation =>
      'Иә. Бұл белгі сізге қарсы келе жатқан көліктерден артықшылық береді.';

  @override
  String get gameSignScenario2_7_1Prompt =>
      'Бұл белгі қарсы келе жатқан көлікке жол құқығын бере ме?';

  @override
  String get gameSignScenario2_7_1Explanation =>
      'Жоқ. Сіздің бағытта қозғалатын көлік басымдыққа ие.';

  @override
  String get gameSignScenario3_1_0Prompt =>
      'Бұл белгі тұрақты таксилерге кіруге тыйым сала ма?';

  @override
  String get gameSignScenario3_1_0Explanation =>
      'Иә. Такси мен көлікті ортақ пайдалану тыйымға сәйкес келуі керек. Ерекшелік - маршруттық тасымалдау.';

  @override
  String get gameSignScenario3_1_1Prompt =>
      'Сіз белгінің артында тұрып жатқандықтан ғана кіре аласыз ба?';

  @override
  String get gameSignScenario3_1_1Explanation =>
      'Жоқ. Тұрғындар үшін ерекшелік жоқ. Бұл белгіні «Жол қозғалысына тыйым салынады» белгісімен шатастырмаңыз.';

  @override
  String get gameSignScenario3_1_2Prompt =>
      'Маршруттық автобус өз бағытына кіре ала ма?';

  @override
  String get gameSignScenario3_1_2Explanation =>
      'Иә. Бұл белгіге тыйым салу маршруттық көліктерге қолданылмайды.';

  @override
  String get gameSignScenario3_2_0Prompt =>
      'Сіз осы белгі аймағындағы үйіңізге бара аласыз ба?';

  @override
  String get gameSignScenario3_2_0Explanation =>
      'Иә. Тұрғындарға үйге кіруге рұқсат етілген. Оған ең жақын қиылысқа кіріп, шығу керек.';

  @override
  String get gameSignScenario3_2_1Prompt =>
      'Бұл аймақ арқылы қарапайым көлікпен жүруге бола ма?';

  @override
  String get gameSignScenario3_2_1Explanation =>
      'Жоқ. Белгі қозғалысқа тыйым салады. Тұрғындар мен қызметтік көліктердің өтуі межелі жерге жету үшін ерекше жағдайлар болып табылады.';

  @override
  String get gameSignScenario3_2_2Prompt =>
      'Белгі I топтағы мүгедек және «Мүгедек» белгісі бар жүргізушінің жүруіне тыйым сала ма?';

  @override
  String get gameSignScenario3_2_2Explanation =>
      'Жоқ. Бұл белгі I–II топтағы мүгедектердің немесе оларды тасымалдайтындардың және «Мүгедек» белгісі бар мүгедек балалардың көліктеріне қолданылмайды.';

  @override
  String get gameSignScenario3_4_0Prompt =>
      'Бұл белгі жеңіл көліктерге тыйым сала ма?';

  @override
  String get gameSignScenario3_4_0Explanation =>
      'Жоқ. Ол жүк көліктерінің, тракторлардың және өздігінен жүретін көліктердің қозғалысын шектейді.';

  @override
  String get gameSignScenario3_4_1Prompt =>
      'Бұл белгінің астынан рұқсат етілген салмағы 5 тонна қарапайым жүк көлігі өте ала ма?';

  @override
  String get gameSignScenario3_4_1Explanation =>
      'Иә. Көрсетілген белгі 8 тонна шекті көрсетеді. Рұқсат етілген максималды салмағы 5 тоннадан аспайды.';

  @override
  String get gameSignScenario3_18_1_0Prompt =>
      'Бұл белгі солға бұруға тыйым сала ма?';

  @override
  String get gameSignScenario3_18_1_0Explanation =>
      'Жоқ. Ол тек жолдардың ең жақын қиылысында оңға бұрылуға тыйым салады.';

  @override
  String get gameSignScenario3_18_1_1Prompt =>
      'Ең жақын қиылыстан оңға бұрылуға бола ма?';

  @override
  String get gameSignScenario3_18_1_1Explanation =>
      'Жоқ. Жақын қиылыстан оңға бұрылуға тыйым салынады.';

  @override
  String get gameSignScenario3_18_2_0Prompt =>
      'Бұл белгі кері бұрылуға тыйым сала ма?';

  @override
  String get gameSignScenario3_18_2_0Explanation =>
      'Жоқ. Ол солға бұруға тыйым салады, бірақ кері бұрылуға тыйым салмайды.';

  @override
  String get gameSignScenario3_18_2_1Prompt =>
      'Ең жақын қиылыстан солға бұрыла аламын ба?';

  @override
  String get gameSignScenario3_18_2_1Explanation =>
      'Жоқ. Жақын қиылыста солға бұрылуға тыйым салынады.';

  @override
  String get gameSignScenario3_19_0Prompt =>
      'Бұл белгі солға бұруға тыйым сала ма?';

  @override
  String get gameSignScenario3_19_0Explanation =>
      'Жоқ. Ол тек бұрылуға тыйым салады.';

  @override
  String get gameSignScenario3_19_1Prompt =>
      'Бұл белгі белсенді жерде бұрыла аламын ба?';

  @override
  String get gameSignScenario3_19_1Explanation =>
      'Жоқ. Бұрылысқа тыйым салынады.';

  @override
  String get gameSignScenario3_20_0Prompt =>
      'Бұл белгі тиісті белгісі бар баяу жүретін көлікті басып озуға мүмкіндік бере ме?';

  @override
  String get gameSignScenario3_20_0Explanation =>
      'Иә. Төмен жылдамдықтағы көліктер 3.20 белгісінің тыйым салуынан ерекшелік болып табылады. Басқа басып озуға тыйым салулар мен белгілерді де ескеру қажет.';

  @override
  String get gameSignScenario3_20_1Prompt =>
      'Тек 25 км/сағ жылдамдықпен келе жатқан қарапайым көлікті басып озуға бола ма?';

  @override
  String get gameSignScenario3_20_1Explanation =>
      'Жоқ. Төмен жылдамдық жеңіл көлікті баяу жүретін көлікке айналдырмайды.';

  @override
  String get gameSignScenario3_20_2Prompt =>
      'Бұл белгі арбасыз мотоциклді басып озуға мүмкіндік береді ме?';

  @override
  String get gameSignScenario3_20_2Explanation =>
      'Иә. Бүйірлік тіркемесі жоқ екі доңғалақты мотоциклдер бұл белгіге тыйым салудан ерекшелік болып табылады.';

  @override
  String get gameSignScenario3_24_0Prompt =>
      'Белгідегі нөмір максималды жылдамдық шегі ме?';

  @override
  String get gameSignScenario3_24_0Explanation =>
      'Иә. Сіз бұдан жылдам жүре алмайсыз. Көріну нашар болса, қауіпсіз жылдамдық төмен болуы мүмкін.';

  @override
  String get gameSignScenario3_24_1Prompt =>
      'Бұл белгі сізге көрсетілген саннан баяу жүруді талап ете ме?';

  @override
  String get gameSignScenario3_24_1Explanation =>
      'Жоқ. Бұл ең төменгі жылдамдық шегі емес, максималды жылдамдық шегі.';

  @override
  String get gameSignScenario3_27_0Prompt =>
      'Жолаушыны шығару үшін қарапайым көлікті бір минутқа тоқтатуға бола ма?';

  @override
  String get gameSignScenario3_27_0Explanation =>
      'Жоқ. Белгі тоқтауға және тұраққа қоюға тыйым салады. Жолаушыны түсіру де аялдама.';

  @override
  String get gameSignScenario3_27_1Prompt =>
      '«Мүгедек» белгісінің өзі осы жерде тоқтауға мүмкіндік бере ме?';

  @override
  String get gameSignScenario3_27_1Explanation =>
      'Жоқ. Жеңілдіктің өзі «Тоқтауға болмайды» белгісін жоймайды. Ерекшелік 8.18 пластинасында көрсетілуі мүмкін.';

  @override
  String get gameSignScenario3_27_2Prompt =>
      'Осы белгінің астына кәдімгі көлікті қоя аламын ба?';

  @override
  String get gameSignScenario3_27_2Explanation =>
      'Жоқ. Бұл белгі тоқтауға да, тұраққа да тыйым салады.';

  @override
  String get gameSignScenario3_28_0Prompt =>
      'Жолаушыны түсіру үшін тоқтай аламын ба?';

  @override
  String get gameSignScenario3_28_0Explanation =>
      'Иә. Белгі тұраққа тыйым салады, бірақ тоқтатуға мүмкіндік береді. Отырғызу, түсіру немесе тиеу үшін қажетті уақыт 5 минуттан асуы мүмкін.';

  @override
  String get gameSignScenario3_28_1Prompt =>
      'Кәдімгі көлікті 20 минутқа қондырмай немесе тиеусіз қалдыра аламын ба?';

  @override
  String get gameSignScenario3_28_1Explanation =>
      'Жоқ. Бұл тұрақ: отырғызуға, түсіруге немесе тиеуге байланысты емес 5 минуттан астам аялдама (1.2-тармақ).';

  @override
  String get gameSignScenario3_28_2Prompt =>
      'Бұл тыйым жәрдемақы алуға құқығы бар «Мүгедек» белгісі бар көлікке қатысты ма?';

  @override
  String get gameSignScenario3_28_2Explanation =>
      'Жоқ. Егер сізде тегін автотұраққа және «Мүгедек» белгісіне құқығыңыз болса, мұндай мүгедектер мен мүгедек балаларды тасымалдауды қоса алғанда, ерекшелік қарастырылған.';

  @override
  String get gameSignScenario3_29_0Prompt =>
      'Тақ және жұп күндердегі тыйым салу белгілері екі жағында орналасқан. Мен 21:00-ден 24:00-ге дейін тұрақ қоя аламын ба?';

  @override
  String get gameSignScenario3_29_0Explanation =>
      'Иә. Белгілердің бұл тіркесімімен сағат 21:00-ден 24:00-ге дейін ауыстыру уақыты, бұл кезде екі жағынан да тұраққа рұқсат етіледі.';

  @override
  String get gameSignScenario3_29_1Prompt =>
      'Бұл белгі жолаушыны алып кету үшін 3 минут тоқтауға тыйым сала ма?';

  @override
  String get gameSignScenario3_29_1Explanation =>
      'Жоқ. Ол тек тақ нөмірлерге тұрақ қоюға тыйым салады. Тоқтауға рұқсат етіледі.';

  @override
  String get gameSignScenario3_31_0Prompt =>
      'Бұл белгі басып озу мен жылдамдықты шектейді ме?';

  @override
  String get gameSignScenario3_31_0Explanation =>
      'Иә. Ол 3.16, 3.20, 3.22, 3.24 және 3.26–3.30 белгілерінің әрекетін аяқтайды.';

  @override
  String get gameSignScenario3_31_1Prompt =>
      'Бұл белгі бағдаршамдар мен белгілерді жоққа шығарады ма?';

  @override
  String get gameSignScenario3_31_1Explanation =>
      'Жоқ. Бағдаршамдар мен белгілер жұмысын жалғастыруда.';

  @override
  String get gameSignScenario4_1_1_0Prompt =>
      'Белгі сайттың басында орналасқан. Мен аулаға оңға бұрылсам бола ма?';

  @override
  String get gameSignScenario4_1_1_0Explanation =>
      'Иә. Учаскенің басында белгі ең жақын қиылысқа дейін жарамды, бірақ іргелес аумаққа оңға бұрылуға мүмкіндік береді.';

  @override
  String get gameSignScenario4_1_1_1Prompt =>
      'Белгі қиылыстың алдында орналасқан. Солға бұрыла аламын ба?';

  @override
  String get gameSignScenario4_1_1_1Explanation =>
      'Жоқ. Жолдардың ең жақын қиылысында тек түзу қозғалысқа рұқсат етіледі.';

  @override
  String get gameSignScenario4_1_2_0Prompt =>
      'Келесі қиылыста оңға бұрылу керек пе?';

  @override
  String get gameSignScenario4_1_2_0Explanation =>
      'Иә. Кәдімгі көлік үшін белгі тек оңға бұрылуға мүмкіндік береді.';

  @override
  String get gameSignScenario4_1_2_1Prompt =>
      'Ең жақын қиылыста тура жүре аламын ба?';

  @override
  String get gameSignScenario4_1_2_1Explanation =>
      'Жоқ. Белгі тек оңға қарай мүмкіндік береді.';

  @override
  String get gameSignScenario4_1_3_0Prompt =>
      'Бұл белгі кері бұрылуға мүмкіндік береді ме?';

  @override
  String get gameSignScenario4_1_3_0Explanation =>
      'Иә. Солға бұрылуға рұқсат беретін белгі кері бұрылуға да мүмкіндік береді.';

  @override
  String get gameSignScenario4_1_3_1Prompt =>
      'Ең жақын қиылыста тура жүре аламын ба?';

  @override
  String get gameSignScenario4_1_3_1Explanation =>
      'Жоқ. Белгі солға және кері бұрылуға мүмкіндік береді.';

  @override
  String get gameSignScenario4_1_4_0Prompt =>
      'Мен тура немесе оңға жүре аламын ба?';

  @override
  String get gameSignScenario4_1_4_0Explanation =>
      'Иә. Белгі осы екі бағытқа да мүмкіндік береді.';

  @override
  String get gameSignScenario4_1_4_1Prompt =>
      'Ең жақын қиылыста бұрыла аламын ба?';

  @override
  String get gameSignScenario4_1_4_1Explanation =>
      'Жоқ. Тек алға және оңға ғана рұқсат етіледі.';

  @override
  String get gameSignScenario4_1_5_0Prompt =>
      'Мен сол жақ жолақтан бұрыла аламын ба?';

  @override
  String get gameSignScenario4_1_5_0Explanation =>
      'Иә. Рұқсат етілген солға бұрылу сонымен қатар кері бұрылуға мүмкіндік береді.';

  @override
  String get gameSignScenario4_1_5_1Prompt =>
      'Ең жақын қиылыстан оңға бұрылуға бола ма?';

  @override
  String get gameSignScenario4_1_5_1Explanation =>
      'Жоқ. Белгі тура алға, солға және кері бұрылуға мүмкіндік береді.';

  @override
  String get gameSignScenario4_2_1_0Prompt =>
      'Оң жақтағы кедергіні айналып өту керек пе?';

  @override
  String get gameSignScenario4_2_1_0Explanation =>
      'Иә. Айналып өту тек көрсеткімен көрсетілген бағытта ғана рұқсат етіледі.';

  @override
  String get gameSignScenario4_2_1_1Prompt =>
      'Қарсы келе жатқан адамдар болмаса, сол жақтағы кедергіні айналып өтуге бола ма?';

  @override
  String get gameSignScenario4_2_1_1Explanation =>
      'Жоқ. Қарсы қозғалыстың болмауы белгіленген айналма бағытты жоймайды.';

  @override
  String get gameSignScenario4_3_0Prompt =>
      'Жебелердің бағытымен жүру керек пе?';

  @override
  String get gameSignScenario4_3_0Explanation =>
      'Иә. Белгі айналмалы қозғалыстың бағытын көрсетеді.';

  @override
  String get gameSignScenario4_3_1Prompt =>
      'Жебелерге қарсы шеңбер бойымен жүре аласыз ба?';

  @override
  String get gameSignScenario4_3_1Explanation =>
      'Жоқ. Олар тек көрсеткілермен көрсетілген бағытта шеңбер бойымен қозғалады.';

  @override
  String get gameSignScenario4_6_0Prompt =>
      'Бұл белгі ең төменгі жылдамдықты белгілейді ме?';

  @override
  String get gameSignScenario4_6_0Explanation =>
      'Иә. Максималды шектеу мен қауіпсіздікті сақтай отырып, белгіленген немесе одан жоғары жылдамдықпен жүргізуге болады.';

  @override
  String get gameSignScenario4_6_1Prompt =>
      'Бұл белгі максималды жылдамдықты белгілейді ме?';

  @override
  String get gameSignScenario4_6_1Explanation =>
      'Жоқ. Бұл ең төменгі жылдамдық. Максимум 3.24 белгісімен шектеледі.';

  @override
  String get gameSignScenario5_1_0Prompt =>
      'Тіркемесіз жеңіл автокөлік: автомобиль жолындағы жалпы шек 110 км/сағ?';

  @override
  String get gameSignScenario5_1_0Explanation =>
      'Иә. Тіркемесі жоқ жеңіл автокөліктің жалпы шегі 110 км/сағ. Белгілер басқа шекті белгілеуі мүмкін (10.3-тармақ).';

  @override
  String get gameSignScenario5_1_1Prompt =>
      'Сіз автожолда кері бұрыла аласыз ба?';

  @override
  String get gameSignScenario5_1_1Explanation =>
      'Жоқ. Автомагистральда кері қозғалысқа тыйым салынады (16.1-тармақ).';

  @override
  String get gameSignScenario5_1_2Prompt =>
      'Автомобиль жолда мопедпен жүруге болады ма?';

  @override
  String get gameSignScenario5_1_2Explanation =>
      'Жоқ. Автомобиль жолдарында мопедтердің жүруіне тыйым салынады (16.1-тармақ).';

  @override
  String get gameSignScenario5_3_0Prompt =>
      'Бұл жолда кері жүруге тыйым салынады ма?';

  @override
  String get gameSignScenario5_3_0Explanation =>
      'Иә. Автомобильдерге арналған жолда 16-бөлімнің тыйымдары тас жолдағы сияқты қолданылады (16.3-тармақ).';

  @override
  String get gameSignScenario5_3_1Prompt =>
      'Демалу үшін жол жиегіне тоқтай аламын ба?';

  @override
  String get gameSignScenario5_3_1Explanation =>
      'Жоқ. Арнайы жерлерде әдейі тоқтауға рұқсат етіледі. Мәжбүрлеп тоқтату - бұл бөлек жағдай.';

  @override
  String get gameSignScenario5_5_0Prompt =>
      'Қауіпсіз болса және орын рұқсат етсе, бір бағыттағы жолда сақтық көшірме жасауға болады ма?';

  @override
  String get gameSignScenario5_5_0Explanation =>
      'Иә. Белгінің өзі бұған тыйым салмайды. Қиылыстарда, өткелдерде және 8.11–8.12-тармақтарда көрсетілген басқа жерлерде артқа жүруге болмайды.';

  @override
  String get gameSignScenario5_5_1Prompt =>
      'Мен бұрылып, бір жақты қозғалысқа қарсы жүре аламын ба?';

  @override
  String get gameSignScenario5_5_1Explanation =>
      'Жоқ. Бұл белгіленген бағытқа қарсы қозғалыс.';

  @override
  String get gameSignScenario5_5_2Prompt =>
      'Елді мекенде бір жақты жолға жолаушылар көлігін сол жаққа қоюға бола ма?';

  @override
  String get gameSignScenario5_5_2Explanation =>
      'Иә. Жеңіл автомобильдер үшін бұл басқа тыйымдар болмаған жағдайда рұқсат етіледі (12.1-тармақ).';

  @override
  String get gameSignScenario5_14_1_0Prompt =>
      'Бұл жолақты таксилер мен мектеп автобустары пайдалана ала ма?';

  @override
  String get gameSignScenario5_14_1_0Explanation =>
      'Иә. 18.2-тармақ жолаушылар таксилері мен мектеп автобустарына рұқсат береді. Велосипедшілер бұл жолақты тек оң жақта пайдалана алады.';

  @override
  String get gameSignScenario5_14_1_1Prompt =>
      'Қарапайым жеңіл автомобиль жол бойындағы автобус жолағымен жүруі мүмкін бе?';

  @override
  String get gameSignScenario5_14_1_1Explanation =>
      'Жоқ. Қарапайым көліктерге жолақпен жүруге тыйым салынады. Бұрылыс үшін жолақтарды өзгерту, мезгіл-мезгіл белгілермен кіру және түсіру белгілі бір ерекшеліктер болып табылады.';

  @override
  String get gameSignScenario5_15_1_0Prompt =>
      'Сол жақ жолақтағы сол жақ көрсеткі де кері бұрылуға мүмкіндік береді ме?';

  @override
  String get gameSignScenario5_15_1_0Explanation =>
      'Иә. Егер белгі одан солға бұрылуға мүмкіндік берсе, ең сол жақ жолақтан бұрылысқа рұқсат етіледі.';

  @override
  String get gameSignScenario5_19_1_0Prompt =>
      'Бағдаршамсыз жолдан өтіп бара жатқан жаяу жүргіншіге жол беру керек пе?';

  @override
  String get gameSignScenario5_19_1_0Explanation =>
      'Иә. Реттелмейтін өткелде жаяу жүргіншілерге жолды кесіп өтуге немесе жол бөлігіне кіруге жол беру керек (14.1-тармақ).';

  @override
  String get gameSignScenario5_19_1_1Prompt =>
      'Жаяу жүргіншілер өткелінде кері жүре аласыз ба?';

  @override
  String get gameSignScenario5_19_1_1Explanation =>
      'Жоқ. Өткелде кері жүруге де, бұрылуға да тыйым салынады (8.11–8.12 тармақтары).';

  @override
  String get gameSignScenario5_19_1_2Prompt =>
      'Өткелге 3 м қалғанда тоқтай аламын ба?';

  @override
  String get gameSignScenario5_19_1_2Explanation =>
      'Жоқ. Өткелде және оның алдында 5 метрден жақын жерде тоқтауға тыйым салынады (12.4-тармақ).';

  @override
  String get gameSignScenario5_20_0Prompt =>
      'Белгі жылдамдықты төмендетудің басталуын көрсетеді ме?';

  @override
  String get gameSignScenario5_20_0Explanation =>
      'Иә. Ол жасанды кедір-бұдырдың ең жақын шекарасында орнатылады.';

  @override
  String get gameSignScenario5_20_1Prompt =>
      'Жылдамдықты бұзбай тұрып тоқтату керек пе?';

  @override
  String get gameSignScenario5_20_1Explanation =>
      'Жоқ. Белгі тоқтауды қажет етпейді. Өту үшін қауіпсіз жылдамдықты таңдаңыз.';

  @override
  String get gameSignScenario5_21_0Prompt =>
      'Тұрғын аудандарда жаяу жүргіншілерге басымдық беріледі ме?';

  @override
  String get gameSignScenario5_21_0Explanation =>
      'Иә. Жаяу жүргіншілер тротуармен және жолдың бойымен жүре алады, бірақ көліктерге негізсіз кедергі жасамауы керек (17.1-тармақ).';

  @override
  String get gameSignScenario5_21_1Prompt =>
      'Тұрғын үй аумағы арқылы 30 км/сағ жылдамдықпен жүруге бола ма?';

  @override
  String get gameSignScenario5_21_1Explanation =>
      'Жоқ. Тұрғын аудандарда және аулада шек 20 км/сағ (10.2 тармақ).';

  @override
  String get gameSignScenario5_21_2Prompt =>
      'Маршрутты қысқарту үшін тұрғын үй аумағы арқылы жүруге бола ма?';

  @override
  String get gameSignScenario5_21_2Explanation =>
      'Жоқ. Тұрғын үй аумағында көлік қозғалысына тыйым салынады (17.2-тармақ).';

  @override
  String get gameSignScenario5_23_1_0Prompt =>
      'Осы белгіден кейін жалпы жылдамдық шегі 60 км/сағ?';

  @override
  String get gameSignScenario5_23_1_0Explanation =>
      'Иә. Елді мекеннің ережелері осыдан басталады. Егер басқасы белгіленбесе, жалпы шек 60 км/сағ құрайды (10.2-тармақ).';

  @override
  String get gameSignScenario5_23_1_1Prompt =>
      'Осы белгіден кейін басқа белгілерсіз бірден 90 км/сағ жылдамдықпен жүруге бола ма?';

  @override
  String get gameSignScenario5_23_1_1Explanation =>
      'Жоқ. Жалпы елді мекен шегі 60 км/сағ.';

  @override
  String get gameSignScenario5_25_0Prompt =>
      'Бұл белгінің өзі 60 км/сағ шегін енгізе ме?';

  @override
  String get gameSignScenario5_25_0Explanation =>
      'Жоқ. Белгіленген жолда елді мекеннің ережелері қолданылмайды. Жылдамдық жолға, көлікке және басқа белгілерге байланысты.';

  @override
  String get gameSignScenario5_25_1Prompt =>
      'Көгілдір елді мекен белгісі бұрын белгіленген жылдамдық шегінен бас тарта ма?';

  @override
  String get gameSignScenario5_25_1Explanation =>
      'Жоқ. Белгінің өзі басқа белгімен белгіленген жылдамдық шегінен бас тартпайды.';

  @override
  String get gameSignScenario6_2_0Prompt =>
      'Бұл белгідегі жылдамдық ұсыныс па?';

  @override
  String get gameSignScenario6_2_0Explanation =>
      'Иә. Белгі жылдамдықты ұсынады, бірақ міндетті шектеулер мен қауіпсіздік талаптарын жоймайды.';

  @override
  String get gameSignScenario6_2_1Prompt =>
      'Сізге дәл көрсетілген жылдамдықпен жүру керек пе?';

  @override
  String get gameSignScenario6_2_1Explanation =>
      'Жоқ. Бұл қажетті жылдамдық емес, ұсынылған жылдамдық.';

  @override
  String get gameSignScenario6_3_1_0Prompt =>
      'Бұл белгі бұрылатын орынды көрсете ме?';

  @override
  String get gameSignScenario6_3_1_0Explanation =>
      'Иә. Мұнда бұрылыс үшін орын бар.';

  @override
  String get gameSignScenario6_3_1_1Prompt =>
      'Осы жерден аулаға солға бұрылуға бола ма?';

  @override
  String get gameSignScenario6_3_1_1Explanation =>
      'Жоқ. Белгі кері бұрылу орнын белгілейді және солға бұрылуға тыйым салады.';

  @override
  String get gameSignScenario6_4_0Prompt =>
      'Бұл белгі автотұрақты көрсетеді ме?';

  @override
  String get gameSignScenario6_4_0Explanation =>
      'Иә. Белгі автотұрақты көрсетеді. Белгілер кімге, қашан және қалай тұраққа рұқсат етілгенін түсіндіре алады.';

  @override
  String get gameSignScenario6_4_1Prompt =>
      'Бұл белгінің алдында тоқтау керек пе?';

  @override
  String get gameSignScenario6_4_1Explanation =>
      'Жоқ. Ол тоқтауды талап етпей, қайда қою керектігін көрсетеді.';

  @override
  String get gameSignScenario6_16_0Prompt =>
      'Белгі бағдаршамда тоқтайтын жерді көрсетеді ме?';

  @override
  String get gameSignScenario6_16_0Explanation =>
      'Иә. Бағдаршамнан немесе жол диспетчерінен тыйым салатын белгі болған кезде белгінің алдына тоқтаңыз (6.13-бөлім).';

  @override
  String get gameSignScenario6_16_1Prompt =>
      'Бағдаршам жасыл, жол диспетчері жоқ. Белгі тоқтауыңызды талап ете ме?';

  @override
  String get gameSignScenario6_16_1Explanation =>
      'Жоқ. «Тоқтату сызығы» белгісінің өзі рұқсат беру сигналы берілген кезде тоқтауды қажет етпейді.';

  @override
  String get gameSignScenario7_1_0Prompt =>
      'Белгі жедел жәрдем станциясын көрсетеді ме?';

  @override
  String get gameSignScenario7_1_0Explanation =>
      'Иә. Ол сізге фельдшерлік пункттің қайда екенін айтады.';

  @override
  String get gameSignScenario7_1_1Prompt =>
      'Бұл белгінің өзі жылдамдықты 20 км/сағ деп шектей ме?';

  @override
  String get gameSignScenario7_1_1Explanation =>
      'Жоқ. Қызмет көрсету белгілері жылдамдықты шектемейді.';

  @override
  String get gameSignScenario7_3_0Prompt =>
      'Белгі жанармай құю станциясын көрсете ме?';

  @override
  String get gameSignScenario7_3_0Explanation =>
      'Иә. Белгі жанармай құю станциясын көрсетеді.';

  @override
  String get gameSignScenario7_3_1Prompt =>
      'Бұл белгі жанармай құю бекетінен жолда қалдырғанда басымдық бере ме?';

  @override
  String get gameSignScenario7_3_1Explanation =>
      'Жоқ. Көрші аумақтан шыққан кезде жол қозғалысына қатысушыларға жол беру керек (8.3-тармақ).';

  @override
  String get gameSignScenario8_1_1_0Prompt =>
      'Белгі шектеу басталатын орынға дейінгі қашықтықты көрсете ме?';

  @override
  String get gameSignScenario8_1_1_0Explanation =>
      'Иә. Белгі бір ғана қашықтықты көрсетеді: белгіден қауіпті аймаққа, объектіге немесе шектеу басталатын орынға дейін.';

  @override
  String get gameSignScenario8_1_1_1Prompt =>
      'Белгі белгінің қамту аймағының ұзындығын көрсетеді ме?';

  @override
  String get gameSignScenario8_1_1_1Explanation =>
      'Жоқ. Қамту аймағының ұзындығы 8.2.1 пластинасында көрсетілген.';

  @override
  String get gameSignScenario8_2_1_0Prompt =>
      'Белгі қауіпті аймақтың немесе қамту аймағының ұзындығын көрсете ме?';

  @override
  String get gameSignScenario8_2_1_0Explanation =>
      'Иә. Бұл белгі аймағының немесе ауданының ұзындығы.';

  @override
  String get gameSignScenario8_2_1_1Prompt =>
      'Белгі белгіленген қашықтықтан кейін ғана жұмыс істей бастайды ма?';

  @override
  String get gameSignScenario8_2_1_1Explanation =>
      'Жоқ. Пластина оның басына дейінгі қашықтықты емес, аймақтың ұзындығын көрсетеді.';

  @override
  String get gameSignScenario8_2_3_0Prompt =>
      'Төмен көрсеткі тоқтау немесе тұраққа тыйым салудың аяқталуын білдіре ме?';

  @override
  String get gameSignScenario8_2_3_0Explanation =>
      'Иә. Ол 3.27–3.30 белгілерінің қамту аймағының аяқталуын көрсетеді.';

  @override
  String get gameSignScenario8_2_3_1Prompt =>
      'Бұрынғы тұраққа тыйым салу осы белгіден кейін де жалғаса ма?';

  @override
  String get gameSignScenario8_2_3_1Explanation =>
      'Жоқ. Шектелген аймақ аяқталады. Басқа тоқтату және тұрақ ережелері өзгеріссіз қалады.';

  @override
  String get gameSignScenario8_4_1_0Prompt =>
      'Бұл нөмір рұқсат етілген салмағы 3,5 тоннадан асатын жүк көліктеріне қатысты ма?';

  @override
  String get gameSignScenario8_4_1_0Explanation =>
      'Иә. Оның ішінде тіркемесі бар осындай жүк көліктері. Нақты салмақ емес, рұқсат етілген максималды салмақ есепке алынады.';

  @override
  String get gameSignScenario8_4_1_1Prompt =>
      'Бұл белгі жеңіл көліктерге қатысты ма?';

  @override
  String get gameSignScenario8_4_1_1Explanation =>
      'Жоқ. Бұл белгі рұқсат етілген максималды салмағы 3,5 тоннадан асатын жүк көліктеріне қолданылады.';

  @override
  String get gameSignScenario8_4_3_0Prompt =>
      'Нөмір салмағы 3,5 тоннаға дейінгі жеңіл және жүк көліктеріне қатысты ма?';

  @override
  String get gameSignScenario8_4_3_0Explanation =>
      'Иә. Жүк көлігінің рұқсат етілген максималды салмағы ескеріледі.';

  @override
  String get gameSignScenario8_4_3_1Prompt => 'Бұл белгі автобусқа қатысты ма?';

  @override
  String get gameSignScenario8_4_3_1Explanation =>
      'Жоқ. Бұл нөмір 3,5 тоннаға дейінгі жеңіл және жүк көліктеріне қолданылады.';

  @override
  String get gameSignScenario8_17_0Prompt =>
      'Тұрақ белгісі «Мүгедек» белгісі бар көліктерге арналған орындарды белгілей ме?';

  @override
  String get gameSignScenario8_17_0Explanation =>
      'Иә. Орындар мүгедек балаларды тасымалдайтындарды қоса алғанда, «Мүгедек» сәйкестендіру белгісі бар осындай тұраққа құқығы бар автокөліктерге арналған.';

  @override
  String get gameSignScenario8_17_1Prompt =>
      'Мен кәдімгі көлікті «Мүгедек» белгісінсіз 10 минутқа қалдыра аламын ба?';

  @override
  String get gameSignScenario8_17_1Explanation =>
      'Жоқ. Бұл тұрақтар жәрдемақы алуға құқығы бар «Мүгедек» белгісі бар көліктерге арналған.';

  @override
  String get gameSignScenario5_15_1_1Prompt =>
      'Ортаңғы жолақтан жебе тек алға қарай. Солға бұрыла аламын ба?';

  @override
  String get gameSignScenario5_15_1_1Explanation =>
      'Жоқ. Бұл жолақтан тек алға жүруге рұқсат етіледі. Бұрылу үшін алдын ала қолайлы жолақты алу керек.';

  @override
  String get gamesBeta => 'Бета';

  @override
  String get gameCityTitle => 'Тірі қала';

  @override
  String gamesRunsAvailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count жарыс қолжетімді',
      one: '$count жарыс қолжетімді',
    );
    return '$_temp0';
  }

  @override
  String get avatarChoiceTitle => 'Аватар';

  @override
  String get avatarOwnPhoto => 'Менің фотом';

  @override
  String get avatarCone => 'қозғалыс конусы';

  @override
  String get gasStationName => 'GasLukPuk';

  @override
  String get gameRatingAllGames =>
      'Барлық ойындардың ұпайлары · шағын ойындар: 5 дұрыс жауап пен 75% дәлдік';

  @override
  String get paymentRegionUnavailable => 'Сіздің аймағыңызда төлем мүмкін емес';

  @override
  String gameCurrentCombo(int count) {
    return 'Комбо $count';
  }

  @override
  String gameRatingResultsIn(int days, int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days күн',
      one: '$days күн',
    );
    String _temp1 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours сағат',
      one: '$hours сағат',
    );
    return 'Рейтинг қорытындысы: $_temp0 $_temp1';
  }

  @override
  String get languageSetting => 'Тіл';

  @override
  String get languageRu => 'Русский';

  @override
  String get languageEn => 'English';

  @override
  String get languageKk => 'Қазақша';

  @override
  String get languageSystem => 'Әдепкі (жүйелік)';

  @override
  String get interfaceSection => 'Интерфейс';

  @override
  String get gameScoreRulesTitle => 'Ұпай қалай есептеледі';

  @override
  String get gameScoreRulesBody =>
      'Әр дұрыс жауап ұпай береді. Қатарынан дұрыс жауаптар шағын бонус қосады; кеңес қолданғанда сыйақының жартысы сақталады. Қате серияны тоқтатады, бірақ жиналған ұпай сақталады.';

  @override
  String gameScoreRewardLine(String game, int min, int max) {
    return '$game: әр дұрыс жауапқа $min–$max ұпай';
  }

  @override
  String gameScoreDailyBudget(int earned, int limit) {
    return 'Бүгінгі рейтинг ұпайы: $earned / $limit';
  }

  @override
  String gameScoreDailyLimitExplanation(int limit) {
    return 'Күніне жалпы рейтингке $limit ұпайға дейін жинауға болады. Одан кейін жеке рекорд пен жаттығу үшін ойнай беріңіз. Шектеу Мәскеу уақытымен түн ортасында жаңарады.';
  }
}
