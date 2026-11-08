import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_be.dart';
import 'app_localizations_en.dart';
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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('be'),
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ru, this message translates to:
  /// **'ПДД Беларусь · Тест'**
  String get appTitle;

  /// No description provided for @welcome.
  ///
  /// In ru, this message translates to:
  /// **'Готовимся к дорогам Беларуси'**
  String get welcome;

  /// No description provided for @intro.
  ///
  /// In ru, this message translates to:
  /// **'Правила и тренировочный экзамен Республики Беларусь.'**
  String get intro;

  /// No description provided for @exam.
  ///
  /// In ru, this message translates to:
  /// **'Экзамен'**
  String get exam;

  /// No description provided for @examRules.
  ///
  /// In ru, this message translates to:
  /// **'10 вопросов · 15 минут · не более одной ошибки'**
  String get examRules;

  /// No description provided for @contentPending.
  ///
  /// In ru, this message translates to:
  /// **'Проверяем актуальные вопросы и ответы. Экзамен станет доступен после проверки базы.'**
  String get contentPending;

  /// No description provided for @startExam.
  ///
  /// In ru, this message translates to:
  /// **'Начать экзамен'**
  String get startExam;

  /// No description provided for @preparing.
  ///
  /// In ru, this message translates to:
  /// **'База готовится'**
  String get preparing;

  /// No description provided for @practiceNotice.
  ///
  /// In ru, this message translates to:
  /// **'Тренажёр для самостоятельной подготовки. Не является официальным экзаменом ГАИ.'**
  String get practiceNotice;

  /// No description provided for @loadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить вопросы.'**
  String get loadError;

  /// No description provided for @retry.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get retry;

  /// No description provided for @leaveTitle.
  ///
  /// In ru, this message translates to:
  /// **'Завершить попытку?'**
  String get leaveTitle;

  /// No description provided for @leaveBody.
  ///
  /// In ru, this message translates to:
  /// **'Ответы текущей попытки не сохранятся. Таймер продолжает идти.'**
  String get leaveBody;

  /// No description provided for @stay.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get stay;

  /// No description provided for @leave.
  ///
  /// In ru, this message translates to:
  /// **'Выйти'**
  String get leave;

  /// No description provided for @result.
  ///
  /// In ru, this message translates to:
  /// **'Результат'**
  String get result;

  /// No description provided for @passed.
  ///
  /// In ru, this message translates to:
  /// **'Сдано'**
  String get passed;

  /// No description provided for @failed.
  ///
  /// In ru, this message translates to:
  /// **'Не сдано'**
  String get failed;

  /// No description provided for @expired.
  ///
  /// In ru, this message translates to:
  /// **'Время вышло'**
  String get expired;

  /// No description provided for @score.
  ///
  /// In ru, this message translates to:
  /// **'Правильных ответов: {count} из 10'**
  String score(int count);

  /// No description provided for @correctAnswer.
  ///
  /// In ru, this message translates to:
  /// **'Правильный ответ: {answer}'**
  String correctAnswer(String answer);

  /// No description provided for @home.
  ///
  /// In ru, this message translates to:
  /// **'На главную'**
  String get home;

  /// No description provided for @questionNumber.
  ///
  /// In ru, this message translates to:
  /// **'Вопрос {number} из 10'**
  String questionNumber(int number);
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
      <String>['be', 'en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'be':
      return AppLocalizationsBe();
    case 'en':
      return AppLocalizationsEn();
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
