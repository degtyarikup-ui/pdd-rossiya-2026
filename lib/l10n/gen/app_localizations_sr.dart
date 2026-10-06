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
  String get termsOfUse => 'Uslovi korišćenja';

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

  @override
  String get notificationsSetting => 'Podsetnici za niz';

  @override
  String get notificationsHint => 'Svakog dana u 20:00 ako niz nije zatvoren';

  @override
  String get game => 'Igra';

  @override
  String get gameSimulator => '3D Simulator';

  @override
  String get gameLeaderboard => 'Tabela lidera';

  @override
  String get gameScore => 'Poeni';

  @override
  String get gameDistance => 'Udaljenost';

  @override
  String get gameOver => 'Vožnja završena';

  @override
  String get gameRestart => 'Pokušaj ponovo';

  @override
  String get gameExit => 'U garažu';

  @override
  String get gameUnavailable =>
      'Situacije u simulatoru su za sada proverene samo prema pravilima Rusije. Igra će biti dostupna nakon provere lokalnih pravila.';

  @override
  String get gameMobileOnly =>
      '3D simulator je dostupan u mobilnoj aplikaciji za iOS i Android.';

  @override
  String get gameLeft => 'Ulevo';

  @override
  String get gameRight => 'Udesno';

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
  String get gameMistake => 'Greška';

  @override
  String get gameCorrect => 'Tačno';

  @override
  String get gameContinue => 'Nastavi vožnju';

  @override
  String get gameResolving => 'Gas — vožnja · strelice — upravljanje';

  @override
  String get gameGarage => 'Izbor automobila';

  @override
  String get gameCarHatch => 'Hečbek';

  @override
  String get gameCarSedan => 'Limuzina';

  @override
  String get gameCarSuv => 'Terenac';

  @override
  String get gameCarPickup => 'Pikap';

  @override
  String get gameCarCoupe => 'Kupe';

  @override
  String get gameCarWagon => 'Karavan';

  @override
  String get gameCarCyber => 'Sajbertrak';

  @override
  String get gamePaintRed => 'crvena';

  @override
  String get gamePaintBlue => 'plava';

  @override
  String get gamePaintGreen => 'zelena';

  @override
  String get gamePaintSand => 'peščana';

  @override
  String get gamePaintWhite => 'bela';

  @override
  String get gamePaintBlack => 'crna';

  @override
  String get gamePaintSilver => 'srebrna';

  @override
  String get gamePaintOrange => 'narandžasta';

  @override
  String get gamePaintPurple => 'ljubičasta';

  @override
  String get gamePaintTeal => 'tirkizna';

  @override
  String get gamePaintYellow => 'žuta';

  @override
  String get gamePaintWine => 'bordo';

  @override
  String get gamePaintGold => 'zlatna';

  @override
  String gameGarageNextCar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sledeći auto za $count tačnih odgovora',
      few: 'Sledeći auto za $count tačna odgovora',
      one: 'Sledeći auto za $count tačan odgovor',
    );
    return '$_temp0';
  }

  @override
  String get gameGaragePremiumCar =>
      'Uz premium su otključani svi automobili i sve boje';

  @override
  String get gameRevealTitle => 'Novi auto!';

  @override
  String get gameRevealTap => 'Dodirnite vrata garaže';

  @override
  String get gameRevealChoose => 'Izaberi';

  @override
  String get gameRevealClose => 'Zatvori';

  @override
  String get feedLockedTitle => 'Fid se otvara posle prijave';

  @override
  String get feedLockedBody =>
      'Kratke kartice sa pravilima, znakovima i savetima za svaki dan. Prijavite se — i fid, niz učenja i napredak biće sa vama na svakom uređaju.';

  @override
  String get feedSignIn => 'Prijavi se';

  @override
  String get gameSceneTitle => 'Vreme i godišnje doba';

  @override
  String get gameSceneWeather => 'Vreme';

  @override
  String get gameSceneSeason => 'Godišnje doba';

  @override
  String get gameSceneAuto => 'Automatski';

  @override
  String get gameSceneClear => 'Vedro';

  @override
  String get gameSceneOvercast => 'Oblačno';

  @override
  String get gameScenePrecip => 'Padavine';

  @override
  String get gameSceneCalendar => 'Po kalendaru';

  @override
  String get gameDebugUnlimitedFuel => 'Beskonačne vožnje';

  @override
  String get gameDebugUnlimitedFuelHint => 'Vožnje se ne troše';

  @override
  String get gameSceneSummer => 'Leto';

  @override
  String get gameSceneAutumn => 'Jesen';

  @override
  String get gameSceneWinter => 'Zima';

  @override
  String get gameCollision => 'Sudar';

  @override
  String get gameOffroad => 'Ivičnjak · skrenite ka kolovozu';

  @override
  String get gamePriorityViolation => 'Niste ustupili prvenstvo prolaza';

  @override
  String get gameWrongManeuver => 'Manevar ne odgovara zadatku';

  @override
  String get gameOncoming => 'Suprotna traka! Vratite se udesno';

  @override
  String get gameOneWayAgainst => 'Jednosmerni put! Vozite suprotno od smera';

  @override
  String get gameRoadworksHit => 'Uleteli ste u zonu radova na putu';

  @override
  String get gameCorrectAnswers => 'Tačnih odgovora';

  @override
  String gameAnswersOf(int correct, int total) {
    return '$correct od $total';
  }

  @override
  String get gameNoViolations => 'Bez prekršaja';

  @override
  String get gameYourCar => 'Vaš automobil';

  @override
  String get gameSpeeding => 'Prekoračenje brzine';

  @override
  String get gameOvertakingProhibited => 'Preticanje je ovde zabranjeno';

  @override
  String get gameStopViolation => 'Niste se zaustavili na propisanom mestu';

  @override
  String get gameRedLightViolation => 'Prolazak na zabranjen signal';

  @override
  String get gameRailwayViolation =>
      'Prelaz je zatvoren — obilaženje i ulazak su zabranjeni';

  @override
  String get gamePedestrianYield => 'Propustite pešaka';

  @override
  String gameSpeedLimitLabel(int limit) {
    return 'Ograničenje $limit km/h';
  }

  @override
  String get gameBrake => 'Kočnica · unazad kad stojite';

  @override
  String get gameNewRecord => 'Novi rekord!';

  @override
  String gameBestScore(int score) {
    return 'Rekord $score';
  }

  @override
  String get gameGasHint => 'Pritisnite i držite — to je gas';

  @override
  String get gameWeeklyRating => 'Rang lista nedelje';

  @override
  String get gameLobbyStart => 'Kreni u vožnju';

  @override
  String get gameLobbyContinue => 'Nastavi vožnju';

  @override
  String get gameLobbyChangeCar => 'Promeni';

  @override
  String get gameLobbyRecord => 'Rekord';

  @override
  String get gameLobbyColour => 'Boja';

  @override
  String get gameLobbyRating => 'Rang lista';

  @override
  String get gameLobbyColoursHint =>
      'Nove boje se otključavaju tačnim odgovorima u igri';

  @override
  String get gameRatingHint =>
      'Poeni svih vožnji za nedelju. U tabeli su najboljih 100.';

  @override
  String get gameRatingEmpty => 'Ove nedelje još niko nije vozio. Budite prvi!';

  @override
  String get gameRatingUnavailable =>
      'Rang lista nije učitana. Proverite internet.';

  @override
  String get gameRatingYou => 'Vi';

  @override
  String gameRatingRuns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vožnji',
      few: '$count vožnje',
      one: '$count vožnja',
    );
    return '$_temp0';
  }

  @override
  String gameRatingEndsIn(int days) {
    return 'Do kraja nedelje: $days d.';
  }

  @override
  String get gameAuthRequired => 'Igra je dostupna posle prijave';

  @override
  String get gameAuthRequiredHint =>
      'Prijavite se da skupljate poene i učestvujete u rang listi nedelje.';

  @override
  String get gameSignIn => 'Prijavi se i vozi';

  @override
  String gamePenaltyHint(int points) {
    return 'Prekršaj: −$points poena';
  }

  @override
  String get pddSettingsItem => 'Propisi, znakovi i oznake';

  @override
  String get gameLockedTitle => 'Spremni za volan?';

  @override
  String get gameLockedHint =>
      'Živi grad, ispitna pitanja na putu i rang lista nedelje. Prijavite se — i krećemo.';

  @override
  String get gameFuel => 'Vožnje';

  @override
  String get gameFuelUnlimited => 'Neograničene vožnje';

  @override
  String get gameFuelEmptyTitle => 'Vožnje su potrošene';

  @override
  String gameFuelRefillIn(String time) {
    return 'Nova vožnja za $time';
  }

  @override
  String get gameFuelPremiumPitch => 'Uz pretplatu vožnje se ne troše';

  @override
  String get gameFuelBuyPremium => 'Uključi Premium';

  @override
  String get gameFuelWait => 'Sačekati';

  @override
  String get gameViolations => 'Prekršaji';

  @override
  String get gameOverDescription =>
      'Sva pitanja vožnje su iza vas. Pogrešni odgovori su već u „Greškama“ — pregledajte ih i pokušajte ponovo.';

  @override
  String get gameYou => 'Vi';

  @override
  String get gameStop => 'STOP';

  @override
  String get gameLoading => 'Učitavanje igre';

  @override
  String get gameLoadError =>
      'Vožnja ne može da se nastavi. Ponovo pokrenite simulator ili se vratite u meni.';

  @override
  String get authSuccess => 'Uspešno ste prijavljeni';

  @override
  String get authFailed =>
      'Prijava je otkazana ili je došlo do greške. Pokušajte ponovo.';

  @override
  String get authErrorCancelled =>
      'Prijava nije završena. Pokušajte ponovo da izaberete nalog.';

  @override
  String get authErrorProvider =>
      'Nije moguće dobiti podatke za prijavu od izabranog servisa.';

  @override
  String get authErrorNetwork =>
      'Nije moguće povezati se sa serverom. Proverite internet vezu.';

  @override
  String get authErrorTimeout =>
      'Server nije odgovorio na vreme. Pokušajte ponovo.';

  @override
  String get authErrorAppKey =>
      'Server je odbio ovu verziju aplikacije. Ažurirajte aplikaciju iz prodavnice.';

  @override
  String get authErrorCredential =>
      'Server nije potvrdio prijavu. Pokušajte sa drugim nalogom ili načinom prijave.';

  @override
  String get authErrorServer =>
      'Nije moguće završiti prijavu na serveru. Pokušajte kasnije.';

  @override
  String get authErrorResponse =>
      'Nije moguće prihvatiti sesiju prijave. Proverite datum i vreme na telefonu.';

  @override
  String get authSessionTemporary =>
      'Prijava je uspešna. Telefon nije mogao da sačuva sesiju: posle ponovnog pokretanja morate se ponovo prijaviti.';

  @override
  String authDiagnosticCode(String code) {
    return 'Kod za podršku: $code';
  }

  @override
  String get authTitle => 'Prijava na nalog';

  @override
  String get authDescription =>
      'Sačuvajte premium pristup i statistiku pri promeni uređaja ili ponovnoj instalaciji';

  @override
  String get authApple => 'Nastavi sa Apple ID';

  @override
  String get authGoogle => 'Nastavi sa Google nalogom';

  @override
  String get authYandex => 'Nastavi sa Yandex ID';

  @override
  String get authDebug => 'Probna prijava (debug verzija)';

  @override
  String get accountDeleted => 'Nalog i podaci su obrisani';

  @override
  String get accountDeleteFailed =>
      'Nije moguće obrisati nalog. Proverite vezu i pokušajte ponovo.';

  @override
  String get gameControlsTitle => 'Upravljanje';

  @override
  String get gameControlsSimple => 'Jednostavno upravljanje';

  @override
  String get gameControlsSimpleHint =>
      'Strelice — promena trake i skretanja, auto vozi samo';

  @override
  String get gameControlsFree => 'Slobodno upravljanje';

  @override
  String get gameControlsFreeHint => 'Strelice okreću volan dok ih držiš';

  @override
  String get gameTipGas =>
      'Drži pedalu gasa — auto ide. Pusti je — auto se polako zaustavlja';

  @override
  String get gameTipSteer =>
      'Drži strelicu — auto skreće. Pusti — samo se poravna u traci';

  @override
  String get gameTipTurn =>
      'Na raskrsnici drži strelicu dok auto skreće, zatim pusti — poravnaće se samo';

  @override
  String get gameTipNext => 'Dalje';

  @override
  String get gameTipDone => 'Kreni';

  @override
  String get gamePause => 'Pauza';

  @override
  String get gameLobbyControls => 'Uprav.';

  @override
  String gameRunProgress(int n, int total) {
    return 'Pitanje $n od $total';
  }

  @override
  String get gameCorrectAnswer => 'Tačan odgovor';

  @override
  String get gameTimeUp => 'Vreme je isteklo';

  @override
  String gamePenaltyPoints(int points) {
    String _temp0 = intl.Intl.pluralLogic(
      points,
      locale: localeName,
      other: '−$points poena',
      few: '−$points poena',
      one: '−$points poen',
    );
    return '$_temp0';
  }

  @override
  String gameRunMistakes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grešaka u vožnji',
      few: '$count greške u vožnji',
      one: '$count greška u vožnji',
    );
    return '$_temp0';
  }

  @override
  String get gameReviewMistakes => 'Pregledaj greške';

  @override
  String get notifGameRunTitle => 'Nova vožnja je spremna';

  @override
  String get notifGameRunBody =>
      'Sedite za volan: raskrsnice iz testova vas čekaju.';

  @override
  String get notifGameChannelName => 'Igra';

  @override
  String get notifGameChannelDesc => 'Kada se vožnja u igri obnovi';

  @override
  String gameRunMistakesButton(int count) {
    return 'Greške · $count';
  }

  @override
  String get gameCorrectShort => 'Tačno';

  @override
  String gameRunsPill(int runs, int max) {
    return 'Vožnje $runs od $max';
  }

  @override
  String get gameRunsUnlimitedPill => 'Vožnje ∞';

  @override
  String get gameRunsTitle => 'Vožnje';

  @override
  String gameRunsExplain(int questions, int max, int minutes) {
    return 'Vožnja je $questions pitanja na putu. U rezervi je do $max vožnje, svaka potrošena se vraća za $minutes minuta.';
  }

  @override
  String gameRunsNextIn(String time) {
    return 'Sledeća vožnja za $time';
  }

  @override
  String get gameRunsFull => 'Rezerva je puna — kreni';

  @override
  String get gameRunsPremium => 'Uz Premium vožnje su neograničene';

  @override
  String get gameRunsGetPremium => 'Neograničeno uz Premium';

  @override
  String gameLobbyRunLength(int count) {
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
  String gameLobbyProgress(int n, int total) {
    return 'Pređeno $n od $total';
  }

  @override
  String get gameLobbyNewCar => 'NOVO';

  @override
  String get gameRunsReady => 'Spremno';

  @override
  String get gameRunsUntil => 'do vožnje';

  @override
  String get gameUturn => 'Polukružno okretanje';

  @override
  String get purchaseVerificationPending =>
      'Prodavnica je prijavila kupovinu, ali pristup još nije potvrđen. Za ponovnu proveru pritisnite „Vrati kupovine” kada internet bude dostupan.';

  @override
  String get notifAdminChannelName => 'Obaveštenja aplikacije';

  @override
  String get noticeAcknowledge => 'U redu';

  @override
  String get noticeOpen => 'Otvori';

  @override
  String get pushMessagesSetting => 'Novosti aplikacije';

  @override
  String get pushMessagesHint =>
      'Push obaveštenja o novostima i važnim događajima';

  @override
  String get gameKeyboardHint =>
      '↑ / W — gas · ↓ / S / razmak — kočnica · ← → / A D — skretanje';

  @override
  String get webQuarter => '3 meseca';

  @override
  String get webPaymentSoon => 'Plaćanje uskoro';

  @override
  String get webPaymentInfo =>
      'Pristup na 3 meseca bez automatskog obnavljanja. Plaćanje na sajtu još nije dostupno.';
}
