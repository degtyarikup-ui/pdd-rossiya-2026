import 'package:pdd_app/data/services/achievement_award_service.dart';

/// Screen/bridge tests isolate awards; their persistence and real completion
/// ordering are exercised by achievement_awards_test.dart.
final noAchievementAwards = achievementAwardServiceProvider.overrideWith(
  (ref) => AchievementAwardService(scope: 'test', load: () async => const []),
);
