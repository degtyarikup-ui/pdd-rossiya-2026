import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Тонкая обёртка над локализацией: строки берутся из ARB текущего языка
/// сборки (см. [appL10n]). Существующие call-sites `AppStrings.*` не менялись —
/// теперь они автоматически переводятся под язык страны.
class AppStrings {
  AppStrings._();

  static String get appName => CountryConfig.current.appTitle;
  static String get exam => appL10n.exam;
  static String get topics => appL10n.topics;
  static String get tickets => appL10n.tickets;
  static String get passedQuestions => appL10n.passedQuestions;
  static String get passedTickets => appL10n.passedTickets;
  static String get examReadiness => appL10n.examReadiness;
  static String get training => appL10n.training;
  static String get pdd => appL10n.pdd;
  static String get signs => appL10n.signs;
  static String get settings => appL10n.settings;
  static String get showHint => appL10n.showHint;
  static String get comment => appL10n.comment;
  static String get pddPoints => appL10n.pddPoints;
  static String get myAnswers => appL10n.myAnswers;
  static String get favorites => appL10n.favorites;
  static String get questionAddedToFavorites => appL10n.questionAddedToFavorites;
  static String get correctAnswer => appL10n.correctAnswer;
  static String get yourAnswer => appL10n.yourAnswer;
  static String get ticket => appL10n.ticket;
  static String get question => appL10n.question;
  static String get goalText => appL10n.goalText;
  static String get goalTextTopics => appL10n.goalTextTopics;
  static String get confirmAnswer => appL10n.confirmAnswer;
  static String get nextQuestion => appL10n.nextQuestion;
  static String get resetStats => appL10n.resetStats;
  static String get resetStatsConfirm => appL10n.resetStatsConfirm;
  static String get yes => appL10n.yes;
  static String get no => appL10n.no;
  static String get cancel => appL10n.cancel;
  static String get back => appL10n.back;
  static String get category => appL10n.category;
  static String get categoryAB => appL10n.categoryAB;
  static String get categoryCD => appL10n.categoryCD;
  static String get sound => appL10n.sound;
  static String get examPassed => appL10n.examPassed;
  static String get examFailed => appL10n.examFailed;
  static String get correctAnswers => appL10n.correctAnswers;
  static String get wrongAnswers => appL10n.wrongAnswers;
  static String get timeLeft => appL10n.timeLeft;
  static String get minutes => appL10n.minutes;
  static String get search => appL10n.search;
  static String get noImage => appL10n.noImage;
}
