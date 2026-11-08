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
  }
}
