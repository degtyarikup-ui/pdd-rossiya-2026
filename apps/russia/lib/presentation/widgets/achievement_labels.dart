import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/l10n/l10n.dart';

String achievementTitle(AchievementId id) {
  switch (id) {
    case AchievementId.streak:
      return appL10n.achievementTitleStreak;
    case AchievementId.coverage:
      return appL10n.achievementTitleCoverage;
    case AchievementId.tickets:
      return appL10n.achievementTitleTickets;
    case AchievementId.attempts:
      return appL10n.achievementTitleAttempts;
    case AchievementId.exams:
      return appL10n.achievementTitleExams;
    case AchievementId.flawless:
      return appL10n.achievementTitleFlawless;
    case AchievementId.mistakes:
      return appL10n.achievementTitleMistakes;
    case AchievementId.game:
      return appL10n.achievementTitleGame;
    case AchievementId.rank:
      return appL10n.achievementTitleRank;
    case AchievementId.trafficController:
      return appL10n.achievementTitleTrafficController;
    case AchievementId.signSwiper:
      return appL10n.achievementTitleSignSwiper;
    case AchievementId.quiz:
      return appL10n.achievementTitleQuiz;
    case AchievementId.violator:
      return appL10n.achievementTitleViolator;
    case AchievementId.parking:
      return appL10n.achievementTitleParking;
    case AchievementId.crossroads:
      return appL10n.achievementTitleCrossroads;
    case AchievementId.marathon:
      return appL10n.achievementTitleMarathon;
    case AchievementId.perfect:
      return appL10n.achievementTitlePerfect;
    case AchievementId.examReady:
      return appL10n.achievementTitleExamReady;
    case AchievementId.signsExpert:
      return appL10n.achievementTitleSignsExpert;
    case AchievementId.earlyBird:
      return appL10n.achievementTitleEarlyBird;
    case AchievementId.nightDriver:
      return appL10n.achievementTitleNightDriver;
    case AchievementId.comeback:
      return appL10n.achievementTitleComeback;
  }
}

String achievementDescription(AchievementId id) {
  switch (id) {
    case AchievementId.streak:
      return appL10n.achievementDescStreak;
    case AchievementId.coverage:
      return appL10n.achievementDescCoverage;
    case AchievementId.tickets:
      return appL10n.achievementDescTickets;
    case AchievementId.attempts:
      return appL10n.achievementDescAttempts;
    case AchievementId.exams:
      return appL10n.achievementDescExams;
    case AchievementId.flawless:
      return appL10n.achievementDescFlawless;
    case AchievementId.mistakes:
      return appL10n.achievementDescMistakes;
    case AchievementId.game:
      return appL10n.achievementDescGame;
    case AchievementId.rank:
      return appL10n.achievementDescRank;
    case AchievementId.trafficController:
      return appL10n.achievementDescTrafficController;
    case AchievementId.signSwiper:
      return appL10n.achievementDescSignSwiper;
    case AchievementId.quiz:
      return appL10n.achievementDescQuiz;
    case AchievementId.violator:
      return appL10n.achievementDescViolator;
    case AchievementId.parking:
      return appL10n.achievementDescParking;
    case AchievementId.crossroads:
      return appL10n.achievementDescCrossroads;
    case AchievementId.marathon:
      return appL10n.achievementDescMarathon;
    case AchievementId.perfect:
      return appL10n.achievementDescPerfect;
    case AchievementId.examReady:
      return appL10n.achievementDescExamReady;
    case AchievementId.signsExpert:
      return appL10n.achievementDescSignsExpert;
    case AchievementId.earlyBird:
      return appL10n.achievementDescEarlyBird;
    case AchievementId.nightDriver:
      return appL10n.achievementDescNightDriver;
    case AchievementId.comeback:
      return appL10n.achievementDescComeback;
  }
}

/// Металл уровня ачивки: 1 бронза, 2 серебро, 3 золото, 4 платина.
String achievementMetalName(int level) => switch (level.clamp(1, 4)) {
  1 => appL10n.achievementMetalBronze,
  2 => appL10n.achievementMetalSilver,
  3 => appL10n.achievementMetalGold,
  _ => appL10n.achievementMetalPlatinum,
};
