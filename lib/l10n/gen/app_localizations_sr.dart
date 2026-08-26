// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Serbian (`sr`).
class AppLocalizationsSr extends AppLocalizations {
  AppLocalizationsSr([String locale = 'sr']) : super(locale);

  @override
  String get exam => 'Ispit';

  @override
  String get topics => 'Oblasti';

  @override
  String get tickets => 'Testovi';

  @override
  String get passedQuestions => 'urađeno pitanja';

  @override
  String get passedTickets => 'urađeno testova';

  @override
  String get examReadiness => 'Spremnost za ispit';

  @override
  String get training => 'Učenje';

  @override
  String get pdd => 'Propisi';

  @override
  String get signs => 'Znakovi';

  @override
  String get video => 'Traka';

  @override
  String get rules => 'Pravila';

  @override
  String get signsAndMarkup => 'Znakovi i oznake';

  @override
  String get settings => 'Podešavanja';

  @override
  String get showHint => 'Prikaži savet';

  @override
  String get comment => 'Objašnjenje';

  @override
  String get pddPoints => 'Članovi propisa';

  @override
  String get myAnswers => 'Moji odgovori';

  @override
  String get favorites => 'Omiljeno';

  @override
  String get questionAddedToFavorites => 'Pitanje je dodato u Omiljeno';

  @override
  String get correctAnswer => 'Tačan odgovor';

  @override
  String get yourAnswer => 'Vaš odgovor';

  @override
  String get ticket => 'test';

  @override
  String get question => 'pitanje';

  @override
  String get goalText =>
      'Kako budete učili, vaš napredak će se popunjavati. Cilj je da svi testovi budu popunjeni!';

  @override
  String get goalTextTopics =>
      'Kako budete učili, vaš napredak će se popunjavati. Cilj je da sve oblasti budu popunjene!';

  @override
  String get confirmAnswer => 'Odgovori';

  @override
  String get nextQuestion => 'Sledeće pitanje';

  @override
  String get resetStats => 'Resetuj statistiku';

  @override
  String get resetStatsConfirm =>
      'Da li ste sigurni da želite da resetujete svu statistiku?';

  @override
  String get yes => 'Da';

  @override
  String get no => 'Ne';

  @override
  String get cancel => 'Otkaži';

  @override
  String get back => 'Nazad';

  @override
  String get category => 'Kategorija';

  @override
  String get categoryAB => 'AB';

  @override
  String get categoryCD => 'CD';

  @override
  String get sound => 'Zvuk';

  @override
  String get examPassed => 'Ispit položen!';

  @override
  String get examFailed => 'Ispit nije položen';

  @override
  String get continueSession => 'Nastavi';

  @override
  String continueSessionSubtitle(String title, int index, int total) {
    return '$title · pitanje $index od $total';
  }

  @override
  String get continueSessionDismiss => 'Ukloni';

  @override
  String get reportQuestionTooltip => 'Prijavi grešku';

  @override
  String get reportQuestionBody =>
      'Šta nije u redu sa ovim pitanjem? Greška u kucanju, netačan odgovor, pogrešna slika — napišite svojim rečima.';

  @override
  String get reportQuestionHint => 'Na primer: greška u odgovoru B';

  @override
  String get reportSend => 'Pošalji';

  @override
  String get reportSent => 'Hvala! Poruka je poslata';

  @override
  String get reportFailed =>
      'Slanje nije uspelo. Proverite internet i pokušajte ponovo';

  @override
  String get correctAnswers => 'Tačnih odgovora';

  @override
  String get wrongAnswers => 'Netačnih odgovora';

