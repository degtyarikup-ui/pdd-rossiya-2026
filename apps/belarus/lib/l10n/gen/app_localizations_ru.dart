// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'ПДД Беларусь · Тест';

  @override
  String get welcome => 'Готовимся к дорогам Беларуси';

  @override
  String get intro => 'Правила и тренировочный экзамен Республики Беларусь.';

  @override
  String get exam => 'Экзамен';

  @override
  String get examRules => '10 вопросов · 15 минут · не более одной ошибки';

  @override
  String get contentPending =>
      'Проверяем актуальные вопросы и ответы. Экзамен станет доступен после проверки базы.';

  @override
  String get startExam => 'Начать экзамен';

  @override
  String get preparing => 'База готовится';

  @override
  String get practiceNotice =>
      'Тренажёр для самостоятельной подготовки. Не является официальным экзаменом ГАИ.';

  @override
  String get loadError => 'Не удалось загрузить вопросы.';

  @override
  String get retry => 'Повторить';

  @override
  String get leaveTitle => 'Завершить попытку?';

  @override
  String get leaveBody =>
      'Ответы текущей попытки не сохранятся. Таймер продолжает идти.';

  @override
  String get stay => 'Продолжить';

  @override
  String get leave => 'Выйти';

  @override
  String get result => 'Результат';

  @override
  String get passed => 'Сдано';

  @override
  String get failed => 'Не сдано';

  @override
  String get expired => 'Время вышло';

  @override
  String score(int count) {
    return 'Правильных ответов: $count из 10';
  }

  @override
  String correctAnswer(String answer) {
    return 'Правильный ответ: $answer';
  }

  @override
  String get home => 'На главную';

  @override
  String questionNumber(int number) {
    return 'Вопрос $number из 10';
  }
}
