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
  String get streakTitle => 'Серия дней';

  @override
  String get streakToday => 'Сегодня засчитано';

  @override
  String get streakTodayPending =>
      'Сегодня ещё не занимались — ответьте на вопрос, чтобы продлить серию';

  @override
  String get streakNewRecord => 'Новый рекорд';

  @override
  String streakNextGoal(int count, int goal) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ещё $count дня до $goal',
      many: 'Ещё $count дней до $goal',
      few: 'Ещё $count дня до $goal',
      one: 'Ещё $count день до $goal',
    );
    return '$_temp0';
  }

  @override
  String get streakGoalReached => 'Все цели взяты — держите темп';

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
  String get gameScore => 'Счёт';

  @override
  String get gameDistance => 'Дистанция';

  @override
  String get gameOver => 'Заезд завершён';

  @override
  String get gameRestart => 'Попробовать снова';

  @override
  String get gameExit => 'Выйти';

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
  String get gameCorrect => 'Верно!';

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
  String get gameDebugUnlimitedFuel => 'Бесконечные заезды';

  @override
  String get gameDebugUnlimitedFuelHint => 'Заезды не расходуются';

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
  String get gameStopViolation => 'Вы не остановились в положенном месте';

  @override
  String get gameRedLightViolation => 'Проезд на запрещающий сигнал';

  @override
  String get gameRailwayViolation =>
      'Переезд закрыт — объезжать и выезжать нельзя';

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
  String get gameLobbyContinue => 'Продолжить заезд';

  @override
  String get gameLobbyChangeCar => 'Сменить';

  @override
  String get gameLobbyRecord => 'Рекорд';

  @override
  String get gameLobbyColour => 'Цвет';

  @override
  String get gameLobbyRating => 'Рейтинг';

  @override
  String get gameLobbyColoursHint =>
      'Новые цвета открываются за правильные ответы в игре';

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
  String get gameFuel => 'Заезды';

  @override
  String get gameFuelUnlimited => 'Безлимитные заезды';

  @override
  String get gameFuelEmptyTitle => 'Заезды закончились';

  @override
  String gameFuelRefillIn(String time) {
    return 'Новый заезд через $time';
  }

  @override
  String get gameFuelPremiumPitch => 'С подпиской заезды не заканчиваются';

  @override
  String get gameFuelBuyPremium => 'Подключить Премиум';

  @override
  String get gameFuelWait => 'Подождать';

  @override
  String get gameViolations => 'Нарушения';

  @override
  String get gameOverDescription =>
      'Все вопросы заезда позади. Неверные ответы уже в «Ошибках» — разберите их и попробуйте снова.';

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
  String get authErrorCancelled =>
      'Вход не завершён. Попробуйте выбрать аккаунт ещё раз.';

  @override
  String get authErrorProvider =>
      'Не удалось получить данные для входа от выбранного сервиса.';

  @override
  String get authErrorNetwork =>
      'Не удалось связаться с сервером. Проверьте подключение к интернету.';

  @override
  String get authErrorTimeout =>
      'Сервер не ответил вовремя. Попробуйте ещё раз.';

  @override
  String get authErrorAppKey =>
      'Сервер отклонил эту сборку приложения. Обновите приложение из магазина.';

  @override
  String get authErrorCredential =>
      'Сервер не подтвердил вход. Попробуйте другой аккаунт или способ входа.';

  @override
  String get authErrorServer =>
      'Не удалось завершить вход на сервере. Попробуйте позже.';

  @override
  String get authErrorResponse =>
      'Не удалось завершить вход. Обновите страницу или перезапустите приложение и попробуйте снова.';

  @override
  String get authSessionTemporary =>
      'Вход выполнен. Телефон не смог сохранить сессию: после перезапуска потребуется войти снова.';

  @override
  String authDiagnosticCode(String code) {
    return 'Код для поддержки: $code';
  }

  @override
  String get authTitle => 'Вход в аккаунт';

  @override
  String get authDescription =>
      'Сохраните премиум-доступ и статистику при смене или переустановке устройства';

  @override
  String get authAppleSafariHint =>
      'Чтобы войти с Face ID без ввода данных, откройте сайт в Safari через меню браузера. Встроенный браузер может попросить email и пароль Apple.';

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

  @override
  String get gameControlsTitle => 'Управление';

  @override
  String get gameControlsSimple => 'Простое управление';

  @override
  String get gameControlsSimpleHint =>
      'Стрелки — перестроения и повороты, машина едет сама';

  @override
  String get gameControlsFree => 'Свободное управление';

  @override
  String get gameControlsFreeHint => 'Стрелки крутят руль, пока их держишь';

  @override
  String get gameTipGas =>
      'Держи педаль газа — машина едет. Отпусти — плавно остановится';

  @override
  String get gameTipSteer =>
      'Держи стрелку — машина поворачивает. Отпустишь — сама выровняется в полосе';

  @override
  String get gameTipTurn =>
      'На перекрёстке держи стрелку, пока машина поворачивает, затем отпусти — она выровняется сама';

  @override
  String get gameTipNext => 'Дальше';

  @override
  String get gameTipDone => 'Поехали';

  @override
  String get gamePause => 'Пауза';

  @override
  String get gameLobbyControls => 'Управ.';

  @override
  String gameRunProgress(int n, int total) {
    return 'Вопрос $n из $total';
  }

  @override
  String get gameCorrectAnswer => 'Правильный ответ';

  @override
  String get gameTimeUp => 'Время вышло';

  @override
  String gamePenaltyPoints(int points) {
    String _temp0 = intl.Intl.pluralLogic(
      points,
      locale: localeName,
      other: '−$points очков',
      many: '−$points очков',
      few: '−$points очка',
      one: '−$points очко',
    );
    return '$_temp0';
  }

  @override
  String gameRunMistakes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ошибки в заезде',
      many: '$count ошибок в заезде',
      few: '$count ошибки в заезде',
      one: '$count ошибка в заезде',
    );
    return '$_temp0';
  }

  @override
  String get gameReviewMistakes => 'Разобрать ошибки';

  @override
  String get notifGameRunTitle => 'Новый заезд готов';

  @override
  String get notifGameRunBody =>
      'Садитесь за руль: перекрёстки из экзаменационных билетов ждут.';

  @override
  String get notifGameChannelName => 'Игра';

  @override
  String get notifGameChannelDesc => 'Когда восстановится заезд в игре';

  @override
  String gameRunMistakesButton(int count) {
    return 'Ошибки · $count';
  }

  @override
  String get gameCorrectShort => 'Верно';

  @override
  String gameRunsPill(int runs, int max) {
    return 'Заезды $runs из $max';
  }

  @override
  String get gameRunsUnlimitedPill => 'Заезды ∞';

  @override
  String get gameRunsTitle => 'Заезды';

  @override
  String gameRunsExplain(int questions, int max, int minutes) {
    return 'Заезд — это $questions вопросов на дороге. В запасе до $max заездов, каждый потраченный возвращается через $minutes минут.';
  }

  @override
  String gameRunsNextIn(String time) {
    return 'Следующий заезд через $time';
  }

  @override
  String get gameRunsFull => 'Запас полный — можно ехать';

  @override
  String get gameRunsPremium => 'С Премиум заезды без ограничений';

  @override
  String get gameRunsGetPremium => 'Безлимит с Премиум';

  @override
  String gameLobbyRunLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count вопроса',
      many: '$count вопросов',
      few: '$count вопроса',
      one: '$count вопрос',
    );
    return '$_temp0';
  }

  @override
  String gameLobbyProgress(int n, int total) {
    return 'Пройдено $n из $total';
  }

  @override
  String get gameLobbyNewCar => 'НОВАЯ';

  @override
  String get gameRunsReady => 'Готов';

  @override
  String get gameRunsUntil => 'до заезда';

  @override
  String get gameUturn => 'Разворот';

  @override
  String get purchaseVerificationPending =>
      'Магазин сообщил о покупке, но доступ пока не подтверждён. Для повторной проверки нажмите «Восстановить» при доступном интернете.';

  @override
  String get notifAdminChannelName => 'Сообщения приложения';

  @override
  String get noticeAcknowledge => 'Понятно';

  @override
  String get noticeOpen => 'Открыть';

  @override
  String get pushMessagesSetting => 'Новости приложения';

  @override
  String get pushMessagesHint => 'Пуши об обновлениях и важных событиях';

  @override
  String get gameKeyboardHint =>
      '↑ / W — газ · ↓ / S / пробел — тормоз · ← → / A D — повороты';

  @override
  String get webQuarter => '3 месяца';

  @override
  String get webPaymentSoon => 'Оплата скоро появится';

  @override
  String get webPaymentInfo =>
      'Доступ на 3 месяца без автопродления. Оплата на сайте пока не подключена.';

  @override
  String get webWeek => '1 неделя';

  @override
  String get webPayButton => 'Оплатить через СБП';

  @override
  String get webPayInfo =>
      'Разовая оплата без автопродления. Премиум откроется и в приложении на телефоне — войдите в нём тем же аккаунтом.';

  @override
  String get sbpPayInfoApp =>
      'Разовая оплата без автопродления. Премиум включится сразу после оплаты и будет работать на всех ваших устройствах с этим аккаунтом.';

  @override
  String get webPayTariffs => 'Тарифы';

  @override
  String get webPayEmailTitle => 'Оплата через СБП';

  @override
  String get webPayEmailBody =>
      'Оплату через СБП подключаем в ближайшие дни. Оставьте почту — напишем, как только она заработает. На неё же придёт чек.';

  @override
  String get webPayEmailHint => 'Электронная почта';

  @override
  String get webPayEmailInvalid => 'Проверьте адрес почты';

  @override
  String get webPayNotify => 'Сообщить мне';

  @override
  String get webPayFailed => 'Не удалось отправить, попробуйте ещё раз';

  @override
  String get webPayNeedsAccount =>
      'Для оплаты войдите через Google, Яндекс или Apple: тестовый вход оплату не принимает.';

  @override
  String get webPayLiveBody =>
      'Укажите почту для чека. Дальше откроется оплата через СБП — по QR-коду или в приложении банка. Премиум включится сразу после оплаты.';

  @override
  String get webPayProceed => 'Перейти к оплате';

  @override
  String get webPaySuccess => 'Оплата прошла — Премиум включён. Спасибо!';

  @override
  String get webPayPending =>
      'Платёж обрабатывается — Премиум включится автоматически в течение нескольких минут';

  @override
  String get webPayCanceled => 'Оплата не завершена — деньги не списаны';

  @override
  String webPaySaved(String email) {
    return 'Спасибо! Напишем на $email, как только оплата заработает';
  }

  @override
  String premiumOneTimeInfo(String date) {
    return 'Доступ действует до $date и не продлевается автоматически.';
  }

  @override
  String get appUpdateTitle => 'Вышло обновление';

  @override
  String get appUpdateBody =>
      'В новой версии — улучшения и исправления. Обновите приложение, чтобы пользоваться ими.';

  @override
  String appUpdateVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get appUpdateAction => 'Обновить';

  @override
  String get appUpdateLater => 'Позже';

  @override
  String get appUpdateReadyTitle => 'Обновление готово';

  @override
  String get appUpdateReadyBody =>
      'Новая версия уже скачана. Перезапустите приложение, чтобы установить её.';

  @override
  String get appUpdateRestart => 'Перезапустить';

  @override
  String get appUpdateOpenFailed =>
      'Не удалось открыть обновление. Попробуйте позже.';

  @override
  String get profile => 'Профиль';

  @override
  String get signInCardTitle => 'Войти в аккаунт';

  @override
  String get signInCardSubtitle => 'Сохранить прогресс и премиум';

  @override
  String get achievements => 'Достижения';

  @override
  String achievementsEarnedCount(int count, int total) {
    return '$count из $total';
  }

  @override
  String achievementLevelFormat(int level, int total) {
    return 'Ур. $level из $total';
  }

  @override
  String achievementSemanticsLabel(String title, int level, int total) {
    return '$title, уровень $level из $total';
  }

  @override
  String achievementProgressFormat(int current, int target) {
    return '$current из $target';
  }

  @override
  String get achievementTitleStreak => 'Без пропусков';

  @override
  String get achievementTitleCoverage => 'Эрудит';

  @override
  String get achievementTitleTickets => 'Билет за билетом';

  @override
  String get achievementTitleAttempts => 'Неутомимый';

  @override
  String get achievementTitleExams => 'Экзаменатор';

  @override
  String get achievementTitleFlawless => 'Без единой ошибки';

  @override
  String get achievementTitleMistakes => 'Работа над ошибками';

  @override
  String get achievementTitleGame => 'Гонщик';

  @override
  String get achievementDescStreak => 'Лучшая серия дней подряд с занятиями';

  @override
  String get achievementDescCoverage => 'Решено разных вопросов из базы';

  @override
  String get achievementDescTickets => 'Билеты, решённые на «сдал»';

  @override
  String get achievementDescAttempts => 'Всего ответов, включая повторные';

  @override
  String get achievementDescExams => 'Сданные пробные экзамены';

  @override
  String get achievementDescFlawless => 'Экзамены, сданные без ошибок';

  @override
  String get achievementDescMistakes =>
      'Вопросы, в которых ошибался, а потом ответил верно';

  @override
  String get achievementDescGame =>
      'Наберите 200, 400, 700 и 950 очков за один заезд в «Живом городе».';

  @override
  String get achievementTitleRank => 'Покоритель рейтинга';

  @override
  String get achievementDescRank => 'Лучшее место в недельном рейтинге игры';

  @override
  String achievementRankTop(int count) {
    return 'Топ-$count';
  }

  @override
  String get achievementRankFirst => '1 место';

  @override
  String get paywallSubscribe => 'Оформить подписку';

  @override
  String get paywallStoreGoogle => 'Google Play';

  @override
  String get paywallPayMethod => 'Способ оплаты';

  @override
  String get paywallMethodSbp => 'СБП';

  @override
  String get paywallStoreApple => 'настройках Apple ID';

  @override
  String get paywallTitle => 'Готовьтесь без ограничений';

  @override
  String get paywallFreeNote => 'Билеты, экзамен и ПДД остаются бесплатными';

  @override
  String get paywallFeatureFeed => 'Безлимитная лента вопросов';

  @override
  String get paywallFeatureAi => 'Разбор ошибок от ИИ';

  @override
  String get paywallFeatureVoice => 'Студийная озвучка билетов';

  @override
  String get paywallFeatureGame => 'Безлимитные заезды в игре';

  @override
  String get paywallPlanQuarter => '3 месяца';

  @override
  String get paywallPlanWeek => '1 неделя';

  @override
  String get paywallEveryQuarter => 'каждые 3 месяца';

  @override
  String get paywallEveryWeek => 'каждую неделю';

  @override
  String get paywallBadgeBest => 'Выгодно';

  @override
  String paywallRenewal(String store) {
    return 'Продлевается автоматически. Отменить можно в любой момент в $store.';
  }

  @override
  String get paywallTerms => 'Условия';

  @override
  String get paywallPrivacy => 'Конфиденциальность';

  @override
  String get paywallRestore => 'Восстановить';

  @override
  String get gameSourceImage => 'Оригинальная картинка вопроса';

  @override
  String get gameSourceImageUnavailable => 'В этом вопросе нет картинки';

  @override
  String get navGames => 'Игры';

  @override
  String get gameTrafficControllerTitle => 'Регулировщик';

  @override
  String get gameBestScoreLabel => 'Рекорд';

  @override
  String get gameComboLabel => 'Макс. комбо';

  @override
  String get gameSolvedLabel => 'Решено';

  @override
  String get gameCombo => 'Комбо';

  @override
  String get gameLives => 'Жизни';

  @override
  String get gameActionStraight => 'Прямо';

  @override
  String get gameActionRight => 'Направо';

  @override
  String get gameActionLeft => 'Налево';

  @override
  String get gameActionUTurn => 'Разворот';

  @override
  String get gameActionStand => 'Стоять';

  @override
  String get gameVehicleCar => 'Автомобиль';

  @override
  String get gameVehicleTram => 'Трамвай';

  @override
  String get gameCameraOverview => 'Обзор';

  @override
  String get gameCameraDriver => 'За рулём';

  @override
  String get gameOverTitle => 'Игра окончена';

  @override
  String get gameOverNewRecord => 'Новый рекорд!';

  @override
  String get gamePlayAgain => 'Играть снова';

  @override
  String get gameWrong => 'Нарушение!';

  @override
  String get gameWhistleNote =>
      'Свисток инспектора: движение в этом направлении запрещено сигналом регулировщика.';

  @override
  String get gameSignSwiperTitle => 'Знак-Свайпер';

  @override
  String get gameSwipedLabel => 'Свайпов';

  @override
  String get gameSignSwiperNext => 'Следующий знак';

  @override
  String get gameSignSwiperCategoryAll => 'Все категории';

  @override
  String get gameMistakesReview => 'Разбор ошибок';

  @override
  String get gameNoMistakes => 'Отличная работа! Ни одной ошибки.';

  @override
  String get gameAccuracyLabel => 'Точность';

  @override
  String gameQuestionCategory(String category) {
    return 'Относится ли этот знак к категории «$category»?';
  }

  @override
  String gameQuestionName(String name) {
    return 'Этот знак называется «$name»?';
  }

  @override
  String gameQuestionFolkName(String name) {
    return 'В народе этот знак называют «$name»?';
  }

  @override
  String get gameQuestionPriorityAdvantage =>
      'Имеете ли вы преимущество проезда при этом знаке?';

  @override
  String get gameQuestionProhibitsEntry => 'Разрешён ли въезд под этот знак?';

  @override
  String get gameQuestionProhibitsOvertaking =>
      'Разрешён ли обгон всех транспортных средств?';

  @override
  String get gameQuestionProhibitsParking =>
      'Разрешена ли стоянка под этот знак?';

  @override
  String get gameQuestionProhibitsStopping =>
      'Разрешена ли остановка под этот знак?';

  @override
  String gameComboStreak(int combo) {
    return 'КОМБО х$combo!';
  }

  @override
  String get gameSoonBadge => 'Скоро';

  @override
  String get gameRoundaboutTitle => 'Круговое движение 3D';

  @override
  String get gameCrossroadsPriorityTitle => 'Разрули перекресток';

  @override
  String get gameCrossroadsPromptWhoGoesFirst => 'Кто проедет первым?';

  @override
  String gameCrossroadsPromptWhoGoesNext(int step) {
    return 'Кто проедет следующим ($step-м)?';
  }

  @override
  String gameCrossroadsStepOf(int current, int total) {
    return 'Шаг $current из $total';
  }

  @override
  String get gameCrossroadsCollision => 'ДТП! Нарушение очередности';

  @override
  String gameCrossroadsShouldGo(String name) {
    return 'Проезжает сейчас: $name';
  }

  @override
  String get gameCrossroadsHowTo =>
      'Расставьте машины по очереди: нажимайте на ту, что едет сейчас.';

  @override
  String get gameCrossroadsNextCrossroad => 'Следующий перекресток';

  @override
  String get gameCrossroadsRepeatCrossroad => 'Попробовать снова';

  @override
  String get gameCrossroadsModeArcade => 'Аркада';

  @override
  String get gameCrossroadsModeTraining => 'Обучение';

  @override
  String gameCrossroadsSolvedCount(int count) {
    return 'Разрулено: $count';
  }

  @override
  String get gameCrossroadsExplanationTitle => 'Разбор ситуации по ПДД РФ';

  @override
  String get gameCrossroadsCompleteTitle => 'Перекресток разрулен!';

  @override
  String get gameGestureRightArm => 'Рука вперёд';

  @override
  String get gameGestureHandsSides => 'Руки в стороны';

  @override
  String get gameGestureArmUp => 'Рука вверх';

  @override
  String get gameApproachLeft => 'Левый бок';

  @override
  String get gameApproachFront => 'Грудь';

  @override
  String get gameApproachRight => 'Правый бок';

  @override
  String get gameApproachBack => 'Спина';

  @override
  String gameSecondsLeft(int seconds) {
    return '$seconds с';
  }

  @override
  String get gameSignsLoadError => 'Не удалось загрузить знаки';

  @override
  String get gameRetry => 'Повторить';

  @override
  String get gameRestartRound => 'Начать сначала';

  @override
  String get gameSignYes => 'ДА';

  @override
  String get gameSignNo => 'НЕТ';

  @override
  String get gameSignCan => 'МОЖНО';

  @override
  String get gameSignCannot => 'НЕЛЬЗЯ';

  @override
  String get gameUnderstood => 'Понятно';

  @override
  String get gamePddOfficialText => 'ПДД РФ:';

  @override
  String get gamePromptWhereCanGo => 'Куда можно проехать?';

  @override
  String get gameCaptionGesture => 'Жест';

  @override
  String get gameCaptionApproach => 'К вам повёрнут';

  @override
  String get gameAnswerWrong => 'Неверно';

  @override
  String get achievementTitleTrafficController => 'Мастер сигналов';

  @override
  String get achievementDescTrafficController =>
      'Наберите 150, 300, 600 и 900 очков за одну игру с регулировщиком.';

  @override
  String get achievementTitleSignSwiper => 'Знаток знаков';

  @override
  String get achievementDescSignSwiper =>
      'Наберите 100, 200, 300 и 450 очков за одну игру в «Знак-свайпер».';

  @override
  String get gameSignQuestionScope => 'Других знаков и запретов нет';

  @override
  String get gameTrafficSignalQuestion => 'Что разрешает сигнал?';

  @override
  String get gameTrafficHintButton => 'Подсказка';

  @override
  String get gameTrafficHintTitle => 'Как запомнить';

  @override
  String get gameTrafficHintPaused => 'Время на паузе';

  @override
  String get gameTrafficHintScope =>
      'Учитывайте свою полосу, знаки и разметку.';

  @override
  String get gameTrafficHintArmUp =>
      'Палка вверх устремлена — всем стоять велит она.';

  @override
  String get gameTrafficHintForwardFront =>
      'Если палка смотрит в рот — делай правый поворот.';

  @override
  String get gameTrafficHintForwardRight =>
      'Если палка смотрит вправо — ехать не имеешь права.';

  @override
  String get gameTrafficHintForwardLeft =>
      'Если палка смотрит влево — поезжай как королева.';

  @override
  String get gameTrafficHintBack => 'Спина — стена.';

  @override
  String get gameTrafficHintWall => 'Грудь и спина — для водителя стена.';

  @override
  String get gameTrafficHintSide =>
      'Боком встал регулировщик — прямо и направо путь открыт.';

  @override
  String get gameTrafficHintTramLeft =>
      'Трамвай едет из рукава в рукав — только налево.';

  @override
  String get gameTrafficHintTramStraight =>
      'Трамвай едет из рукава в рукав — только прямо.';

  @override
  String get gameTrafficHintForbidden => 'Сигнал запрещает движение.';

  @override
  String gameTrafficHintAllowed(String directions) {
    return 'Сигнал разрешает: $directions.';
  }

  @override
  String get gameSignScenario1_1_0Prompt =>
      'Знак предупреждает о переезде со шлагбаумом?';

  @override
  String get gameSignScenario1_1_0Explanation =>
      'Да. Впереди железнодорожный переезд со шлагбаумом.';

  @override
  String get gameSignScenario1_1_1Prompt =>
      'Можно обгонять за 80 м до переезда?';

  @override
  String get gameSignScenario1_1_1Explanation =>
      'Нет. Обгон запрещён на переезде и за 100 м до него (п. 11.4).';

  @override
  String get gameSignScenario1_1_2Prompt =>
      'Можно оставить машину в 30 м от переезда?';

  @override
  String get gameSignScenario1_1_2Explanation =>
      'Нет. Стоянка запрещена ближе 50 м от переезда (п. 12.5).';

  @override
  String get gameSignScenario1_2_0Prompt => 'Впереди переезд без шлагбаума?';

  @override
  String get gameSignScenario1_2_0Explanation =>
      'Да. Знак предупреждает о переезде без шлагбаума.';

  @override
  String get gameSignScenario1_2_1Prompt => 'Можно развернуться на переезде?';

  @override
  String get gameSignScenario1_2_1Explanation =>
      'Нет. На переезде запрещены разворот и движение задним ходом (пп. 8.11–8.12).';

  @override
  String get gameSignScenario1_3_1_0Prompt =>
      'На переезде один железнодорожный путь?';

  @override
  String get gameSignScenario1_3_1_0Explanation =>
      'Да. Этот знак обозначает переезд с одним путём, без шлагбаума.';

  @override
  String get gameSignScenario1_3_1_1Prompt =>
      'Этот знак ставят за 150–300 м до переезда?';

  @override
  String get gameSignScenario1_3_1_1Explanation =>
      'Нет. Знак 1.3.1 ставят непосредственно перед переездом.';

  @override
  String get gameSignScenario1_5_0Prompt =>
      'Трамвай пересекает дорогу вне перекрёстка, не из депо. Нужно уступить?';

  @override
  String get gameSignScenario1_5_0Explanation =>
      'Да. Вне перекрёстка трамвай имеет преимущество, кроме выезда из депо (п. 18.1).';

  @override
  String get gameSignScenario1_5_1Prompt =>
      'Трамвай выезжает из депо. Он должен уступить автомобилям?';

  @override
  String get gameSignScenario1_5_1Explanation =>
      'Да. При выезде из депо трамвай уступает другим транспортным средствам (п. 18.1).';

  @override
  String get gameSignScenario1_6_0Prompt =>
      'Без светофора на равнозначном перекрёстке нужно уступить автомобилю справа?';

  @override
  String get gameSignScenario1_6_0Explanation =>
      'Да. На нерегулируемом равнозначном перекрёстке уступают автомобилям справа (п. 13.11).';

  @override
  String get gameSignScenario1_6_1Prompt =>
      'Можно обгонять на равнозначном перекрёстке без светофора?';

  @override
  String get gameSignScenario1_6_1Explanation =>
      'Нет. На нерегулируемом перекрёстке обгон разрешён только при движении по главной дороге (п. 11.4).';

  @override
  String get gameSignScenario1_7_0Prompt =>
      'Впереди перекрёсток с круговым движением?';

  @override
  String get gameSignScenario1_7_0Explanation =>
      'Да. Знак предупреждает о приближении к круговому перекрёстку.';

  @override
  String get gameSignScenario1_7_1Prompt =>
      'Круговое движение начинается прямо у этого знака?';

  @override
  String get gameSignScenario1_7_1Explanation =>
      'Нет. Это предупреждение. Направление движения на самом круге задаёт знак 4.3.';

  @override
  String get gameSignScenario1_11_1_0Prompt =>
      'Можно развернуться, если дорогу видно только на 70 м?';

  @override
  String get gameSignScenario1_11_1_0Explanation =>
      'Нет. Для разворота видимость должна быть не менее 100 м в каждом направлении (п. 8.11).';

  @override
  String get gameSignScenario1_11_1_1Prompt =>
      'Перед опасным поворотом нужно выбрать безопасную скорость?';

  @override
  String get gameSignScenario1_11_1_1Explanation =>
      'Да. Скорость выбирают с учётом поворота и видимости дороги (п. 10.1).';

  @override
  String get gameSignScenario1_23_0Prompt =>
      'Здесь на дорогу могут неожиданно выйти дети?';

  @override
  String get gameSignScenario1_23_0Explanation =>
      'Да. Знак предупреждает об участке, где на дороге могут появиться дети.';

  @override
  String get gameSignScenario1_23_1Prompt =>
      'Этот знак разрешает детям переходить дорогу где угодно?';

  @override
  String get gameSignScenario1_23_1Explanation =>
      'Нет. Знак предупреждает водителей, но не меняет правила перехода дороги.';

  @override
  String get gameSignScenario1_25_0Prompt =>
      'Временный знак на жёлтом фоне важнее постоянного, если они противоречат?';

  @override
  String get gameSignScenario1_25_0Explanation =>
      'Да. При противоречии временных и постоянных знаков выполняют требование временного.';

  @override
  String get gameSignScenario1_25_1Prompt =>
      'Перед знаком дорожных работ обязательно остановиться?';

  @override
  String get gameSignScenario1_25_1Explanation =>
      'Нет. Сам знак не требует остановки. Нужно учитывать дорожные работы и выбрать безопасную скорость.';

  @override
  String get gameSignScenario2_1_0Prompt =>
      'Без светофора вы имеете преимущество перед машиной со второстепенной?';

  @override
  String get gameSignScenario2_1_0Explanation =>
      'Да. На нерегулируемом перекрёстке главная дорога даёт преимущество перед второстепенной (п. 13.9).';

  @override
  String get gameSignScenario2_1_1Prompt =>
      'Можно ехать на красный, если вы на главной дороге?';

  @override
  String get gameSignScenario2_1_1Explanation =>
      'Нет. На регулируемом перекрёстке нужно выполнять сигналы светофора (п. 6.15).';

  @override
  String get gameSignScenario2_1_2Prompt =>
      'Можно оставить машину на проезжей части главной дороги вне населённого пункта?';

  @override
  String get gameSignScenario2_1_2Explanation =>
      'Нет. На таких дорогах стоянка на проезжей части вне населённого пункта запрещена (п. 12.5).';

  @override
  String get gameSignScenario2_2_0Prompt =>
      'Знак обозначает конец главной дороги?';

  @override
  String get gameSignScenario2_2_0Explanation =>
      'Да. Преимущество, которое давал знак «Главная дорога», заканчивается.';

  @override
  String get gameSignScenario2_2_1Prompt =>
      'Этот знак сам по себе требует остановиться?';

  @override
  String get gameSignScenario2_2_1Explanation =>
      'Нет. Он отменяет статус главной дороги. Порядок проезда определяют другие знаки и правила.';

  @override
  String get gameSignScenario2_3_1_0Prompt =>
      'Без светофора машина с пересекаемой дороги должна уступить вам?';

  @override
  String get gameSignScenario2_3_1_0Explanation =>
      'Да. Знак показывает пересечение главной дороги со второстепенной (п. 13.9).';

  @override
  String get gameSignScenario2_3_1_1Prompt =>
      'Без светофора нужно уступить машине справа со второстепенной дороги?';

  @override
  String get gameSignScenario2_3_1_1Explanation =>
      'Нет. Преимущество у вас: вы на главной дороге. Правило «помехи справа» здесь не применяется.';

  @override
  String get gameSignScenario2_4_0Prompt =>
      'Без светофора нужно уступить машинам на пересекаемой дороге?';

  @override
  String get gameSignScenario2_4_0Explanation =>
      'Да. Знак требует уступить машинам на пересекаемой дороге. При табличке 8.13 — машинам на главной дороге.';

  @override
  String get gameSignScenario2_4_1Prompt =>
      'Дорога свободна. Перед этим знаком всё равно нужно остановиться?';

  @override
  String get gameSignScenario2_4_1Explanation =>
      'Нет. Обязательной остановки нет, если вы никому не мешаете.';

  @override
  String get gameSignScenario2_4_2Prompt =>
      'Оба на второстепенной: вы прямо, встречный налево. Он должен уступить?';

  @override
  String get gameSignScenario2_4_2Explanation =>
      'Да. При равном приоритете встречный автомобиль, поворачивающий налево, уступает едущему прямо (п. 13.12).';

  @override
  String get gameSignScenario2_5_0Prompt =>
      'Перед STOP нужно остановиться, даже если дорога свободна?';

  @override
  String get gameSignScenario2_5_0Explanation =>
      'Да. Остановитесь перед стоп-линией, а если её нет — перед краем пересекаемой проезжей части. У переезда без стоп-линии — перед знаком.';

  @override
  String get gameSignScenario2_5_1Prompt =>
      'Можно проехать STOP без остановки, если всё хорошо видно?';

  @override
  String get gameSignScenario2_5_1Explanation =>
      'Нет. Знак требует полной остановки даже при свободной дороге.';

  @override
  String get gameSignScenario2_6_0Prompt =>
      'Въезд помешает встречной машине. Нужно уступить?';

  @override
  String get gameSignScenario2_6_0Explanation =>
      'Да. Нельзя въезжать на узкий участок, если это затруднит встречное движение.';

  @override
  String get gameSignScenario2_6_1Prompt =>
      'Этот знак даёт вам преимущество перед встречными?';

  @override
  String get gameSignScenario2_6_1Explanation =>
      'Нет. Преимущество у встречного транспорта.';

  @override
  String get gameSignScenario2_7_0Prompt =>
      'На узком участке преимущество у вас?';

  @override
  String get gameSignScenario2_7_0Explanation =>
      'Да. Этот знак даёт преимущество перед встречными машинами.';

  @override
  String get gameSignScenario2_7_1Prompt =>
      'Этот знак даёт преимущество встречной машине?';

  @override
  String get gameSignScenario2_7_1Explanation =>
      'Нет. Преимущество у транспорта, движущегося в вашем направлении.';

  @override
  String get gameSignScenario3_1_0Prompt =>
      'Этот знак запрещает въезд обычному такси?';

  @override
  String get gameSignScenario3_1_0Explanation =>
      'Да. Такси и каршеринг должны выполнять запрет. Исключение — маршрутный транспорт.';

  @override
  String get gameSignScenario3_1_1Prompt =>
      'Можно въехать, только потому что вы живёте за знаком?';

  @override
  String get gameSignScenario3_1_1Explanation =>
      'Нет. Для жителей исключения нет. Не путайте этот знак со знаком «Движение запрещено».';

  @override
  String get gameSignScenario3_1_2Prompt =>
      'Можно въехать маршрутному автобусу на своём маршруте?';

  @override
  String get gameSignScenario3_1_2Explanation =>
      'Да. Запрет этого знака не действует на маршрутные транспортные средства.';

  @override
  String get gameSignScenario3_2_0Prompt =>
      'Можно проехать к своему дому в зоне этого знака?';

  @override
  String get gameSignScenario3_2_0Explanation =>
      'Да. Жителям разрешён проезд к дому. Въезжать и выезжать нужно на ближайшем к нему перекрёстке.';

  @override
  String get gameSignScenario3_2_1Prompt =>
      'Можно проехать эту зону насквозь на обычном автомобиле?';

  @override
  String get gameSignScenario3_2_1Explanation =>
      'Нет. Знак запрещает движение. Проезд жителей и обслуживающих машин — исключения для доступа к месту назначения.';

  @override
  String get gameSignScenario3_2_2Prompt =>
      'Знак запрещает проезд водителю с инвалидностью I группы и знаком «Инвалид»?';

  @override
  String get gameSignScenario3_2_2Explanation =>
      'Нет. Знак не действует на машины водителей с инвалидностью I–II групп или перевозящие их и детей-инвалидов, со знаком «Инвалид».';

  @override
  String get gameSignScenario3_4_0Prompt =>
      'Этот знак запрещает движение легковых автомобилей?';

  @override
  String get gameSignScenario3_4_0Explanation =>
      'Нет. Он ограничивает движение грузовиков, тракторов и самоходных машин.';

  @override
  String get gameSignScenario3_4_1Prompt =>
      'Можно обычному грузовику с разрешённой массой 5 т проехать под этот знак?';

  @override
  String get gameSignScenario3_4_1Explanation =>
      'Да. На показанном знаке указан порог 8 т. Разрешённая максимальная масса 5 т его не превышает.';

  @override
  String get gameSignScenario3_18_1_0Prompt =>
      'Этот знак запрещает поворот налево?';

  @override
  String get gameSignScenario3_18_1_0Explanation =>
      'Нет. Он запрещает только поворот направо на ближайшем пересечении проезжих частей.';

  @override
  String get gameSignScenario3_18_1_1Prompt =>
      'Можно повернуть направо на ближайшем пересечении?';

  @override
  String get gameSignScenario3_18_1_1Explanation =>
      'Нет. Поворот направо на ближайшем пересечении запрещён.';

  @override
  String get gameSignScenario3_18_2_0Prompt => 'Этот знак запрещает разворот?';

  @override
  String get gameSignScenario3_18_2_0Explanation =>
      'Нет. Он запрещает поворот налево, но сам по себе не запрещает разворот.';

  @override
  String get gameSignScenario3_18_2_1Prompt =>
      'Можно повернуть налево на ближайшем пересечении?';

  @override
  String get gameSignScenario3_18_2_1Explanation =>
      'Нет. Поворот налево на ближайшем пересечении запрещён.';

  @override
  String get gameSignScenario3_19_0Prompt =>
      'Этот знак запрещает поворот налево?';

  @override
  String get gameSignScenario3_19_0Explanation =>
      'Нет. Он запрещает только разворот.';

  @override
  String get gameSignScenario3_19_1Prompt =>
      'Можно развернуться в месте действия этого знака?';

  @override
  String get gameSignScenario3_19_1Explanation => 'Нет. Разворот запрещён.';

  @override
  String get gameSignScenario3_20_0Prompt =>
      'Этот знак разрешает обгон тихоходной машины с соответствующим знаком?';

  @override
  String get gameSignScenario3_20_0Explanation =>
      'Да. Тихоходные машины — исключение из запрета знака 3.20. Другие запреты обгона и разметку тоже нужно учитывать.';

  @override
  String get gameSignScenario3_20_1Prompt =>
      'Можно обогнать обычную легковую машину, если она едет всего 25 км/ч?';

  @override
  String get gameSignScenario3_20_1Explanation =>
      'Нет. Низкая скорость не делает легковой автомобиль тихоходным транспортным средством.';

  @override
  String get gameSignScenario3_20_2Prompt =>
      'Этот знак разрешает обгон мотоцикла без коляски?';

  @override
  String get gameSignScenario3_20_2Explanation =>
      'Да. Двухколёсные мотоциклы без бокового прицепа — исключение из запрета этого знака.';

  @override
  String get gameSignScenario3_24_0Prompt =>
      'Число на знаке — максимально разрешённая скорость?';

  @override
  String get gameSignScenario3_24_0Explanation =>
      'Да. Быстрее указанного ехать нельзя. При плохой видимости безопасная скорость может быть ниже.';

  @override
  String get gameSignScenario3_24_1Prompt =>
      'Этот знак требует ехать не медленнее указанного числа?';

  @override
  String get gameSignScenario3_24_1Explanation =>
      'Нет. Это ограничение максимальной скорости, а не минимальной.';

  @override
  String get gameSignScenario3_27_0Prompt =>
      'Можно остановить обычную машину на минуту, чтобы высадить пассажира?';

  @override
  String get gameSignScenario3_27_0Explanation =>
      'Нет. Знак запрещает остановку и стоянку. Высадка пассажира — тоже остановка.';

  @override
  String get gameSignScenario3_27_1Prompt =>
      'Знак «Инвалид» сам по себе разрешает остановку здесь?';

  @override
  String get gameSignScenario3_27_1Explanation =>
      'Нет. Льгота сама по себе не отменяет знак «Остановка запрещена». Исключение может обозначаться табличкой 8.18.';

  @override
  String get gameSignScenario3_27_2Prompt =>
      'Можно оставить обычную машину под этим знаком?';

  @override
  String get gameSignScenario3_27_2Explanation =>
      'Нет. Знак запрещает и остановку, и стоянку.';

  @override
  String get gameSignScenario3_28_0Prompt =>
      'Можно остановиться, чтобы высадить пассажира?';

  @override
  String get gameSignScenario3_28_0Explanation =>
      'Да. Знак запрещает стоянку, но допускает остановку. Время, необходимое для посадки, высадки или погрузки, может превышать 5 минут.';

  @override
  String get gameSignScenario3_28_1Prompt =>
      'Можно оставить обычную машину на 20 минут, без посадки и погрузки?';

  @override
  String get gameSignScenario3_28_1Explanation =>
      'Нет. Это стоянка: остановка более 5 минут, не связанная с посадкой, высадкой или погрузкой (п. 1.2).';

  @override
  String get gameSignScenario3_28_2Prompt =>
      'Этот запрет действует на машину со знаком «Инвалид», имеющую право на льготу?';

  @override
  String get gameSignScenario3_28_2Explanation =>
      'Нет. При наличии права на бесплатную парковку и знака «Инвалид» предусмотрено исключение, включая перевозку таких инвалидов и детей-инвалидов.';

  @override
  String get gameSignScenario3_29_0Prompt =>
      'Знаки запрета по чётным и нечётным дням стоят с двух сторон. Можно парковаться с 21 до 24 часов?';

  @override
  String get gameSignScenario3_29_0Explanation =>
      'Да. При таком сочетании знаков с 21:00 до 24:00 — время перестановки, когда стоянка разрешена с обеих сторон.';

  @override
  String get gameSignScenario3_29_1Prompt =>
      'Этот знак запрещает остановку на 3 минуты для посадки пассажира?';

  @override
  String get gameSignScenario3_29_1Explanation =>
      'Нет. Он запрещает только стоянку по нечётным числам. Остановка разрешена.';

  @override
  String get gameSignScenario3_31_0Prompt =>
      'Этот знак отменяет ограничения обгона и скорости?';

  @override
  String get gameSignScenario3_31_0Explanation =>
      'Да. Он завершает действие знаков 3.16, 3.20, 3.22, 3.24 и 3.26–3.30.';

  @override
  String get gameSignScenario3_31_1Prompt =>
      'Этот знак отменяет сигналы светофора и разметку?';

  @override
  String get gameSignScenario3_31_1Explanation =>
      'Нет. Светофоры и разметка продолжают действовать.';

  @override
  String get gameSignScenario4_1_1_0Prompt =>
      'Знак стоит в начале участка. Можно повернуть направо во двор?';

  @override
  String get gameSignScenario4_1_1_0Explanation =>
      'Да. В начале участка знак действует до ближайшего перекрёстка, но разрешает поворот направо на прилегающую территорию.';

  @override
  String get gameSignScenario4_1_1_1Prompt =>
      'Знак стоит перед перекрёстком. Можно повернуть налево?';

  @override
  String get gameSignScenario4_1_1_1Explanation =>
      'Нет. На ближайшем пересечении проезжих частей разрешено только прямо.';

  @override
  String get gameSignScenario4_1_2_0Prompt =>
      'На ближайшем пересечении нужно повернуть направо?';

  @override
  String get gameSignScenario4_1_2_0Explanation =>
      'Да. Для обычного автомобиля знак разрешает только поворот направо.';

  @override
  String get gameSignScenario4_1_2_1Prompt =>
      'Можно ехать прямо на ближайшем пересечении?';

  @override
  String get gameSignScenario4_1_2_1Explanation =>
      'Нет. Знак разрешает только направо.';

  @override
  String get gameSignScenario4_1_3_0Prompt => 'Этот знак разрешает разворот?';

  @override
  String get gameSignScenario4_1_3_0Explanation =>
      'Да. Знак, разрешающий поворот налево, разрешает и разворот.';

  @override
  String get gameSignScenario4_1_3_1Prompt =>
      'Можно ехать прямо на ближайшем пересечении?';

  @override
  String get gameSignScenario4_1_3_1Explanation =>
      'Нет. Знак разрешает налево и разворот.';

  @override
  String get gameSignScenario4_1_4_0Prompt => 'Можно ехать прямо или направо?';

  @override
  String get gameSignScenario4_1_4_0Explanation =>
      'Да. Знак разрешает оба этих направления.';

  @override
  String get gameSignScenario4_1_4_1Prompt =>
      'Можно развернуться на ближайшем пересечении?';

  @override
  String get gameSignScenario4_1_4_1Explanation =>
      'Нет. Разрешены только прямо и направо.';

  @override
  String get gameSignScenario4_1_5_0Prompt =>
      'Можно развернуться из крайней левой полосы?';

  @override
  String get gameSignScenario4_1_5_0Explanation =>
      'Да. Разрешённый поворот налево допускает и разворот.';

  @override
  String get gameSignScenario4_1_5_1Prompt =>
      'Можно повернуть направо на ближайшем пересечении?';

  @override
  String get gameSignScenario4_1_5_1Explanation =>
      'Нет. Знак разрешает прямо, налево и разворот.';

  @override
  String get gameSignScenario4_2_1_0Prompt =>
      'Препятствие нужно объехать справа?';

  @override
  String get gameSignScenario4_2_1_0Explanation =>
      'Да. Объезд разрешён только с указанной стрелкой стороны.';

  @override
  String get gameSignScenario4_2_1_1Prompt =>
      'Можно объехать препятствие слева, если встречных нет?';

  @override
  String get gameSignScenario4_2_1_1Explanation =>
      'Нет. Отсутствие встречных не отменяет предписанную сторону объезда.';

  @override
  String get gameSignScenario4_3_0Prompt =>
      'По кругу нужно ехать в направлении стрелок?';

  @override
  String get gameSignScenario4_3_0Explanation =>
      'Да. Знак задаёт направление кругового движения.';

  @override
  String get gameSignScenario4_3_1Prompt =>
      'Можно ехать по кругу против стрелок?';

  @override
  String get gameSignScenario4_3_1Explanation =>
      'Нет. По кругу едут только в указанном стрелками направлении.';

  @override
  String get gameSignScenario4_6_0Prompt =>
      'Этот знак задаёт минимальную скорость?';

  @override
  String get gameSignScenario4_6_0Explanation =>
      'Да. Можно ехать с указанной или большей скоростью, соблюдая максимальный предел и безопасность.';

  @override
  String get gameSignScenario4_6_1Prompt =>
      'Этот знак задаёт максимальную скорость?';

  @override
  String get gameSignScenario4_6_1Explanation =>
      'Нет. Это минимальная скорость. Максимальную ограничивает знак 3.24.';

  @override
  String get gameSignScenario5_1_0Prompt =>
      'Легковое авто без прицепа: общий предел на автомагистрали 110 км/ч?';

  @override
  String get gameSignScenario5_1_0Explanation =>
      'Да. Общий предел для легкового автомобиля без прицепа — 110 км/ч. Знаки могут устанавливать другой предел (п. 10.3).';

  @override
  String get gameSignScenario5_1_1Prompt =>
      'Можно сдать назад на автомагистрали?';

  @override
  String get gameSignScenario5_1_1Explanation =>
      'Нет. На автомагистрали движение задним ходом запрещено (п. 16.1).';

  @override
  String get gameSignScenario5_1_2Prompt => 'Мопеду можно на автомагистраль?';

  @override
  String get gameSignScenario5_1_2Explanation =>
      'Нет. Движение мопедов по автомагистралям запрещено (п. 16.1).';

  @override
  String get gameSignScenario5_3_0Prompt =>
      'На этой дороге запрещено движение задним ходом?';

  @override
  String get gameSignScenario5_3_0Explanation =>
      'Да. На дороге для автомобилей действуют запреты раздела 16, как на автомагистрали (п. 16.3).';

  @override
  String get gameSignScenario5_3_1Prompt =>
      'Можно остановиться на обочине просто для отдыха?';

  @override
  String get gameSignScenario5_3_1Explanation =>
      'Нет. Преднамеренная остановка допускается на специальных площадках. Вынужденная остановка — отдельный случай.';

  @override
  String get gameSignScenario5_5_0Prompt =>
      'Можно сдать назад на односторонней дороге, если это безопасно и место разрешает?';

  @override
  String get gameSignScenario5_5_0Explanation =>
      'Да. Сам знак этого не запрещает. Нельзя сдавать назад на перекрёстках, переходах и в других местах из пп. 8.11–8.12.';

  @override
  String get gameSignScenario5_5_1Prompt =>
      'Можно развернуться и ехать против одностороннего движения?';

  @override
  String get gameSignScenario5_5_1Explanation =>
      'Нет. Это движение против установленного направления.';

  @override
  String get gameSignScenario5_5_2Prompt =>
      'В населённом пункте можно парковать легковое авто слева на односторонней дороге?';

  @override
  String get gameSignScenario5_5_2Explanation =>
      'Да. Для легкового автомобиля это разрешено, если нет других запретов (п. 12.1).';

  @override
  String get gameSignScenario5_14_1_0Prompt =>
      'Такси и школьному автобусу можно ехать по этой полосе?';

  @override
  String get gameSignScenario5_14_1_0Explanation =>
      'Да. Пункт 18.2 допускает легковые такси и школьные автобусы. Велосипедистам можно лишь по такой полосе справа.';

  @override
  String get gameSignScenario5_14_1_1Prompt =>
      'Можно обычной легковушке ехать по автобусной полосе вдоль дороги?';

  @override
  String get gameSignScenario5_14_1_1Explanation =>
      'Нет. Обычным автомобилям движение по полосе запрещено. Перестроение для поворота, въезд и высадка при прерывистой разметке — отдельные исключения.';

  @override
  String get gameSignScenario5_15_1_0Prompt =>
      'Стрелка налево из крайней левой полосы разрешает и разворот?';

  @override
  String get gameSignScenario5_15_1_0Explanation =>
      'Да. Разворот разрешается из крайней левой полосы, если знак разрешает из неё поворот налево.';

  @override
  String get gameSignScenario5_19_1_0Prompt =>
      'Без светофора нужно уступить пешеходу, который переходит вашу дорогу?';

  @override
  String get gameSignScenario5_19_1_0Explanation =>
      'Да. На нерегулируемом переходе нужно уступить переходящим или вступившим на проезжую часть пешеходам (п. 14.1).';

  @override
  String get gameSignScenario5_19_1_1Prompt =>
      'Можно сдать назад на пешеходном переходе?';

  @override
  String get gameSignScenario5_19_1_1Explanation =>
      'Нет. На переходе запрещены и движение задним ходом, и разворот (пп. 8.11–8.12).';

  @override
  String get gameSignScenario5_19_1_2Prompt =>
      'Можно остановиться за 3 м перед переходом?';

  @override
  String get gameSignScenario5_19_1_2Explanation =>
      'Нет. Остановка запрещена на переходе и ближе 5 м перед ним (п. 12.4).';

  @override
  String get gameSignScenario5_20_0Prompt =>
      'Знак показывает начало искусственной неровности?';

  @override
  String get gameSignScenario5_20_0Explanation =>
      'Да. Его устанавливают на ближайшей границе искусственной неровности.';

  @override
  String get gameSignScenario5_20_1Prompt =>
      'Перед искусственной неровностью обязательно остановиться?';

  @override
  String get gameSignScenario5_20_1Explanation =>
      'Нет. Знак не требует остановки. Выберите безопасную скорость для проезда.';

  @override
  String get gameSignScenario5_21_0Prompt =>
      'В жилой зоне пешеходы имеют преимущество?';

  @override
  String get gameSignScenario5_21_0Explanation =>
      'Да. Пешеходы могут идти и по тротуару, и по проезжей части, но не должны необоснованно мешать машинам (п. 17.1).';

  @override
  String get gameSignScenario5_21_1Prompt =>
      'Можно ехать по жилой зоне со скоростью 30 км/ч?';

  @override
  String get gameSignScenario5_21_1Explanation =>
      'Нет. В жилой зоне и во дворе предел — 20 км/ч (п. 10.2).';

  @override
  String get gameSignScenario5_21_2Prompt =>
      'Можно проехать жилую зону насквозь, чтобы сократить путь?';

  @override
  String get gameSignScenario5_21_2Explanation =>
      'Нет. Сквозное движение в жилой зоне запрещено (п. 17.2).';

  @override
  String get gameSignScenario5_23_1_0Prompt =>
      'После этого знака общий предел скорости — 60 км/ч?';

  @override
  String get gameSignScenario5_23_1_0Explanation =>
      'Да. Здесь начинаются правила для населённого пункта. Общий предел — 60 км/ч, если не установлен другой (п. 10.2).';

  @override
  String get gameSignScenario5_23_1_1Prompt =>
      'Можно сразу после этого знака ехать 90 км/ч без других знаков?';

  @override
  String get gameSignScenario5_23_1_1Explanation =>
      'Нет. Действует общий предел населённого пункта — 60 км/ч.';

  @override
  String get gameSignScenario5_25_0Prompt =>
      'Этот знак сам по себе вводит предел 60 км/ч?';

  @override
  String get gameSignScenario5_25_0Explanation =>
      'Нет. На обозначенной дороге правила для населённого пункта не действуют. Скорость зависит от дороги, машины и других знаков.';

  @override
  String get gameSignScenario5_25_1Prompt =>
      'Синий знак населённого пункта отменяет ранее установленный предел скорости?';

  @override
  String get gameSignScenario5_25_1Explanation =>
      'Нет. Сам знак не отменяет ограничение скорости, установленное другим знаком.';

  @override
  String get gameSignScenario6_2_0Prompt =>
      'Скорость на этом знаке — рекомендация?';

  @override
  String get gameSignScenario6_2_0Explanation =>
      'Да. Знак рекомендует скорость, но не отменяет обязательные ограничения и требование безопасности.';

  @override
  String get gameSignScenario6_2_1Prompt =>
      'Нужно обязательно ехать ровно с указанной скоростью?';

  @override
  String get gameSignScenario6_2_1Explanation =>
      'Нет. Это рекомендуемая, а не обязательная скорость.';

  @override
  String get gameSignScenario6_3_1_0Prompt =>
      'Этот знак обозначает место для разворота?';

  @override
  String get gameSignScenario6_3_1_0Explanation =>
      'Да. Здесь предусмотрено место для разворота.';

  @override
  String get gameSignScenario6_3_1_1Prompt =>
      'Можно здесь повернуть налево во двор?';

  @override
  String get gameSignScenario6_3_1_1Explanation =>
      'Нет. Знак обозначает место для разворота и запрещает поворот налево.';

  @override
  String get gameSignScenario6_4_0Prompt => 'Этот знак обозначает парковку?';

  @override
  String get gameSignScenario6_4_0Explanation =>
      'Да. Знак указывает парковку. Таблички могут уточнять, кому, когда и как разрешена стоянка.';

  @override
  String get gameSignScenario6_4_1Prompt =>
      'Перед этим знаком нужно обязательно остановиться?';

  @override
  String get gameSignScenario6_4_1Explanation =>
      'Нет. Он указывает место парковки, а не требует остановки.';

  @override
  String get gameSignScenario6_16_0Prompt =>
      'Знак показывает, где остановиться на запрещающий сигнал?';

  @override
  String get gameSignScenario6_16_0Explanation =>
      'Да. Остановитесь перед знаком при запрещающем сигнале светофора или регулировщика (п. 6.13).';

  @override
  String get gameSignScenario6_16_1Prompt =>
      'Светофор зелёный, регулировщика нет. Знак требует остановиться?';

  @override
  String get gameSignScenario6_16_1Explanation =>
      'Нет. Сам знак «Стоп-линия» при разрешающем сигнале не требует остановки.';

  @override
  String get gameSignScenario7_1_0Prompt =>
      'Знак указывает пункт первой медицинской помощи?';

  @override
  String get gameSignScenario7_1_0Explanation =>
      'Да. Он сообщает, где находится пункт первой медицинской помощи.';

  @override
  String get gameSignScenario7_1_1Prompt =>
      'Этот знак сам по себе ограничивает скорость до 20 км/ч?';

  @override
  String get gameSignScenario7_1_1Explanation =>
      'Нет. Знаки сервиса не вводят ограничений скорости.';

  @override
  String get gameSignScenario7_3_0Prompt => 'Знак указывает автозаправку?';

  @override
  String get gameSignScenario7_3_0Explanation =>
      'Да. Знак обозначает автозаправочную станцию.';

  @override
  String get gameSignScenario7_3_1Prompt =>
      'Этот знак даёт преимущество при выезде с заправки на дорогу?';

  @override
  String get gameSignScenario7_3_1Explanation =>
      'Нет. При выезде с прилегающей территории нужно уступить участникам движения на дороге (п. 8.3).';

  @override
  String get gameSignScenario8_1_1_0Prompt =>
      'Табличка показывает расстояние до объекта или начала ограничения?';

  @override
  String get gameSignScenario8_1_1_0Explanation =>
      'Да. Это расстояние от знака до опасного участка, объекта или места начала ограничения.';

  @override
  String get gameSignScenario8_1_1_1Prompt =>
      'Табличка показывает длину зоны действия знака?';

  @override
  String get gameSignScenario8_1_1_1Explanation =>
      'Нет. Длину зоны действия показывает табличка 8.2.1.';

  @override
  String get gameSignScenario8_2_1_0Prompt =>
      'Табличка показывает длину опасного участка или зоны действия?';

  @override
  String get gameSignScenario8_2_1_0Explanation =>
      'Да. Это протяжённость участка или зоны действия знака.';

  @override
  String get gameSignScenario8_2_1_1Prompt =>
      'Знак начнёт действовать только через указанное расстояние?';

  @override
  String get gameSignScenario8_2_1_1Explanation =>
      'Нет. Табличка показывает длину зоны, а не расстояние до её начала.';

  @override
  String get gameSignScenario8_2_3_0Prompt =>
      'Стрелка вниз означает конец запрета остановки или стоянки?';

  @override
  String get gameSignScenario8_2_3_0Explanation =>
      'Да. Она указывает конец зоны действия знаков 3.27–3.30.';

  @override
  String get gameSignScenario8_2_3_1Prompt =>
      'После этой таблички прежний запрет стоянки продолжается?';

  @override
  String get gameSignScenario8_2_3_1Explanation =>
      'Нет. Зона запрета заканчивается. Другие правила остановки и стоянки сохраняются.';

  @override
  String get gameSignScenario8_4_1_0Prompt =>
      'Табличка относится к грузовикам с разрешённой массой более 3,5 т?';

  @override
  String get gameSignScenario8_4_1_0Explanation =>
      'Да. В том числе к таким грузовикам с прицепом. Учитывают разрешённую максимальную, а не фактическую массу.';

  @override
  String get gameSignScenario8_4_1_1Prompt =>
      'Знак с этой табличкой действует на легковое авто?';

  @override
  String get gameSignScenario8_4_1_1Explanation =>
      'Нет. Табличка распространяет знак на грузовики с разрешённой максимальной массой более 3,5 т.';

  @override
  String get gameSignScenario8_4_3_0Prompt =>
      'Табличка относится к легковым авто и грузовикам до 3,5 т включительно?';

  @override
  String get gameSignScenario8_4_3_0Explanation =>
      'Да. Учитывается разрешённая максимальная масса грузовика.';

  @override
  String get gameSignScenario8_4_3_1Prompt =>
      'Знак с этой табличкой действует на автобус?';

  @override
  String get gameSignScenario8_4_3_1Explanation =>
      'Нет. Эта табличка относится к легковым автомобилям и грузовикам до 3,5 т включительно.';

  @override
  String get gameSignScenario8_17_0Prompt =>
      'Со знаком парковки табличка выделяет места для машин со знаком «Инвалид»?';

  @override
  String get gameSignScenario8_17_0Explanation =>
      'Да. Места предназначены для машин, имеющих право на такую парковку, с опознавательным знаком «Инвалид», в том числе перевозящих детей-инвалидов.';

  @override
  String get gameSignScenario8_17_1Prompt =>
      'Можно оставить здесь обычную машину без знака «Инвалид» на 10 минут?';

  @override
  String get gameSignScenario8_17_1Explanation =>
      'Нет. Эти парковочные места предназначены для машин со знаком «Инвалид», имеющих право на льготу.';

  @override
  String get gameSignScenario5_15_1_1Prompt =>
      'Из средней полосы стрелка только прямо. Можно повернуть налево?';

  @override
  String get gameSignScenario5_15_1_1Explanation =>
      'Нет. Из этой полосы разрешено только прямо. Для поворота нужно заранее занять подходящую полосу.';

  @override
  String get gamesBeta => 'Бета';

  @override
  String get gameCityTitle => 'Живой город';

  @override
  String gamesRunsAvailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count заезда доступны',
      many: '$count заездов доступны',
      few: '$count заезда доступны',
      one: '$count заезд доступен',
    );
    return '$_temp0';
  }

  @override
  String get avatarChoiceTitle => 'Аватар';

  @override
  String get avatarOwnPhoto => 'Моё фото';

  @override
  String get avatarCone => 'Дорожный конус';

  @override
  String get gasStationName => 'ГазЛукПук';

  @override
  String get gameRatingAllGames =>
      'Очки всех игр · мини-игры: от 5 верных ответов и 75% точности';

  @override
  String get paymentRegionUnavailable => 'Оплата недоступна в вашем регионе';

  @override
  String gameCurrentCombo(int count) {
    return 'Комбо $count';
  }

  @override
  String gameRatingResultsIn(int days, int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days дня',
      many: '$days дней',
      few: '$days дня',
      one: '$days день',
    );
    String _temp1 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours часа',
      many: '$hours часов',
      few: '$hours часа',
      one: '$hours час',
    );
    return 'Итоги рейтинга через: $_temp0 $_temp1';
  }

  @override
  String get languageSetting => 'Язык';

  @override
  String get languageRu => 'Русский';

  @override
  String get languageEn => 'English';

  @override
  String get languageKk => 'Қазақша';

  @override
  String get languageSystem => 'По умолчанию (системный)';

  @override
  String get interfaceSection => 'Интерфейс';

  @override
  String gameScoreDailyBudget(int earned, int limit) {
    return 'Сегодня в рейтинг: $earned / $limit';
  }
}
