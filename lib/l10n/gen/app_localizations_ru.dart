// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get exam => 'Экзамен';

  @override
  String get topics => 'Темы';

  @override
  String get tickets => 'Билеты';

  @override
  String get passedQuestions => 'пройдено вопросов';

  @override
  String get passedTickets => 'билетов пройдено';

  @override
  String get examReadiness => 'Готовность к экзамену';

  @override
  String get training => 'Обучение';

  @override
  String get pdd => 'ПДД';

  @override
  String get signs => 'Знаки';

  @override
  String get video => 'Лента';

  @override
  String get rules => 'Правила';

  @override
  String get signsAndMarkup => 'Знаки и разметка';

  @override
  String get settings => 'Настройки';

  @override
  String get showHint => 'Показать подсказку';

  @override
  String get comment => 'Комментарий';

  @override
  String get pddPoints => 'Пункты ПДД';

  @override
  String get myAnswers => 'Мои ответы';

  @override
  String get favorites => 'Избранное';

  @override
  String get questionAddedToFavorites => 'Вопрос добавлен в Избранное';

  @override
  String get correctAnswer => 'Правильный ответ';

  @override
  String get yourAnswer => 'Ваш ответ';

  @override
  String get ticket => 'билет';

  @override
  String get question => 'вопрос';

  @override
  String get goalText =>
      'По мере обучения ваш прогресс будет заполняться. Ваша цель – все билеты должны быть заполнены!';

  @override
  String get goalTextTopics =>
      'По мере обучения ваш прогресс будет заполняться. Ваша цель – все темы должны быть заполнены!';

  @override
  String get confirmAnswer => 'Ответить';

  @override
  String get nextQuestion => 'Следующий вопрос';

  @override
  String get resetStats => 'Сбросить статистику';

  @override
  String get resetStatsConfirm =>
      'Вы уверены, что хотите сбросить всю статистику?';

  @override
  String get yes => 'Да';

  @override
  String get no => 'Нет';

  @override
  String get cancel => 'Отмена';

  @override
  String get back => 'Назад';

  @override
  String get category => 'Категория';

  @override
  String get categoryAB => 'AB';

  @override
  String get categoryCD => 'CD';

  @override
  String get sound => 'Звук';

  @override
  String get examPassed => 'Экзамен сдан!';

  @override
  String get examFailed => 'Экзамен не сдан';

  @override
  String get continueSession => 'Продолжить';

  @override
  String continueSessionSubtitle(String title, int index, int total) {
    return '$title · вопрос $index из $total';
  }

  @override
  String get continueSessionDismiss => 'Убрать';

  @override
  String get reportQuestionTooltip => 'Сообщить об ошибке';

  @override
  String get reportQuestionBody =>
      'Что не так с этим вопросом? Опечатка, неверный ответ, не та картинка — напишите своими словами.';

  @override
  String get reportQuestionHint => 'Например: в ответе Б опечатка';

  @override
  String get reportSend => 'Отправить';

  @override
  String get reportSent => 'Спасибо! Сообщение отправлено';

  @override
  String get reportFailed =>
      'Не удалось отправить. Проверьте интернет и попробуйте ещё раз';

  @override
  String get correctAnswers => 'Правильных ответов';

  @override
  String get wrongAnswers => 'Неправильных ответов';

  @override
  String shareCardCorrectWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'правильных',
      many: 'правильных',
      few: 'правильных',
      one: 'правильный',
    );
    return '$_temp0';
  }

  @override
  String shareCardWrongWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ошибок',
      many: 'ошибок',
      few: 'ошибки',
      one: 'ошибка',
    );
    return '$_temp0';
  }

  @override
  String get timeLeft => 'Осталось времени';

  @override
  String get minutes => 'мин';

  @override
  String get search => 'Поиск';

  @override
  String get noImage => 'Без картинки';

  @override
  String get mistakes => 'Ошибки';

  @override
  String progressRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'До экзамена осталось $count вопросов',
      many: 'До экзамена осталось $count вопросов',
      few: 'До экзамена осталось $count вопроса',
      one: 'До экзамена остался $count вопрос',
    );
    return '$_temp0';
  }

  @override
  String get progressDone => 'пройдено';

  @override
  String get progressCorrect => 'верно';

  @override
  String get progressWrong => 'ошибок';

  @override
  String get progressTickets => 'билетов';

  @override
  String progressStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дней',
      many: '$count дней',
      few: '$count дня',
      one: '$count день',
    );
    return '$_temp0';
  }

  @override
  String progressRecord(int count) {
    return 'Рекорд $count';
  }

  @override
  String get progressAllDone => 'Все вопросы пройдены верно';

  @override
  String get homePassedQuestions => 'Пройдено вопросов';

  @override
  String get homeCorrectSolved => 'Верно решено';

  @override
  String get homePassedTickets => 'Сдано билетов';

  @override
  String examQuestionsBadge(int count) {
    return '$count вопросов';
  }

  @override
  String examMinutesBadge(int count) {
    return '$count минут';
  }

  @override
  String examReadinessPercent(int percent) {
    return '$percent% Готовность к экзамену';
  }

  @override
  String get streakStart => 'Начните серию';

  @override
  String get streakStartHint => 'Ответьте на вопрос сегодня — зажжётся огонёк';

  @override
  String streakDaysWord(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'дней подряд',
      many: 'дней подряд',
      few: 'дня подряд',
      one: 'день подряд',
    );
    return '$_temp0';
  }

  @override
  String get continueButton => 'Продолжить';

  @override
  String get streakBarrierLabel => 'Серия';

  @override
  String get personalRecord => 'Личный рекорд';

  @override
  String get streakMotivationRecord => 'Новый личный рекорд! Так держать.';

  @override
  String get streakMotivationFirst =>
      'Огонёк зажжён. Возвращайтесь завтра, чтобы серия росла.';

  @override
  String get streakMotivationWeek =>
      'Отличный темп. Ещё чуть-чуть и наберётся целая неделя.';

  @override
  String get streakMotivationHabit =>
      'Целая неделя за плечами. Привычка формируется именно так.';

  @override
  String get streakMotivationMonth =>
      'Месяц без перерыва — это уровень настоящего студента автошколы.';

  @override
  String get weekdayMon => 'Пн';

  @override
  String get weekdayTue => 'Вт';

  @override
  String get weekdayWed => 'Ср';

  @override
  String get weekdayThu => 'Чт';

  @override
  String get weekdayFri => 'Пт';

  @override
  String get weekdaySat => 'Сб';

  @override
  String get weekdaySun => 'Вс';

  @override
  String get linkOpenFailed => 'Не удалось открыть ссылку';

  @override
  String get telegramOpenFailed => 'Не удалось открыть Telegram';

  @override
  String get supportDeveloper => 'Поддержать разработчика';

  @override
  String get techSupport => 'Тех. поддержка';

  @override
  String get termsOfUse => 'Условия использования';

  @override
  String get privacyPolicy => 'Политика конфиденциальности';

  @override
  String get aboutSection => 'О приложении';

  @override
  String get dataSourceTitle => 'Источники данных';

  @override
  String get preparation => 'Подготовка';

  @override
  String get feedbackSection => 'Отклики и звуки';

  @override
  String get confirmAnswerSetting => 'Подтверждать ответ';

  @override
  String get confirmAnswerHint =>
      'Ответ сначала выбирается, а затем подтверждается кнопкой.';

  @override
  String get hapticFeedback => 'Тактильный отклик';

  @override
  String get soundEffects => 'Звуки';

  @override
  String get voiceOverQuestions => 'Озвучка вопросов';

  @override
  String get ticketCategorySetting => 'Категория билетов';

  @override
  String get ticketCategoryHint =>
      'A/B – легковые и мото, C/D – грузовые и автобусы';

  @override
  String get dataSection => 'Данные';

  @override
  String get resetStatsDetail =>
      'Будут очищены прогресс по вопросам, результаты экзаменов и избранные вопросы.';

  @override
  String get reset => 'Сбросить';

  @override
  String get statsReset => 'Статистика сброшена';

  @override
  String get searchByQuestionOrTopic => 'Поиск по вопросу или теме';

  @override
  String get emptyHere => 'Пока здесь пусто';

  @override
  String get favoritesEmptyHint =>
      'Отмечай сложные вопросы звёздочкой, и они будут собираться в одном месте для быстрого повторения.';

  @override
  String get favoritesSearchEmpty =>
      'По этому запросу ничего не найдено. Попробуй часть формулировки вопроса или название темы.';

  @override
  String get favoritesSubtitle => 'Личные сложные вопросы';

  @override
  String favoritesCountHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count вопросов',
      many: '$count вопросов',
      few: '$count вопроса',
      one: '$count вопрос',
    );
    return 'Сейчас в избранном $_temp0. Используй этот режим как персональную подборку перед экзаменом.';
  }

  @override
  String get practiceAllFavorites => 'Пройти всё избранное';

  @override
  String get noTopic => 'Без темы';

  @override
  String get favoriteQuestion => 'Избранный вопрос';

  @override
  String ticketNumber(Object number) {
    return 'Билет $number';
  }

  @override
  String get mistakesTitle => 'Работа над ошибками';

  @override
  String get noMistakesYet => 'Ошибок пока нет';

  @override
  String get mistakesEmptyHint =>
      'Когда появятся неверные ответы, здесь можно будет быстро повторить только слабые вопросы.';

  @override
  String get repeatAllMistakes => 'Повторить все ошибки';

  @override
  String get mistakeReview => 'Разбор ошибки';

  @override
  String get mistakeLabel => 'Ошибка';

  @override
  String get nothingFoundTryAnother =>
      'Ничего не найдено. Попробуйте другое слово.';

  @override
  String get pddSearchEmpty =>
      'Ничего не найдено. Попробуйте номер раздела или ключевое слово.';

  @override
  String get onboardingTitle => 'На чем планируешь ездить?';

  @override
  String get categoryABDesc => 'автомобиль, мотоцикл';

  @override
  String get categoryCDDesc => 'грузовик, автобус';

  @override
  String get ttsAnswerOptions => ' Варианты ответов ';

  @override
  String get ttsAnswer => 'Ответ ';

  @override
  String get noQuestions => 'Нет вопросов';

  @override
  String get hint => 'Подсказка';

  @override
  String questionOfTotal(int current, int total) {
    return 'Вопрос $current из $total';
  }

  @override
  String get finishButton => 'Завершить';

  @override
  String get hideHint => 'Скрыть подсказку';

  @override
  String get confirmAnswerButton => 'Подтвердить ответ';

  @override
  String get myMistakes => 'Мои ошибки';

  @override
  String get noQuestionsToReview => 'Нет вопросов для разбора';

  @override
  String get examReview => 'Разбор экзамена';

  @override
  String get zoomIn => 'Увеличить';

  @override
  String get trainingResultPerfect => 'Ни одной ошибки — так держать';

  @override
  String get trainingResultWithMistakes => 'Повторите вопросы, где ошиблись';

  @override
  String get trainingRepeatMistakes => 'Повторить ошибки';

  @override
  String get done => 'Готово';

  @override
  String get close => 'Закрыть';

  @override
  String get next => 'Следующий';

  @override
  String get notAnsweredThisQuestion => 'Вы не ответили на этот вопрос';

  @override
  String get description => 'Описание';

  @override
  String get folkNameLabel => 'Народное название';

  @override
  String get examAdditionalTitle => 'Дополнительные вопросы';

  @override
  String examAdditionalQuestionOfTotal(int current, int total) {
    return 'Доп. вопрос $current из $total';
  }

  @override
  String get examResultTimeout =>
      'Время вышло. Попробуйте снова в спокойном темпе.';

  @override
  String get examResultPassed =>
      'Отличный результат. Можно закрепить его билетами.';

  @override
  String get examResultFailed => 'Разберите ошибки и повторите слабые места.';

  @override
  String valueOfTotal(int value, int total) {
    return '$value из $total';
  }

  @override
  String examFailedByBlock(int count) {
    return 'Билет состоит из 4 тематических блоков по 5 вопросов. По регламенту ГИБДД $count ошибки в одном блоке — экзамен не сдан, даже если всего ошибок не больше двух.';
  }

  @override
  String get examAdditionalBlock => 'Дополнительный блок';

  @override
  String examAdditionalBlockValue(int count, int errors) {
    return '$count вопросов, ошибок: $errors';
  }

  @override
  String get examTimeSpent => 'Затраченное время';

  @override
  String get examMainBlockErrors => 'Ошибок в основном блоке';

  @override
  String get backToTraining => 'Вернуться к обучению';

  @override
  String get examPointsLabel => 'Набрано баллов';

  @override
  String get examScoreLabel => 'Ваш результат';

  @override
  String examScorePercent(int percent) {
    return '$percent%';
  }

  @override
  String get share => 'Поделиться';

  @override
  String get copiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String examShareText(
    String result,
    int correct,
    int total,
    String title,
    String url,
  ) {
    return '$result\nВерных ответов: $correct из $total\n\n$title\n$url';
  }

  @override
  String get supportChooseMethod => 'Выберите способ';

  @override
  String get supportYoomoney => 'ЮMoney (карта, кошелёк)';

  @override
  String get supportUsdt => 'USDT · сеть TRC-20 (TRON)';

  @override
  String get supportUsdtWarning =>
      'Отправляйте только USDT по сети TRC-20 (TRON). Перевод по другой сети приведёт к потере средств.';

  @override
  String get copyAddress => 'Копировать адрес';

  @override
  String get notifStreakTitle1 => 'Серия под угрозой';

  @override
  String get notifStreakBody1 => 'Потренируйся и сохрани огонёк 🔥';

  @override
  String get notifStreakTitle2 => 'Ты слишком близко, чтобы бросать';

  @override
  String get notifStreakBody2 => 'Каждый день приближает к экзамену';

  @override
  String get notifStreakTitle3 => '🔥 Огонёк вот-вот погаснет';

  @override
  String get notifStreakBody3 => 'Зайди и ответь на пару вопросов';

  @override
  String get notifStreakTitle4 => 'День почти прошёл';

  @override
  String get notifStreakBody4 => 'А тренировки сегодня не было';

  @override
  String get notifStreakTitle5 => 'Твой рекорд под угрозой';

  @override
  String get notifStreakBody5 => 'Сохрани его одним заходом';

  @override
  String get notifStreakTitle6 => 'Экзамен ближе, чем кажется';

  @override
  String get notifStreakBody6 => 'Потренируйся сегодня';

  @override
  String get notifChannelName => 'Напоминания о серии';

  @override
  String get notifChannelDesc => 'Чтобы вы не теряли серию тренировок';

  @override
  String get dataLoadError =>
      'Не удалось загрузить данные. Проверьте подключение и попробуйте снова.';

  @override
  String get themeSetting => 'Тема оформления';

  @override
  String get themeSystem => 'Как на устройстве';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get themeChoose => 'Тема оформления';

  @override
  String get notificationsSetting => 'Напоминания о серии';

  @override
  String get notificationsHint => 'Каждый день в 20:00, если серия не закрыта';

  @override
  String get game => 'Игра';

  @override
  String get gameSimulator => '3D Тренажёр';

  @override
  String get gameLeaderboard => 'Таблица лидеров';

  @override
  String get gameScore => 'Очки';

  @override
  String get gameDistance => 'Дистанция';

  @override
  String get gameOver => 'Заезд завершён';

  @override
  String get gameRestart => 'Попробовать снова';

  @override
  String get gameExit => 'В меню';

  @override
  String get gameUnavailable =>
      'Сценарии тренажёра пока проверены только для ПДД России. Для этой страны игра станет доступна после проверки местных правил.';

  @override
  String get gameMobileOnly =>
      '3D-тренажёр доступен в мобильном приложении на iOS и Android.';

  @override
  String get gameLeft => 'Левее';

  @override
  String get gameRight => 'Правее';

  @override
  String get gameGas => 'ГАЗ';

  @override
  String get gameSpeedUnit => 'км/ч';

  @override
  String get gameMeters => 'м';

  @override
  String get gameKilometers => 'км';

  @override
  String get gameSeconds => 'с';

  @override
  String get gameMistake => 'Ошибка';

  @override
  String get gameCorrect => 'Верно';

  @override
  String get gameContinue => 'Продолжить движение';

  @override
  String get gameResolving => 'Газ — ехать · стрелки — рулить';

  @override
  String get gameGarage => 'Выбор машины';

  @override
  String get gameCarHatch => 'Хэтчбек';

  @override
  String get gameCarSedan => 'Седан';

  @override
  String get gameCarSuv => 'Внедорожник';

  @override
  String get gameCarPickup => 'Пикап';

  @override
  String get gameCarCoupe => 'Купе';

  @override
  String get gameCarWagon => 'Универсал';

  @override
  String get gameCarCyber => 'Кибертрак';

  @override
  String get gamePaintRed => 'красный';

  @override
  String get gamePaintBlue => 'синий';

  @override
  String get gamePaintGreen => 'зелёный';

  @override
  String get gamePaintSand => 'песочный';

  @override
  String get gamePaintWhite => 'белый';

  @override
  String get gamePaintBlack => 'чёрный';

  @override
  String get gamePaintSilver => 'серебристый';

  @override
  String get gamePaintOrange => 'оранжевый';

  @override
  String get gamePaintPurple => 'фиолетовый';

  @override
  String get gamePaintTeal => 'бирюзовый';

  @override
  String get gamePaintYellow => 'жёлтый';

  @override
  String get gamePaintWine => 'бордовый';

  @override
  String get gamePaintGold => 'золотой';

  @override
  String gameGarageNextCar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Следующая машина через $count правильных ответов',
      many: 'Следующая машина через $count правильных ответов',
      few: 'Следующая машина через $count правильных ответа',
      one: 'Следующая машина через $count правильный ответ',
    );
    return '$_temp0';
  }

  @override
  String get gameGaragePremiumCar =>
      'С премиумом открыты все машины и все цвета';

  @override
  String get gameRevealTitle => 'Новая машина!';

  @override
  String get gameRevealTap => 'Нажмите на ворота';

  @override
  String get gameRevealChoose => 'Выбрать';

  @override
  String get gameRevealClose => 'Закрыть';

  @override
  String get feedLockedTitle => 'Лента откроется после входа';

  @override
  String get feedLockedBody =>
      'Короткие карточки с правилами, знаками и советами на каждый день. Войдите — и лента, серия занятий и прогресс будут с вами на любом устройстве.';

  @override
  String get feedSignIn => 'Войти';

  @override
  String get gameSceneTitle => 'Погода и сезон';

  @override
  String get gameSceneWeather => 'Погода';

  @override
  String get gameSceneSeason => 'Время года';

  @override
  String get gameSceneAuto => 'Авто';

  @override
  String get gameSceneClear => 'Ясно';

  @override
  String get gameSceneOvercast => 'Пасмурно';

  @override
  String get gameScenePrecip => 'Осадки';

  @override
  String get gameSceneCalendar => 'По календарю';

  @override
  String get gameDebugUnlimitedFuel => 'Бесконечный бензин';

  @override
  String get gameDebugUnlimitedFuelHint => 'Ошибки не расходуют бензин';

  @override
  String get gameSceneSummer => 'Лето';

  @override
  String get gameSceneAutumn => 'Осень';

  @override
  String get gameSceneWinter => 'Зима';

  @override
  String get gameCollision => 'Столкновение';

  @override
  String get gameOffroad => 'Бордюр · поверните к дороге';

  @override
  String get gamePriorityViolation => 'Вы не уступили дорогу';

  @override
  String get gameWrongManeuver => 'Манёвр не соответствует заданию';

  @override
  String get gameOncoming => 'Встречная полоса! Вернитесь вправо';

  @override
  String get gameOneWayAgainst =>
      'Одностороннее движение! Вы едете против потока';

  @override
  String get gameRoadworksHit => 'Вы въехали в зону дорожных работ';

  @override
  String get gameCorrectAnswers => 'Верных ответов';

  @override
  String gameAnswersOf(int correct, int total) {
    return '$correct из $total';
  }

  @override
  String get gameNoViolations => 'Без нарушений';

  @override
  String get gameYourCar => 'Ваш автомобиль';

  @override
  String get gameSpeeding => 'Превышение скорости';

  @override
  String get gameOvertakingProhibited => 'Обгон здесь запрещён';

  @override
  String get gamePedestrianYield => 'Уступите дорогу пешеходу';

  @override
  String gameSpeedLimitLabel(int limit) {
    return 'Ограничение $limit км/ч';
  }

  @override
  String get gameBrake => 'Тормоз · назад при остановке';

  @override
  String get gameNewRecord => 'Новый рекорд!';

  @override
  String gameBestScore(int score) {
    return 'Рекорд $score';
  }

  @override
  String get gameGasHint => 'Зажмите и держите — это газ';

  @override
  String get gameWeeklyRating => 'Рейтинг недели';

  @override
  String get gameLobbyStart => 'Начать заезд';

  @override
  String get gameLobbyChangeCar => 'Сменить';

  @override
  String get gameLobbyRecord => 'Рекорд';

  @override
  String get gameRatingHint =>
      'Очки всех заездов за неделю. В таблице — лучшие 100.';

  @override
  String get gameRatingEmpty =>
      'На этой неделе ещё никто не проехал. Будьте первым!';

  @override
  String get gameRatingUnavailable =>
      'Не удалось загрузить рейтинг. Проверьте интернет.';

  @override
  String get gameRatingYou => 'Вы';

  @override
  String gameRatingRuns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count заезда',
      many: '$count заездов',
      few: '$count заезда',
      one: '$count заезд',
    );
    return '$_temp0';
  }

  @override
  String gameRatingEndsIn(int days) {
    return 'До конца недели: $days дн.';
  }

  @override
  String get gameAuthRequired => 'Игра доступна после входа';

  @override
  String get gameAuthRequiredHint =>
      'Войдите, чтобы копить очки и участвовать в рейтинге недели.';

  @override
  String get gameSignIn => 'Войти и поехать';

  @override
  String gamePenaltyHint(int points) {
    return 'Нарушение: −$points очков';
  }

  @override
  String get pddSettingsItem => 'Правила, знаки и разметка';

  @override
  String get gameLockedTitle => 'Готовы сесть за руль?';

  @override
  String get gameLockedHint =>
      'Живой город, билеты ГИБДД прямо на дороге и рейтинг недели. Войдите — и поехали.';

  @override
  String get gameFuel => 'Топливо';

  @override
  String get gameFuelUnlimited => 'Безлимитное топливо';

  @override
  String get gameFuelEmptyTitle => 'Бензин закончился';

  @override
  String gameFuelRefillIn(String time) {
    return 'Бак пополнится через $time';
  }

  @override
  String get gameFuelPremiumPitch => 'С подпиской бензин не заканчивается';

  @override
  String get gameFuelBuyPremium => 'Подключить Премиум';

  @override
  String get gameFuelWait => 'Подождать';

  @override
  String get gameViolations => 'Нарушения';

  @override
  String get gameOverDescription =>
      'Жизни закончились. Разберите ошибки и попробуйте снова.';

  @override
  String get gameYou => 'Вы';

  @override
  String get gameStop => 'СТОП';

  @override
  String get gameLoading => 'Загрузка игры';

  @override
  String get gameLoadError =>
      'Не удалось продолжить заезд. Перезапустите тренажёр или вернитесь в меню.';

  @override
  String get authSuccess => 'Вход выполнен успешно';

  @override
  String get authFailed =>
      'Вход отменён или возникла ошибка. Попробуйте ещё раз.';

  @override
  String get authTitle => 'Вход в аккаунт';

  @override
  String get authDescription =>
      'Сохраните премиум-доступ и статистику при смене или переустановке устройства';

  @override
  String get authApple => 'Продолжить с Apple ID';

  @override
  String get authGoogle => 'Продолжить с Google';

  @override
  String get authYandex => 'Продолжить с Яндекс ID';

  @override
  String get authDebug => 'Тестовый вход (debug-сборка)';

  @override
  String get accountDeleted => 'Аккаунт и данные удалены';

  @override
  String get accountDeleteFailed =>
      'Не удалось удалить аккаунт. Проверьте подключение и попробуйте ещё раз.';
}
