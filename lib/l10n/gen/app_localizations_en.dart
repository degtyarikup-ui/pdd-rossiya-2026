// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get exam => 'Exam';

  @override
  String get topics => 'Topics';

  @override
  String get tickets => 'Tickets';

  @override
  String get passedQuestions => 'questions passed';

  @override
  String get passedTickets => 'tickets passed';

  @override
  String get examReadiness => 'Readiness for the exam';

  @override
  String get training => 'Training';

  @override
  String get pdd => 'Traffic Rules';

  @override
  String get signs => 'Road Signs';

  @override
  String get video => 'Tape';

  @override
  String get rules => 'Rules';

  @override
  String get signsAndMarkup => 'Signs and markings';

  @override
  String get settings => 'Settings';

  @override
  String get showHint => 'Show hint';

  @override
  String get comment => 'Comment';

  @override
  String get pddPoints => 'Traffic rules';

  @override
  String get myAnswers => 'My answers';

  @override
  String get favorites => 'Favorites';

  @override
  String get questionAddedToFavorites => 'Question added to Favorites';

  @override
  String get correctAnswer => 'Correct answer';

  @override
  String get yourAnswer => 'Your answer';

  @override
  String get ticket => 'ticket';

  @override
  String get question => 'question';

  @override
  String get goalText =>
      'As you learn, your progress will be completed. Your goal is to have all tickets filled!';

  @override
  String get goalTextTopics =>
      'As you learn, your progress will fill in. Your goal is to complete all topics!';

  @override
  String get confirmAnswer => 'Reply';

  @override
  String get nextQuestion => 'Next question';

  @override
  String get resetStats => 'Reset statistics';

  @override
  String get resetStatsConfirm =>
      'Are you sure you want to reset all statistics?';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get cancel => 'Cancel';

  @override
  String get back => 'Back';

  @override
  String get category => 'Category';

  @override
  String get categoryAB => 'AB';

  @override
  String get categoryCD => 'CD';

  @override
  String get sound => 'Sound';

  @override
  String get examPassed => 'Exam passed!';

  @override
  String get examFailed => 'Exam failed';

  @override
  String get continueSession => 'Continue';

  @override
  String continueSessionSubtitle(String title, int index, int total) {
    return '$title · question $index of $total';
  }

  @override
  String get continueSessionDismiss => 'Remove';

  @override
  String get reportQuestionTooltip => 'Report an error';

  @override
  String get reportQuestionBody =>
      'What\'s wrong with this question? A typo, wrong answer, wrong picture - write in your own words.';

  @override
  String get reportQuestionHint => 'For example: there is a typo in answer B';

  @override
  String get reportSend => 'Submit';

  @override
  String get reportSent => 'Thank you! Message sent';

  @override
  String get reportFailed => 'Failed to send. Check the Internet and try again';

  @override
  String get correctAnswers => 'Correct answers';

  @override
  String get wrongAnswers => 'Incorrect answers';

  @override
  String shareCardCorrectWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'correct',
      one: 'correct',
    );
    return '$_temp0';
  }

  @override
  String shareCardWrongWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mistakes',
      one: 'mistake',
    );
    return '$_temp0';
  }

  @override
  String get timeLeft => 'Time left';

  @override
  String get minutes => 'min';

  @override
  String get search => 'Search';

  @override
  String get noImage => 'No picture';

  @override
  String get mistakes => 'Mistakes';

  @override
  String progressRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count questions left until the exam',
      one: '$count question left until the exam',
    );
    return '$_temp0';
  }

  @override
  String get progressDone => 'passed';

  @override
  String get progressCorrect => 'correct';

  @override
  String get progressWrong => 'errors';

  @override
  String get progressTickets => 'tickets';

  @override
  String progressStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return '$_temp0';
  }

  @override
  String progressRecord(int count) {
    return 'Record $count';
  }

  @override
  String get progressAllDone => 'All questions passed correctly';

  @override
  String get homePassedQuestions => 'Questions passed';

  @override
  String get homeCorrectSolved => 'Correctly solved';

  @override
  String get homePassedTickets => 'Tickets handed in';

  @override
  String examQuestionsBadge(int count) {
    return '$count questions';
  }

  @override
  String examMinutesBadge(int count) {
    return '$count minutes';
  }

  @override
  String examReadinessPercent(int percent) {
    return '$percent% Readiness for the exam';
  }

  @override
  String get streakStart => 'Start the series';

  @override
  String get streakStartHint =>
      'Answer the question today - the light will light up';

  @override
  String streakDaysWord(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days in a row',
      one: 'day in a row',
    );
    return '$_temp0';
  }

  @override
  String get continueButton => 'Continue';

  @override
  String get streakBarrierLabel => 'Series';

  @override
  String get personalRecord => 'Personal best';

  @override
  String get streakMotivationRecord => 'New personal best! Keep it up.';

  @override
  String get streakMotivationFirst =>
      'The flame is lit. Check back tomorrow as the series continues to grow.';

  @override
  String get streakMotivationWeek =>
      'Great pace. Just a little more and it will be a whole week.';

  @override
  String get streakMotivationHabit =>
      'A whole week behind us. This is how a habit is formed.';

  @override
  String get streakMotivationMonth =>
      'A month without a break is the level of a real driving school student.';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get linkOpenFailed => 'Failed to open link';

  @override
  String get telegramOpenFailed => 'Failed to open Telegram';

  @override
  String get supportDeveloper => 'Support the developer';

  @override
  String get techSupport => 'Technical support';

  @override
  String get termsOfUse => 'Terms of Use';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get preparation => 'Preparation';

  @override
  String get feedbackSection => 'Feedback and sounds';

  @override
  String get confirmAnswerSetting => 'Confirm answer';

  @override
  String get confirmAnswerHint =>
      'Reply first is selected and then confirmed with a button.';

  @override
  String get hapticFeedback => 'Vibration';

  @override
  String get soundEffects => 'Sound effects';

  @override
  String get voiceOverQuestions => 'Voiceover questions';

  @override
  String get ticketCategorySetting => 'Category';

  @override
  String get ticketCategoryHint =>
      'A/B – cars and motorcycles, C/D – trucks and buses';

  @override
  String get dataSection => 'Data';

  @override
  String get resetStatsDetail =>
      'Data Progress on questions, exam results and favorite questions will be cleared.';

  @override
  String get reset => 'Reset';

  @override
  String get statsReset => 'Statistics reset';

  @override
  String get searchByQuestionOrTopic => 'Search by question or topic';

  @override
  String get emptyHere => 'Empty here for now';

  @override
  String get favoritesEmptyHint =>
      'Mark difficult questions with a star, and they will be collected in one place for quick review.';

  @override
  String get favoritesSearchEmpty =>
      'Nothing was found for this request. Try part of the question wording or the title of the topic.';

  @override
  String get favoritesSubtitle => 'Personal difficult questions';

  @override
  String favoritesCountHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count questions',
      one: '$count question',
    );
    return 'Currently in favorites: $_temp0. Use this mode as your personal study set before the exam.';
  }

  @override
  String get practiceAllFavorites => 'Go through all favorites';

  @override
  String get noTopic => 'No topic';

  @override
  String get favoriteQuestion => 'Favorite question';

  @override
  String ticketNumber(Object number) {
    return 'Ticket $number';
  }

  @override
  String get mistakesTitle => 'Working on errors';

  @override
  String get noMistakesYet => 'No errors yet';

  @override
  String get mistakesEmptyHint =>
      'When incorrect answers appear, here you can quickly repeat only weak questions.';

  @override
  String get repeatAllMistakes => 'Repeat all errors';

  @override
  String get mistakeReview => 'Error parsing';

  @override
  String get mistakeLabel => 'Error';

  @override
  String get nothingFoundTryAnother => 'Nothing found. Try another word.';

  @override
  String get pddSearchEmpty =>
      'Nothing found. Try the section number or keyword.';

  @override
  String get onboardingTitle => 'What are you planning to ride?';

  @override
  String get categoryABDesc => 'car, motorcycle';

  @override
  String get categoryCDDesc => 'truck, bus';

  @override
  String get ttsAnswerOptions => 'Answer options';

  @override
  String get ttsAnswer => 'Answer';

  @override
  String get noQuestions => 'No questions';

  @override
  String get hint => 'Hint';

  @override
  String questionOfTotal(int current, int total) {
    return 'Question $current of $total';
  }

  @override
  String get finishButton => 'Complete';

  @override
  String get hideHint => 'Hide hint';

  @override
  String get confirmAnswerButton => 'Confirm answer';

  @override
  String get myMistakes => 'My mistakes';

  @override
  String get noQuestionsToReview => 'No questions to review';

  @override
  String get examReview => 'Exam analysis';

  @override
  String get zoomIn => 'Enlarge';

  @override
  String get trainingResultPerfect => 'Not a single mistake - keep it up';

  @override
  String get trainingResultWithMistakes =>
      'Repeat the questions where you made mistakes';

  @override
  String get trainingRepeatMistakes => 'Repeat mistakes';

  @override
  String get done => 'Done';

  @override
  String get close => 'Close';

  @override
  String get next => 'Next';

  @override
  String get notAnsweredThisQuestion => 'You did not answer this question';

  @override
  String get description => 'Description';

  @override
  String get folkNameLabel => 'Common name';

  @override
  String get examAdditionalTitle => 'Additional questions';

  @override
  String examAdditionalQuestionOfTotal(int current, int total) {
    return 'Additional question $current of $total';
  }

  @override
  String get examResultTimeout => 'Time\'s up. Try again at a relaxed pace.';

  @override
  String get examResultPassed =>
      'Excellent result. You can secure it with tickets.';

  @override
  String get examResultFailed => 'Analyze mistakes and repeat weak points.';

  @override
  String valueOfTotal(int value, int total) {
    return '$value of $total';
  }

  @override
  String examFailedByBlock(int count) {
    return 'The ticket consists of 4 thematic blocks of 5 questions each. According to the traffic police regulations, $count errors in one block means the exam is not passed, even if there are no more than two errors in total.';
  }

  @override
  String get examAdditionalBlock => 'Additional block';

  @override
  String examAdditionalBlockValue(int count, int errors) {
    return '$count questions, errors: $errors';
  }

  @override
  String get examTimeSpent => 'Time spent';

  @override
  String get examMainBlockErrors => 'Errors in the main block';

  @override
  String get backToTraining => 'Return to training';

  @override
  String get share => 'Share';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String examShareText(
    String result,
    int correct,
    int total,
    String title,
    String url,
  ) {
    return '$result\nCorrect answers: $correct of $total\n\n$title\n$url';
  }

  @override
  String get supportChooseMethod => 'Select method';

  @override
  String get supportYoomoney => 'УMoney (card, wallet)';

  @override
  String get supportUsdt => 'USDT · TRC-20 Network (TRON)';

  @override
  String get supportUsdtWarning =>
      'Send only USDT over the TRC-20 Network (TRON). Transferring via another network will result in loss of funds.';

  @override
  String get copyAddress => 'Copy address';

  @override
  String get notifStreakTitle1 => 'The series is under threat';

  @override
  String get notifStreakBody1 => 'Practice and keep the light burning 🔥';

  @override
  String get notifStreakTitle2 => 'You\'re too close to throw';

  @override
  String get notifStreakBody2 => 'Every day brings you closer to the exam';

  @override
  String get notifStreakTitle3 => '🔥 The light is about to go out';

  @override
  String get notifStreakBody3 => 'Come in and answer a couple of questions';

  @override
  String get notifStreakTitle4 => 'The day is almost over';

  @override
  String get notifStreakBody4 => 'And there was no training today';

  @override
  String get notifStreakTitle5 => 'Your record is at risk';

  @override
  String get notifStreakBody5 => 'Save it in one go';

  @override
  String get notifStreakTitle6 => 'The exam is closer than it seems';

  @override
  String get notifStreakBody6 => 'Practice today';

  @override
  String get notifChannelName => 'Series reminders';

  @override
  String get notifChannelDesc => 'So you don\'t lose your practice streak';

  @override
  String get dataLoadError =>
      'Failed to load data. Check your connection and try again.';

  @override
  String get themeSetting => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeChoose => 'Theme';

  @override
  String get notificationsSetting => 'Daily reminder';

  @override
  String get notificationsHint =>
      'Every day at 20:00, unless the series is closed';

  @override
  String get game => 'Game';

  @override
  String get gameSimulator => '3D Simulator';

  @override
  String get gameLeaderboard => 'Leaderboard';

  @override
  String get gameScore => 'Score';

  @override
  String get gameDistance => 'Distance';

  @override
  String get gameOver => 'Race completed';

  @override
  String get gameRestart => 'Try again';

  @override
  String get gameExit => 'Exit';

  @override
  String get gameLeft => 'Left';

  @override
  String get gameRight => 'Right';

  @override
  String get gameGas => 'GAS';

  @override
  String get gameSpeedUnit => 'km/h';

  @override
  String get gameMeters => 'm';

  @override
  String get gameKilometers => 'km';

  @override
  String get gameSeconds => 's';

  @override
  String get gameMistake => 'Error';

  @override
  String get gameCorrect => 'Correct!';

  @override
  String get gameContinue => 'Continue driving';

  @override
  String get gameResolving => 'Gas - drive · arrows - steer';

  @override
  String get gameGarage => 'Select a car';

  @override
  String get gameCarHatch => 'Hatchback';

  @override
  String get gameCarSedan => 'Sedan';

  @override
  String get gameCarSuv => 'SUV';

  @override
  String get gameCarPickup => 'Pickup';

  @override
  String get gameCarCoupe => 'Coupe';

  @override
  String get gameCarWagon => 'Station wagon';

  @override
  String get gameCarCyber => 'Cybertruck';

  @override
  String get gamePaintRed => 'red';

  @override
  String get gamePaintBlue => 'blue';

  @override
  String get gamePaintGreen => 'green';

  @override
  String get gamePaintSand => 'sand';

  @override
  String get gamePaintWhite => 'white';

  @override
  String get gamePaintBlack => 'black';

  @override
  String get gamePaintSilver => 'silver';

  @override
  String get gamePaintOrange => 'orange';

  @override
  String get gamePaintPurple => 'purple';

  @override
  String get gamePaintTeal => 'turquoise';

  @override
  String get gamePaintYellow => 'yellow';

  @override
  String get gamePaintWine => 'burgundy';

  @override
  String get gamePaintGold => 'gold';

  @override
  String gameGarageNextCar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Next car in $count correct answers',
      one: 'Next car in $count correct answer',
    );
    return '$_temp0';
  }

  @override
  String get gameGaragePremiumCar =>
      'All cars and all colors are available with premium';

  @override
  String get gameRevealTitle => 'New car!';

  @override
  String get gameRevealTap => 'Click on the gate';

  @override
  String get gameRevealChoose => 'Select';

  @override
  String get gameRevealClose => 'Close';

  @override
  String get feedLockedTitle => 'The feed will open after logging in';

  @override
  String get feedLockedBody =>
      'Short cards with rules, signs and tips for every day. Sign in and your feed, activity series, and progress will be with you on any device.';

  @override
  String get feedSignIn => 'Login';

  @override
  String get gameSceneTitle => 'Weather and season';

  @override
  String get gameSceneWeather => 'Weather';

  @override
  String get gameSceneSeason => 'Time of year';

  @override
  String get gameSceneAuto => 'Auto';

  @override
  String get gameSceneClear => 'Clear';

  @override
  String get gameSceneOvercast => 'Cloudy';

  @override
  String get gameScenePrecip => 'Precipitation';

  @override
  String get gameSceneCalendar => 'By calendar';

  @override
  String get gameDebugUnlimitedFuel => 'Endless races';

  @override
  String get gameDebugUnlimitedFuelHint => 'Races are not spent';

  @override
  String get gameSceneSummer => 'Summer';

  @override
  String get gameSceneAutumn => 'Autumn';

  @override
  String get gameSceneWinter => 'Winter';

  @override
  String get gameCollision => 'Collision';

  @override
  String get gameOffroad => 'Curb · turn toward the road';

  @override
  String get gamePriorityViolation => 'You failed to give way';

  @override
  String get gameWrongManeuver =>
      'The maneuver does not correspond to the task';

  @override
  String get gameOncoming => 'Oncoming lane! Go back to the right';

  @override
  String get gameOneWayAgainst =>
      'One-way traffic! You are driving against traffic';

  @override
  String get gameRoadworksHit => 'You have entered a road work zone';

  @override
  String get gameCorrectAnswers => 'Correct answers';

  @override
  String gameAnswersOf(int correct, int total) {
    return '$correct from $total';
  }

  @override
  String get gameNoViolations => 'No violations';

  @override
  String get gameYourCar => 'Your car';

  @override
  String get gameSpeeding => 'Speeding';

  @override
  String get gameOvertakingProhibited => 'Overtaking is prohibited here';

  @override
  String get gameStopViolation => 'You have not stopped in the required place';

  @override
  String get gameRedLightViolation => 'Passing through a prohibitory signal';

  @override
  String get gameRailwayViolation =>
      'The crossing is closed - you cannot go around or exit';

  @override
  String get gamePedestrianYield => 'Give way to a pedestrian';

  @override
  String gameSpeedLimitLabel(int limit) {
    return 'Limit $limit km/h';
  }

  @override
  String get gameBrake => 'Brake · back when stopping';

  @override
  String get gameNewRecord => 'New record!';

  @override
  String gameBestScore(int score) {
    return 'Record $score';
  }

  @override
  String get gameGasHint => 'Press and hold - this is gas';

  @override
  String get gameWeeklyRating => 'Rating of the week';

  @override
  String get gameLobbyStart => 'Start race';

  @override
  String get gameLobbyContinue => 'Continue race';

  @override
  String get gameLobbyChangeCar => 'Change';

  @override
  String get gameLobbyRecord => 'Record';

  @override
  String get gameLobbyColour => 'Color';

  @override
  String get gameLobbyRating => 'Rating';

  @override
  String get gameLobbyColoursHint =>
      'New colors are unlocked for correct answers in the game';

  @override
  String get gameRatingHint =>
      'Points for all races for the week. The table shows the best 100.';

  @override
  String get gameRatingEmpty =>
      'No one has ridden this week yet. Be the first!';

  @override
  String get gameRatingUnavailable =>
      'Failed to load rating. Check the Internet.';

  @override
  String get gameRatingYou => 'You';

  @override
  String gameRatingRuns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs',
      one: '$count run',
    );
    return '$_temp0';
  }

  @override
  String gameRatingEndsIn(int days) {
    return 'Until the end of the week: $days days.';
  }

  @override
  String get gameAuthRequired => 'The game is available after logging in';

  @override
  String get gameAuthRequiredHint =>
      'Log in to accumulate points and participate in the weekly rating.';

  @override
  String get gameSignIn => 'Enter and drive';

  @override
  String gamePenaltyHint(int points) {
    return 'Violation: −$points points';
  }

  @override
  String get pddSettingsItem => 'Rules, signs and markings';

  @override
  String get gameLockedTitle => 'Ready to get behind the wheel?';

  @override
  String get gameLockedHint =>
      'Lively city, traffic police tickets right on the road and rating of the week. Sign in and let\'s go.';

  @override
  String get gameFuel => 'Arrivals';

  @override
  String get gameFuelUnlimited => 'Unlimited races';

  @override
  String get gameFuelEmptyTitle => 'Races have ended';

  @override
  String gameFuelRefillIn(String time) {
    return 'New race through $time';
  }

  @override
  String get gameFuelPremiumPitch => 'With a subscription, races do not end';

  @override
  String get gameFuelBuyPremium => 'Connect Premium';

  @override
  String get gameFuelWait => 'Wait';

  @override
  String get gameViolations => 'Violations';

  @override
  String get gameOverDescription =>
      'All race issues are over. Incorrect answers are already in the “Errors” - sort them out and try again.';

  @override
  String get gameYou => 'You';

  @override
  String get gameStop => 'STOP';

  @override
  String get gameLoading => 'Loading game';

  @override
  String get gameLoadError =>
      'Failed to continue the race. Restart the machine or return to the menu.';

  @override
  String get authSuccess => 'Login successful';

  @override
  String get authFailed => 'Login canceled or an error occurred. Try again.';

  @override
  String get authErrorCancelled =>
      'Login incomplete. Try selecting your account again.';

  @override
  String get authErrorProvider =>
      'Failed to obtain login information from the selected service.';

  @override
  String get authErrorNetwork =>
      'Failed to contact the server. Check your internet connection.';

  @override
  String get authErrorTimeout =>
      'The server did not respond on time. Try again.';

  @override
  String get authErrorAppKey =>
      'The server rejected this application build. Update the app from the store.';

  @override
  String get authErrorCredential =>
      'The server did not confirm the login. Try a different account or login method.';

  @override
  String get authErrorServer =>
      'Failed to complete login on the server. Please try again later.';

  @override
  String get authErrorResponse =>
      'Login failed. Refresh the page or restart the application and try again.';

  @override
  String get authSessionTemporary =>
      'Login completed. The phone was unable to save the session: after restarting, you will need to log in again.';

  @override
  String authDiagnosticCode(String code) {
    return 'Support code: $code';
  }

  @override
  String get authTitle => 'Account login';

  @override
  String get authDescription =>
      'Maintain premium access and statistics when changing or reinstalling your device';

  @override
  String get authAppleSafariHint =>
      'To log in with Face ID without entering data, open the site in Safari through the browser menu. The built-in browser may ask for your Apple email and password.';

  @override
  String get authApple => 'Continue with Apple ID';

  @override
  String get authGoogle => 'Continue with Google';

  @override
  String get authYandex => 'Continue with Yandex ID';

  @override
  String get authDebug => 'Test login (debug build)';

  @override
  String get accountDeleted => 'Account and data deleted';

  @override
  String get accountDeleteFailed =>
      'Failed to delete account. Check your connection and try again.';

  @override
  String get gameControlsTitle => 'Controls';

  @override
  String get gameControlsSimple => 'Simple controls';

  @override
  String get gameControlsSimpleHint =>
      'Arrows - change lanes and turns, the car drives itself';

  @override
  String get gameControlsFree => 'Free control';

  @override
  String get gameControlsFreeHint =>
      'Arrows turn the steering wheel while you hold them';

  @override
  String get gameTipGas => 'Hold the gas pedal - the car drives. Let go -';

  @override
  String get gameTipSteer =>
      'will stop smoothly. Hold the arrow - the car turns. If you let go, it will align itself in the lane';

  @override
  String get gameTipTurn =>
      'At the intersection, hold the arrow while the car turns, then let go - it will straighten itself';

  @override
  String get gameTipNext => 'Next';

  @override
  String get gameTipDone => 'Let\'s go';

  @override
  String get gamePause => 'Pause';

  @override
  String get gameLobbyControls => 'Control.';

  @override
  String gameRunProgress(int n, int total) {
    return 'Question $n from $total';
  }

  @override
  String get gameCorrectAnswer => 'Correct answer';

  @override
  String get gameTimeUp => 'Time\'s up';

  @override
  String gamePenaltyPoints(int points) {
    String _temp0 = intl.Intl.pluralLogic(
      points,
      locale: localeName,
      other: '−$points points',
      one: '−$points point',
    );
    return '$_temp0';
  }

  @override
  String gameRunMistakes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mistakes in run',
      one: '$count mistake in run',
    );
    return '$_temp0';
  }

  @override
  String get gameReviewMistakes => 'Troubleshoot errors';

  @override
  String get notifGameRunTitle => 'New race is ready';

  @override
  String get notifGameRunBody =>
      'Get behind the wheel: intersections from the exam tickets are waiting.';

  @override
  String get notifGameChannelName => 'Game';

  @override
  String get notifGameChannelDesc =>
      'When will the race be restored in the game';

  @override
  String gameRunMistakesButton(int count) {
    return 'Errors · $count';
  }

  @override
  String get gameCorrectShort => 'Correct';

  @override
  String gameRunsPill(int runs, int max) {
    return 'Races $runs from $max';
  }

  @override
  String get gameRunsUnlimitedPill => 'Races ∞';

  @override
  String get gameRunsTitle => 'Races';

  @override
  String gameRunsExplain(int questions, int max, int minutes) {
    return 'Race is $questions questions on the road. There are up to $max races left, each spent is returned in $minutes minutes.';
  }

  @override
  String gameRunsNextIn(String time) {
    return 'Next race via $time';
  }

  @override
  String get gameRunsFull => 'The stock is full - you can go';

  @override
  String get gameRunsPremium => 'With Premium races without restrictions';

  @override
  String get gameRunsGetPremium => 'Unlimited with Premium';

  @override
  String gameLobbyRunLength(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count questions',
      one: '$count question',
    );
    return '$_temp0';
  }

  @override
  String gameLobbyProgress(int n, int total) {
    return 'Passed $n from $total';
  }

  @override
  String get gameLobbyNewCar => 'NEW';

  @override
  String get gameRunsReady => 'Ready';

  @override
  String get gameRunsUntil => 'before arrival';

  @override
  String get gameUturn => 'U-turn';

  @override
  String get purchaseVerificationPending =>
      'The store reported the purchase, but access has not yet been confirmed. To check again, click “Restore” when the Internet is available.';

  @override
  String get notifAdminChannelName => 'Application messages';

  @override
  String get noticeAcknowledge => 'Clear';

  @override
  String get noticeOpen => 'Open';

  @override
  String get pushMessagesSetting => 'Application news';

  @override
  String get pushMessagesHint =>
      'Push notifications about updates and important events';

  @override
  String get gameKeyboardHint =>
      '↑ / W - gas · ↓ / S / space - brake · ← → / A D - turns';

  @override
  String get webQuarter => '3 months';

  @override
  String get webPaymentSoon => 'Payment coming soon';

  @override
  String get webPaymentInfo =>
      'Access to 3 months without auto-renewal. Payment on the site is not yet connected.';

  @override
  String get webWeek => '1 week';

  @override
  String get webPayButton => 'Pay via SBP';

  @override
  String get webPayInfo =>
      'One-time payment without auto-renewal. Premium will also open in the application on your phone - log in to it with the same account.';

  @override
  String get sbpPayInfoApp =>
      'One-time payment without auto-renewal. Premium will be activated immediately after payment and will work on all your devices with this account.';

  @override
  String get webPayTariffs => 'Tariffs';

  @override
  String get webPayEmailTitle => 'Payment through SBP';

  @override
  String get webPayEmailBody =>
      'We will connect payment through SBP in the coming days. Leave your email and we\'ll write you as soon as it\'s up and running. A check will come for her.';

  @override
  String get webPayEmailHint => 'Email';

  @override
  String get webPayEmailInvalid => 'Check your email address';

  @override
  String get webPayNotify => 'Notify me';

  @override
  String get webPayFailed => 'Failed to send, try again';

  @override
  String get webPayNeedsAccount =>
      'To pay, log in via Google, Yandex or Apple: test login does not accept payment.';

  @override
  String get webPayLiveBody =>
      'Indicate the mail for the check. Next, payment will open through SBP - using a QR code or in the bank’s application. Premium will be activated immediately after payment.';

  @override
  String get webPayProceed => 'Proceed to payment';

  @override
  String get webPaySuccess => 'Payment completed - Premium enabled. Thank you!';

  @override
  String get webPayPending =>
      'Payment is being processed - Premium will be activated automatically within a few minutes';

  @override
  String get webPayCanceled =>
      'Payment is not completed - money has not been debited';

  @override
  String webPaySaved(String email) {
    return 'Thank you! We will write to $email as soon as payment is received';
  }

  @override
  String premiumOneTimeInfo(String date) {
    return 'Access is valid until $date and is not automatically renewed.';
  }

  @override
  String get appUpdateTitle => 'Update has been released';

  @override
  String get appUpdateBody =>
      'The new version contains improvements and fixes. Please update the app to use them.';

  @override
  String appUpdateVersion(String version) {
    return 'Version $version';
  }

  @override
  String get appUpdateAction => 'Update';

  @override
  String get appUpdateLater => 'Later';

  @override
  String get appUpdateReadyTitle => 'Update ready';

  @override
  String get appUpdateReadyBody =>
      'New version has already been downloaded. Restart the application to install it.';

  @override
  String get appUpdateRestart => 'Restart';

  @override
  String get appUpdateOpenFailed =>
      'The update could not be opened. Please try again later.';

  @override
  String get profile => 'Profile';

  @override
  String get signInCardTitle => 'Login to your account';

  @override
  String get signInCardSubtitle => 'Save progress and premium';

  @override
  String get achievements => 'Achievements';

  @override
  String achievementsEarnedCount(int count, int total) {
    return '$count from $total';
  }

  @override
  String achievementLevelFormat(int level, int total) {
    return 'Lv. $level from $total';
  }

  @override
  String achievementSemanticsLabel(String title, int level, int total) {
    return '$title, level $level from $total';
  }

  @override
  String achievementProgressFormat(int current, int target) {
    return '$current from $target';
  }

  @override
  String get achievementTitleStreak => 'Without passes';

  @override
  String get achievementTitleCoverage => 'Erudite';

  @override
  String get achievementTitleTickets => 'Ticket by ticket';

  @override
  String get achievementTitleAttempts => 'Tireless';

  @override
  String get achievementTitleExams => 'Examiner';

  @override
  String get achievementTitleFlawless => 'Without single error';

  @override
  String get achievementTitleMistakes => 'Work on errors';

  @override
  String get achievementTitleGame => 'Racer';

  @override
  String get achievementDescStreak =>
      'Best series of days in a row with classes';

  @override
  String get achievementDescCoverage =>
      'Various questions solved from the database';

  @override
  String get achievementDescTickets => 'Passed tickets';

  @override
  String get achievementDescAttempts => 'Total answers, including repeat ones';

  @override
  String get achievementDescExams => 'Trial exams passed';

  @override
  String get achievementDescFlawless => 'Exams passed without errors';

  @override
  String get achievementDescMistakes =>
      'Questions in which I was wrong and then answered correctly';

  @override
  String get achievementDescGame => 'Best score for one race in the game';

  @override
  String get achievementTitleRank => 'Conqueror of the rating';

  @override
  String get achievementDescRank =>
      'Best place in the weekly rating of the game';

  @override
  String achievementRankTop(int count) {
    return 'Top-$count';
  }

  @override
  String get achievementRankFirst => '1st place';

  @override
  String get paywallSubscribe => 'Subscribe';

  @override
  String get paywallStoreGoogle => 'Google Play';

  @override
  String get paywallPayMethod => 'Payment method';

  @override
  String get paywallMethodSbp => 'SBP';

  @override
  String get paywallStoreApple => 'Apple ID settings';

  @override
  String get paywallTitle => 'Get ready without restrictions';

  @override
  String get paywallFreeNote => 'Tickets, exam and traffic rules remain free';

  @override
  String get paywallFeatureFeed => 'Unlimited feed of questions';

  @override
  String get paywallFeatureAi => 'Analysis of errors from AI';

  @override
  String get paywallFeatureVoice => 'Studio voice-over of tickets';

  @override
  String get paywallFeatureGame => 'Unlimited races in the game';

  @override
  String get paywallPlanQuarter => '3 months';

  @override
  String get paywallPlanWeek => '1 week';

  @override
  String get paywallEveryQuarter => 'every 3 months';

  @override
  String get paywallEveryWeek => 'every week';

  @override
  String get paywallBadgeBest => 'Profitable';

  @override
  String paywallRenewal(String store) {
    return 'Automatically renewed. You can cancel at any time in $store.';
  }

  @override
  String get paywallTerms => 'Terms';

  @override
  String get paywallPrivacy => 'Confidentiality';

  @override
  String get paywallRestore => 'Restore';

  @override
  String get gameSourceImage => 'Original question picture';

  @override
  String get gameSourceImageUnavailable =>
      'There is no picture in this question';

  @override
  String get navGames => 'Games';

  @override
  String get gameTrafficControllerTitle => 'Traffic cop';

  @override
  String get gameBestScoreLabel => 'Record';

  @override
  String get gameComboLabel => 'Max. combo';

  @override
  String get gameSolvedLabel => 'Solved';

  @override
  String get gameCombo => 'Combo';

  @override
  String get gameLives => 'Lives';

  @override
  String get gameActionStraight => 'Straight';

  @override
  String get gameActionRight => 'Right';

  @override
  String get gameActionLeft => 'Left';

  @override
  String get gameActionUTurn => 'U-turn';

  @override
  String get gameActionStand => 'Stand';

  @override
  String get gameVehicleCar => 'Car';

  @override
  String get gameVehicleTram => 'Tram';

  @override
  String get gameCameraOverview => 'Review';

  @override
  String get gameCameraDriver => 'Driving';

  @override
  String get gameOverTitle => 'Game over';

  @override
  String get gameOverNewRecord => 'New record!';

  @override
  String get gamePlayAgain => 'Play again';

  @override
  String get gameWrong => 'Violation!';

  @override
  String get gameWhistleNote =>
      'Inspector\'s whistle: movement in this direction is prohibited by the traffic controller\'s signal.';

  @override
  String get gameSignSwiperTitle => 'Sign-Swiper';

  @override
  String get gameSwipedLabel => 'Swipes';

  @override
  String get gameSignSwiperNext => 'Next sign';

  @override
  String get gameSignSwiperCategoryAll => 'All categories';

  @override
  String get gameMistakesReview => 'Error analysis';

  @override
  String get gameNoMistakes => 'Great job! Not a single mistake.';

  @override
  String get gameAccuracyLabel => 'Accuracy';

  @override
  String gameQuestionCategory(String category) {
    return 'Is this sign classified as “$category”?';
  }

  @override
  String gameQuestionName(String name) {
    return 'Is this sign called “$name”?';
  }

  @override
  String gameQuestionFolkName(String name) {
    return 'People call this sign “$name”?';
  }

  @override
  String get gameQuestionPriorityAdvantage =>
      'Do you have the right of way at this sign?';

  @override
  String get gameQuestionProhibitsEntry => 'Is entry allowed under this sign?';

  @override
  String get gameQuestionProhibitsOvertaking =>
      'Is overtaking of all vehicles allowed?';

  @override
  String get gameQuestionProhibitsParking =>
      'Is parking permitted under this sign?';

  @override
  String get gameQuestionProhibitsStopping =>
      'Is stopping under this sign allowed?';

  @override
  String gameComboStreak(int combo) {
    return 'COMBO x$combo!';
  }

  @override
  String get gameSoonBadge => 'Coming soon';

  @override
  String get gameRoundaboutTitle => 'Roundabout 3D';

  @override
  String get gameCrossroadsPriorityTitle => 'Cleared the intersection';

  @override
  String get gameCrossroadsPromptWhoGoesFirst => 'Who will pass first?';

  @override
  String gameCrossroadsPromptWhoGoesNext(int step) {
    return 'Who will pass next ($step-th)?';
  }

  @override
  String gameCrossroadsStepOf(int current, int total) {
    return 'Step $current from $total';
  }

  @override
  String get gameCrossroadsCollision => 'Accident! Irregularity';

  @override
  String get gameCrossroadsNextCrossroad => 'Next intersection';

  @override
  String get gameCrossroadsRepeatCrossroad => 'Try again';

  @override
  String get gameCrossroadsModeArcade => 'Arcade';

  @override
  String get gameCrossroadsModeTraining => 'Training';

  @override
  String gameCrossroadsSolvedCount(int count) {
    return 'Cleared: $count';
  }

  @override
  String get gameCrossroadsExplanationTitle =>
      'Analysis of the situation according to the Russian Federation traffic rules';

  @override
  String get gameCrossroadsCompleteTitle =>
      'The intersection has been cleared!';

  @override
  String get gameGestureRightArm => 'Arm forward';

  @override
  String get gameGestureHandsSides => 'Arms to the sides';

  @override
  String get gameGestureArmUp => 'Arm up';

  @override
  String get gameApproachLeft => 'Left side';

  @override
  String get gameApproachFront => 'Chest';

  @override
  String get gameApproachRight => 'Right side';

  @override
  String get gameApproachBack => 'Back';

  @override
  String gameSecondsLeft(int seconds) {
    return '$seconds with';
  }

  @override
  String get gameSignsLoadError => 'Failed to load signs';

  @override
  String get gameRetry => 'Repeat';

  @override
  String get gameRestartRound => 'Start over';

  @override
  String get gameSignYes => 'YES';

  @override
  String get gameSignNo => 'NO';

  @override
  String get gameSignCan => 'POSSIBLE';

  @override
  String get gameSignCannot => 'IT IS IMPOSSIBLE';

  @override
  String get gameUnderstood => 'I understand';

  @override
  String get gamePddOfficialText => 'Russian Traffic Regulations:';

  @override
  String get gamePromptWhereCanGo => 'Where can I go?';

  @override
  String get gameCaptionGesture => 'Gesture';

  @override
  String get gameCaptionApproach => 'Facing you';

  @override
  String get gameAnswerWrong => 'Incorrect';

  @override
  String get achievementTitleTrafficController => 'Signal Master';

  @override
  String get achievementDescTrafficController =>
      'Score 1000, 2500, 5000 and 7500 points in one game with the traffic controller.';

  @override
  String get achievementTitleSignSwiper => 'Sign Master';

  @override
  String get achievementDescSignSwiper =>
      'Score 1000, 2500, 5000 and 7500 points in a single game of Sign Swipe.';

  @override
  String get gameSignQuestionScope =>
      'There are no other signs or prohibitions';

  @override
  String get gameTrafficSignalQuestion => 'What does the signal allow?';

  @override
  String get gameTrafficHintButton => 'Hint';

  @override
  String get gameTrafficHintTitle => 'How to remember';

  @override
  String get gameTrafficHintPaused => 'Paused time';

  @override
  String get gameTrafficHintScope => 'Consider your lane, signs and markings.';

  @override
  String get gameTrafficHintArmUp =>
      'The stick is pointed upward - she tells everyone to stand.';

  @override
  String get gameTrafficHintForwardFront =>
      'If the stick points to your mouth, make a right turn.';

  @override
  String get gameTrafficHintForwardRight =>
      'If the stick points to the right, you have no right to drive.';

  @override
  String get gameTrafficHintForwardLeft =>
      'If the stick points to the left, ride like a queen.';

  @override
  String get gameTrafficHintBack => 'The back is a wall.';

  @override
  String get gameTrafficHintWall =>
      'The chest and back are a wall for the driver.';

  @override
  String get gameTrafficHintSide =>
      'The traffic controller stood sideways - the path was open straight and to the right.';

  @override
  String get gameTrafficHintTramLeft =>
      'The tram goes from arm to arm - only to the left.';

  @override
  String get gameTrafficHintTramStraight =>
      'The tram goes from arm to arm - only straight.';

  @override
  String get gameTrafficHintForbidden => 'Signal prohibits movement.';

  @override
  String gameTrafficHintAllowed(String directions) {
    return 'Signal allows: $directions.';
  }

  @override
  String get gameSignScenario1_1_0Prompt =>
      'A sign warning of a crossing with a barrier?';

  @override
  String get gameSignScenario1_1_0Explanation =>
      'Yes. Ahead is a railway crossing with a barrier.';

  @override
  String get gameSignScenario1_1_1Prompt =>
      'Is it possible to overtake 80 meters before the crossing?';

  @override
  String get gameSignScenario1_1_1Explanation =>
      'No. Overtaking is prohibited at a crossing and 100 m before it (clause 11.4).';

  @override
  String get gameSignScenario1_1_2Prompt =>
      'Can I park my car 30 meters from the crossing?';

  @override
  String get gameSignScenario1_1_2Explanation =>
      'No. Parking is prohibited closer than 50 m from the crossing (clause 12.5).';

  @override
  String get gameSignScenario1_2_0Prompt =>
      'Is there a crossing ahead without a barrier?';

  @override
  String get gameSignScenario1_2_0Explanation =>
      'Yes. The sign warns about crossing without a barrier.';

  @override
  String get gameSignScenario1_2_1Prompt =>
      'Can I turn around at the crossing?';

  @override
  String get gameSignScenario1_2_1Explanation =>
      'No. At the crossing, turning and reversing are prohibited (clauses 8.11–8.12).';

  @override
  String get gameSignScenario1_3_1_0Prompt =>
      'Is there only one railway track at the crossing?';

  @override
  String get gameSignScenario1_3_1_0Explanation =>
      'Yes. This sign indicates a crossing with one path, without a barrier.';

  @override
  String get gameSignScenario1_3_1_1Prompt =>
      'Is this sign placed 150–300 m before the crossing?';

  @override
  String get gameSignScenario1_3_1_1Explanation =>
      'No. Sign 1.3.1 is placed immediately before the crossing.';

  @override
  String get gameSignScenario1_5_0Prompt =>
      'The tram crosses the road outside the intersection, not from the depot. Should I give in?';

  @override
  String get gameSignScenario1_5_0Explanation =>
      'Yes. Outside the intersection, the tram has priority except for leaving the depot (clause 18.1).';

  @override
  String get gameSignScenario1_5_1Prompt =>
      'The tram leaves the depot. Should it give way to cars?';

  @override
  String get gameSignScenario1_5_1Explanation =>
      'Yes. When leaving the depot, the tram gives way to other vehicles (clause 18.1).';

  @override
  String get gameSignScenario1_6_0Prompt =>
      'Without a traffic light at an equivalent intersection, do you need to give way to the car on the right?';

  @override
  String get gameSignScenario1_6_0Explanation =>
      'Yes. At an uncontrolled intersection of equal significance, give way to cars on the right (clause 13.11).';

  @override
  String get gameSignScenario1_6_1Prompt =>
      'Is it possible to overtake at an equivalent intersection without a traffic light?';

  @override
  String get gameSignScenario1_6_1Explanation =>
      'No. At an uncontrolled intersection, overtaking is allowed only when driving on the main road (clause 11.4).';

  @override
  String get gameSignScenario1_7_0Prompt => 'Is there a roundabout ahead?';

  @override
  String get gameSignScenario1_7_0Explanation =>
      'Yes. A sign warns you when approaching a roundabout.';

  @override
  String get gameSignScenario1_7_1Prompt =>
      'Does the roundabout start right at this sign?';

  @override
  String get gameSignScenario1_7_1Explanation =>
      'No. This is a warning. The direction of movement on the circle itself is set by sign 4.3.';

  @override
  String get gameSignScenario1_11_1_0Prompt =>
      'Is it possible to turn around if the road is only visible at 70 m?';

  @override
  String get gameSignScenario1_11_1_0Explanation =>
      'No. To turn around, visibility must be at least 100 m in each direction (clause 8.11).';

  @override
  String get gameSignScenario1_11_1_1Prompt =>
      'Before a dangerous turn, should you choose a safe speed?';

  @override
  String get gameSignScenario1_11_1_1Explanation =>
      'Yes. The speed is chosen taking into account the turn and visibility of the road (clause 10.1).';

  @override
  String get gameSignScenario1_23_0Prompt =>
      'Could children suddenly come onto the road here?';

  @override
  String get gameSignScenario1_23_0Explanation =>
      'Yes. The sign warns of an area where children may appear on the road.';

  @override
  String get gameSignScenario1_23_1Prompt =>
      'Does this sign allow children to cross the road anywhere?';

  @override
  String get gameSignScenario1_23_1Explanation =>
      'No. The sign warns drivers, but does not change the rules for crossing the road.';

  @override
  String get gameSignScenario1_25_0Prompt =>
      'A temporary sign on a yellow background is more important than a permanent one if they conflict?';

  @override
  String get gameSignScenario1_25_0Explanation =>
      'Yes. If there is a contradiction between temporary and permanent signs, the temporary requirement is fulfilled.';

  @override
  String get gameSignScenario1_25_1Prompt =>
      'Do you have to stop at a road works sign?';

  @override
  String get gameSignScenario1_25_1Explanation =>
      'No. The sign itself does not require stopping. You need to take roadworks into account and choose a safe speed.';

  @override
  String get gameSignScenario2_1_0Prompt =>
      'Without a traffic light, do you have the right of way over a car with a second priority?';

  @override
  String get gameSignScenario2_1_0Explanation =>
      'Yes. At an uncontrolled intersection, the main road gives priority over the secondary one (clause 13.9).';

  @override
  String get gameSignScenario2_1_1Prompt =>
      'Is it possible to drive on a red light if you are on the main road?';

  @override
  String get gameSignScenario2_1_1Explanation =>
      'No. At a signalized intersection, you must follow the traffic lights (clause 6.15).';

  @override
  String get gameSignScenario2_1_2Prompt =>
      'Is it possible to park a car on the roadway of a main road outside a populated area?';

  @override
  String get gameSignScenario2_1_2Explanation =>
      'No. On such roads, parking on the roadway outside a populated area is prohibited (clause 12.5).';

  @override
  String get gameSignScenario2_2_0Prompt =>
      'Does the sign mark the end of the main road?';

  @override
  String get gameSignScenario2_2_0Explanation =>
      'Yes. The advantage that the “Main Road” sign gave is ending.';

  @override
  String get gameSignScenario2_2_1Prompt =>
      'Does this sign itself require you to stop?';

  @override
  String get gameSignScenario2_2_1Explanation =>
      'No. It revokes the main road status. The order of travel is determined by other signs and rules.';

  @override
  String get gameSignScenario2_3_1_0Prompt =>
      'Without a traffic light, should a car from the road you are crossing have to give way to you?';

  @override
  String get gameSignScenario2_3_1_0Explanation =>
      'Yes. The sign shows the intersection of the main road with the secondary one (clause 13.9).';

  @override
  String get gameSignScenario2_3_1_1Prompt =>
      'Without a traffic light, do you need to give way to a car on the right from a secondary road?';

  @override
  String get gameSignScenario2_3_1_1Explanation =>
      'No. You have the advantage: you are on the main road. The “interference from the right” rule does not apply here.';

  @override
  String get gameSignScenario2_4_0Prompt =>
      'Without a traffic light, do you need to give way to cars on the road you are crossing?';

  @override
  String get gameSignScenario2_4_0Explanation =>
      'Yes. The sign requires you to yield to cars on the road you are crossing. At the sign 8.13 - cars on the main road.';

  @override
  String get gameSignScenario2_4_1Prompt =>
      'The road is clear. Do you still need to stop at this sign?';

  @override
  String get gameSignScenario2_4_1Explanation =>
      'No. There is no mandatory stop if you are not disturbing anyone.';

  @override
  String get gameSignScenario2_4_2Prompt =>
      'Both are on the secondary road: you are straight, oncoming traffic is to the left. Should he give in?';

  @override
  String get gameSignScenario2_4_2Explanation =>
      'Yes. With equal priority, an oncoming car turning left gives way to the one going straight (clause 13.12).';

  @override
  String get gameSignScenario2_5_0Prompt =>
      'Do you need to stop before STOP, even if the road is clear?';

  @override
  String get gameSignScenario2_5_0Explanation =>
      'Yes. Stop in front of the stop line, and if there is none, in front of the edge of the roadway you are crossing. At a crossing without a stop line - in front of the sign.';

  @override
  String get gameSignScenario2_5_1Prompt =>
      'Is it possible to drive STOP without stopping if everything is clearly visible?';

  @override
  String get gameSignScenario2_5_1Explanation =>
      'No. The sign requires a complete stop even when the road is clear.';

  @override
  String get gameSignScenario2_6_0Prompt =>
      'The entry will interfere with the oncoming car. Should I give in?';

  @override
  String get gameSignScenario2_6_0Explanation =>
      'Yes. You must not drive into a narrow area if it will impede oncoming traffic.';

  @override
  String get gameSignScenario2_6_1Prompt =>
      'Does this sign give you an advantage over people you meet?';

  @override
  String get gameSignScenario2_6_1Explanation =>
      'No. Oncoming traffic has the right of way.';

  @override
  String get gameSignScenario2_7_0Prompt =>
      'Do you have an advantage in a narrow area?';

  @override
  String get gameSignScenario2_7_0Explanation =>
      'Yes. This sign gives you an advantage over oncoming cars.';

  @override
  String get gameSignScenario2_7_1Prompt =>
      'Does this sign give an oncoming car the right of way?';

  @override
  String get gameSignScenario2_7_1Explanation =>
      'No. Transport moving in your direction has priority.';

  @override
  String get gameSignScenario3_1_0Prompt =>
      'Is this sign prohibiting entry for regular taxis?';

  @override
  String get gameSignScenario3_1_0Explanation =>
      'Yes. Taxis and car sharing must comply with the ban. The exception is route transport.';

  @override
  String get gameSignScenario3_1_1Prompt =>
      'Can you move in just because you live behind the sign?';

  @override
  String get gameSignScenario3_1_1Explanation =>
      'No. There is no exception for residents. Do not confuse this sign with the \"No Traffic\" sign.';

  @override
  String get gameSignScenario3_1_2Prompt =>
      'Can a shuttle bus enter on its route?';

  @override
  String get gameSignScenario3_1_2Explanation =>
      'Yes. The prohibition of this sign does not apply to route vehicles.';

  @override
  String get gameSignScenario3_2_0Prompt =>
      'Can you drive to your home in the area of ​​this sign?';

  @override
  String get gameSignScenario3_2_0Explanation =>
      'Yes. Residents are allowed access to the house. You need to enter and exit at the intersection closest to it.';

  @override
  String get gameSignScenario3_2_1Prompt =>
      'Is it possible to drive through this zone in a regular car?';

  @override
  String get gameSignScenario3_2_1Explanation =>
      'No. The sign prohibits movement. The passage of residents and service vehicles are exceptions to access to the destination.';

  @override
  String get gameSignScenario3_2_2Prompt =>
      'A sign prohibits passage for a driver with a group I disability and a “Disabled” sign?';

  @override
  String get gameSignScenario3_2_2Explanation =>
      'No. The sign does not apply to cars of drivers with disabilities of groups I–II or those transporting them and disabled children with the “Disabled” sign.';

  @override
  String get gameSignScenario3_4_0Prompt =>
      'Is this sign prohibiting the movement of passenger cars?';

  @override
  String get gameSignScenario3_4_0Explanation =>
      'No. It restricts the movement of trucks, tractors and self-propelled vehicles.';

  @override
  String get gameSignScenario3_4_1Prompt =>
      'Is it possible for an ordinary truck with a permissible weight of 5 tons to pass this sign?';

  @override
  String get gameSignScenario3_4_1Explanation =>
      'Yes. The sign shown indicates a threshold of 8 tons. The permissible maximum weight of 5 tons does not exceed this.';

  @override
  String get gameSignScenario3_18_1_0Prompt =>
      'Is this sign prohibiting left turns?';

  @override
  String get gameSignScenario3_18_1_0Explanation =>
      'No. It only prohibits turning right at the nearest intersection of roadways.';

  @override
  String get gameSignScenario3_18_1_1Prompt =>
      'Can I turn right at the nearest intersection?';

  @override
  String get gameSignScenario3_18_1_1Explanation =>
      'No. Turning right at the nearest intersection is prohibited.';

  @override
  String get gameSignScenario3_18_2_0Prompt =>
      'Is this sign prohibiting U-turns?';

  @override
  String get gameSignScenario3_18_2_0Explanation =>
      'No. It prohibits a left turn, but does not itself prohibit a U-turn.';

  @override
  String get gameSignScenario3_18_2_1Prompt =>
      'Can I turn left at the nearest intersection?';

  @override
  String get gameSignScenario3_18_2_1Explanation =>
      'No. Turning left at the nearest intersection is prohibited.';

  @override
  String get gameSignScenario3_19_0Prompt =>
      'Is this sign prohibiting left turns?';

  @override
  String get gameSignScenario3_19_0Explanation =>
      'No. It only prohibits turning around.';

  @override
  String get gameSignScenario3_19_1Prompt =>
      'Can you turn around in the area where this sign is active?';

  @override
  String get gameSignScenario3_19_1Explanation => 'No. U-turn is prohibited.';

  @override
  String get gameSignScenario3_20_0Prompt =>
      'Does this sign allow overtaking of a slow-moving vehicle with the appropriate sign?';

  @override
  String get gameSignScenario3_20_0Explanation =>
      'Yes. Low-speed vehicles are an exception to the prohibition of sign 3.20. Other overtaking prohibitions and markings also need to be taken into account.';

  @override
  String get gameSignScenario3_20_1Prompt =>
      'Is it possible to overtake a regular passenger car if it travels only 25 km/h?';

  @override
  String get gameSignScenario3_20_1Explanation =>
      'No. Low speed does not make a passenger car a slow-moving vehicle.';

  @override
  String get gameSignScenario3_20_2Prompt =>
      'Does this sign allow overtaking of a motorcycle without a sidecar?';

  @override
  String get gameSignScenario3_20_2Explanation =>
      'Yes. Two-wheeled motorcycles without a side trailer are an exception to the prohibition of this sign.';

  @override
  String get gameSignScenario3_24_0Prompt =>
      'Is the number on the sign the maximum speed limit?';

  @override
  String get gameSignScenario3_24_0Explanation =>
      'Yes. You cannot go faster than this. If visibility is poor, the safe speed may be lower.';

  @override
  String get gameSignScenario3_24_1Prompt =>
      'Does this sign require you to drive no slower than the indicated number?';

  @override
  String get gameSignScenario3_24_1Explanation =>
      'No. This is a maximum speed limit, not a minimum speed limit.';

  @override
  String get gameSignScenario3_27_0Prompt =>
      'Can a regular car stop for a minute to let a passenger out?';

  @override
  String get gameSignScenario3_27_0Explanation =>
      'No. The sign prohibits stopping and parking. Disembarking a passenger is also a stop.';

  @override
  String get gameSignScenario3_27_1Prompt =>
      'Does the “Disabled Person” sign itself allow you to stop here?';

  @override
  String get gameSignScenario3_27_1Explanation =>
      'No. The benefit itself does not cancel the “No Stopping” sign. An exception may be indicated by plate 8.18.';

  @override
  String get gameSignScenario3_27_2Prompt =>
      'Can I park a regular car under this sign?';

  @override
  String get gameSignScenario3_27_2Explanation =>
      'No. The sign prohibits both stopping and parking.';

  @override
  String get gameSignScenario3_28_0Prompt =>
      'Can I stop to drop off a passenger?';

  @override
  String get gameSignScenario3_28_0Explanation =>
      'Yes. The sign prohibits parking, but allows stopping. The time required for boarding, disembarking or loading may exceed 5 minutes.';

  @override
  String get gameSignScenario3_28_1Prompt =>
      'Can I leave a regular car for 20 minutes, without getting in or loading?';

  @override
  String get gameSignScenario3_28_1Explanation =>
      'No. This is a parking: a stop for more than 5 minutes, not related to boarding, disembarking or loading (clause 1.2).';

  @override
  String get gameSignScenario3_28_2Prompt =>
      'Does this prohibition apply to a car with a \"Disabled Person\" sign that is eligible for the benefit?';

  @override
  String get gameSignScenario3_28_2Explanation =>
      'No. If you have the right to free parking and a “Disabled Person” sign, an exception is provided, including the transportation of such disabled people and children with disabilities.';

  @override
  String get gameSignScenario3_29_0Prompt =>
      'Prohibition signs on even and odd days are on both sides. Can I park from 21:00 to 24:00?';

  @override
  String get gameSignScenario3_29_0Explanation =>
      'Yes. With this combination of signs, from 21:00 to 24:00 is the time of reshuffling, when parking is allowed on both sides.';

  @override
  String get gameSignScenario3_29_1Prompt =>
      'Does this sign prohibit stopping for 3 minutes to pick up a passenger?';

  @override
  String get gameSignScenario3_29_1Explanation =>
      'No. It only prohibits parking on odd numbers. Stopping is permitted.';

  @override
  String get gameSignScenario3_31_0Prompt =>
      'Does this sign eliminate overtaking and speed restrictions?';

  @override
  String get gameSignScenario3_31_0Explanation =>
      'Yes. It completes the action of signs 3.16, 3.20, 3.22, 3.24 and 3.26–3.30.';

  @override
  String get gameSignScenario3_31_1Prompt =>
      'Does this sign override traffic signals and markings?';

  @override
  String get gameSignScenario3_31_1Explanation =>
      'No. Traffic lights and markings continue to operate.';

  @override
  String get gameSignScenario4_1_1_0Prompt =>
      'The sign is at the beginning of the site. Can I turn right into the courtyard?';

  @override
  String get gameSignScenario4_1_1_0Explanation =>
      'Yes. At the beginning of the site, the sign is valid until the nearest intersection, but allows a right turn into the adjacent territory.';

  @override
  String get gameSignScenario4_1_1_1Prompt =>
      'The sign is in front of the intersection. Can I turn left?';

  @override
  String get gameSignScenario4_1_1_1Explanation =>
      'No. At the nearest intersection of roadways, only straight traffic is allowed.';

  @override
  String get gameSignScenario4_1_2_0Prompt =>
      'Do you need to turn right at the next intersection?';

  @override
  String get gameSignScenario4_1_2_0Explanation =>
      'Yes. For a regular car, the sign only allows right turns.';

  @override
  String get gameSignScenario4_1_2_1Prompt =>
      'Can you go straight at the nearest intersection?';

  @override
  String get gameSignScenario4_1_2_1Explanation =>
      'No. The sign allows only to the right.';

  @override
  String get gameSignScenario4_1_3_0Prompt => 'Does this sign allow a U-turn?';

  @override
  String get gameSignScenario4_1_3_0Explanation =>
      'Yes. A sign permitting a left turn also permits a U-turn.';

  @override
  String get gameSignScenario4_1_3_1Prompt =>
      'Can you go straight at the nearest intersection?';

  @override
  String get gameSignScenario4_1_3_1Explanation =>
      'No. The sign allows left and U-turn.';

  @override
  String get gameSignScenario4_1_4_0Prompt => 'Can you go straight or right?';

  @override
  String get gameSignScenario4_1_4_0Explanation =>
      'Yes. The sign allows both of these directions.';

  @override
  String get gameSignScenario4_1_4_1Prompt =>
      'Can I turn around at the nearest intersection?';

  @override
  String get gameSignScenario4_1_4_1Explanation =>
      'No. Allowed only straight ahead and to the right.';

  @override
  String get gameSignScenario4_1_5_0Prompt =>
      'Is it possible to turn around from the leftmost lane?';

  @override
  String get gameSignScenario4_1_5_0Explanation =>
      'Yes. A permitted left turn also allows for a U-turn.';

  @override
  String get gameSignScenario4_1_5_1Prompt =>
      'Can I turn right at the nearest intersection?';

  @override
  String get gameSignScenario4_1_5_1Explanation =>
      'No. The sign allows straight ahead, left and U-turn.';

  @override
  String get gameSignScenario4_2_1_0Prompt =>
      'Do you need to go around an obstacle on the right?';

  @override
  String get gameSignScenario4_2_1_0Explanation =>
      'Yes. Detour is allowed only from the direction indicated by the arrow.';

  @override
  String get gameSignScenario4_2_1_1Prompt =>
      'Is it possible to go around an obstacle on the left if there are no oncoming people?';

  @override
  String get gameSignScenario4_2_1_1Explanation =>
      'No. The absence of oncoming traffic does not cancel the prescribed detour direction.';

  @override
  String get gameSignScenario4_3_0Prompt =>
      'Should you drive around in the direction of the arrows?';

  @override
  String get gameSignScenario4_3_0Explanation =>
      'Yes. The sign specifies the direction of the circular motion.';

  @override
  String get gameSignScenario4_3_1Prompt =>
      'Can you drive in a circle against the arrows?';

  @override
  String get gameSignScenario4_3_1Explanation =>
      'No. They drive in a circle only in the direction indicated by the arrows.';

  @override
  String get gameSignScenario4_6_0Prompt =>
      'Does this sign set the minimum speed?';

  @override
  String get gameSignScenario4_6_0Explanation =>
      'Yes. You can drive at the specified speed or higher while respecting the maximum limit and safety.';

  @override
  String get gameSignScenario4_6_1Prompt =>
      'Does this sign indicate the maximum speed?';

  @override
  String get gameSignScenario4_6_1Explanation =>
      'No. This is the minimum speed. The maximum is limited by the sign 3.24.';

  @override
  String get gameSignScenario5_1_0Prompt =>
      'Passenger car without trailer: general limit on the motorway 110 km/h?';

  @override
  String get gameSignScenario5_1_0Explanation =>
      'Yes. The general limit for a passenger car without a trailer is 110 km/h. Signs may set a different limit (clause 10.3).';

  @override
  String get gameSignScenario5_1_1Prompt => 'Can you reverse on the motorway?';

  @override
  String get gameSignScenario5_1_1Explanation =>
      'No. On the highway, reversing is prohibited (clause 16.1).';

  @override
  String get gameSignScenario5_1_2Prompt =>
      'Is a moped allowed on the motorway?';

  @override
  String get gameSignScenario5_1_2Explanation =>
      'No. The movement of mopeds on highways is prohibited (clause 16.1).';

  @override
  String get gameSignScenario5_3_0Prompt =>
      'Is reversing prohibited on this road?';

  @override
  String get gameSignScenario5_3_0Explanation =>
      'Yes. On the road for cars, the prohibitions of section 16 apply, as on the highway (clause 16.3).';

  @override
  String get gameSignScenario5_3_1Prompt =>
      'Can I stop on the side of the road just to relax?';

  @override
  String get gameSignScenario5_3_1Explanation =>
      'No. Intentional stopping is allowed in special areas. A forced stop is a separate case.';

  @override
  String get gameSignScenario5_5_0Prompt =>
      'Is it possible to back up on a one-way road if it is safe and the place allows it?';

  @override
  String get gameSignScenario5_5_0Explanation =>
      'Yes. The sign itself does not prohibit this. You cannot reverse at intersections, crossings and other places from paragraphs. 8.11–8.12.';

  @override
  String get gameSignScenario5_5_1Prompt =>
      'Can I turn around and drive against one-way traffic?';

  @override
  String get gameSignScenario5_5_1Explanation =>
      'No. This is movement against the established direction.';

  @override
  String get gameSignScenario5_5_2Prompt =>
      'In a populated area, is it possible to park a passenger car on the left on a one-way road?';

  @override
  String get gameSignScenario5_5_2Explanation =>
      'Yes. For a passenger car this is permitted if there are no other prohibitions (clause 12.1).';

  @override
  String get gameSignScenario5_14_1_0Prompt =>
      'Can taxis and school buses use this lane?';

  @override
  String get gameSignScenario5_14_1_0Explanation =>
      'Yes. Clause 18.2 allows passenger taxis and school buses. Cyclists can only use this lane on the right.';

  @override
  String get gameSignScenario5_14_1_1Prompt =>
      'Is it possible for an ordinary passenger car to drive along the bus lane along the road?';

  @override
  String get gameSignScenario5_14_1_1Explanation =>
      'No. Regular cars are prohibited from driving in the lane. Changing lanes for a turn, entering and disembarking with intermittent markings are certain exceptions.';

  @override
  String get gameSignScenario5_15_1_0Prompt =>
      'Does the left arrow from the leftmost lane also allow for a U-turn?';

  @override
  String get gameSignScenario5_15_1_0Explanation =>
      'Yes. A turn is allowed from the leftmost lane if the sign allows a left turn from it.';

  @override
  String get gameSignScenario5_19_1_0Prompt =>
      'Without a traffic light, do you need to give way to a pedestrian crossing your road?';

  @override
  String get gameSignScenario5_19_1_0Explanation =>
      'Yes. At an unregulated crossing, you must give way to pedestrians crossing or entering the roadway (clause 14.1).';

  @override
  String get gameSignScenario5_19_1_1Prompt =>
      'Can you back up at a pedestrian crossing?';

  @override
  String get gameSignScenario5_19_1_1Explanation =>
      'No. At the crossing, both reversing and turning around are prohibited (clauses 8.11–8.12).';

  @override
  String get gameSignScenario5_19_1_2Prompt =>
      'Can you stop 3 m before crossing?';

  @override
  String get gameSignScenario5_19_1_2Explanation =>
      'No. Stopping is prohibited at the crossing and closer than 5 m in front of it (clause 12.4).';

  @override
  String get gameSignScenario5_20_0Prompt =>
      'Does the sign indicate the start of a speed bump?';

  @override
  String get gameSignScenario5_20_0Explanation =>
      'Yes. It is installed at the nearest border of the artificial roughness.';

  @override
  String get gameSignScenario5_20_1Prompt =>
      'Do you have to stop before an artificial hump?';

  @override
  String get gameSignScenario5_20_1Explanation =>
      'No. The sign does not require stopping. Select a safe speed to travel.';

  @override
  String get gameSignScenario5_21_0Prompt =>
      'Do pedestrians have priority in residential areas?';

  @override
  String get gameSignScenario5_21_0Explanation =>
      'Yes. Pedestrians can walk on the sidewalk and along the roadway, but should not unreasonably interfere with cars (clause 17.1).';

  @override
  String get gameSignScenario5_21_1Prompt =>
      'Is it possible to drive through a residential area at a speed of 30 km/h?';

  @override
  String get gameSignScenario5_21_1Explanation =>
      'No. In residential areas and in the yard the limit is 20 km/h (clause 10.2).';

  @override
  String get gameSignScenario5_21_2Prompt =>
      'Is it possible to drive through a residential area to shorten the route?';

  @override
  String get gameSignScenario5_21_2Explanation =>
      'No. Through traffic in a residential area is prohibited (clause 17.2).';

  @override
  String get gameSignScenario5_23_1_0Prompt =>
      'After this sign the general speed limit is 60 km/h?';

  @override
  String get gameSignScenario5_23_1_0Explanation =>
      'Yes. This is where the rules for the locality begin. The general limit is 60 km/h, unless another is established (clause 10.2).';

  @override
  String get gameSignScenario5_23_1_1Prompt =>
      'Is it possible to drive 90 km/h immediately after this sign without other signs?';

  @override
  String get gameSignScenario5_23_1_1Explanation =>
      'No. The general locality limit is 60 km/h.';

  @override
  String get gameSignScenario5_25_0Prompt =>
      'Does this sign itself introduce a 60 km/h limit?';

  @override
  String get gameSignScenario5_25_0Explanation =>
      'No. On a designated road, the rules for a populated area do not apply. Speed ​​depends on the road, car and other signs.';

  @override
  String get gameSignScenario5_25_1Prompt =>
      'Does a blue populated area sign override a previously set speed limit?';

  @override
  String get gameSignScenario5_25_1Explanation =>
      'No. The sign itself does not override the speed limit set by another sign.';

  @override
  String get gameSignScenario6_2_0Prompt =>
      'Is the speed at this sign a recommendation?';

  @override
  String get gameSignScenario6_2_0Explanation =>
      'Yes. The sign recommends speed, but does not cancel mandatory restrictions and safety requirements.';

  @override
  String get gameSignScenario6_2_1Prompt =>
      'Is it necessary to drive exactly at the specified speed?';

  @override
  String get gameSignScenario6_2_1Explanation =>
      'No. This is a recommended speed, not a required speed.';

  @override
  String get gameSignScenario6_3_1_0Prompt =>
      'Does this sign indicate a turning point?';

  @override
  String get gameSignScenario6_3_1_0Explanation =>
      'Yes. There is room for a turn here.';

  @override
  String get gameSignScenario6_3_1_1Prompt =>
      'Can I turn left into the courtyard here?';

  @override
  String get gameSignScenario6_3_1_1Explanation =>
      'No. The sign marks the place for a U-turn and prohibits turning left.';

  @override
  String get gameSignScenario6_4_0Prompt => 'Does this sign indicate parking?';

  @override
  String get gameSignScenario6_4_0Explanation =>
      'Yes. The sign indicates parking. Signs may clarify who, when and how parking is allowed.';

  @override
  String get gameSignScenario6_4_1Prompt =>
      'Do you have to stop before this sign?';

  @override
  String get gameSignScenario6_4_1Explanation =>
      'No. It indicates where to park, rather than requiring you to stop.';

  @override
  String get gameSignScenario6_16_0Prompt =>
      'Does the sign show where to stop at a traffic signal?';

  @override
  String get gameSignScenario6_16_0Explanation =>
      'Yes. Stop in front of the sign when there is a prohibitory signal from a traffic light or a traffic controller (section 6.13).';

  @override
  String get gameSignScenario6_16_1Prompt =>
      'The traffic light is green, there is no traffic controller. Does the sign require you to stop?';

  @override
  String get gameSignScenario6_16_1Explanation =>
      'No. The “Stop Line” sign itself does not require a stop when the permitting signal is given.';

  @override
  String get gameSignScenario7_1_0Prompt =>
      'Does the sign indicate a first aid station?';

  @override
  String get gameSignScenario7_1_0Explanation =>
      'Yes. He tells you where the first aid station is.';

  @override
  String get gameSignScenario7_1_1Prompt =>
      'This sign itself limits the speed to 20 km/h?';

  @override
  String get gameSignScenario7_1_1Explanation =>
      'No. Service signs do not impose speed limits.';

  @override
  String get gameSignScenario7_3_0Prompt =>
      'Does the sign indicate a gas station?';

  @override
  String get gameSignScenario7_3_0Explanation =>
      'Yes. The sign indicates a gas station.';

  @override
  String get gameSignScenario7_3_1Prompt =>
      'Does this sign give you priority when leaving the gas station on the road?';

  @override
  String get gameSignScenario7_3_1Explanation =>
      'No. When leaving the adjacent territory, you must yield to road users (clause 8.3).';

  @override
  String get gameSignScenario8_1_1_0Prompt =>
      'Does the sign indicate the distance to the object or the beginning of the restriction?';

  @override
  String get gameSignScenario8_1_1_0Explanation =>
      'Yes. This is the distance from the sign to the dangerous area, object or place where the restriction begins.';

  @override
  String get gameSignScenario8_1_1_1Prompt =>
      'Does the sign indicate the length of the sign\'s coverage area?';

  @override
  String get gameSignScenario8_1_1_1Explanation =>
      'No. The length of the coverage area is indicated by plate 8.2.1.';

  @override
  String get gameSignScenario8_2_1_0Prompt =>
      'Does the sign indicate the length of the hazardous area or coverage area?';

  @override
  String get gameSignScenario8_2_1_0Explanation =>
      'Yes. This is the length of the area or area of ​​the sign.';

  @override
  String get gameSignScenario8_2_1_1Prompt =>
      'Will the sign begin to operate only after the specified distance?';

  @override
  String get gameSignScenario8_2_1_1Explanation =>
      'No. The plate shows the length of the zone, not the distance to its beginning.';

  @override
  String get gameSignScenario8_2_3_0Prompt =>
      'Does the down arrow mean the end of the stop or stop prohibition?';

  @override
  String get gameSignScenario8_2_3_0Explanation =>
      'Yes. It indicates the end of the coverage area of ​​signs 3.27–3.30.';

  @override
  String get gameSignScenario8_2_3_1Prompt =>
      'Does the previous parking ban continue after this sign?';

  @override
  String get gameSignScenario8_2_3_1Explanation =>
      'No. The restricted zone ends. Other stopping and parking rules remain the same.';

  @override
  String get gameSignScenario8_4_1_0Prompt =>
      'Does the plate apply to trucks with a permissible weight of more than 3.5 tons?';

  @override
  String get gameSignScenario8_4_1_0Explanation =>
      'Yes. Including such trucks with trailers. The permitted maximum weight is taken into account, not the actual weight.';

  @override
  String get gameSignScenario8_4_1_1Prompt =>
      'Does this sign apply to passenger cars?';

  @override
  String get gameSignScenario8_4_1_1Explanation =>
      'No. The plate applies the sign to trucks with a permissible maximum weight of more than 3.5 tons.';

  @override
  String get gameSignScenario8_4_3_0Prompt =>
      'Does the plate apply to passenger cars and trucks up to 3.5 tons inclusive?';

  @override
  String get gameSignScenario8_4_3_0Explanation =>
      'Yes. The permissible maximum weight of the truck is taken into account.';

  @override
  String get gameSignScenario8_4_3_1Prompt => 'Does this sign apply to a bus?';

  @override
  String get gameSignScenario8_4_3_1Explanation =>
      'No. This plate applies to cars and trucks up to and including 3.5 tonnes.';

  @override
  String get gameSignScenario8_17_0Prompt =>
      'With a parking sign, does the sign designate spaces for cars with a “Disabled” sign?';

  @override
  String get gameSignScenario8_17_0Explanation =>
      'Yes. The spaces are intended for cars entitled to such parking, with the identification sign “Disabled”, including those transporting disabled children.';

  @override
  String get gameSignScenario8_17_1Prompt =>
      'Can I leave a regular car here without a “Disabled” sign for 10 minutes?';

  @override
  String get gameSignScenario8_17_1Explanation =>
      'No. These parking spaces are intended for cars with a \"Disabled Person\" sign that are eligible for benefits.';

  @override
  String get gameSignScenario5_15_1_1Prompt =>
      'From the middle lane, the arrow only goes straight. Can I turn left?';

  @override
  String get gameSignScenario5_15_1_1Explanation =>
      'No. Only straight ahead is allowed from this lane. To turn, you need to take a suitable lane in advance.';

  @override
  String get gamesBeta => 'Beta';

  @override
  String get gameCityTitle => 'Living City';

  @override
  String gamesRunsAvailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs available',
      one: '$count run available',
    );
    return '$_temp0';
  }

  @override
  String get avatarChoiceTitle => 'Avatar';

  @override
  String get avatarOwnPhoto => 'My photo';

  @override
  String get avatarCone => 'Traffic cone';

  @override
  String get gasStationName => 'GazLukPuk';

  @override
  String get gameRatingAllGames =>
      'Points for all games · mini-games: from 5 correct answers and 75% accuracy';

  @override
  String get paymentRegionUnavailable =>
      'Payment is not available in your region';

  @override
  String gameCurrentCombo(int count) {
    return 'Combo $count';
  }

  @override
  String gameRatingResultsIn(int days, int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '$days day',
    );
    String _temp1 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '$hours hour',
    );
    return 'Leaderboard ends in: $_temp0 $_temp1';
  }

  @override
  String get languageSetting => 'Language';

  @override
  String get languageRu => 'Русский';

  @override
  String get languageEn => 'English';

  @override
  String get languageKk => 'Қазақша';

  @override
  String get languageSystem => 'System default';

  @override
  String get interfaceSection => 'Interface';
}
