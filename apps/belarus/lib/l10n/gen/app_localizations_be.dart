// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Belarusian (`be`).
class AppLocalizationsBe extends AppLocalizations {
  AppLocalizationsBe([String locale = 'be']) : super(locale);

  @override
  String get appTitle => 'ПДР Беларусь · Тэст';

  @override
  String get welcome => 'Рыхтуемся да дарог Беларусі';

  @override
  String get intro => 'Правілы і трэніровачны экзамен Рэспублікі Беларусь.';

  @override
  String get exam => 'Экзамен';

  @override
  String get examRules => '10 пытанняў · 15 хвілін · не больш за адну памылку';

  @override
  String get contentPending =>
      'Правяраем актуальныя пытанні і адказы. Экзамен стане даступны пасля праверкі базы.';

  @override
  String get startExam => 'Пачаць экзамен';

  @override
  String get preparing => 'База рыхтуецца';

  @override
  String get practiceNotice =>
      'Трэнажор для самастойнай падрыхтоўкі. Не з’яўляецца афіцыйным экзаменам ДАІ.';

  @override
  String get loadError => 'Не атрымалася загрузіць пытанні.';

  @override
  String get retry => 'Паўтарыць';

  @override
  String get leaveTitle => 'Завяршыць спробу?';

  @override
  String get leaveBody =>
      'Адказы бягучай спробы не захаваюцца. Таймер працягвае ісці.';

  @override
  String get stay => 'Працягнуць';

  @override
  String get leave => 'Выйсці';

  @override
  String get result => 'Вынік';

  @override
  String get passed => 'Здадзена';

  @override
  String get failed => 'Не здадзена';

  @override
  String get expired => 'Час скончыўся';

  @override
  String score(int count) {
    return 'Правільных адказаў: $count з 10';
  }

  @override
  String correctAnswer(String answer) {
    return 'Правільны адказ: $answer';
  }

  @override
  String get home => 'На галоўную';

  @override
  String questionNumber(int number) {
    return 'Пытанне $number з 10';
  }

  @override
  String get previewOpen => 'Прагляд базы';

  @override
  String get previewNotice =>
      'Тэставая выбарка ПДД.by. Паўната і актуальнасць яшчэ правяраюцца.';

  @override
  String previewCount(int count) {
    return 'Пытанняў у здымку: $count';
  }

  @override
  String previewPosition(int number, int total) {
    return '$number з $total';
  }

  @override
  String get previewReveal => 'Паказаць адказ';

  @override
  String get previewPrevious => 'Назад';

  @override
  String get previewNext => 'Далей';

  @override
  String get previewImageError =>
      'Не ўдалося загрузіць выяву. Пытанне нельга ацэньваць без ілюстрацыі.';
}
