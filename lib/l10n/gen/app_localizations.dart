import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ru.dart';
import 'app_localizations_sr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ru'),
    Locale('sr'),
  ];

  /// No description provided for @exam.
  ///
  /// In ru, this message translates to:
  /// **'Экзамен'**
  String get exam;

  /// No description provided for @topics.
  ///
  /// In ru, this message translates to:
  /// **'Темы'**
  String get topics;

  /// No description provided for @tickets.
  ///
  /// In ru, this message translates to:
  /// **'Билеты'**
  String get tickets;

  /// No description provided for @passedQuestions.
  ///
  /// In ru, this message translates to:
  /// **'пройдено вопросов'**
  String get passedQuestions;

  /// No description provided for @passedTickets.
  ///
  /// In ru, this message translates to:
  /// **'билетов пройдено'**
  String get passedTickets;

  /// No description provided for @examReadiness.
  ///
  /// In ru, this message translates to:
  /// **'Готовность к экзамену'**
  String get examReadiness;

  /// No description provided for @training.
  ///
  /// In ru, this message translates to:
  /// **'Обучение'**
  String get training;

  /// No description provided for @pdd.
  ///
  /// In ru, this message translates to:
  /// **'ПДД'**
  String get pdd;

  /// No description provided for @signs.
  ///
  /// In ru, this message translates to:
  /// **'Знаки'**
  String get signs;

  /// No description provided for @video.
  ///
  /// In ru, this message translates to:
  /// **'Лента'**
  String get video;

  /// No description provided for @rules.
  ///
  /// In ru, this message translates to:
  /// **'Правила'**
  String get rules;

  /// No description provided for @signsAndMarkup.
  ///
  /// In ru, this message translates to:
  /// **'Знаки и разметка'**
  String get signsAndMarkup;

  /// No description provided for @settings.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settings;

  /// No description provided for @showHint.
  ///
  /// In ru, this message translates to:
  /// **'Показать подсказку'**
  String get showHint;

  /// No description provided for @comment.
  ///
  /// In ru, this message translates to:
  /// **'Комментарий'**
  String get comment;

  /// No description provided for @pddPoints.
  ///
  /// In ru, this message translates to:
  /// **'Пункты ПДД'**
  String get pddPoints;

  /// No description provided for @myAnswers.
  ///
  /// In ru, this message translates to:
  /// **'Мои ответы'**
  String get myAnswers;

  /// No description provided for @favorites.
  ///
  /// In ru, this message translates to:
  /// **'Избранное'**
  String get favorites;

  /// No description provided for @questionAddedToFavorites.
  ///
  /// In ru, this message translates to:
  /// **'Вопрос добавлен в Избранное'**
  String get questionAddedToFavorites;

  /// No description provided for @correctAnswer.
  ///
  /// In ru, this message translates to:
  /// **'Правильный ответ'**
  String get correctAnswer;

  /// No description provided for @yourAnswer.
  ///
  /// In ru, this message translates to:
  /// **'Ваш ответ'**
  String get yourAnswer;

  /// No description provided for @ticket.
  ///
  /// In ru, this message translates to:
  /// **'билет'**
  String get ticket;

  /// No description provided for @question.
  ///
  /// In ru, this message translates to:
  /// **'вопрос'**
  String get question;

  /// No description provided for @goalText.
  ///
  /// In ru, this message translates to:
  /// **'По мере обучения ваш прогресс будет заполняться. Ваша цель – все билеты должны быть заполнены!'**
  String get goalText;

  /// No description provided for @goalTextTopics.
  ///
  /// In ru, this message translates to:
  /// **'По мере обучения ваш прогресс будет заполняться. Ваша цель – все темы должны быть заполнены!'**
  String get goalTextTopics;

  /// No description provided for @confirmAnswer.
  ///
  /// In ru, this message translates to:
  /// **'Ответить'**
  String get confirmAnswer;

  /// No description provided for @nextQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Следующий вопрос'**
  String get nextQuestion;

  /// No description provided for @resetStats.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить статистику'**
  String get resetStats;

  /// No description provided for @resetStatsConfirm.
  ///
  /// In ru, this message translates to:
  /// **'Вы уверены, что хотите сбросить всю статистику?'**
  String get resetStatsConfirm;

  /// No description provided for @yes.
  ///
  /// In ru, this message translates to:
  /// **'Да'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In ru, this message translates to:
  /// **'Нет'**
  String get no;

  /// No description provided for @cancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancel;

  /// No description provided for @back.
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get back;

  /// No description provided for @category.
  ///
  /// In ru, this message translates to:
  /// **'Категория'**
  String get category;

  /// No description provided for @categoryAB.
  ///
  /// In ru, this message translates to:
  /// **'AB'**
  String get categoryAB;

  /// No description provided for @categoryCD.
  ///
  /// In ru, this message translates to:
  /// **'CD'**
  String get categoryCD;

  /// No description provided for @sound.
  ///
  /// In ru, this message translates to:
  /// **'Звук'**
  String get sound;

  /// No description provided for @examPassed.
  ///
  /// In ru, this message translates to:
  /// **'Экзамен сдан!'**
  String get examPassed;

  /// No description provided for @examFailed.
  ///
  /// In ru, this message translates to:
  /// **'Экзамен не сдан'**
  String get examFailed;

  /// No description provided for @continueSession.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get continueSession;

  /// No description provided for @continueSessionSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'{title} · вопрос {index} из {total}'**
  String continueSessionSubtitle(String title, int index, int total);

  /// No description provided for @continueSessionDismiss.
  ///
  /// In ru, this message translates to:
  /// **'Убрать'**
  String get continueSessionDismiss;

  /// No description provided for @reportQuestionTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Сообщить об ошибке'**
  String get reportQuestionTooltip;

  /// No description provided for @reportQuestionBody.
  ///
  /// In ru, this message translates to:
  /// **'Что не так с этим вопросом? Опечатка, неверный ответ, не та картинка — напишите своими словами.'**
  String get reportQuestionBody;

  /// No description provided for @reportQuestionHint.
  ///
  /// In ru, this message translates to:
  /// **'Например: в ответе Б опечатка'**
  String get reportQuestionHint;

  /// No description provided for @reportSend.
  ///
  /// In ru, this message translates to:
  /// **'Отправить'**
  String get reportSend;

  /// No description provided for @reportSent.
  ///
  /// In ru, this message translates to:
  /// **'Спасибо! Сообщение отправлено'**
  String get reportSent;

  /// No description provided for @reportFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отправить. Проверьте интернет и попробуйте ещё раз'**
  String get reportFailed;

  /// No description provided for @correctAnswers.
  ///
  /// In ru, this message translates to:
  /// **'Правильных ответов'**
  String get correctAnswers;

  /// No description provided for @wrongAnswers.
  ///
  /// In ru, this message translates to:
  /// **'Неправильных ответов'**
  String get wrongAnswers;

  /// No description provided for @shareCardCorrectWord.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{правильный} few{правильных} many{правильных} other{правильных}}'**
  String shareCardCorrectWord(int count);

  /// No description provided for @shareCardWrongWord.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{ошибка} few{ошибки} many{ошибок} other{ошибок}}'**
  String shareCardWrongWord(int count);

  /// No description provided for @timeLeft.
  ///
  /// In ru, this message translates to:
  /// **'Осталось времени'**
  String get timeLeft;

  /// No description provided for @minutes.
  ///
  /// In ru, this message translates to:
  /// **'мин'**
  String get minutes;

  /// No description provided for @search.
  ///
  /// In ru, this message translates to:
  /// **'Поиск'**
  String get search;

  /// No description provided for @noImage.
  ///
  /// In ru, this message translates to:
  /// **'Без картинки'**
  String get noImage;

  /// No description provided for @mistakes.
  ///
  /// In ru, this message translates to:
  /// **'Ошибки'**
  String get mistakes;

  /// No description provided for @progressRemaining.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{До экзамена остался {count} вопрос} few{До экзамена осталось {count} вопроса} many{До экзамена осталось {count} вопросов} other{До экзамена осталось {count} вопросов}}'**
  String progressRemaining(int count);

  /// No description provided for @progressDone.
  ///
  /// In ru, this message translates to:
  /// **'пройдено'**
  String get progressDone;

  /// No description provided for @progressCorrect.
  ///
  /// In ru, this message translates to:
  /// **'верно'**
  String get progressCorrect;

  /// No description provided for @progressWrong.
  ///
  /// In ru, this message translates to:
  /// **'ошибок'**
  String get progressWrong;

  /// No description provided for @progressTickets.
  ///
  /// In ru, this message translates to:
  /// **'билетов'**
  String get progressTickets;

  /// No description provided for @progressStreakDays.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} день} few{{count} дня} many{{count} дней} other{{count} дней}}'**
  String progressStreakDays(int count);

  /// No description provided for @progressRecord.
  ///
  /// In ru, this message translates to:
  /// **'Рекорд {count}'**
  String progressRecord(int count);

  /// No description provided for @progressAllDone.
  ///
  /// In ru, this message translates to:
  /// **'Все вопросы пройдены верно'**
  String get progressAllDone;

  /// No description provided for @homePassedQuestions.
  ///
  /// In ru, this message translates to:
  /// **'Пройдено вопросов'**
  String get homePassedQuestions;

  /// No description provided for @homeCorrectSolved.
  ///
  /// In ru, this message translates to:
  /// **'Верно решено'**
  String get homeCorrectSolved;

  /// No description provided for @homePassedTickets.
  ///
  /// In ru, this message translates to:
  /// **'Сдано билетов'**
  String get homePassedTickets;

  /// No description provided for @examQuestionsBadge.
  ///
  /// In ru, this message translates to:
  /// **'{count} вопросов'**
  String examQuestionsBadge(int count);

  /// No description provided for @examMinutesBadge.
  ///
  /// In ru, this message translates to:
  /// **'{count} минут'**
  String examMinutesBadge(int count);

  /// No description provided for @examReadinessPercent.
  ///
  /// In ru, this message translates to:
  /// **'{percent}% Готовность к экзамену'**
  String examReadinessPercent(int percent);

  /// No description provided for @streakStart.
  ///
  /// In ru, this message translates to:
  /// **'Начните серию'**
  String get streakStart;

  /// No description provided for @streakStartHint.
  ///
  /// In ru, this message translates to:
  /// **'Ответьте на вопрос сегодня — зажжётся огонёк'**
  String get streakStartHint;

  /// No description provided for @streakDaysWord.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{день подряд} few{дня подряд} many{дней подряд} other{дней подряд}}'**
  String streakDaysWord(num count);

  /// No description provided for @continueButton.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get continueButton;

  /// No description provided for @streakBarrierLabel.
  ///
  /// In ru, this message translates to:
  /// **'Серия'**
  String get streakBarrierLabel;

  /// No description provided for @personalRecord.
  ///
  /// In ru, this message translates to:
  /// **'Личный рекорд'**
  String get personalRecord;

  /// No description provided for @streakMotivationRecord.
  ///
  /// In ru, this message translates to:
  /// **'Новый личный рекорд! Так держать.'**
  String get streakMotivationRecord;

  /// No description provided for @streakMotivationFirst.
  ///
  /// In ru, this message translates to:
  /// **'Огонёк зажжён. Возвращайтесь завтра, чтобы серия росла.'**
  String get streakMotivationFirst;

  /// No description provided for @streakMotivationWeek.
  ///
  /// In ru, this message translates to:
  /// **'Отличный темп. Ещё чуть-чуть и наберётся целая неделя.'**
  String get streakMotivationWeek;

  /// No description provided for @streakMotivationHabit.
  ///
  /// In ru, this message translates to:
  /// **'Целая неделя за плечами. Привычка формируется именно так.'**
  String get streakMotivationHabit;

  /// No description provided for @streakMotivationMonth.
  ///
  /// In ru, this message translates to:
  /// **'Месяц без перерыва — это уровень настоящего студента автошколы.'**
  String get streakMotivationMonth;

  /// No description provided for @weekdayMon.
  ///
  /// In ru, this message translates to:
  /// **'Пн'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In ru, this message translates to:
  /// **'Вт'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In ru, this message translates to:
  /// **'Ср'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In ru, this message translates to:
  /// **'Чт'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In ru, this message translates to:
  /// **'Пт'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In ru, this message translates to:
  /// **'Сб'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In ru, this message translates to:
  /// **'Вс'**
  String get weekdaySun;

  /// No description provided for @linkOpenFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть ссылку'**
  String get linkOpenFailed;

  /// No description provided for @telegramOpenFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть Telegram'**
  String get telegramOpenFailed;

  /// No description provided for @supportDeveloper.
  ///
  /// In ru, this message translates to:
  /// **'Поддержать разработчика'**
  String get supportDeveloper;

  /// No description provided for @techSupport.
  ///
  /// In ru, this message translates to:
  /// **'Тех. поддержка'**
  String get techSupport;

  /// No description provided for @privacyPolicy.
  ///
  /// In ru, this message translates to:
  /// **'Политика конфиденциальности'**
  String get privacyPolicy;

  /// No description provided for @aboutSection.
  ///
  /// In ru, this message translates to:
  /// **'О приложении'**
  String get aboutSection;

  /// No description provided for @dataSourceTitle.
  ///
  /// In ru, this message translates to:
  /// **'Источники данных'**
  String get dataSourceTitle;

  /// No description provided for @preparation.
  ///
  /// In ru, this message translates to:
  /// **'Подготовка'**
  String get preparation;

  /// No description provided for @feedbackSection.
  ///
  /// In ru, this message translates to:
  /// **'Отклики и звуки'**
  String get feedbackSection;

  /// No description provided for @confirmAnswerSetting.
  ///
  /// In ru, this message translates to:
  /// **'Подтверждать ответ'**
  String get confirmAnswerSetting;

  /// No description provided for @confirmAnswerHint.
  ///
  /// In ru, this message translates to:
  /// **'Ответ сначала выбирается, а затем подтверждается кнопкой.'**
  String get confirmAnswerHint;

  /// No description provided for @hapticFeedback.
  ///
  /// In ru, this message translates to:
  /// **'Тактильный отклик'**
  String get hapticFeedback;

  /// No description provided for @soundEffects.
  ///
  /// In ru, this message translates to:
  /// **'Звуки'**
  String get soundEffects;

  /// No description provided for @voiceOverQuestions.
  ///
  /// In ru, this message translates to:
  /// **'Озвучка вопросов'**
  String get voiceOverQuestions;

  /// No description provided for @ticketCategorySetting.
  ///
  /// In ru, this message translates to:
  /// **'Категория билетов'**
  String get ticketCategorySetting;

  /// No description provided for @ticketCategoryHint.
  ///
  /// In ru, this message translates to:
  /// **'A/B – легковые и мото, C/D – грузовые и автобусы'**
  String get ticketCategoryHint;

  /// No description provided for @dataSection.
  ///
  /// In ru, this message translates to:
  /// **'Данные'**
  String get dataSection;

  /// No description provided for @resetStatsDetail.
  ///
  /// In ru, this message translates to:
  /// **'Будут очищены прогресс по вопросам, результаты экзаменов и избранные вопросы.'**
  String get resetStatsDetail;

  /// No description provided for @reset.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить'**
  String get reset;

  /// No description provided for @statsReset.
  ///
  /// In ru, this message translates to:
  /// **'Статистика сброшена'**
  String get statsReset;

  /// No description provided for @searchByQuestionOrTopic.
  ///
  /// In ru, this message translates to:
  /// **'Поиск по вопросу или теме'**
  String get searchByQuestionOrTopic;

  /// No description provided for @emptyHere.
  ///
  /// In ru, this message translates to:
  /// **'Пока здесь пусто'**
  String get emptyHere;

  /// No description provided for @favoritesEmptyHint.
  ///
  /// In ru, this message translates to:
  /// **'Отмечай сложные вопросы звёздочкой, и они будут собираться в одном месте для быстрого повторения.'**
  String get favoritesEmptyHint;

  /// No description provided for @favoritesSearchEmpty.
  ///
  /// In ru, this message translates to:
  /// **'По этому запросу ничего не найдено. Попробуй часть формулировки вопроса или название темы.'**
  String get favoritesSearchEmpty;

  /// No description provided for @favoritesSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Личные сложные вопросы'**
  String get favoritesSubtitle;

  /// No description provided for @favoritesCountHint.
  ///
  /// In ru, this message translates to:
  /// **'Сейчас в избранном {count, plural, one{{count} вопрос} few{{count} вопроса} many{{count} вопросов} other{{count} вопросов}}. Используй этот режим как персональную подборку перед экзаменом.'**
  String favoritesCountHint(int count);

  /// No description provided for @practiceAllFavorites.
  ///
  /// In ru, this message translates to:
  /// **'Пройти всё избранное'**
  String get practiceAllFavorites;

  /// No description provided for @noTopic.
  ///
  /// In ru, this message translates to:
  /// **'Без темы'**
  String get noTopic;

  /// No description provided for @favoriteQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Избранный вопрос'**
  String get favoriteQuestion;

  /// No description provided for @ticketNumber.
  ///
  /// In ru, this message translates to:
  /// **'Билет {number}'**
  String ticketNumber(Object number);

  /// No description provided for @mistakesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Работа над ошибками'**
  String get mistakesTitle;

  /// No description provided for @noMistakesYet.
  ///
  /// In ru, this message translates to:
  /// **'Ошибок пока нет'**
  String get noMistakesYet;

  /// No description provided for @mistakesEmptyHint.
  ///
  /// In ru, this message translates to:
  /// **'Когда появятся неверные ответы, здесь можно будет быстро повторить только слабые вопросы.'**
  String get mistakesEmptyHint;

  /// No description provided for @repeatAllMistakes.
  ///
  /// In ru, this message translates to:
  /// **'Повторить все ошибки'**
  String get repeatAllMistakes;

  /// No description provided for @mistakeReview.
  ///
  /// In ru, this message translates to:
  /// **'Разбор ошибки'**
  String get mistakeReview;

  /// No description provided for @mistakeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка'**
  String get mistakeLabel;

  /// No description provided for @nothingFoundTryAnother.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено. Попробуйте другое слово.'**
  String get nothingFoundTryAnother;

  /// No description provided for @pddSearchEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено. Попробуйте номер раздела или ключевое слово.'**
  String get pddSearchEmpty;

  /// No description provided for @onboardingTitle.
  ///
  /// In ru, this message translates to:
  /// **'На чем планируешь ездить?'**
  String get onboardingTitle;

  /// No description provided for @categoryABDesc.
  ///
  /// In ru, this message translates to:
  /// **'автомобиль, мотоцикл'**
  String get categoryABDesc;

  /// No description provided for @categoryCDDesc.
  ///
  /// In ru, this message translates to:
  /// **'грузовик, автобус'**
  String get categoryCDDesc;

  /// No description provided for @ttsAnswerOptions.
  ///
  /// In ru, this message translates to:
  /// **' Варианты ответов '**
  String get ttsAnswerOptions;

  /// No description provided for @ttsAnswer.
  ///
  /// In ru, this message translates to:
  /// **'Ответ '**
  String get ttsAnswer;

  /// No description provided for @noQuestions.
  ///
  /// In ru, this message translates to:
  /// **'Нет вопросов'**
  String get noQuestions;

  /// No description provided for @hint.
  ///
  /// In ru, this message translates to:
  /// **'Подсказка'**
  String get hint;

  /// No description provided for @questionOfTotal.
  ///
  /// In ru, this message translates to:
  /// **'Вопрос {current} из {total}'**
  String questionOfTotal(int current, int total);

  /// No description provided for @finishButton.
  ///
  /// In ru, this message translates to:
  /// **'Завершить'**
  String get finishButton;

  /// No description provided for @hideHint.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть подсказку'**
  String get hideHint;

  /// No description provided for @confirmAnswerButton.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердить ответ'**
  String get confirmAnswerButton;

  /// No description provided for @myMistakes.
  ///
  /// In ru, this message translates to:
  /// **'Мои ошибки'**
  String get myMistakes;

  /// No description provided for @noQuestionsToReview.
  ///
  /// In ru, this message translates to:
  /// **'Нет вопросов для разбора'**
  String get noQuestionsToReview;

  /// No description provided for @examReview.
  ///
  /// In ru, this message translates to:
  /// **'Разбор экзамена'**
  String get examReview;

  /// No description provided for @zoomIn.
  ///
  /// In ru, this message translates to:
  /// **'Увеличить'**
  String get zoomIn;

  /// No description provided for @trainingResultPerfect.
  ///
  /// In ru, this message translates to:
  /// **'Ни одной ошибки — так держать'**
  String get trainingResultPerfect;

  /// No description provided for @trainingResultWithMistakes.
  ///
  /// In ru, this message translates to:
  /// **'Повторите вопросы, где ошиблись'**
  String get trainingResultWithMistakes;

  /// No description provided for @trainingRepeatMistakes.
  ///
  /// In ru, this message translates to:
  /// **'Повторить ошибки'**
  String get trainingRepeatMistakes;

  /// No description provided for @done.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get done;

  /// No description provided for @close.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get close;

  /// No description provided for @next.
  ///
  /// In ru, this message translates to:
  /// **'Следующий'**
  String get next;

  /// No description provided for @notAnsweredThisQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Вы не ответили на этот вопрос'**
  String get notAnsweredThisQuestion;

  /// No description provided for @description.
  ///
  /// In ru, this message translates to:
  /// **'Описание'**
  String get description;

  /// No description provided for @folkNameLabel.
  ///
  /// In ru, this message translates to:
  /// **'Народное название'**
  String get folkNameLabel;

  /// No description provided for @examAdditionalTitle.
  ///
  /// In ru, this message translates to:
  /// **'Дополнительные вопросы'**
  String get examAdditionalTitle;

  /// No description provided for @examAdditionalQuestionOfTotal.
  ///
  /// In ru, this message translates to:
  /// **'Доп. вопрос {current} из {total}'**
  String examAdditionalQuestionOfTotal(int current, int total);

  /// No description provided for @examResultTimeout.
  ///
  /// In ru, this message translates to:
  /// **'Время вышло. Попробуйте снова в спокойном темпе.'**
  String get examResultTimeout;

  /// No description provided for @examResultPassed.
  ///
  /// In ru, this message translates to:
  /// **'Отличный результат. Можно закрепить его билетами.'**
  String get examResultPassed;

  /// No description provided for @examResultFailed.
  ///
  /// In ru, this message translates to:
  /// **'Разберите ошибки и повторите слабые места.'**
  String get examResultFailed;

  /// No description provided for @valueOfTotal.
  ///
  /// In ru, this message translates to:
  /// **'{value} из {total}'**
  String valueOfTotal(int value, int total);

  /// No description provided for @examFailedByBlock.
  ///
  /// In ru, this message translates to:
  /// **'Билет состоит из 4 тематических блоков по 5 вопросов. По регламенту ГИБДД {count} ошибки в одном блоке — экзамен не сдан, даже если всего ошибок не больше двух.'**
  String examFailedByBlock(int count);

  /// No description provided for @examAdditionalBlock.
  ///
  /// In ru, this message translates to:
  /// **'Дополнительный блок'**
  String get examAdditionalBlock;

  /// No description provided for @examAdditionalBlockValue.
  ///
  /// In ru, this message translates to:
  /// **'{count} вопросов, ошибок: {errors}'**
  String examAdditionalBlockValue(int count, int errors);

  /// No description provided for @examTimeSpent.
  ///
  /// In ru, this message translates to:
  /// **'Затраченное время'**
  String get examTimeSpent;

  /// No description provided for @examMainBlockErrors.
  ///
  /// In ru, this message translates to:
  /// **'Ошибок в основном блоке'**
  String get examMainBlockErrors;

  /// No description provided for @backToTraining.
  ///
  /// In ru, this message translates to:
  /// **'Вернуться к обучению'**
  String get backToTraining;

  /// No description provided for @examPointsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Набрано баллов'**
  String get examPointsLabel;

  /// No description provided for @examScoreLabel.
  ///
  /// In ru, this message translates to:
  /// **'Ваш результат'**
  String get examScoreLabel;

  /// No description provided for @examScorePercent.
  ///
  /// In ru, this message translates to:
  /// **'{percent}%'**
  String examScorePercent(int percent);

  /// No description provided for @share.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться'**
  String get share;

  /// No description provided for @copiedToClipboard.
  ///
  /// In ru, this message translates to:
  /// **'Скопировано в буфер обмена'**
  String get copiedToClipboard;

  /// No description provided for @examShareText.
  ///
  /// In ru, this message translates to:
  /// **'{result}\nВерных ответов: {correct} из {total}\n\n{title}\n{url}'**
  String examShareText(
    String result,
    int correct,
    int total,
    String title,
    String url,
  );

  /// No description provided for @supportChooseMethod.
  ///
  /// In ru, this message translates to:
  /// **'Выберите способ'**
  String get supportChooseMethod;

  /// No description provided for @supportYoomoney.
  ///
  /// In ru, this message translates to:
  /// **'ЮMoney (карта, кошелёк)'**
  String get supportYoomoney;

  /// No description provided for @supportUsdt.
  ///
  /// In ru, this message translates to:
  /// **'USDT · сеть TRC-20 (TRON)'**
  String get supportUsdt;

  /// No description provided for @supportUsdtWarning.
  ///
  /// In ru, this message translates to:
  /// **'Отправляйте только USDT по сети TRC-20 (TRON). Перевод по другой сети приведёт к потере средств.'**
  String get supportUsdtWarning;

  /// No description provided for @copyAddress.
  ///
  /// In ru, this message translates to:
  /// **'Копировать адрес'**
  String get copyAddress;

  /// No description provided for @notifStreakTitle1.
  ///
  /// In ru, this message translates to:
  /// **'Серия под угрозой'**
  String get notifStreakTitle1;

  /// No description provided for @notifStreakBody1.
  ///
  /// In ru, this message translates to:
  /// **'Потренируйся и сохрани огонёк 🔥'**
  String get notifStreakBody1;

  /// No description provided for @notifStreakTitle2.
  ///
  /// In ru, this message translates to:
  /// **'Ты слишком близко, чтобы бросать'**
  String get notifStreakTitle2;

  /// No description provided for @notifStreakBody2.
  ///
  /// In ru, this message translates to:
  /// **'Каждый день приближает к экзамену'**
  String get notifStreakBody2;

  /// No description provided for @notifStreakTitle3.
  ///
  /// In ru, this message translates to:
  /// **'🔥 Огонёк вот-вот погаснет'**
  String get notifStreakTitle3;

  /// No description provided for @notifStreakBody3.
  ///
  /// In ru, this message translates to:
  /// **'Зайди и ответь на пару вопросов'**
  String get notifStreakBody3;

  /// No description provided for @notifStreakTitle4.
  ///
  /// In ru, this message translates to:
  /// **'День почти прошёл'**
  String get notifStreakTitle4;

  /// No description provided for @notifStreakBody4.
  ///
  /// In ru, this message translates to:
  /// **'А тренировки сегодня не было'**
  String get notifStreakBody4;

  /// No description provided for @notifStreakTitle5.
  ///
  /// In ru, this message translates to:
  /// **'Твой рекорд под угрозой'**
  String get notifStreakTitle5;

  /// No description provided for @notifStreakBody5.
  ///
  /// In ru, this message translates to:
  /// **'Сохрани его одним заходом'**
  String get notifStreakBody5;

  /// No description provided for @notifStreakTitle6.
  ///
  /// In ru, this message translates to:
  /// **'Экзамен ближе, чем кажется'**
  String get notifStreakTitle6;

  /// No description provided for @notifStreakBody6.
  ///
  /// In ru, this message translates to:
  /// **'Потренируйся сегодня'**
  String get notifStreakBody6;

  /// No description provided for @notifChannelName.
  ///
  /// In ru, this message translates to:
  /// **'Напоминания о серии'**
  String get notifChannelName;

  /// No description provided for @notifChannelDesc.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы вы не теряли серию тренировок'**
  String get notifChannelDesc;

  /// No description provided for @dataLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить данные. Проверьте подключение и попробуйте снова.'**
  String get dataLoadError;

  /// No description provided for @themeSetting.
  ///
  /// In ru, this message translates to:
  /// **'Тема оформления'**
  String get themeSetting;

  /// No description provided for @themeSystem.
  ///
  /// In ru, this message translates to:
  /// **'Как на устройстве'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get themeDark;

  /// No description provided for @themeChoose.
  ///
  /// In ru, this message translates to:
  /// **'Тема оформления'**
  String get themeChoose;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ru', 'sr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ru':
      return AppLocalizationsRu();
    case 'sr':
      return AppLocalizationsSr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
