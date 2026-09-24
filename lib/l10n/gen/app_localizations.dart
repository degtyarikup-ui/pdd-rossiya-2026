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

  /// No description provided for @termsOfUse.
  ///
  /// In ru, this message translates to:
  /// **'Условия использования'**
  String get termsOfUse;

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

  /// No description provided for @notificationsSetting.
  ///
  /// In ru, this message translates to:
  /// **'Напоминания о серии'**
  String get notificationsSetting;

  /// No description provided for @notificationsHint.
  ///
  /// In ru, this message translates to:
  /// **'Каждый день в 20:00, если серия не закрыта'**
  String get notificationsHint;

  /// No description provided for @game.
  ///
  /// In ru, this message translates to:
  /// **'Игра'**
  String get game;

  /// No description provided for @gameSimulator.
  ///
  /// In ru, this message translates to:
  /// **'3D Тренажёр'**
  String get gameSimulator;

  /// No description provided for @gameLeaderboard.
  ///
  /// In ru, this message translates to:
  /// **'Таблица лидеров'**
  String get gameLeaderboard;

  /// No description provided for @gameScore.
  ///
  /// In ru, this message translates to:
  /// **'Очки'**
  String get gameScore;

  /// No description provided for @gameDistance.
  ///
  /// In ru, this message translates to:
  /// **'Дистанция'**
  String get gameDistance;

  /// No description provided for @gameOver.
  ///
  /// In ru, this message translates to:
  /// **'Заезд завершён'**
  String get gameOver;

  /// No description provided for @gameRestart.
  ///
  /// In ru, this message translates to:
  /// **'Попробовать снова'**
  String get gameRestart;

  /// No description provided for @gameExit.
  ///
  /// In ru, this message translates to:
  /// **'В меню'**
  String get gameExit;

  /// No description provided for @gameUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Сценарии тренажёра пока проверены только для ПДД России. Для этой страны игра станет доступна после проверки местных правил.'**
  String get gameUnavailable;

  /// No description provided for @gameMobileOnly.
  ///
  /// In ru, this message translates to:
  /// **'3D-тренажёр доступен в мобильном приложении на iOS и Android.'**
  String get gameMobileOnly;

  /// No description provided for @gameLeft.
  ///
  /// In ru, this message translates to:
  /// **'Левее'**
  String get gameLeft;

  /// No description provided for @gameRight.
  ///
  /// In ru, this message translates to:
  /// **'Правее'**
  String get gameRight;

  /// No description provided for @gameGas.
  ///
  /// In ru, this message translates to:
  /// **'ГАЗ'**
  String get gameGas;

  /// No description provided for @gameSpeedUnit.
  ///
  /// In ru, this message translates to:
  /// **'км/ч'**
  String get gameSpeedUnit;

  /// No description provided for @gameMeters.
  ///
  /// In ru, this message translates to:
  /// **'м'**
  String get gameMeters;

  /// No description provided for @gameKilometers.
  ///
  /// In ru, this message translates to:
  /// **'км'**
  String get gameKilometers;

  /// No description provided for @gameSeconds.
  ///
  /// In ru, this message translates to:
  /// **'с'**
  String get gameSeconds;

  /// No description provided for @gameMistake.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка'**
  String get gameMistake;

  /// No description provided for @gameCorrect.
  ///
  /// In ru, this message translates to:
  /// **'Верно'**
  String get gameCorrect;

  /// No description provided for @gameContinue.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить движение'**
  String get gameContinue;

  /// No description provided for @gameResolving.
  ///
  /// In ru, this message translates to:
  /// **'Газ — ехать · стрелки — рулить'**
  String get gameResolving;

  /// No description provided for @gameGarage.
  ///
  /// In ru, this message translates to:
  /// **'Выбор машины'**
  String get gameGarage;

  /// No description provided for @gameCarHatch.
  ///
  /// In ru, this message translates to:
  /// **'Хэтчбек'**
  String get gameCarHatch;

  /// No description provided for @gameCarSedan.
  ///
  /// In ru, this message translates to:
  /// **'Седан'**
  String get gameCarSedan;

  /// No description provided for @gameCarSuv.
  ///
  /// In ru, this message translates to:
  /// **'Внедорожник'**
  String get gameCarSuv;

  /// No description provided for @gameCarPickup.
  ///
  /// In ru, this message translates to:
  /// **'Пикап'**
  String get gameCarPickup;

  /// No description provided for @gameCarCoupe.
  ///
  /// In ru, this message translates to:
  /// **'Купе'**
  String get gameCarCoupe;

  /// No description provided for @gameCarWagon.
  ///
  /// In ru, this message translates to:
  /// **'Универсал'**
  String get gameCarWagon;

  /// No description provided for @gameCarCyber.
  ///
  /// In ru, this message translates to:
  /// **'Кибертрак'**
  String get gameCarCyber;

  /// No description provided for @gamePaintRed.
  ///
  /// In ru, this message translates to:
  /// **'красный'**
  String get gamePaintRed;

  /// No description provided for @gamePaintBlue.
  ///
  /// In ru, this message translates to:
  /// **'синий'**
  String get gamePaintBlue;

  /// No description provided for @gamePaintGreen.
  ///
  /// In ru, this message translates to:
  /// **'зелёный'**
  String get gamePaintGreen;

  /// No description provided for @gamePaintSand.
  ///
  /// In ru, this message translates to:
  /// **'песочный'**
  String get gamePaintSand;

  /// No description provided for @gamePaintWhite.
  ///
  /// In ru, this message translates to:
  /// **'белый'**
  String get gamePaintWhite;

  /// No description provided for @gamePaintBlack.
  ///
  /// In ru, this message translates to:
  /// **'чёрный'**
  String get gamePaintBlack;

  /// No description provided for @gamePaintSilver.
  ///
  /// In ru, this message translates to:
  /// **'серебристый'**
  String get gamePaintSilver;

  /// No description provided for @gamePaintOrange.
  ///
  /// In ru, this message translates to:
  /// **'оранжевый'**
  String get gamePaintOrange;

  /// No description provided for @gamePaintPurple.
  ///
  /// In ru, this message translates to:
  /// **'фиолетовый'**
  String get gamePaintPurple;

  /// No description provided for @gamePaintTeal.
  ///
  /// In ru, this message translates to:
  /// **'бирюзовый'**
  String get gamePaintTeal;

  /// No description provided for @gamePaintYellow.
  ///
  /// In ru, this message translates to:
  /// **'жёлтый'**
  String get gamePaintYellow;

  /// No description provided for @gamePaintWine.
  ///
  /// In ru, this message translates to:
  /// **'бордовый'**
  String get gamePaintWine;

  /// No description provided for @gamePaintGold.
  ///
  /// In ru, this message translates to:
  /// **'золотой'**
  String get gamePaintGold;

  /// No description provided for @gameGarageNextCar.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{Следующая машина через {count} правильный ответ} few{Следующая машина через {count} правильных ответа} many{Следующая машина через {count} правильных ответов} other{Следующая машина через {count} правильных ответов}}'**
  String gameGarageNextCar(int count);

  /// No description provided for @gameGaragePremiumCar.
  ///
  /// In ru, this message translates to:
  /// **'С премиумом открыты все машины и все цвета'**
  String get gameGaragePremiumCar;

  /// No description provided for @gameRevealTitle.
  ///
  /// In ru, this message translates to:
  /// **'Новая машина!'**
  String get gameRevealTitle;

  /// No description provided for @gameRevealTap.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите на ворота'**
  String get gameRevealTap;

  /// No description provided for @gameRevealChoose.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать'**
  String get gameRevealChoose;

  /// No description provided for @gameRevealClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get gameRevealClose;

  /// No description provided for @feedLockedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Лента откроется после входа'**
  String get feedLockedTitle;

  /// No description provided for @feedLockedBody.
  ///
  /// In ru, this message translates to:
  /// **'Короткие карточки с правилами, знаками и советами на каждый день. Войдите — и лента, серия занятий и прогресс будут с вами на любом устройстве.'**
  String get feedLockedBody;

  /// No description provided for @feedSignIn.
  ///
  /// In ru, this message translates to:
  /// **'Войти'**
  String get feedSignIn;

  /// No description provided for @gameSceneTitle.
  ///
  /// In ru, this message translates to:
  /// **'Погода и сезон'**
  String get gameSceneTitle;

  /// No description provided for @gameSceneWeather.
  ///
  /// In ru, this message translates to:
  /// **'Погода'**
  String get gameSceneWeather;

  /// No description provided for @gameSceneSeason.
  ///
  /// In ru, this message translates to:
  /// **'Время года'**
  String get gameSceneSeason;

  /// No description provided for @gameSceneAuto.
  ///
  /// In ru, this message translates to:
  /// **'Авто'**
  String get gameSceneAuto;

  /// No description provided for @gameSceneClear.
  ///
  /// In ru, this message translates to:
  /// **'Ясно'**
  String get gameSceneClear;

  /// No description provided for @gameSceneOvercast.
  ///
  /// In ru, this message translates to:
  /// **'Пасмурно'**
  String get gameSceneOvercast;

  /// No description provided for @gameScenePrecip.
  ///
  /// In ru, this message translates to:
  /// **'Осадки'**
  String get gameScenePrecip;

  /// No description provided for @gameSceneCalendar.
  ///
  /// In ru, this message translates to:
  /// **'По календарю'**
  String get gameSceneCalendar;

  /// No description provided for @gameDebugUnlimitedFuel.
  ///
  /// In ru, this message translates to:
  /// **'Бесконечный бензин'**
  String get gameDebugUnlimitedFuel;

  /// No description provided for @gameDebugUnlimitedFuelHint.
  ///
  /// In ru, this message translates to:
  /// **'Ошибки не расходуют бензин'**
  String get gameDebugUnlimitedFuelHint;

  /// No description provided for @gameSceneSummer.
  ///
  /// In ru, this message translates to:
  /// **'Лето'**
  String get gameSceneSummer;

  /// No description provided for @gameSceneAutumn.
  ///
  /// In ru, this message translates to:
  /// **'Осень'**
  String get gameSceneAutumn;

  /// No description provided for @gameSceneWinter.
  ///
  /// In ru, this message translates to:
  /// **'Зима'**
  String get gameSceneWinter;

  /// No description provided for @gameCollision.
  ///
  /// In ru, this message translates to:
  /// **'Столкновение'**
  String get gameCollision;

  /// No description provided for @gameOffroad.
  ///
  /// In ru, this message translates to:
  /// **'Бордюр · поверните к дороге'**
  String get gameOffroad;

  /// No description provided for @gamePriorityViolation.
  ///
  /// In ru, this message translates to:
  /// **'Вы не уступили дорогу'**
  String get gamePriorityViolation;

  /// No description provided for @gameWrongManeuver.
  ///
  /// In ru, this message translates to:
  /// **'Манёвр не соответствует заданию'**
  String get gameWrongManeuver;

  /// No description provided for @gameOncoming.
  ///
  /// In ru, this message translates to:
  /// **'Встречная полоса! Вернитесь вправо'**
  String get gameOncoming;

  /// No description provided for @gameOneWayAgainst.
  ///
  /// In ru, this message translates to:
  /// **'Одностороннее движение! Вы едете против потока'**
  String get gameOneWayAgainst;

  /// No description provided for @gameRoadworksHit.
  ///
  /// In ru, this message translates to:
  /// **'Вы въехали в зону дорожных работ'**
  String get gameRoadworksHit;

  /// No description provided for @gameCorrectAnswers.
  ///
  /// In ru, this message translates to:
  /// **'Верных ответов'**
  String get gameCorrectAnswers;

  /// No description provided for @gameAnswersOf.
  ///
  /// In ru, this message translates to:
  /// **'{correct} из {total}'**
  String gameAnswersOf(int correct, int total);

  /// No description provided for @gameNoViolations.
  ///
  /// In ru, this message translates to:
  /// **'Без нарушений'**
  String get gameNoViolations;

  /// No description provided for @gameYourCar.
  ///
  /// In ru, this message translates to:
  /// **'Ваш автомобиль'**
  String get gameYourCar;

  /// No description provided for @gameSpeeding.
  ///
  /// In ru, this message translates to:
  /// **'Превышение скорости'**
  String get gameSpeeding;

  /// No description provided for @gameOvertakingProhibited.
  ///
  /// In ru, this message translates to:
  /// **'Обгон здесь запрещён'**
  String get gameOvertakingProhibited;

  /// No description provided for @gamePedestrianYield.
  ///
  /// In ru, this message translates to:
  /// **'Уступите дорогу пешеходу'**
  String get gamePedestrianYield;

  /// No description provided for @gameSpeedLimitLabel.
  ///
  /// In ru, this message translates to:
  /// **'Ограничение {limit} км/ч'**
  String gameSpeedLimitLabel(int limit);

  /// No description provided for @gameBrake.
  ///
  /// In ru, this message translates to:
  /// **'Тормоз · назад при остановке'**
  String get gameBrake;

  /// No description provided for @gameNewRecord.
  ///
  /// In ru, this message translates to:
  /// **'Новый рекорд!'**
  String get gameNewRecord;

  /// No description provided for @gameBestScore.
  ///
  /// In ru, this message translates to:
  /// **'Рекорд {score}'**
  String gameBestScore(int score);

  /// No description provided for @gameGasHint.
  ///
  /// In ru, this message translates to:
  /// **'Зажмите и держите — это газ'**
  String get gameGasHint;

  /// No description provided for @gameWeeklyRating.
  ///
  /// In ru, this message translates to:
  /// **'Рейтинг недели'**
  String get gameWeeklyRating;

  /// No description provided for @gameLobbyStart.
  ///
  /// In ru, this message translates to:
  /// **'Начать заезд'**
  String get gameLobbyStart;

  /// No description provided for @gameLobbyChangeCar.
  ///
  /// In ru, this message translates to:
  /// **'Сменить'**
  String get gameLobbyChangeCar;

  /// No description provided for @gameLobbyRecord.
  ///
  /// In ru, this message translates to:
  /// **'Рекорд'**
  String get gameLobbyRecord;

  /// No description provided for @gameLobbyColour.
  ///
  /// In ru, this message translates to:
  /// **'Цвет'**
  String get gameLobbyColour;

  /// No description provided for @gameLobbyRating.
  ///
  /// In ru, this message translates to:
  /// **'Рейтинг'**
  String get gameLobbyRating;

  /// No description provided for @gameLobbyColoursHint.
  ///
  /// In ru, this message translates to:
  /// **'Новые цвета открываются за правильные ответы в игре'**
  String get gameLobbyColoursHint;

  /// No description provided for @gameRatingHint.
  ///
  /// In ru, this message translates to:
  /// **'Очки всех заездов за неделю. В таблице — лучшие 100.'**
  String get gameRatingHint;

  /// No description provided for @gameRatingEmpty.
  ///
  /// In ru, this message translates to:
  /// **'На этой неделе ещё никто не проехал. Будьте первым!'**
  String get gameRatingEmpty;

  /// No description provided for @gameRatingUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить рейтинг. Проверьте интернет.'**
  String get gameRatingUnavailable;

  /// No description provided for @gameRatingYou.
  ///
  /// In ru, this message translates to:
  /// **'Вы'**
  String get gameRatingYou;

  /// No description provided for @gameRatingRuns.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} заезд} few{{count} заезда} many{{count} заездов} other{{count} заезда}}'**
  String gameRatingRuns(int count);

  /// No description provided for @gameRatingEndsIn.
  ///
  /// In ru, this message translates to:
  /// **'До конца недели: {days} дн.'**
  String gameRatingEndsIn(int days);

  /// No description provided for @gameAuthRequired.
  ///
  /// In ru, this message translates to:
  /// **'Игра доступна после входа'**
  String get gameAuthRequired;

  /// No description provided for @gameAuthRequiredHint.
  ///
  /// In ru, this message translates to:
  /// **'Войдите, чтобы копить очки и участвовать в рейтинге недели.'**
  String get gameAuthRequiredHint;

  /// No description provided for @gameSignIn.
  ///
  /// In ru, this message translates to:
  /// **'Войти и поехать'**
  String get gameSignIn;

  /// No description provided for @gamePenaltyHint.
  ///
  /// In ru, this message translates to:
  /// **'Нарушение: −{points} очков'**
  String gamePenaltyHint(int points);

  /// No description provided for @pddSettingsItem.
  ///
  /// In ru, this message translates to:
  /// **'Правила, знаки и разметка'**
  String get pddSettingsItem;

  /// No description provided for @gameLockedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Готовы сесть за руль?'**
  String get gameLockedTitle;

  /// No description provided for @gameLockedHint.
  ///
  /// In ru, this message translates to:
  /// **'Живой город, билеты ГИБДД прямо на дороге и рейтинг недели. Войдите — и поехали.'**
  String get gameLockedHint;

  /// No description provided for @gameFuel.
  ///
  /// In ru, this message translates to:
  /// **'Топливо'**
  String get gameFuel;

  /// No description provided for @gameFuelUnlimited.
  ///
  /// In ru, this message translates to:
  /// **'Безлимитное топливо'**
  String get gameFuelUnlimited;

  /// No description provided for @gameFuelEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Бензин закончился'**
  String get gameFuelEmptyTitle;

  /// No description provided for @gameFuelRefillIn.
  ///
  /// In ru, this message translates to:
  /// **'Бак пополнится через {time}'**
  String gameFuelRefillIn(String time);

  /// No description provided for @gameFuelPremiumPitch.
  ///
  /// In ru, this message translates to:
  /// **'С подпиской бензин не заканчивается'**
  String get gameFuelPremiumPitch;

  /// No description provided for @gameFuelBuyPremium.
  ///
  /// In ru, this message translates to:
  /// **'Подключить Премиум'**
  String get gameFuelBuyPremium;

  /// No description provided for @gameFuelWait.
  ///
  /// In ru, this message translates to:
  /// **'Подождать'**
  String get gameFuelWait;

  /// No description provided for @gameViolations.
  ///
  /// In ru, this message translates to:
  /// **'Нарушения'**
  String get gameViolations;

  /// No description provided for @gameOverDescription.
  ///
  /// In ru, this message translates to:
  /// **'Жизни закончились. Разберите ошибки и попробуйте снова.'**
  String get gameOverDescription;

  /// No description provided for @gameYou.
  ///
  /// In ru, this message translates to:
  /// **'Вы'**
  String get gameYou;

  /// No description provided for @gameStop.
  ///
  /// In ru, this message translates to:
  /// **'СТОП'**
  String get gameStop;

  /// No description provided for @gameLoading.
  ///
  /// In ru, this message translates to:
  /// **'Загрузка игры'**
  String get gameLoading;

  /// No description provided for @gameLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось продолжить заезд. Перезапустите тренажёр или вернитесь в меню.'**
  String get gameLoadError;

  /// No description provided for @authSuccess.
  ///
  /// In ru, this message translates to:
  /// **'Вход выполнен успешно'**
  String get authSuccess;

  /// No description provided for @authFailed.
  ///
  /// In ru, this message translates to:
  /// **'Вход отменён или возникла ошибка. Попробуйте ещё раз.'**
  String get authFailed;

  /// No description provided for @authTitle.
  ///
  /// In ru, this message translates to:
  /// **'Вход в аккаунт'**
  String get authTitle;

  /// No description provided for @authDescription.
  ///
  /// In ru, this message translates to:
  /// **'Сохраните премиум-доступ и статистику при смене или переустановке устройства'**
  String get authDescription;

  /// No description provided for @authApple.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить с Apple ID'**
  String get authApple;

  /// No description provided for @authGoogle.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить с Google'**
  String get authGoogle;

  /// No description provided for @authYandex.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить с Яндекс ID'**
  String get authYandex;

  /// No description provided for @authDebug.
  ///
  /// In ru, this message translates to:
  /// **'Тестовый вход (debug-сборка)'**
  String get authDebug;

  /// No description provided for @accountDeleted.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт и данные удалены'**
  String get accountDeleted;

  /// No description provided for @accountDeleteFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось удалить аккаунт. Проверьте подключение и попробуйте ещё раз.'**
  String get accountDeleteFailed;
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
