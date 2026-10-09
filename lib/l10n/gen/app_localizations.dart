import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ru.dart';

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
  static const List<Locale> supportedLocales = <Locale>[Locale('ru')];

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
  /// **'Счёт'**
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
  /// **'Выйти'**
  String get gameExit;

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
  /// **'Верно!'**
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
  /// **'Бесконечные заезды'**
  String get gameDebugUnlimitedFuel;

  /// No description provided for @gameDebugUnlimitedFuelHint.
  ///
  /// In ru, this message translates to:
  /// **'Заезды не расходуются'**
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

  /// No description provided for @gameStopViolation.
  ///
  /// In ru, this message translates to:
  /// **'Вы не остановились в положенном месте'**
  String get gameStopViolation;

  /// No description provided for @gameRedLightViolation.
  ///
  /// In ru, this message translates to:
  /// **'Проезд на запрещающий сигнал'**
  String get gameRedLightViolation;

  /// No description provided for @gameRailwayViolation.
  ///
  /// In ru, this message translates to:
  /// **'Переезд закрыт — объезжать и выезжать нельзя'**
  String get gameRailwayViolation;

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

  /// No description provided for @gameLobbyContinue.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить заезд'**
  String get gameLobbyContinue;

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
  /// **'Заезды'**
  String get gameFuel;

  /// No description provided for @gameFuelUnlimited.
  ///
  /// In ru, this message translates to:
  /// **'Безлимитные заезды'**
  String get gameFuelUnlimited;

  /// No description provided for @gameFuelEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Заезды закончились'**
  String get gameFuelEmptyTitle;

  /// No description provided for @gameFuelRefillIn.
  ///
  /// In ru, this message translates to:
  /// **'Новый заезд через {time}'**
  String gameFuelRefillIn(String time);

  /// No description provided for @gameFuelPremiumPitch.
  ///
  /// In ru, this message translates to:
  /// **'С подпиской заезды не заканчиваются'**
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
  /// **'Все вопросы заезда позади. Неверные ответы уже в «Ошибках» — разберите их и попробуйте снова.'**
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

  /// No description provided for @authErrorCancelled.
  ///
  /// In ru, this message translates to:
  /// **'Вход не завершён. Попробуйте выбрать аккаунт ещё раз.'**
  String get authErrorCancelled;

  /// No description provided for @authErrorProvider.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось получить данные для входа от выбранного сервиса.'**
  String get authErrorProvider;

  /// No description provided for @authErrorNetwork.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось связаться с сервером. Проверьте подключение к интернету.'**
  String get authErrorNetwork;

  /// No description provided for @authErrorTimeout.
  ///
  /// In ru, this message translates to:
  /// **'Сервер не ответил вовремя. Попробуйте ещё раз.'**
  String get authErrorTimeout;

  /// No description provided for @authErrorAppKey.
  ///
  /// In ru, this message translates to:
  /// **'Сервер отклонил эту сборку приложения. Обновите приложение из магазина.'**
  String get authErrorAppKey;

  /// No description provided for @authErrorCredential.
  ///
  /// In ru, this message translates to:
  /// **'Сервер не подтвердил вход. Попробуйте другой аккаунт или способ входа.'**
  String get authErrorCredential;

  /// No description provided for @authErrorServer.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось завершить вход на сервере. Попробуйте позже.'**
  String get authErrorServer;

  /// No description provided for @authErrorResponse.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось завершить вход. Обновите страницу или перезапустите приложение и попробуйте снова.'**
  String get authErrorResponse;

  /// No description provided for @authSessionTemporary.
  ///
  /// In ru, this message translates to:
  /// **'Вход выполнен. Телефон не смог сохранить сессию: после перезапуска потребуется войти снова.'**
  String get authSessionTemporary;

  /// No description provided for @authDiagnosticCode.
  ///
  /// In ru, this message translates to:
  /// **'Код для поддержки: {code}'**
  String authDiagnosticCode(String code);

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

  /// No description provided for @authAppleSafariHint.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы войти с Face ID без ввода данных, откройте сайт в Safari через меню браузера. Встроенный браузер может попросить email и пароль Apple.'**
  String get authAppleSafariHint;

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

  /// No description provided for @gameControlsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Управление'**
  String get gameControlsTitle;

  /// No description provided for @gameControlsSimple.
  ///
  /// In ru, this message translates to:
  /// **'Простое управление'**
  String get gameControlsSimple;

  /// No description provided for @gameControlsSimpleHint.
  ///
  /// In ru, this message translates to:
  /// **'Стрелки — перестроения и повороты, машина едет сама'**
  String get gameControlsSimpleHint;

  /// No description provided for @gameControlsFree.
  ///
  /// In ru, this message translates to:
  /// **'Свободное управление'**
  String get gameControlsFree;

  /// No description provided for @gameControlsFreeHint.
  ///
  /// In ru, this message translates to:
  /// **'Стрелки крутят руль, пока их держишь'**
  String get gameControlsFreeHint;

  /// No description provided for @gameTipGas.
  ///
  /// In ru, this message translates to:
  /// **'Держи педаль газа — машина едет. Отпусти — плавно остановится'**
  String get gameTipGas;

  /// No description provided for @gameTipSteer.
  ///
  /// In ru, this message translates to:
  /// **'Держи стрелку — машина поворачивает. Отпустишь — сама выровняется в полосе'**
  String get gameTipSteer;

  /// No description provided for @gameTipTurn.
  ///
  /// In ru, this message translates to:
  /// **'На перекрёстке держи стрелку, пока машина поворачивает, затем отпусти — она выровняется сама'**
  String get gameTipTurn;

  /// No description provided for @gameTipNext.
  ///
  /// In ru, this message translates to:
  /// **'Дальше'**
  String get gameTipNext;

  /// No description provided for @gameTipDone.
  ///
  /// In ru, this message translates to:
  /// **'Поехали'**
  String get gameTipDone;

  /// No description provided for @gamePause.
  ///
  /// In ru, this message translates to:
  /// **'Пауза'**
  String get gamePause;

  /// No description provided for @gameLobbyControls.
  ///
  /// In ru, this message translates to:
  /// **'Управ.'**
  String get gameLobbyControls;

  /// No description provided for @gameRunProgress.
  ///
  /// In ru, this message translates to:
  /// **'Вопрос {n} из {total}'**
  String gameRunProgress(int n, int total);

  /// No description provided for @gameCorrectAnswer.
  ///
  /// In ru, this message translates to:
  /// **'Правильный ответ'**
  String get gameCorrectAnswer;

  /// No description provided for @gameTimeUp.
  ///
  /// In ru, this message translates to:
  /// **'Время вышло'**
  String get gameTimeUp;

  /// No description provided for @gamePenaltyPoints.
  ///
  /// In ru, this message translates to:
  /// **'{points, plural, one{−{points} очко} few{−{points} очка} many{−{points} очков} other{−{points} очков}}'**
  String gamePenaltyPoints(int points);

  /// No description provided for @gameRunMistakes.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} ошибка в заезде} few{{count} ошибки в заезде} many{{count} ошибок в заезде} other{{count} ошибки в заезде}}'**
  String gameRunMistakes(int count);

  /// No description provided for @gameReviewMistakes.
  ///
  /// In ru, this message translates to:
  /// **'Разобрать ошибки'**
  String get gameReviewMistakes;

  /// No description provided for @notifGameRunTitle.
  ///
  /// In ru, this message translates to:
  /// **'Новый заезд готов'**
  String get notifGameRunTitle;

  /// No description provided for @notifGameRunBody.
  ///
  /// In ru, this message translates to:
  /// **'Садитесь за руль: перекрёстки из экзаменационных билетов ждут.'**
  String get notifGameRunBody;

  /// No description provided for @notifGameChannelName.
  ///
  /// In ru, this message translates to:
  /// **'Игра'**
  String get notifGameChannelName;

  /// No description provided for @notifGameChannelDesc.
  ///
  /// In ru, this message translates to:
  /// **'Когда восстановится заезд в игре'**
  String get notifGameChannelDesc;

  /// No description provided for @gameRunMistakesButton.
  ///
  /// In ru, this message translates to:
  /// **'Ошибки · {count}'**
  String gameRunMistakesButton(int count);

  /// No description provided for @gameCorrectShort.
  ///
  /// In ru, this message translates to:
  /// **'Верно'**
  String get gameCorrectShort;

  /// No description provided for @gameRunsPill.
  ///
  /// In ru, this message translates to:
  /// **'Заезды {runs} из {max}'**
  String gameRunsPill(int runs, int max);

  /// No description provided for @gameRunsUnlimitedPill.
  ///
  /// In ru, this message translates to:
  /// **'Заезды ∞'**
  String get gameRunsUnlimitedPill;

  /// No description provided for @gameRunsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Заезды'**
  String get gameRunsTitle;

  /// No description provided for @gameRunsExplain.
  ///
  /// In ru, this message translates to:
  /// **'Заезд — это {questions} вопросов на дороге. В запасе до {max} заездов, каждый потраченный возвращается через {minutes} минут.'**
  String gameRunsExplain(int questions, int max, int minutes);

  /// No description provided for @gameRunsNextIn.
  ///
  /// In ru, this message translates to:
  /// **'Следующий заезд через {time}'**
  String gameRunsNextIn(String time);

  /// No description provided for @gameRunsFull.
  ///
  /// In ru, this message translates to:
  /// **'Запас полный — можно ехать'**
  String get gameRunsFull;

  /// No description provided for @gameRunsPremium.
  ///
  /// In ru, this message translates to:
  /// **'С Премиум заезды без ограничений'**
  String get gameRunsPremium;

  /// No description provided for @gameRunsGetPremium.
  ///
  /// In ru, this message translates to:
  /// **'Безлимит с Премиум'**
  String get gameRunsGetPremium;

  /// No description provided for @gameLobbyRunLength.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} вопрос} few{{count} вопроса} many{{count} вопросов} other{{count} вопроса}}'**
  String gameLobbyRunLength(int count);

  /// No description provided for @gameLobbyProgress.
  ///
  /// In ru, this message translates to:
  /// **'Пройдено {n} из {total}'**
  String gameLobbyProgress(int n, int total);

  /// No description provided for @gameLobbyNewCar.
  ///
  /// In ru, this message translates to:
  /// **'НОВАЯ'**
  String get gameLobbyNewCar;

  /// No description provided for @gameRunsReady.
  ///
  /// In ru, this message translates to:
  /// **'Готов'**
  String get gameRunsReady;

  /// No description provided for @gameRunsUntil.
  ///
  /// In ru, this message translates to:
  /// **'до заезда'**
  String get gameRunsUntil;

  /// No description provided for @gameUturn.
  ///
  /// In ru, this message translates to:
  /// **'Разворот'**
  String get gameUturn;

  /// No description provided for @purchaseVerificationPending.
  ///
  /// In ru, this message translates to:
  /// **'Магазин сообщил о покупке, но доступ пока не подтверждён. Для повторной проверки нажмите «Восстановить» при доступном интернете.'**
  String get purchaseVerificationPending;

  /// No description provided for @notifAdminChannelName.
  ///
  /// In ru, this message translates to:
  /// **'Сообщения приложения'**
  String get notifAdminChannelName;

  /// No description provided for @noticeAcknowledge.
  ///
  /// In ru, this message translates to:
  /// **'Понятно'**
  String get noticeAcknowledge;

  /// No description provided for @noticeOpen.
  ///
  /// In ru, this message translates to:
  /// **'Открыть'**
  String get noticeOpen;

  /// No description provided for @pushMessagesSetting.
  ///
  /// In ru, this message translates to:
  /// **'Новости приложения'**
  String get pushMessagesSetting;

  /// No description provided for @pushMessagesHint.
  ///
  /// In ru, this message translates to:
  /// **'Пуши об обновлениях и важных событиях'**
  String get pushMessagesHint;

  /// No description provided for @gameKeyboardHint.
  ///
  /// In ru, this message translates to:
  /// **'↑ / W — газ · ↓ / S / пробел — тормоз · ← → / A D — повороты'**
  String get gameKeyboardHint;

  /// No description provided for @webQuarter.
  ///
  /// In ru, this message translates to:
  /// **'3 месяца'**
  String get webQuarter;

  /// No description provided for @webPaymentSoon.
  ///
  /// In ru, this message translates to:
  /// **'Оплата скоро появится'**
  String get webPaymentSoon;

  /// No description provided for @webPaymentInfo.
  ///
  /// In ru, this message translates to:
  /// **'Доступ на 3 месяца без автопродления. Оплата на сайте пока не подключена.'**
  String get webPaymentInfo;

  /// No description provided for @webWeek.
  ///
  /// In ru, this message translates to:
  /// **'1 неделя'**
  String get webWeek;

  /// No description provided for @webPayButton.
  ///
  /// In ru, this message translates to:
  /// **'Оплатить через СБП'**
  String get webPayButton;

  /// No description provided for @webPayInfo.
  ///
  /// In ru, this message translates to:
  /// **'Разовая оплата без автопродления. Премиум откроется и в приложении на телефоне — войдите в нём тем же аккаунтом.'**
  String get webPayInfo;

  /// No description provided for @sbpPayInfoApp.
  ///
  /// In ru, this message translates to:
  /// **'Разовая оплата без автопродления. Премиум включится сразу после оплаты и будет работать на всех ваших устройствах с этим аккаунтом.'**
  String get sbpPayInfoApp;

  /// No description provided for @webPayTariffs.
  ///
  /// In ru, this message translates to:
  /// **'Тарифы'**
  String get webPayTariffs;

  /// No description provided for @webPayEmailTitle.
  ///
  /// In ru, this message translates to:
  /// **'Оплата через СБП'**
  String get webPayEmailTitle;

  /// No description provided for @webPayEmailBody.
  ///
  /// In ru, this message translates to:
  /// **'Оплату через СБП подключаем в ближайшие дни. Оставьте почту — напишем, как только она заработает. На неё же придёт чек.'**
  String get webPayEmailBody;

  /// No description provided for @webPayEmailHint.
  ///
  /// In ru, this message translates to:
  /// **'Электронная почта'**
  String get webPayEmailHint;

  /// No description provided for @webPayEmailInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте адрес почты'**
  String get webPayEmailInvalid;

  /// No description provided for @webPayNotify.
  ///
  /// In ru, this message translates to:
  /// **'Сообщить мне'**
  String get webPayNotify;

  /// No description provided for @webPayFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отправить, попробуйте ещё раз'**
  String get webPayFailed;

  /// No description provided for @webPayLiveBody.
  ///
  /// In ru, this message translates to:
  /// **'Укажите почту для чека. Дальше откроется оплата через СБП — по QR-коду или в приложении банка. Премиум включится сразу после оплаты.'**
  String get webPayLiveBody;

  /// No description provided for @webPayProceed.
  ///
  /// In ru, this message translates to:
  /// **'Перейти к оплате'**
  String get webPayProceed;

  /// No description provided for @webPaySuccess.
  ///
  /// In ru, this message translates to:
  /// **'Оплата прошла — Премиум включён. Спасибо!'**
  String get webPaySuccess;

  /// No description provided for @webPayPending.
  ///
  /// In ru, this message translates to:
  /// **'Платёж обрабатывается — Премиум включится автоматически в течение нескольких минут'**
  String get webPayPending;

  /// No description provided for @webPayCanceled.
  ///
  /// In ru, this message translates to:
  /// **'Оплата не завершена — деньги не списаны'**
  String get webPayCanceled;

  /// No description provided for @webPaySaved.
  ///
  /// In ru, this message translates to:
  /// **'Спасибо! Напишем на {email}, как только оплата заработает'**
  String webPaySaved(String email);

  /// No description provided for @premiumOneTimeInfo.
  ///
  /// In ru, this message translates to:
  /// **'Доступ действует до {date} и не продлевается автоматически.'**
  String premiumOneTimeInfo(String date);

  /// No description provided for @appUpdateTitle.
  ///
  /// In ru, this message translates to:
  /// **'Вышло обновление'**
  String get appUpdateTitle;

  /// No description provided for @appUpdateBody.
  ///
  /// In ru, this message translates to:
  /// **'В новой версии — улучшения и исправления. Обновите приложение, чтобы пользоваться ими.'**
  String get appUpdateBody;

  /// No description provided for @appUpdateVersion.
  ///
  /// In ru, this message translates to:
  /// **'Версия {version}'**
  String appUpdateVersion(String version);

  /// No description provided for @appUpdateAction.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get appUpdateAction;

  /// No description provided for @appUpdateLater.
  ///
  /// In ru, this message translates to:
  /// **'Позже'**
  String get appUpdateLater;

  /// No description provided for @appUpdateReadyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Обновление готово'**
  String get appUpdateReadyTitle;

  /// No description provided for @appUpdateReadyBody.
  ///
  /// In ru, this message translates to:
  /// **'Новая версия уже скачана. Перезапустите приложение, чтобы установить её.'**
  String get appUpdateReadyBody;

  /// No description provided for @appUpdateRestart.
  ///
  /// In ru, this message translates to:
  /// **'Перезапустить'**
  String get appUpdateRestart;

  /// No description provided for @appUpdateOpenFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть обновление. Попробуйте позже.'**
  String get appUpdateOpenFailed;

  /// No description provided for @profile.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get profile;

  /// No description provided for @signInCardTitle.
  ///
  /// In ru, this message translates to:
  /// **'Войти в аккаунт'**
  String get signInCardTitle;

  /// No description provided for @signInCardSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить прогресс и премиум'**
  String get signInCardSubtitle;

  /// No description provided for @achievements.
  ///
  /// In ru, this message translates to:
  /// **'Достижения'**
  String get achievements;

  /// No description provided for @achievementsEarnedCount.
  ///
  /// In ru, this message translates to:
  /// **'{count} из {total}'**
  String achievementsEarnedCount(int count, int total);

  /// No description provided for @achievementLevelFormat.
  ///
  /// In ru, this message translates to:
  /// **'Ур. {level} из {total}'**
  String achievementLevelFormat(int level, int total);

  /// No description provided for @achievementSemanticsLabel.
  ///
  /// In ru, this message translates to:
  /// **'{title}, уровень {level} из {total}'**
  String achievementSemanticsLabel(String title, int level, int total);

  /// No description provided for @achievementProgressFormat.
  ///
  /// In ru, this message translates to:
  /// **'{current} из {target}'**
  String achievementProgressFormat(int current, int target);

  /// No description provided for @achievementTitleStreak.
  ///
  /// In ru, this message translates to:
  /// **'Без пропусков'**
  String get achievementTitleStreak;

  /// No description provided for @achievementTitleCoverage.
  ///
  /// In ru, this message translates to:
  /// **'Эрудит'**
  String get achievementTitleCoverage;

  /// No description provided for @achievementTitleTickets.
  ///
  /// In ru, this message translates to:
  /// **'Билет за билетом'**
  String get achievementTitleTickets;

  /// No description provided for @achievementTitleAttempts.
  ///
  /// In ru, this message translates to:
  /// **'Неутомимый'**
  String get achievementTitleAttempts;

  /// No description provided for @achievementTitleExams.
  ///
  /// In ru, this message translates to:
  /// **'Экзаменатор'**
  String get achievementTitleExams;

  /// No description provided for @achievementTitleFlawless.
  ///
  /// In ru, this message translates to:
  /// **'Без единой ошибки'**
  String get achievementTitleFlawless;

  /// No description provided for @achievementTitleMistakes.
  ///
  /// In ru, this message translates to:
  /// **'Работа над ошибками'**
  String get achievementTitleMistakes;

  /// No description provided for @achievementTitleGame.
  ///
  /// In ru, this message translates to:
  /// **'Гонщик'**
  String get achievementTitleGame;

  /// No description provided for @achievementDescStreak.
  ///
  /// In ru, this message translates to:
  /// **'Лучшая серия дней подряд с занятиями'**
  String get achievementDescStreak;

  /// No description provided for @achievementDescCoverage.
  ///
  /// In ru, this message translates to:
  /// **'Решено разных вопросов из базы'**
  String get achievementDescCoverage;

  /// No description provided for @achievementDescTickets.
  ///
  /// In ru, this message translates to:
  /// **'Билеты, решённые на «сдал»'**
  String get achievementDescTickets;

  /// No description provided for @achievementDescAttempts.
  ///
  /// In ru, this message translates to:
  /// **'Всего ответов, включая повторные'**
  String get achievementDescAttempts;

  /// No description provided for @achievementDescExams.
  ///
  /// In ru, this message translates to:
  /// **'Сданные пробные экзамены'**
  String get achievementDescExams;

  /// No description provided for @achievementDescFlawless.
  ///
  /// In ru, this message translates to:
  /// **'Экзамены, сданные без ошибок'**
  String get achievementDescFlawless;

  /// No description provided for @achievementDescMistakes.
  ///
  /// In ru, this message translates to:
  /// **'Вопросы, в которых ошибался, а потом ответил верно'**
  String get achievementDescMistakes;

  /// No description provided for @achievementDescGame.
  ///
  /// In ru, this message translates to:
  /// **'Лучший счёт за один заезд в игре'**
  String get achievementDescGame;

  /// No description provided for @achievementTitleRank.
  ///
  /// In ru, this message translates to:
  /// **'Покоритель рейтинга'**
  String get achievementTitleRank;

  /// No description provided for @achievementDescRank.
  ///
  /// In ru, this message translates to:
  /// **'Лучшее место в недельном рейтинге игры'**
  String get achievementDescRank;

  /// No description provided for @achievementRankTop.
  ///
  /// In ru, this message translates to:
  /// **'Топ-{count}'**
  String achievementRankTop(int count);

  /// No description provided for @achievementRankFirst.
  ///
  /// In ru, this message translates to:
  /// **'1 место'**
  String get achievementRankFirst;

  /// No description provided for @paywallSubscribe.
  ///
  /// In ru, this message translates to:
  /// **'Оформить подписку'**
  String get paywallSubscribe;

  /// No description provided for @paywallStoreGoogle.
  ///
  /// In ru, this message translates to:
  /// **'Google Play'**
  String get paywallStoreGoogle;

  /// No description provided for @paywallPayMethod.
  ///
  /// In ru, this message translates to:
  /// **'Способ оплаты'**
  String get paywallPayMethod;

  /// No description provided for @paywallMethodSbp.
  ///
  /// In ru, this message translates to:
  /// **'СБП'**
  String get paywallMethodSbp;

  /// No description provided for @paywallStoreApple.
  ///
  /// In ru, this message translates to:
  /// **'настройках Apple ID'**
  String get paywallStoreApple;

  /// No description provided for @paywallTitle.
  ///
  /// In ru, this message translates to:
  /// **'Готовьтесь без ограничений'**
  String get paywallTitle;

  /// No description provided for @paywallFreeNote.
  ///
  /// In ru, this message translates to:
  /// **'Билеты, экзамен и ПДД остаются бесплатными'**
  String get paywallFreeNote;

  /// No description provided for @paywallFeatureFeed.
  ///
  /// In ru, this message translates to:
  /// **'Безлимитная лента вопросов'**
  String get paywallFeatureFeed;

  /// No description provided for @paywallFeatureAi.
  ///
  /// In ru, this message translates to:
  /// **'Разбор ошибок от ИИ'**
  String get paywallFeatureAi;

  /// No description provided for @paywallFeatureVoice.
  ///
  /// In ru, this message translates to:
  /// **'Студийная озвучка билетов'**
  String get paywallFeatureVoice;

  /// No description provided for @paywallFeatureGame.
  ///
  /// In ru, this message translates to:
  /// **'Безлимитные заезды в игре'**
  String get paywallFeatureGame;

  /// No description provided for @paywallPlanQuarter.
  ///
  /// In ru, this message translates to:
  /// **'3 месяца'**
  String get paywallPlanQuarter;

  /// No description provided for @paywallPlanWeek.
  ///
  /// In ru, this message translates to:
  /// **'1 неделя'**
  String get paywallPlanWeek;

  /// No description provided for @paywallEveryQuarter.
  ///
  /// In ru, this message translates to:
  /// **'каждые 3 месяца'**
  String get paywallEveryQuarter;

  /// No description provided for @paywallEveryWeek.
  ///
  /// In ru, this message translates to:
  /// **'каждую неделю'**
  String get paywallEveryWeek;

  /// No description provided for @paywallBadgeBest.
  ///
  /// In ru, this message translates to:
  /// **'Выгодно'**
  String get paywallBadgeBest;

  /// No description provided for @paywallRenewal.
  ///
  /// In ru, this message translates to:
  /// **'Продлевается автоматически. Отменить можно в любой момент в {store}.'**
  String paywallRenewal(String store);

  /// No description provided for @paywallTerms.
  ///
  /// In ru, this message translates to:
  /// **'Условия'**
  String get paywallTerms;

  /// No description provided for @paywallPrivacy.
  ///
  /// In ru, this message translates to:
  /// **'Конфиденциальность'**
  String get paywallPrivacy;

  /// No description provided for @paywallRestore.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить'**
  String get paywallRestore;

  /// No description provided for @gameSourceImage.
  ///
  /// In ru, this message translates to:
  /// **'Оригинальная картинка вопроса'**
  String get gameSourceImage;

  /// No description provided for @gameSourceImageUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'В этом вопросе нет картинки'**
  String get gameSourceImageUnavailable;

  /// No description provided for @navGames.
  ///
  /// In ru, this message translates to:
  /// **'Игры'**
  String get navGames;

  /// No description provided for @gameTrafficControllerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Регулировщик'**
  String get gameTrafficControllerTitle;

  /// No description provided for @gameBestScoreLabel.
  ///
  /// In ru, this message translates to:
  /// **'Рекорд'**
  String get gameBestScoreLabel;

  /// No description provided for @gameComboLabel.
  ///
  /// In ru, this message translates to:
  /// **'Макс. комбо'**
  String get gameComboLabel;

  /// No description provided for @gameSolvedLabel.
  ///
  /// In ru, this message translates to:
  /// **'Решено'**
  String get gameSolvedLabel;

  /// No description provided for @gameCombo.
  ///
  /// In ru, this message translates to:
  /// **'Комбо'**
  String get gameCombo;

  /// No description provided for @gameLives.
  ///
  /// In ru, this message translates to:
  /// **'Жизни'**
  String get gameLives;

  /// No description provided for @gameActionStraight.
  ///
  /// In ru, this message translates to:
  /// **'Прямо'**
  String get gameActionStraight;

  /// No description provided for @gameActionRight.
  ///
  /// In ru, this message translates to:
  /// **'Направо'**
  String get gameActionRight;

  /// No description provided for @gameActionLeft.
  ///
  /// In ru, this message translates to:
  /// **'Налево'**
  String get gameActionLeft;

  /// No description provided for @gameActionUTurn.
  ///
  /// In ru, this message translates to:
  /// **'Разворот'**
  String get gameActionUTurn;

  /// No description provided for @gameActionStand.
  ///
  /// In ru, this message translates to:
  /// **'Стоять'**
  String get gameActionStand;

  /// No description provided for @gameVehicleCar.
  ///
  /// In ru, this message translates to:
  /// **'Автомобиль'**
  String get gameVehicleCar;

  /// No description provided for @gameVehicleTram.
  ///
  /// In ru, this message translates to:
  /// **'Трамвай'**
  String get gameVehicleTram;

  /// No description provided for @gameCameraOverview.
  ///
  /// In ru, this message translates to:
  /// **'Обзор'**
  String get gameCameraOverview;

  /// No description provided for @gameCameraDriver.
  ///
  /// In ru, this message translates to:
  /// **'За рулём'**
  String get gameCameraDriver;

  /// No description provided for @gameOverTitle.
  ///
  /// In ru, this message translates to:
  /// **'Игра окончена'**
  String get gameOverTitle;

  /// No description provided for @gameOverNewRecord.
  ///
  /// In ru, this message translates to:
  /// **'Новый рекорд!'**
  String get gameOverNewRecord;

  /// No description provided for @gamePlayAgain.
  ///
  /// In ru, this message translates to:
  /// **'Играть снова'**
  String get gamePlayAgain;

  /// No description provided for @gameWrong.
  ///
  /// In ru, this message translates to:
  /// **'Нарушение!'**
  String get gameWrong;

  /// No description provided for @gameWhistleNote.
  ///
  /// In ru, this message translates to:
  /// **'Свисток инспектора: движение в этом направлении запрещено сигналом регулировщика.'**
  String get gameWhistleNote;

  /// No description provided for @gameSignSwiperTitle.
  ///
  /// In ru, this message translates to:
  /// **'Знак-Свайпер'**
  String get gameSignSwiperTitle;

  /// No description provided for @gameSwipedLabel.
  ///
  /// In ru, this message translates to:
  /// **'Свайпов'**
  String get gameSwipedLabel;

  /// No description provided for @gameSignSwiperNext.
  ///
  /// In ru, this message translates to:
  /// **'Следующий знак'**
  String get gameSignSwiperNext;

  /// No description provided for @gameSignSwiperCategoryAll.
  ///
  /// In ru, this message translates to:
  /// **'Все категории'**
  String get gameSignSwiperCategoryAll;

  /// No description provided for @gameMistakesReview.
  ///
  /// In ru, this message translates to:
  /// **'Разбор ошибок'**
  String get gameMistakesReview;

  /// No description provided for @gameNoMistakes.
  ///
  /// In ru, this message translates to:
  /// **'Отличная работа! Ни одной ошибки.'**
  String get gameNoMistakes;

  /// No description provided for @gameAccuracyLabel.
  ///
  /// In ru, this message translates to:
  /// **'Точность'**
  String get gameAccuracyLabel;

  /// No description provided for @gameQuestionCategory.
  ///
  /// In ru, this message translates to:
  /// **'Относится ли этот знак к категории «{category}»?'**
  String gameQuestionCategory(String category);

  /// No description provided for @gameQuestionName.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак называется «{name}»?'**
  String gameQuestionName(String name);

  /// No description provided for @gameQuestionFolkName.
  ///
  /// In ru, this message translates to:
  /// **'В народе этот знак называют «{name}»?'**
  String gameQuestionFolkName(String name);

  /// No description provided for @gameQuestionPriorityAdvantage.
  ///
  /// In ru, this message translates to:
  /// **'Имеете ли вы преимущество проезда при этом знаке?'**
  String get gameQuestionPriorityAdvantage;

  /// No description provided for @gameQuestionProhibitsEntry.
  ///
  /// In ru, this message translates to:
  /// **'Разрешён ли въезд под этот знак?'**
  String get gameQuestionProhibitsEntry;

  /// No description provided for @gameQuestionProhibitsOvertaking.
  ///
  /// In ru, this message translates to:
  /// **'Разрешён ли обгон всех транспортных средств?'**
  String get gameQuestionProhibitsOvertaking;

  /// No description provided for @gameQuestionProhibitsParking.
  ///
  /// In ru, this message translates to:
  /// **'Разрешена ли стоянка под этот знак?'**
  String get gameQuestionProhibitsParking;

  /// No description provided for @gameQuestionProhibitsStopping.
  ///
  /// In ru, this message translates to:
  /// **'Разрешена ли остановка под этот знак?'**
  String get gameQuestionProhibitsStopping;

  /// No description provided for @gameComboStreak.
  ///
  /// In ru, this message translates to:
  /// **'КОМБО х{combo}!'**
  String gameComboStreak(int combo);

  /// No description provided for @gameSoonBadge.
  ///
  /// In ru, this message translates to:
  /// **'Скоро'**
  String get gameSoonBadge;

  /// No description provided for @gameRoundaboutTitle.
  ///
  /// In ru, this message translates to:
  /// **'Круговое движение 3D'**
  String get gameRoundaboutTitle;

  /// No description provided for @gameCrossroadsPriorityTitle.
  ///
  /// In ru, this message translates to:
  /// **'Разрули перекресток'**
  String get gameCrossroadsPriorityTitle;

  /// No description provided for @gameCrossroadsPromptWhoGoesFirst.
  ///
  /// In ru, this message translates to:
  /// **'Кто проедет первым?'**
  String get gameCrossroadsPromptWhoGoesFirst;

  /// No description provided for @gameCrossroadsPromptWhoGoesNext.
  ///
  /// In ru, this message translates to:
  /// **'Кто проедет следующим ({step}-м)?'**
  String gameCrossroadsPromptWhoGoesNext(int step);

  /// No description provided for @gameCrossroadsStepOf.
  ///
  /// In ru, this message translates to:
  /// **'Шаг {current} из {total}'**
  String gameCrossroadsStepOf(int current, int total);

  /// No description provided for @gameCrossroadsCollision.
  ///
  /// In ru, this message translates to:
  /// **'ДТП! Нарушение очередности'**
  String get gameCrossroadsCollision;

  /// No description provided for @gameCrossroadsNextCrossroad.
  ///
  /// In ru, this message translates to:
  /// **'Следующий перекресток'**
  String get gameCrossroadsNextCrossroad;

  /// No description provided for @gameCrossroadsRepeatCrossroad.
  ///
  /// In ru, this message translates to:
  /// **'Попробовать снова'**
  String get gameCrossroadsRepeatCrossroad;

  /// No description provided for @gameCrossroadsModeArcade.
  ///
  /// In ru, this message translates to:
  /// **'Аркада'**
  String get gameCrossroadsModeArcade;

  /// No description provided for @gameCrossroadsModeTraining.
  ///
  /// In ru, this message translates to:
  /// **'Обучение'**
  String get gameCrossroadsModeTraining;

  /// No description provided for @gameCrossroadsSolvedCount.
  ///
  /// In ru, this message translates to:
  /// **'Разрулено: {count}'**
  String gameCrossroadsSolvedCount(int count);

  /// No description provided for @gameCrossroadsExplanationTitle.
  ///
  /// In ru, this message translates to:
  /// **'Разбор ситуации по ПДД РФ'**
  String get gameCrossroadsExplanationTitle;

  /// No description provided for @gameCrossroadsCompleteTitle.
  ///
  /// In ru, this message translates to:
  /// **'Перекресток разрулен!'**
  String get gameCrossroadsCompleteTitle;

  /// No description provided for @gameGestureRightArm.
  ///
  /// In ru, this message translates to:
  /// **'Рука вперёд'**
  String get gameGestureRightArm;

  /// No description provided for @gameGestureHandsSides.
  ///
  /// In ru, this message translates to:
  /// **'Руки в стороны'**
  String get gameGestureHandsSides;

  /// No description provided for @gameGestureArmUp.
  ///
  /// In ru, this message translates to:
  /// **'Рука вверх'**
  String get gameGestureArmUp;

  /// No description provided for @gameApproachLeft.
  ///
  /// In ru, this message translates to:
  /// **'Левый бок'**
  String get gameApproachLeft;

  /// No description provided for @gameApproachFront.
  ///
  /// In ru, this message translates to:
  /// **'Грудь'**
  String get gameApproachFront;

  /// No description provided for @gameApproachRight.
  ///
  /// In ru, this message translates to:
  /// **'Правый бок'**
  String get gameApproachRight;

  /// No description provided for @gameApproachBack.
  ///
  /// In ru, this message translates to:
  /// **'Спина'**
  String get gameApproachBack;

  /// No description provided for @gameSecondsLeft.
  ///
  /// In ru, this message translates to:
  /// **'{seconds} с'**
  String gameSecondsLeft(int seconds);

  /// No description provided for @gameSignsLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить знаки'**
  String get gameSignsLoadError;

  /// No description provided for @gameRetry.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get gameRetry;

  /// No description provided for @gameRestartRound.
  ///
  /// In ru, this message translates to:
  /// **'Начать сначала'**
  String get gameRestartRound;

  /// No description provided for @gameSignYes.
  ///
  /// In ru, this message translates to:
  /// **'ДА'**
  String get gameSignYes;

  /// No description provided for @gameSignNo.
  ///
  /// In ru, this message translates to:
  /// **'НЕТ'**
  String get gameSignNo;

  /// No description provided for @gameSignCan.
  ///
  /// In ru, this message translates to:
  /// **'МОЖНО'**
  String get gameSignCan;

  /// No description provided for @gameSignCannot.
  ///
  /// In ru, this message translates to:
  /// **'НЕЛЬЗЯ'**
  String get gameSignCannot;

  /// No description provided for @gameUnderstood.
  ///
  /// In ru, this message translates to:
  /// **'Понятно'**
  String get gameUnderstood;

  /// No description provided for @gamePddOfficialText.
  ///
  /// In ru, this message translates to:
  /// **'ПДД РФ:'**
  String get gamePddOfficialText;

  /// No description provided for @gamePromptWhereCanGo.
  ///
  /// In ru, this message translates to:
  /// **'Куда можно проехать?'**
  String get gamePromptWhereCanGo;

  /// No description provided for @gameCaptionGesture.
  ///
  /// In ru, this message translates to:
  /// **'Жест'**
  String get gameCaptionGesture;

  /// No description provided for @gameCaptionApproach.
  ///
  /// In ru, this message translates to:
  /// **'К вам повёрнут'**
  String get gameCaptionApproach;

  /// No description provided for @gameAnswerWrong.
  ///
  /// In ru, this message translates to:
  /// **'Неверно'**
  String get gameAnswerWrong;

  /// No description provided for @achievementTitleTrafficController.
  ///
  /// In ru, this message translates to:
  /// **'Мастер сигналов'**
  String get achievementTitleTrafficController;

  /// No description provided for @achievementDescTrafficController.
  ///
  /// In ru, this message translates to:
  /// **'Наберите 1000, 2500, 5000 и 7500 очков за одну игру с регулировщиком.'**
  String get achievementDescTrafficController;

  /// No description provided for @achievementTitleSignSwiper.
  ///
  /// In ru, this message translates to:
  /// **'Знаток знаков'**
  String get achievementTitleSignSwiper;

  /// No description provided for @achievementDescSignSwiper.
  ///
  /// In ru, this message translates to:
  /// **'Наберите 1000, 2500, 5000 и 7500 очков за одну игру в «Знак-свайпер».'**
  String get achievementDescSignSwiper;

  /// No description provided for @gameSignQuestionScope.
  ///
  /// In ru, this message translates to:
  /// **'Других знаков и запретов нет'**
  String get gameSignQuestionScope;

  /// No description provided for @gameTrafficSignalQuestion.
  ///
  /// In ru, this message translates to:
  /// **'Что разрешает сигнал?'**
  String get gameTrafficSignalQuestion;

  /// No description provided for @gameTrafficHintButton.
  ///
  /// In ru, this message translates to:
  /// **'Подсказка'**
  String get gameTrafficHintButton;

  /// No description provided for @gameTrafficHintTitle.
  ///
  /// In ru, this message translates to:
  /// **'Как запомнить'**
  String get gameTrafficHintTitle;

  /// No description provided for @gameTrafficHintPaused.
  ///
  /// In ru, this message translates to:
  /// **'Время на паузе'**
  String get gameTrafficHintPaused;

  /// No description provided for @gameTrafficHintScope.
  ///
  /// In ru, this message translates to:
  /// **'Учитывайте свою полосу, знаки и разметку.'**
  String get gameTrafficHintScope;

  /// No description provided for @gameTrafficHintArmUp.
  ///
  /// In ru, this message translates to:
  /// **'Палка вверх устремлена — всем стоять велит она.'**
  String get gameTrafficHintArmUp;

  /// No description provided for @gameTrafficHintForwardFront.
  ///
  /// In ru, this message translates to:
  /// **'Если палка смотрит в рот — делай правый поворот.'**
  String get gameTrafficHintForwardFront;

  /// No description provided for @gameTrafficHintForwardRight.
  ///
  /// In ru, this message translates to:
  /// **'Если палка смотрит вправо — ехать не имеешь права.'**
  String get gameTrafficHintForwardRight;

  /// No description provided for @gameTrafficHintForwardLeft.
  ///
  /// In ru, this message translates to:
  /// **'Если палка смотрит влево — поезжай как королева.'**
  String get gameTrafficHintForwardLeft;

  /// No description provided for @gameTrafficHintBack.
  ///
  /// In ru, this message translates to:
  /// **'Спина — стена.'**
  String get gameTrafficHintBack;

  /// No description provided for @gameTrafficHintWall.
  ///
  /// In ru, this message translates to:
  /// **'Грудь и спина — для водителя стена.'**
  String get gameTrafficHintWall;

  /// No description provided for @gameTrafficHintSide.
  ///
  /// In ru, this message translates to:
  /// **'Боком встал регулировщик — прямо и направо путь открыт.'**
  String get gameTrafficHintSide;

  /// No description provided for @gameTrafficHintTramLeft.
  ///
  /// In ru, this message translates to:
  /// **'Трамвай едет из рукава в рукав — только налево.'**
  String get gameTrafficHintTramLeft;

  /// No description provided for @gameTrafficHintTramStraight.
  ///
  /// In ru, this message translates to:
  /// **'Трамвай едет из рукава в рукав — только прямо.'**
  String get gameTrafficHintTramStraight;

  /// No description provided for @gameTrafficHintForbidden.
  ///
  /// In ru, this message translates to:
  /// **'Сигнал запрещает движение.'**
  String get gameTrafficHintForbidden;

  /// No description provided for @gameTrafficHintAllowed.
  ///
  /// In ru, this message translates to:
  /// **'Сигнал разрешает: {directions}.'**
  String gameTrafficHintAllowed(String directions);

  /// No description provided for @gameSignScenario1_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак предупреждает о переезде со шлагбаумом?'**
  String get gameSignScenario1_1_0Prompt;

  /// No description provided for @gameSignScenario1_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Впереди железнодорожный переезд со шлагбаумом.'**
  String get gameSignScenario1_1_0Explanation;

  /// No description provided for @gameSignScenario1_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно обгонять за 80 м до переезда?'**
  String get gameSignScenario1_1_1Prompt;

  /// No description provided for @gameSignScenario1_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Обгон запрещён на переезде и за 100 м до него (п. 11.4).'**
  String get gameSignScenario1_1_1Explanation;

  /// No description provided for @gameSignScenario1_1_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно оставить машину в 30 м от переезда?'**
  String get gameSignScenario1_1_2Prompt;

  /// No description provided for @gameSignScenario1_1_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Стоянка запрещена ближе 50 м от переезда (п. 12.5).'**
  String get gameSignScenario1_1_2Explanation;

  /// No description provided for @gameSignScenario1_2_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Впереди переезд без шлагбаума?'**
  String get gameSignScenario1_2_0Prompt;

  /// No description provided for @gameSignScenario1_2_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак предупреждает о переезде без шлагбаума.'**
  String get gameSignScenario1_2_0Explanation;

  /// No description provided for @gameSignScenario1_2_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно развернуться на переезде?'**
  String get gameSignScenario1_2_1Prompt;

  /// No description provided for @gameSignScenario1_2_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. На переезде запрещены разворот и движение задним ходом (пп. 8.11–8.12).'**
  String get gameSignScenario1_2_1Explanation;

  /// No description provided for @gameSignScenario1_3_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'На переезде один железнодорожный путь?'**
  String get gameSignScenario1_3_1_0Prompt;

  /// No description provided for @gameSignScenario1_3_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Этот знак обозначает переезд с одним путём, без шлагбаума.'**
  String get gameSignScenario1_3_1_0Explanation;

  /// No description provided for @gameSignScenario1_3_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак ставят за 150–300 м до переезда?'**
  String get gameSignScenario1_3_1_1Prompt;

  /// No description provided for @gameSignScenario1_3_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак 1.3.1 ставят непосредственно перед переездом.'**
  String get gameSignScenario1_3_1_1Explanation;

  /// No description provided for @gameSignScenario1_5_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Трамвай пересекает дорогу вне перекрёстка, не из депо. Нужно уступить?'**
  String get gameSignScenario1_5_0Prompt;

  /// No description provided for @gameSignScenario1_5_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Вне перекрёстка трамвай имеет преимущество, кроме выезда из депо (п. 18.1).'**
  String get gameSignScenario1_5_0Explanation;

  /// No description provided for @gameSignScenario1_5_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Трамвай выезжает из депо. Он должен уступить автомобилям?'**
  String get gameSignScenario1_5_1Prompt;

  /// No description provided for @gameSignScenario1_5_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. При выезде из депо трамвай уступает другим транспортным средствам (п. 18.1).'**
  String get gameSignScenario1_5_1Explanation;

  /// No description provided for @gameSignScenario1_6_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Без светофора на равнозначном перекрёстке нужно уступить автомобилю справа?'**
  String get gameSignScenario1_6_0Prompt;

  /// No description provided for @gameSignScenario1_6_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. На нерегулируемом равнозначном перекрёстке уступают автомобилям справа (п. 13.11).'**
  String get gameSignScenario1_6_0Explanation;

  /// No description provided for @gameSignScenario1_6_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно обгонять на равнозначном перекрёстке без светофора?'**
  String get gameSignScenario1_6_1Prompt;

  /// No description provided for @gameSignScenario1_6_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. На нерегулируемом перекрёстке обгон разрешён только при движении по главной дороге (п. 11.4).'**
  String get gameSignScenario1_6_1Explanation;

  /// No description provided for @gameSignScenario1_7_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Впереди перекрёсток с круговым движением?'**
  String get gameSignScenario1_7_0Prompt;

  /// No description provided for @gameSignScenario1_7_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак предупреждает о приближении к круговому перекрёстку.'**
  String get gameSignScenario1_7_0Explanation;

  /// No description provided for @gameSignScenario1_7_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Круговое движение начинается прямо у этого знака?'**
  String get gameSignScenario1_7_1Prompt;

  /// No description provided for @gameSignScenario1_7_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Это предупреждение. Направление движения на самом круге задаёт знак 4.3.'**
  String get gameSignScenario1_7_1Explanation;

  /// No description provided for @gameSignScenario1_11_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно развернуться, если дорогу видно только на 70 м?'**
  String get gameSignScenario1_11_1_0Prompt;

  /// No description provided for @gameSignScenario1_11_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Для разворота видимость должна быть не менее 100 м в каждом направлении (п. 8.11).'**
  String get gameSignScenario1_11_1_0Explanation;

  /// No description provided for @gameSignScenario1_11_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Перед опасным поворотом нужно выбрать безопасную скорость?'**
  String get gameSignScenario1_11_1_1Prompt;

  /// No description provided for @gameSignScenario1_11_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Скорость выбирают с учётом поворота и видимости дороги (п. 10.1).'**
  String get gameSignScenario1_11_1_1Explanation;

  /// No description provided for @gameSignScenario1_23_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Здесь на дорогу могут неожиданно выйти дети?'**
  String get gameSignScenario1_23_0Prompt;

  /// No description provided for @gameSignScenario1_23_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак предупреждает об участке, где на дороге могут появиться дети.'**
  String get gameSignScenario1_23_0Explanation;

  /// No description provided for @gameSignScenario1_23_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак разрешает детям переходить дорогу где угодно?'**
  String get gameSignScenario1_23_1Prompt;

  /// No description provided for @gameSignScenario1_23_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак предупреждает водителей, но не меняет правила перехода дороги.'**
  String get gameSignScenario1_23_1Explanation;

  /// No description provided for @gameSignScenario1_25_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Временный знак на жёлтом фоне важнее постоянного, если они противоречат?'**
  String get gameSignScenario1_25_0Prompt;

  /// No description provided for @gameSignScenario1_25_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. При противоречии временных и постоянных знаков выполняют требование временного.'**
  String get gameSignScenario1_25_0Explanation;

  /// No description provided for @gameSignScenario1_25_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Перед знаком дорожных работ обязательно остановиться?'**
  String get gameSignScenario1_25_1Prompt;

  /// No description provided for @gameSignScenario1_25_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Сам знак не требует остановки. Нужно учитывать дорожные работы и выбрать безопасную скорость.'**
  String get gameSignScenario1_25_1Explanation;

  /// No description provided for @gameSignScenario2_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Без светофора вы имеете преимущество перед машиной со второстепенной?'**
  String get gameSignScenario2_1_0Prompt;

  /// No description provided for @gameSignScenario2_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. На нерегулируемом перекрёстке главная дорога даёт преимущество перед второстепенной (п. 13.9).'**
  String get gameSignScenario2_1_0Explanation;

  /// No description provided for @gameSignScenario2_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно ехать на красный, если вы на главной дороге?'**
  String get gameSignScenario2_1_1Prompt;

  /// No description provided for @gameSignScenario2_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. На регулируемом перекрёстке нужно выполнять сигналы светофора (п. 6.15).'**
  String get gameSignScenario2_1_1Explanation;

  /// No description provided for @gameSignScenario2_1_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно оставить машину на проезжей части главной дороги вне населённого пункта?'**
  String get gameSignScenario2_1_2Prompt;

  /// No description provided for @gameSignScenario2_1_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. На таких дорогах стоянка на проезжей части вне населённого пункта запрещена (п. 12.5).'**
  String get gameSignScenario2_1_2Explanation;

  /// No description provided for @gameSignScenario2_2_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак обозначает конец главной дороги?'**
  String get gameSignScenario2_2_0Prompt;

  /// No description provided for @gameSignScenario2_2_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Преимущество, которое давал знак «Главная дорога», заканчивается.'**
  String get gameSignScenario2_2_0Explanation;

  /// No description provided for @gameSignScenario2_2_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак сам по себе требует остановиться?'**
  String get gameSignScenario2_2_1Prompt;

  /// No description provided for @gameSignScenario2_2_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Он отменяет статус главной дороги. Порядок проезда определяют другие знаки и правила.'**
  String get gameSignScenario2_2_1Explanation;

  /// No description provided for @gameSignScenario2_3_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Без светофора машина с пересекаемой дороги должна уступить вам?'**
  String get gameSignScenario2_3_1_0Prompt;

  /// No description provided for @gameSignScenario2_3_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак показывает пересечение главной дороги со второстепенной (п. 13.9).'**
  String get gameSignScenario2_3_1_0Explanation;

  /// No description provided for @gameSignScenario2_3_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Без светофора нужно уступить машине справа со второстепенной дороги?'**
  String get gameSignScenario2_3_1_1Prompt;

  /// No description provided for @gameSignScenario2_3_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Преимущество у вас: вы на главной дороге. Правило «помехи справа» здесь не применяется.'**
  String get gameSignScenario2_3_1_1Explanation;

  /// No description provided for @gameSignScenario2_4_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Без светофора нужно уступить машинам на пересекаемой дороге?'**
  String get gameSignScenario2_4_0Prompt;

  /// No description provided for @gameSignScenario2_4_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак требует уступить машинам на пересекаемой дороге. При табличке 8.13 — машинам на главной дороге.'**
  String get gameSignScenario2_4_0Explanation;

  /// No description provided for @gameSignScenario2_4_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Дорога свободна. Перед этим знаком всё равно нужно остановиться?'**
  String get gameSignScenario2_4_1Prompt;

  /// No description provided for @gameSignScenario2_4_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Обязательной остановки нет, если вы никому не мешаете.'**
  String get gameSignScenario2_4_1Explanation;

  /// No description provided for @gameSignScenario2_4_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Оба на второстепенной: вы прямо, встречный налево. Он должен уступить?'**
  String get gameSignScenario2_4_2Prompt;

  /// No description provided for @gameSignScenario2_4_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. При равном приоритете встречный автомобиль, поворачивающий налево, уступает едущему прямо (п. 13.12).'**
  String get gameSignScenario2_4_2Explanation;

  /// No description provided for @gameSignScenario2_5_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Перед STOP нужно остановиться, даже если дорога свободна?'**
  String get gameSignScenario2_5_0Prompt;

  /// No description provided for @gameSignScenario2_5_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Остановитесь перед стоп-линией, а если её нет — перед краем пересекаемой проезжей части. У переезда без стоп-линии — перед знаком.'**
  String get gameSignScenario2_5_0Explanation;

  /// No description provided for @gameSignScenario2_5_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно проехать STOP без остановки, если всё хорошо видно?'**
  String get gameSignScenario2_5_1Prompt;

  /// No description provided for @gameSignScenario2_5_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак требует полной остановки даже при свободной дороге.'**
  String get gameSignScenario2_5_1Explanation;

  /// No description provided for @gameSignScenario2_6_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Въезд помешает встречной машине. Нужно уступить?'**
  String get gameSignScenario2_6_0Prompt;

  /// No description provided for @gameSignScenario2_6_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Нельзя въезжать на узкий участок, если это затруднит встречное движение.'**
  String get gameSignScenario2_6_0Explanation;

  /// No description provided for @gameSignScenario2_6_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак даёт вам преимущество перед встречными?'**
  String get gameSignScenario2_6_1Prompt;

  /// No description provided for @gameSignScenario2_6_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Преимущество у встречного транспорта.'**
  String get gameSignScenario2_6_1Explanation;

  /// No description provided for @gameSignScenario2_7_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'На узком участке преимущество у вас?'**
  String get gameSignScenario2_7_0Prompt;

  /// No description provided for @gameSignScenario2_7_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Этот знак даёт преимущество перед встречными машинами.'**
  String get gameSignScenario2_7_0Explanation;

  /// No description provided for @gameSignScenario2_7_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак даёт преимущество встречной машине?'**
  String get gameSignScenario2_7_1Prompt;

  /// No description provided for @gameSignScenario2_7_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Преимущество у транспорта, движущегося в вашем направлении.'**
  String get gameSignScenario2_7_1Explanation;

  /// No description provided for @gameSignScenario3_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак запрещает въезд обычному такси?'**
  String get gameSignScenario3_1_0Prompt;

  /// No description provided for @gameSignScenario3_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Такси и каршеринг должны выполнять запрет. Исключение — маршрутный транспорт.'**
  String get gameSignScenario3_1_0Explanation;

  /// No description provided for @gameSignScenario3_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно въехать, только потому что вы живёте за знаком?'**
  String get gameSignScenario3_1_1Prompt;

  /// No description provided for @gameSignScenario3_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Для жителей исключения нет. Не путайте этот знак со знаком «Движение запрещено».'**
  String get gameSignScenario3_1_1Explanation;

  /// No description provided for @gameSignScenario3_1_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно въехать маршрутному автобусу на своём маршруте?'**
  String get gameSignScenario3_1_2Prompt;

  /// No description provided for @gameSignScenario3_1_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Запрет этого знака не действует на маршрутные транспортные средства.'**
  String get gameSignScenario3_1_2Explanation;

  /// No description provided for @gameSignScenario3_2_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно проехать к своему дому в зоне этого знака?'**
  String get gameSignScenario3_2_0Prompt;

  /// No description provided for @gameSignScenario3_2_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Жителям разрешён проезд к дому. Въезжать и выезжать нужно на ближайшем к нему перекрёстке.'**
  String get gameSignScenario3_2_0Explanation;

  /// No description provided for @gameSignScenario3_2_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно проехать эту зону насквозь на обычном автомобиле?'**
  String get gameSignScenario3_2_1Prompt;

  /// No description provided for @gameSignScenario3_2_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак запрещает движение. Проезд жителей и обслуживающих машин — исключения для доступа к месту назначения.'**
  String get gameSignScenario3_2_1Explanation;

  /// No description provided for @gameSignScenario3_2_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак запрещает проезд водителю с инвалидностью I группы и знаком «Инвалид»?'**
  String get gameSignScenario3_2_2Prompt;

  /// No description provided for @gameSignScenario3_2_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак не действует на машины водителей с инвалидностью I–II групп или перевозящие их и детей-инвалидов, со знаком «Инвалид».'**
  String get gameSignScenario3_2_2Explanation;

  /// No description provided for @gameSignScenario3_4_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак запрещает движение легковых автомобилей?'**
  String get gameSignScenario3_4_0Prompt;

  /// No description provided for @gameSignScenario3_4_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Он ограничивает движение грузовиков, тракторов и самоходных машин.'**
  String get gameSignScenario3_4_0Explanation;

  /// No description provided for @gameSignScenario3_4_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно обычному грузовику с разрешённой массой 5 т проехать под этот знак?'**
  String get gameSignScenario3_4_1Prompt;

  /// No description provided for @gameSignScenario3_4_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. На показанном знаке указан порог 8 т. Разрешённая максимальная масса 5 т его не превышает.'**
  String get gameSignScenario3_4_1Explanation;

  /// No description provided for @gameSignScenario3_18_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак запрещает поворот налево?'**
  String get gameSignScenario3_18_1_0Prompt;

  /// No description provided for @gameSignScenario3_18_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Он запрещает только поворот направо на ближайшем пересечении проезжих частей.'**
  String get gameSignScenario3_18_1_0Explanation;

  /// No description provided for @gameSignScenario3_18_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно повернуть направо на ближайшем пересечении?'**
  String get gameSignScenario3_18_1_1Prompt;

  /// No description provided for @gameSignScenario3_18_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Поворот направо на ближайшем пересечении запрещён.'**
  String get gameSignScenario3_18_1_1Explanation;

  /// No description provided for @gameSignScenario3_18_2_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак запрещает разворот?'**
  String get gameSignScenario3_18_2_0Prompt;

  /// No description provided for @gameSignScenario3_18_2_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Он запрещает поворот налево, но сам по себе не запрещает разворот.'**
  String get gameSignScenario3_18_2_0Explanation;

  /// No description provided for @gameSignScenario3_18_2_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно повернуть налево на ближайшем пересечении?'**
  String get gameSignScenario3_18_2_1Prompt;

  /// No description provided for @gameSignScenario3_18_2_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Поворот налево на ближайшем пересечении запрещён.'**
  String get gameSignScenario3_18_2_1Explanation;

  /// No description provided for @gameSignScenario3_19_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак запрещает поворот налево?'**
  String get gameSignScenario3_19_0Prompt;

  /// No description provided for @gameSignScenario3_19_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Он запрещает только разворот.'**
  String get gameSignScenario3_19_0Explanation;

  /// No description provided for @gameSignScenario3_19_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно развернуться в месте действия этого знака?'**
  String get gameSignScenario3_19_1Prompt;

  /// No description provided for @gameSignScenario3_19_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Разворот запрещён.'**
  String get gameSignScenario3_19_1Explanation;

  /// No description provided for @gameSignScenario3_20_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак разрешает обгон тихоходной машины с соответствующим знаком?'**
  String get gameSignScenario3_20_0Prompt;

  /// No description provided for @gameSignScenario3_20_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Тихоходные машины — исключение из запрета знака 3.20. Другие запреты обгона и разметку тоже нужно учитывать.'**
  String get gameSignScenario3_20_0Explanation;

  /// No description provided for @gameSignScenario3_20_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно обогнать обычную легковую машину, если она едет всего 25 км/ч?'**
  String get gameSignScenario3_20_1Prompt;

  /// No description provided for @gameSignScenario3_20_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Низкая скорость не делает легковой автомобиль тихоходным транспортным средством.'**
  String get gameSignScenario3_20_1Explanation;

  /// No description provided for @gameSignScenario3_20_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак разрешает обгон мотоцикла без коляски?'**
  String get gameSignScenario3_20_2Prompt;

  /// No description provided for @gameSignScenario3_20_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Двухколёсные мотоциклы без бокового прицепа — исключение из запрета этого знака.'**
  String get gameSignScenario3_20_2Explanation;

  /// No description provided for @gameSignScenario3_24_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Число на знаке — максимально разрешённая скорость?'**
  String get gameSignScenario3_24_0Prompt;

  /// No description provided for @gameSignScenario3_24_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Быстрее указанного ехать нельзя. При плохой видимости безопасная скорость может быть ниже.'**
  String get gameSignScenario3_24_0Explanation;

  /// No description provided for @gameSignScenario3_24_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак требует ехать не медленнее указанного числа?'**
  String get gameSignScenario3_24_1Prompt;

  /// No description provided for @gameSignScenario3_24_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Это ограничение максимальной скорости, а не минимальной.'**
  String get gameSignScenario3_24_1Explanation;

  /// No description provided for @gameSignScenario3_27_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно остановить обычную машину на минуту, чтобы высадить пассажира?'**
  String get gameSignScenario3_27_0Prompt;

  /// No description provided for @gameSignScenario3_27_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак запрещает остановку и стоянку. Высадка пассажира — тоже остановка.'**
  String get gameSignScenario3_27_0Explanation;

  /// No description provided for @gameSignScenario3_27_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак «Инвалид» сам по себе разрешает остановку здесь?'**
  String get gameSignScenario3_27_1Prompt;

  /// No description provided for @gameSignScenario3_27_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Льгота сама по себе не отменяет знак «Остановка запрещена». Исключение может обозначаться табличкой 8.18.'**
  String get gameSignScenario3_27_1Explanation;

  /// No description provided for @gameSignScenario3_27_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно оставить обычную машину под этим знаком?'**
  String get gameSignScenario3_27_2Prompt;

  /// No description provided for @gameSignScenario3_27_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак запрещает и остановку, и стоянку.'**
  String get gameSignScenario3_27_2Explanation;

  /// No description provided for @gameSignScenario3_28_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно остановиться, чтобы высадить пассажира?'**
  String get gameSignScenario3_28_0Prompt;

  /// No description provided for @gameSignScenario3_28_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак запрещает стоянку, но допускает остановку. Время, необходимое для посадки, высадки или погрузки, может превышать 5 минут.'**
  String get gameSignScenario3_28_0Explanation;

  /// No description provided for @gameSignScenario3_28_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно оставить обычную машину на 20 минут, без посадки и погрузки?'**
  String get gameSignScenario3_28_1Prompt;

  /// No description provided for @gameSignScenario3_28_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Это стоянка: остановка более 5 минут, не связанная с посадкой, высадкой или погрузкой (п. 1.2).'**
  String get gameSignScenario3_28_1Explanation;

  /// No description provided for @gameSignScenario3_28_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот запрет действует на машину со знаком «Инвалид», имеющую право на льготу?'**
  String get gameSignScenario3_28_2Prompt;

  /// No description provided for @gameSignScenario3_28_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. При наличии права на бесплатную парковку и знака «Инвалид» предусмотрено исключение, включая перевозку таких инвалидов и детей-инвалидов.'**
  String get gameSignScenario3_28_2Explanation;

  /// No description provided for @gameSignScenario3_29_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знаки запрета по чётным и нечётным дням стоят с двух сторон. Можно парковаться с 21 до 24 часов?'**
  String get gameSignScenario3_29_0Prompt;

  /// No description provided for @gameSignScenario3_29_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. При таком сочетании знаков с 21:00 до 24:00 — время перестановки, когда стоянка разрешена с обеих сторон.'**
  String get gameSignScenario3_29_0Explanation;

  /// No description provided for @gameSignScenario3_29_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак запрещает остановку на 3 минуты для посадки пассажира?'**
  String get gameSignScenario3_29_1Prompt;

  /// No description provided for @gameSignScenario3_29_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Он запрещает только стоянку по нечётным числам. Остановка разрешена.'**
  String get gameSignScenario3_29_1Explanation;

  /// No description provided for @gameSignScenario3_31_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак отменяет ограничения обгона и скорости?'**
  String get gameSignScenario3_31_0Prompt;

  /// No description provided for @gameSignScenario3_31_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Он завершает действие знаков 3.16, 3.20, 3.22, 3.24 и 3.26–3.30.'**
  String get gameSignScenario3_31_0Explanation;

  /// No description provided for @gameSignScenario3_31_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак отменяет сигналы светофора и разметку?'**
  String get gameSignScenario3_31_1Prompt;

  /// No description provided for @gameSignScenario3_31_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Светофоры и разметка продолжают действовать.'**
  String get gameSignScenario3_31_1Explanation;

  /// No description provided for @gameSignScenario4_1_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак стоит в начале участка. Можно повернуть направо во двор?'**
  String get gameSignScenario4_1_1_0Prompt;

  /// No description provided for @gameSignScenario4_1_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. В начале участка знак действует до ближайшего перекрёстка, но разрешает поворот направо на прилегающую территорию.'**
  String get gameSignScenario4_1_1_0Explanation;

  /// No description provided for @gameSignScenario4_1_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак стоит перед перекрёстком. Можно повернуть налево?'**
  String get gameSignScenario4_1_1_1Prompt;

  /// No description provided for @gameSignScenario4_1_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. На ближайшем пересечении проезжих частей разрешено только прямо.'**
  String get gameSignScenario4_1_1_1Explanation;

  /// No description provided for @gameSignScenario4_1_2_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'На ближайшем пересечении нужно повернуть направо?'**
  String get gameSignScenario4_1_2_0Prompt;

  /// No description provided for @gameSignScenario4_1_2_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Для обычного автомобиля знак разрешает только поворот направо.'**
  String get gameSignScenario4_1_2_0Explanation;

  /// No description provided for @gameSignScenario4_1_2_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно ехать прямо на ближайшем пересечении?'**
  String get gameSignScenario4_1_2_1Prompt;

  /// No description provided for @gameSignScenario4_1_2_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак разрешает только направо.'**
  String get gameSignScenario4_1_2_1Explanation;

  /// No description provided for @gameSignScenario4_1_3_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак разрешает разворот?'**
  String get gameSignScenario4_1_3_0Prompt;

  /// No description provided for @gameSignScenario4_1_3_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак, разрешающий поворот налево, разрешает и разворот.'**
  String get gameSignScenario4_1_3_0Explanation;

  /// No description provided for @gameSignScenario4_1_3_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно ехать прямо на ближайшем пересечении?'**
  String get gameSignScenario4_1_3_1Prompt;

  /// No description provided for @gameSignScenario4_1_3_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак разрешает налево и разворот.'**
  String get gameSignScenario4_1_3_1Explanation;

  /// No description provided for @gameSignScenario4_1_4_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно ехать прямо или направо?'**
  String get gameSignScenario4_1_4_0Prompt;

  /// No description provided for @gameSignScenario4_1_4_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак разрешает оба этих направления.'**
  String get gameSignScenario4_1_4_0Explanation;

  /// No description provided for @gameSignScenario4_1_4_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно развернуться на ближайшем пересечении?'**
  String get gameSignScenario4_1_4_1Prompt;

  /// No description provided for @gameSignScenario4_1_4_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Разрешены только прямо и направо.'**
  String get gameSignScenario4_1_4_1Explanation;

  /// No description provided for @gameSignScenario4_1_5_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно развернуться из крайней левой полосы?'**
  String get gameSignScenario4_1_5_0Prompt;

  /// No description provided for @gameSignScenario4_1_5_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Разрешённый поворот налево допускает и разворот.'**
  String get gameSignScenario4_1_5_0Explanation;

  /// No description provided for @gameSignScenario4_1_5_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно повернуть направо на ближайшем пересечении?'**
  String get gameSignScenario4_1_5_1Prompt;

  /// No description provided for @gameSignScenario4_1_5_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак разрешает прямо, налево и разворот.'**
  String get gameSignScenario4_1_5_1Explanation;

  /// No description provided for @gameSignScenario4_2_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Препятствие нужно объехать справа?'**
  String get gameSignScenario4_2_1_0Prompt;

  /// No description provided for @gameSignScenario4_2_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Объезд разрешён только с указанной стрелкой стороны.'**
  String get gameSignScenario4_2_1_0Explanation;

  /// No description provided for @gameSignScenario4_2_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно объехать препятствие слева, если встречных нет?'**
  String get gameSignScenario4_2_1_1Prompt;

  /// No description provided for @gameSignScenario4_2_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Отсутствие встречных не отменяет предписанную сторону объезда.'**
  String get gameSignScenario4_2_1_1Explanation;

  /// No description provided for @gameSignScenario4_3_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'По кругу нужно ехать в направлении стрелок?'**
  String get gameSignScenario4_3_0Prompt;

  /// No description provided for @gameSignScenario4_3_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак задаёт направление кругового движения.'**
  String get gameSignScenario4_3_0Explanation;

  /// No description provided for @gameSignScenario4_3_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно ехать по кругу против стрелок?'**
  String get gameSignScenario4_3_1Prompt;

  /// No description provided for @gameSignScenario4_3_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. По кругу едут только в указанном стрелками направлении.'**
  String get gameSignScenario4_3_1Explanation;

  /// No description provided for @gameSignScenario4_6_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак задаёт минимальную скорость?'**
  String get gameSignScenario4_6_0Prompt;

  /// No description provided for @gameSignScenario4_6_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Можно ехать с указанной или большей скоростью, соблюдая максимальный предел и безопасность.'**
  String get gameSignScenario4_6_0Explanation;

  /// No description provided for @gameSignScenario4_6_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак задаёт максимальную скорость?'**
  String get gameSignScenario4_6_1Prompt;

  /// No description provided for @gameSignScenario4_6_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Это минимальная скорость. Максимальную ограничивает знак 3.24.'**
  String get gameSignScenario4_6_1Explanation;

  /// No description provided for @gameSignScenario5_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Легковое авто без прицепа: общий предел на автомагистрали 110 км/ч?'**
  String get gameSignScenario5_1_0Prompt;

  /// No description provided for @gameSignScenario5_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Общий предел для легкового автомобиля без прицепа — 110 км/ч. Знаки могут устанавливать другой предел (п. 10.3).'**
  String get gameSignScenario5_1_0Explanation;

  /// No description provided for @gameSignScenario5_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно сдать назад на автомагистрали?'**
  String get gameSignScenario5_1_1Prompt;

  /// No description provided for @gameSignScenario5_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. На автомагистрали движение задним ходом запрещено (п. 16.1).'**
  String get gameSignScenario5_1_1Explanation;

  /// No description provided for @gameSignScenario5_1_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Мопеду можно на автомагистраль?'**
  String get gameSignScenario5_1_2Prompt;

  /// No description provided for @gameSignScenario5_1_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Движение мопедов по автомагистралям запрещено (п. 16.1).'**
  String get gameSignScenario5_1_2Explanation;

  /// No description provided for @gameSignScenario5_3_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'На этой дороге запрещено движение задним ходом?'**
  String get gameSignScenario5_3_0Prompt;

  /// No description provided for @gameSignScenario5_3_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. На дороге для автомобилей действуют запреты раздела 16, как на автомагистрали (п. 16.3).'**
  String get gameSignScenario5_3_0Explanation;

  /// No description provided for @gameSignScenario5_3_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно остановиться на обочине просто для отдыха?'**
  String get gameSignScenario5_3_1Prompt;

  /// No description provided for @gameSignScenario5_3_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Преднамеренная остановка допускается на специальных площадках. Вынужденная остановка — отдельный случай.'**
  String get gameSignScenario5_3_1Explanation;

  /// No description provided for @gameSignScenario5_5_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно сдать назад на односторонней дороге, если это безопасно и место разрешает?'**
  String get gameSignScenario5_5_0Prompt;

  /// No description provided for @gameSignScenario5_5_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Сам знак этого не запрещает. Нельзя сдавать назад на перекрёстках, переходах и в других местах из пп. 8.11–8.12.'**
  String get gameSignScenario5_5_0Explanation;

  /// No description provided for @gameSignScenario5_5_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно развернуться и ехать против одностороннего движения?'**
  String get gameSignScenario5_5_1Prompt;

  /// No description provided for @gameSignScenario5_5_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Это движение против установленного направления.'**
  String get gameSignScenario5_5_1Explanation;

  /// No description provided for @gameSignScenario5_5_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'В населённом пункте можно парковать легковое авто слева на односторонней дороге?'**
  String get gameSignScenario5_5_2Prompt;

  /// No description provided for @gameSignScenario5_5_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Для легкового автомобиля это разрешено, если нет других запретов (п. 12.1).'**
  String get gameSignScenario5_5_2Explanation;

  /// No description provided for @gameSignScenario5_14_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Такси и школьному автобусу можно ехать по этой полосе?'**
  String get gameSignScenario5_14_1_0Prompt;

  /// No description provided for @gameSignScenario5_14_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Пункт 18.2 допускает легковые такси и школьные автобусы. Велосипедистам можно лишь по такой полосе справа.'**
  String get gameSignScenario5_14_1_0Explanation;

  /// No description provided for @gameSignScenario5_14_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно обычной легковушке ехать по автобусной полосе вдоль дороги?'**
  String get gameSignScenario5_14_1_1Prompt;

  /// No description provided for @gameSignScenario5_14_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Обычным автомобилям движение по полосе запрещено. Перестроение для поворота, въезд и высадка при прерывистой разметке — отдельные исключения.'**
  String get gameSignScenario5_14_1_1Explanation;

  /// No description provided for @gameSignScenario5_15_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Стрелка налево из крайней левой полосы разрешает и разворот?'**
  String get gameSignScenario5_15_1_0Prompt;

  /// No description provided for @gameSignScenario5_15_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Разворот разрешается из крайней левой полосы, если знак разрешает из неё поворот налево.'**
  String get gameSignScenario5_15_1_0Explanation;

  /// No description provided for @gameSignScenario5_19_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Без светофора нужно уступить пешеходу, который переходит вашу дорогу?'**
  String get gameSignScenario5_19_1_0Prompt;

  /// No description provided for @gameSignScenario5_19_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. На нерегулируемом переходе нужно уступить переходящим или вступившим на проезжую часть пешеходам (п. 14.1).'**
  String get gameSignScenario5_19_1_0Explanation;

  /// No description provided for @gameSignScenario5_19_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно сдать назад на пешеходном переходе?'**
  String get gameSignScenario5_19_1_1Prompt;

  /// No description provided for @gameSignScenario5_19_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. На переходе запрещены и движение задним ходом, и разворот (пп. 8.11–8.12).'**
  String get gameSignScenario5_19_1_1Explanation;

  /// No description provided for @gameSignScenario5_19_1_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно остановиться за 3 м перед переходом?'**
  String get gameSignScenario5_19_1_2Prompt;

  /// No description provided for @gameSignScenario5_19_1_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Остановка запрещена на переходе и ближе 5 м перед ним (п. 12.4).'**
  String get gameSignScenario5_19_1_2Explanation;

  /// No description provided for @gameSignScenario5_20_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак показывает начало искусственной неровности?'**
  String get gameSignScenario5_20_0Prompt;

  /// No description provided for @gameSignScenario5_20_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Его устанавливают на ближайшей границе искусственной неровности.'**
  String get gameSignScenario5_20_0Explanation;

  /// No description provided for @gameSignScenario5_20_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Перед искусственной неровностью обязательно остановиться?'**
  String get gameSignScenario5_20_1Prompt;

  /// No description provided for @gameSignScenario5_20_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак не требует остановки. Выберите безопасную скорость для проезда.'**
  String get gameSignScenario5_20_1Explanation;

  /// No description provided for @gameSignScenario5_21_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'В жилой зоне пешеходы имеют преимущество?'**
  String get gameSignScenario5_21_0Prompt;

  /// No description provided for @gameSignScenario5_21_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Пешеходы могут идти и по тротуару, и по проезжей части, но не должны необоснованно мешать машинам (п. 17.1).'**
  String get gameSignScenario5_21_0Explanation;

  /// No description provided for @gameSignScenario5_21_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно ехать по жилой зоне со скоростью 30 км/ч?'**
  String get gameSignScenario5_21_1Prompt;

  /// No description provided for @gameSignScenario5_21_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. В жилой зоне и во дворе предел — 20 км/ч (п. 10.2).'**
  String get gameSignScenario5_21_1Explanation;

  /// No description provided for @gameSignScenario5_21_2Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно проехать жилую зону насквозь, чтобы сократить путь?'**
  String get gameSignScenario5_21_2Prompt;

  /// No description provided for @gameSignScenario5_21_2Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Сквозное движение в жилой зоне запрещено (п. 17.2).'**
  String get gameSignScenario5_21_2Explanation;

  /// No description provided for @gameSignScenario5_23_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'После этого знака общий предел скорости — 60 км/ч?'**
  String get gameSignScenario5_23_1_0Prompt;

  /// No description provided for @gameSignScenario5_23_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Здесь начинаются правила для населённого пункта. Общий предел — 60 км/ч, если не установлен другой (п. 10.2).'**
  String get gameSignScenario5_23_1_0Explanation;

  /// No description provided for @gameSignScenario5_23_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно сразу после этого знака ехать 90 км/ч без других знаков?'**
  String get gameSignScenario5_23_1_1Prompt;

  /// No description provided for @gameSignScenario5_23_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Действует общий предел населённого пункта — 60 км/ч.'**
  String get gameSignScenario5_23_1_1Explanation;

  /// No description provided for @gameSignScenario5_25_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак сам по себе вводит предел 60 км/ч?'**
  String get gameSignScenario5_25_0Prompt;

  /// No description provided for @gameSignScenario5_25_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. На обозначенной дороге правила для населённого пункта не действуют. Скорость зависит от дороги, машины и других знаков.'**
  String get gameSignScenario5_25_0Explanation;

  /// No description provided for @gameSignScenario5_25_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Синий знак населённого пункта отменяет ранее установленный предел скорости?'**
  String get gameSignScenario5_25_1Prompt;

  /// No description provided for @gameSignScenario5_25_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Сам знак не отменяет ограничение скорости, установленное другим знаком.'**
  String get gameSignScenario5_25_1Explanation;

  /// No description provided for @gameSignScenario6_2_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Скорость на этом знаке — рекомендация?'**
  String get gameSignScenario6_2_0Prompt;

  /// No description provided for @gameSignScenario6_2_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак рекомендует скорость, но не отменяет обязательные ограничения и требование безопасности.'**
  String get gameSignScenario6_2_0Explanation;

  /// No description provided for @gameSignScenario6_2_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Нужно обязательно ехать ровно с указанной скоростью?'**
  String get gameSignScenario6_2_1Prompt;

  /// No description provided for @gameSignScenario6_2_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Это рекомендуемая, а не обязательная скорость.'**
  String get gameSignScenario6_2_1Explanation;

  /// No description provided for @gameSignScenario6_3_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак обозначает место для разворота?'**
  String get gameSignScenario6_3_1_0Prompt;

  /// No description provided for @gameSignScenario6_3_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Здесь предусмотрено место для разворота.'**
  String get gameSignScenario6_3_1_0Explanation;

  /// No description provided for @gameSignScenario6_3_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно здесь повернуть налево во двор?'**
  String get gameSignScenario6_3_1_1Prompt;

  /// No description provided for @gameSignScenario6_3_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знак обозначает место для разворота и запрещает поворот налево.'**
  String get gameSignScenario6_3_1_1Explanation;

  /// No description provided for @gameSignScenario6_4_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак обозначает парковку?'**
  String get gameSignScenario6_4_0Prompt;

  /// No description provided for @gameSignScenario6_4_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак указывает парковку. Таблички могут уточнять, кому, когда и как разрешена стоянка.'**
  String get gameSignScenario6_4_0Explanation;

  /// No description provided for @gameSignScenario6_4_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Перед этим знаком нужно обязательно остановиться?'**
  String get gameSignScenario6_4_1Prompt;

  /// No description provided for @gameSignScenario6_4_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Он указывает место парковки, а не требует остановки.'**
  String get gameSignScenario6_4_1Explanation;

  /// No description provided for @gameSignScenario6_16_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак показывает, где остановиться на запрещающий сигнал?'**
  String get gameSignScenario6_16_0Prompt;

  /// No description provided for @gameSignScenario6_16_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Остановитесь перед знаком при запрещающем сигнале светофора или регулировщика (п. 6.13).'**
  String get gameSignScenario6_16_0Explanation;

  /// No description provided for @gameSignScenario6_16_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Светофор зелёный, регулировщика нет. Знак требует остановиться?'**
  String get gameSignScenario6_16_1Prompt;

  /// No description provided for @gameSignScenario6_16_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Сам знак «Стоп-линия» при разрешающем сигнале не требует остановки.'**
  String get gameSignScenario6_16_1Explanation;

  /// No description provided for @gameSignScenario7_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак указывает пункт первой медицинской помощи?'**
  String get gameSignScenario7_1_0Prompt;

  /// No description provided for @gameSignScenario7_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Он сообщает, где находится пункт первой медицинской помощи.'**
  String get gameSignScenario7_1_0Explanation;

  /// No description provided for @gameSignScenario7_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак сам по себе ограничивает скорость до 20 км/ч?'**
  String get gameSignScenario7_1_1Prompt;

  /// No description provided for @gameSignScenario7_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Знаки сервиса не вводят ограничений скорости.'**
  String get gameSignScenario7_1_1Explanation;

  /// No description provided for @gameSignScenario7_3_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак указывает автозаправку?'**
  String get gameSignScenario7_3_0Prompt;

  /// No description provided for @gameSignScenario7_3_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Знак обозначает автозаправочную станцию.'**
  String get gameSignScenario7_3_0Explanation;

  /// No description provided for @gameSignScenario7_3_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Этот знак даёт преимущество при выезде с заправки на дорогу?'**
  String get gameSignScenario7_3_1Prompt;

  /// No description provided for @gameSignScenario7_3_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. При выезде с прилегающей территории нужно уступить участникам движения на дороге (п. 8.3).'**
  String get gameSignScenario7_3_1Explanation;

  /// No description provided for @gameSignScenario8_1_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Табличка показывает расстояние до объекта или начала ограничения?'**
  String get gameSignScenario8_1_1_0Prompt;

  /// No description provided for @gameSignScenario8_1_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Это расстояние от знака до опасного участка, объекта или места начала ограничения.'**
  String get gameSignScenario8_1_1_0Explanation;

  /// No description provided for @gameSignScenario8_1_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Табличка показывает длину зоны действия знака?'**
  String get gameSignScenario8_1_1_1Prompt;

  /// No description provided for @gameSignScenario8_1_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Длину зоны действия показывает табличка 8.2.1.'**
  String get gameSignScenario8_1_1_1Explanation;

  /// No description provided for @gameSignScenario8_2_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Табличка показывает длину опасного участка или зоны действия?'**
  String get gameSignScenario8_2_1_0Prompt;

  /// No description provided for @gameSignScenario8_2_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Это протяжённость участка или зоны действия знака.'**
  String get gameSignScenario8_2_1_0Explanation;

  /// No description provided for @gameSignScenario8_2_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак начнёт действовать только через указанное расстояние?'**
  String get gameSignScenario8_2_1_1Prompt;

  /// No description provided for @gameSignScenario8_2_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Табличка показывает длину зоны, а не расстояние до её начала.'**
  String get gameSignScenario8_2_1_1Explanation;

  /// No description provided for @gameSignScenario8_2_3_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Стрелка вниз означает конец запрета остановки или стоянки?'**
  String get gameSignScenario8_2_3_0Prompt;

  /// No description provided for @gameSignScenario8_2_3_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Она указывает конец зоны действия знаков 3.27–3.30.'**
  String get gameSignScenario8_2_3_0Explanation;

  /// No description provided for @gameSignScenario8_2_3_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'После этой таблички прежний запрет стоянки продолжается?'**
  String get gameSignScenario8_2_3_1Prompt;

  /// No description provided for @gameSignScenario8_2_3_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Зона запрета заканчивается. Другие правила остановки и стоянки сохраняются.'**
  String get gameSignScenario8_2_3_1Explanation;

  /// No description provided for @gameSignScenario8_4_1_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Табличка относится к грузовикам с разрешённой массой более 3,5 т?'**
  String get gameSignScenario8_4_1_0Prompt;

  /// No description provided for @gameSignScenario8_4_1_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. В том числе к таким грузовикам с прицепом. Учитывают разрешённую максимальную, а не фактическую массу.'**
  String get gameSignScenario8_4_1_0Explanation;

  /// No description provided for @gameSignScenario8_4_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак с этой табличкой действует на легковое авто?'**
  String get gameSignScenario8_4_1_1Prompt;

  /// No description provided for @gameSignScenario8_4_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Табличка распространяет знак на грузовики с разрешённой максимальной массой более 3,5 т.'**
  String get gameSignScenario8_4_1_1Explanation;

  /// No description provided for @gameSignScenario8_4_3_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Табличка относится к легковым авто и грузовикам до 3,5 т включительно?'**
  String get gameSignScenario8_4_3_0Prompt;

  /// No description provided for @gameSignScenario8_4_3_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Учитывается разрешённая максимальная масса грузовика.'**
  String get gameSignScenario8_4_3_0Explanation;

  /// No description provided for @gameSignScenario8_4_3_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Знак с этой табличкой действует на автобус?'**
  String get gameSignScenario8_4_3_1Prompt;

  /// No description provided for @gameSignScenario8_4_3_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Эта табличка относится к легковым автомобилям и грузовикам до 3,5 т включительно.'**
  String get gameSignScenario8_4_3_1Explanation;

  /// No description provided for @gameSignScenario8_17_0Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Со знаком парковки табличка выделяет места для машин со знаком «Инвалид»?'**
  String get gameSignScenario8_17_0Prompt;

  /// No description provided for @gameSignScenario8_17_0Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Да. Места предназначены для машин, имеющих право на такую парковку, с опознавательным знаком «Инвалид», в том числе перевозящих детей-инвалидов.'**
  String get gameSignScenario8_17_0Explanation;

  /// No description provided for @gameSignScenario8_17_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Можно оставить здесь обычную машину без знака «Инвалид» на 10 минут?'**
  String get gameSignScenario8_17_1Prompt;

  /// No description provided for @gameSignScenario8_17_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Эти парковочные места предназначены для машин со знаком «Инвалид», имеющих право на льготу.'**
  String get gameSignScenario8_17_1Explanation;

  /// No description provided for @gameSignScenario5_15_1_1Prompt.
  ///
  /// In ru, this message translates to:
  /// **'Из средней полосы стрелка только прямо. Можно повернуть налево?'**
  String get gameSignScenario5_15_1_1Prompt;

  /// No description provided for @gameSignScenario5_15_1_1Explanation.
  ///
  /// In ru, this message translates to:
  /// **'Нет. Из этой полосы разрешено только прямо. Для поворота нужно заранее занять подходящую полосу.'**
  String get gameSignScenario5_15_1_1Explanation;
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
      <String>['ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