  @override
  String shareCardCorrectWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tačnih',
      few: 'tačna',
      one: 'tačan',
    );
    return '$_temp0';
  }

  @override
  String shareCardWrongWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'grešaka',
      few: 'greške',
      one: 'greška',
    );
    return '$_temp0';
  }

  @override
  String get timeLeft => 'Preostalo vreme';

  @override
  String get minutes => 'min';

  @override
  String get search => 'Pretraga';

  @override
  String get noImage => 'Bez slike';

  @override
  String get mistakes => 'Greške';

  @override
  String progressRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Do ispita ostalo $count pitanja',
      few: 'Do ispita ostalo $count pitanja',
      one: 'Do ispita ostalo $count pitanje',
    );
    return '$_temp0';
  }

  @override
  String get progressDone => 'urađeno';

  @override
  String get progressCorrect => 'tačno';

  @override
  String get progressWrong => 'grešaka';

  @override
  String get progressTickets => 'testova';

  @override
  String progressStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dana',
      few: '$count dana',
      one: '$count dan',
    );
    return '$_temp0';
  }

  @override
  String progressRecord(int count) {
    return 'Rekord $count';
  }

  @override
  String get progressAllDone => 'Sva pitanja su tačno urađena';

  @override
  String get homePassedQuestions => 'Urađeno pitanja';

  @override
  String get homeCorrectSolved => 'Tačno rešeno';

  @override
  String get homePassedTickets => 'Urađeno testova';

  @override
  String examQuestionsBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pitanja',
      few: '$count pitanja',
      one: '$count pitanje',
    );
    return '$_temp0';
  }

  @override
  String examMinutesBadge(int count) {
    return '$count minuta';
  }

  @override
  String examReadinessPercent(int percent) {
    return '$percent% Spremnost za ispit';
  }

  @override
  String get streakStart => 'Započnite niz';

  @override
  String get streakStartHint =>
      'Odgovorite na pitanje danas — upaliće se plamen';

  @override
  String streakDaysWord(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'dana zaredom',
      few: 'dana zaredom',
      one: 'dan zaredom',
    );
    return '$_temp0';
  }

  @override
  String get continueButton => 'Nastavi';

  @override
  String get streakBarrierLabel => 'Niz';

  @override
  String get personalRecord => 'Lični rekord';

  @override
  String get streakMotivationRecord =>
      'Novi lični rekord! Samo tako nastavite.';

  @override
  String get streakMotivationFirst =>
      'Plamen je upaljen. Vratite se sutra da niz raste.';

  @override
  String get streakMotivationWeek =>
      'Odličan tempo. Još malo i biće cela nedelja.';

  @override
  String get streakMotivationHabit =>
      'Cela nedelja je iza vas. Navika se stvara upravo tako.';

  @override
  String get streakMotivationMonth =>
      'Mesec dana bez prekida — to je nivo pravog polaznika auto-škole.';

  @override
  String get weekdayMon => 'Pon';

  @override
  String get weekdayTue => 'Uto';

  @override
  String get weekdayWed => 'Sre';

  @override
  String get weekdayThu => 'Čet';

  @override
  String get weekdayFri => 'Pet';

  @override
  String get weekdaySat => 'Sub';

  @override
  String get weekdaySun => 'Ned';

  @override
  String get linkOpenFailed => 'Nije moguće otvoriti link';

  @override
  String get telegramOpenFailed => 'Nije moguće otvoriti Telegram';

  @override
  String get supportDeveloper => 'Podržite programera';

  @override
  String get techSupport => 'Tehnička podrška';

  @override
  String get privacyPolicy => 'Politika privatnosti';

  @override
  String get aboutSection => 'O aplikaciji';

  @override
  String get dataSourceTitle => 'Izvori podataka';

  @override
  String get preparation => 'Priprema';

  @override
  String get feedbackSection => 'Odziv i zvuci';

  @override
  String get confirmAnswerSetting => 'Potvrda odgovora';

  @override
  String get confirmAnswerHint =>
      'Odgovor se prvo bira, a zatim potvrđuje dugmetom.';

  @override
  String get hapticFeedback => 'Vibracija';

  @override
  String get soundEffects => 'Zvučni efekti';

  @override
  String get voiceOverQuestions => 'Izgovaranje pitanja';

  @override
  String get ticketCategorySetting => 'Kategorija testova';

  @override
  String get ticketCategoryHint =>
      'A/B – automobili i motocikli, C/D – kamioni i autobusi';

  @override
  String get dataSection => 'Podaci';

  @override
  String get resetStatsDetail =>
      'Napredak po pitanjima, rezultati ispita i omiljena pitanja biće obrisani.';

  @override
  String get reset => 'Resetuj';

  @override
  String get statsReset => 'Statistika je resetovana';

  @override
  String get searchByQuestionOrTopic => 'Pretraga po pitanju ili oblasti';

  @override
  String get emptyHere => 'Ovde je za sada prazno';

  @override
  String get favoritesEmptyHint =>
      'Označite teška pitanja zvezdicom i ona će se skupljati na jednom mestu za brzo ponavljanje.';

  @override
  String get favoritesSearchEmpty =>
      'Za ovaj upit nije pronađeno ništa. Probajte deo teksta pitanja ili naziv oblasti.';

  @override
  String get favoritesSubtitle => 'Lična teška pitanja';

  @override
  String favoritesCountHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pitanja',
      few: '$count pitanja',
      one: '$count pitanje',
    );
    return 'Trenutno u omiljenima $_temp0. Koristite ovaj režim kao ličnu selekciju pre ispita.';
  }

  @override
  String get practiceAllFavorites => 'Prođi sve omiljeno';

  @override
  String get noTopic => 'Bez oblasti';

  @override
  String get favoriteQuestion => 'Omiljeno pitanje';

  @override
  String ticketNumber(Object number) {
    return 'Test $number';
  }

  @override
  String get mistakesTitle => 'Rad na greškama';

  @override
  String get noMistakesYet => 'Za sada nema grešaka';

  @override
  String get mistakesEmptyHint =>
      'Kada se pojave netačni odgovori, ovde ćete moći brzo da ponovite samo pitanja koja slabije znate.';

  @override
  String get repeatAllMistakes => 'Ponovi sve greške';

  @override
  String get mistakeReview => 'Analiza greške';

  @override
  String get mistakeLabel => 'Greška';

  @override
  String get nothingFoundTryAnother =>
      'Ništa nije pronađeno. Probajte drugu reč.';

  @override
  String get pddSearchEmpty =>
      'Ništa nije pronađeno. Probajte broj poglavlja ili ključnu reč.';

  @override
  String get onboardingTitle => 'Šta planirate da vozite?';

  @override
  String get categoryABDesc => 'automobil, motocikl';

  @override
  String get categoryCDDesc => 'kamion, autobus';

  @override
  String get ttsAnswerOptions => ' Opcije odgovora ';

  @override
  String get ttsAnswer => 'Odgovor ';

  @override
  String get noQuestions => 'Nema pitanja';

  @override
  String get hint => 'Savet';

  @override
  String questionOfTotal(int current, int total) {
    return 'Pitanje $current od $total';
  }

  @override
  String get finishButton => 'Završi';

  @override
  String get hideHint => 'Sakrij savet';

  @override
  String get confirmAnswerButton => 'Potvrdi odgovor';

  @override
  String get myMistakes => 'Moje greške';

  @override
  String get noQuestionsToReview => 'Nema pitanja za analizu';

  @override
  String get examReview => 'Analiza ispita';

  @override
  String get zoomIn => 'Uvećaj';

  @override
  String get trainingResultPerfect => 'Nijedna greška — samo tako nastavite';

  @override
  String get trainingResultWithMistakes =>
      'Ponovite pitanja u kojima ste pogrešili';

  @override
  String get trainingRepeatMistakes => 'Ponovi greške';

  @override
  String get done => 'Gotovo';

  @override
  String get close => 'Zatvori';

  @override
  String get next => 'Sledeće';

  @override
  String get notAnsweredThisQuestion => 'Niste odgovorili na ovo pitanje';

  @override
  String get description => 'Opis';

  @override
  String get folkNameLabel => 'Narodni naziv';

  @override
  String get examAdditionalTitle => 'Dodatna pitanja';

  @override
  String examAdditionalQuestionOfTotal(int current, int total) {
    return 'Dodatno pitanje $current od $total';
  }

  @override
  String get examResultTimeout =>
      'Vreme je isteklo. Pokušajte ponovo u mirnijem tempu.';

  @override
  String get examResultPassed =>
      'Odličan rezultat. Možete ga učvrstiti testovima.';

  @override
  String get examResultFailed => 'Analizirajte greške i ponovite slabe tačke.';

  @override
  String valueOfTotal(int value, int total) {
    return '$value od $total';
  }

  @override
  String examFailedByBlock(int count) {
    return 'Test se sastoji od tematskih blokova. $count greške u istom bloku znače da ispit nije položen, čak i ako ukupan broj grešaka nije veći od dozvoljenog.';
  }

  @override
  String get examAdditionalBlock => 'Dodatni blok';

  @override
  String examAdditionalBlockValue(int count, int errors) {
    return '$count pitanja, grešaka: $errors';
  }

  @override
  String get examTimeSpent => 'Utrošeno vreme';

  @override
  String get examMainBlockErrors => 'Grešaka u glavnom bloku';

  @override
  String get backToTraining => 'Nazad na učenje';

  @override
  String get examPointsLabel => 'Osvojeni bodovi';

  @override
  String get examScoreLabel => 'Vaš rezultat';

  @override
  String examScorePercent(int percent) {
    return '$percent%';
  }

  @override
  String get share => 'Podeli';

  @override
  String get copiedToClipboard => 'Kopirano u privremenu memoriju';

  @override
  String examShareText(
    String result,
    int correct,
    int total,
    String title,
    String url,
  ) {
    return '$result\nTačnih odgovora: $correct od $total\n\n$title\n$url';
  }

  @override
  String get supportChooseMethod => 'Izaberite način';

  @override
  String get supportYoomoney => 'YooMoney (kartica, novčanik)';

  @override
  String get supportUsdt => 'USDT · TRC-20 (TRON) mreža';

  @override
  String get supportUsdtWarning =>
      'Šaljite isključivo USDT preko TRC-20 (TRON) mreže. Slanje preko druge mreže znači gubitak sredstava.';

  @override
  String get copyAddress => 'Kopiraj adresu';

  @override
  String get notifStreakTitle1 => 'Niz je u opasnosti';

  @override
  String get notifStreakBody1 => 'Vežbajte i sačuvajte plamen 🔥';

  @override
  String get notifStreakTitle2 => 'Predaleko ste stigli da odustanete';

  @override
  String get notifStreakBody2 => 'Svaki dan vas približava ispitu';

  @override
  String get notifStreakTitle3 => '🔥 Plamen samo što se nije ugasio';

  @override
  String get notifStreakBody3 => 'Uđite i odgovorite na par pitanja';

  @override
  String get notifStreakTitle4 => 'Dan je skoro prošao';

  @override
  String get notifStreakBody4 => 'A danas još niste vežbali';

  @override
  String get notifStreakTitle5 => 'Vaš rekord je u opasnosti';

  @override
  String get notifStreakBody5 => 'Sačuvajte ga jednim ulaskom';

  @override
  String get notifStreakTitle6 => 'Ispit je bliži nego što mislite';

  @override
  String get notifStreakBody6 => 'Vežbajte danas';

  @override
  String get notifChannelName => 'Podsetnici o nizu';

  @override
  String get notifChannelDesc => 'Da ne izgubite niz vežbanja';

  @override
  String get dataLoadError =>
      'Učitavanje podataka nije uspelo. Proverite vezu i pokušajte ponovo.';

  @override
  String get themeSetting => 'Tema';

  @override
  String get themeSystem => 'Kao na uređaju';

  @override
  String get themeLight => 'Svetla';

  @override
  String get themeDark => 'Tamna';

  @override
  String get themeChoose => 'Izbor teme';
}
