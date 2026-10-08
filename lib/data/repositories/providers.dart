import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/repositories/feed_repository.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/notification_service.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/models/traffic_controller_progress.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';

final questionsDataSourceProvider = Provider<QuestionsDataSource>((ref) {
  return QuestionsDataSource();
});

final progressDataSourceProvider = Provider<ProgressDataSource>((ref) {
  throw UnimplementedError('Must be overridden with actual instance');
});

final appDataRefreshProvider = StateProvider<int>((ref) => 0);

/// True while a screen takes the whole window (the game's garage reveal):
/// the home shell hides its bottom navigation.
final fullscreenProvider = StateProvider<bool>((ref) => false);

class AppSettingsController extends StateNotifier<AppSettings> {
  AppSettingsController(this._dataSource) : super(const AppSettings()) {
    _loadFuture = _load();
  }

  final ProgressDataSource _dataSource;
  late final Future<void> _loadFuture;

  /// Дождаться первой загрузки настроек из хранилища.
  Future<void> get ready => _loadFuture;

  Future<void> _load() async {
    state = await _dataSource.loadAppSettings();
    SoundEffectsService.instance.setEnabled(state.soundEffectsEnabled);
  }

  Future<void> setHapticsEnabled(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
    await _dataSource.saveAppSettings(state);
  }

  Future<void> setSoundEffectsEnabled(bool value) async {
    state = state.copyWith(soundEffectsEnabled: value);
    SoundEffectsService.instance.setEnabled(value);
    await _dataSource.saveAppSettings(state);
  }

  Future<void> setConfirmAnswerEnabled(bool value) async {
    state = state.copyWith(confirmAnswerEnabled: value);
    await _dataSource.saveAppSettings(state);
  }

  Future<void> setVoiceEnabled(bool value) async {
    state = state.copyWith(voiceEnabled: value);
    await _dataSource.saveAppSettings(state);
  }

  Future<void> setNotificationsEnabled(bool value) async {
    state = state.copyWith(notificationsEnabled: value);
    await StreakNotifier.instance.setUserStreakEnabled(value);
    if (value) {
      await StreakNotifier.instance.requestPermission();
      final streak = await _dataSource.loadStreak();
      await StreakNotifier.instance.refreshStreakReminder(streak);
    } else {
      await StreakNotifier.instance.cancelStreakReminder();
    }
    await _dataSource.saveAppSettings(state);
  }

  Future<void> setPushMessagesEnabled(bool value) async {
    state = state.copyWith(pushMessagesEnabled: value);
    await _dataSource.saveAppSettings(state);
    await RemoteNotificationsService.instance.setPushConsent(value);
  }

  Future<void> setTicketCategory(TicketCategory value) async {
    state = state.copyWith(ticketCategory: value);
    await _dataSource.saveAppSettings(state);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    state = state.copyWith(themeMode: value);
    await _dataSource.saveAppSettings(state);
  }

  // Методы онбординга категории удалены вместе с модальным окном «На чём
  // планируешь ездить?»: категория теперь по умолчанию A/B и меняется в
  // настройках. Само поле vehicleOnboardingCompleted в AppSettings оставлено —
  // оно уже записано в SharedPreferences у существующих пользователей, и
  // выкидывать его из схемы значило бы ломать разбор их настроек.
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsController, AppSettings>((ref) {
      return AppSettingsController(ref.watch(progressDataSourceProvider));
    });

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService.instance;
  ref.onDispose(service.dispose);
  return service;
});

/// Незаконченная тренировка для карточки «Продолжить» на главной.
///
/// Возвращает null, если сессии нет, она из другой категории или её вопросы
/// уже не находятся в базе (контент пересобрали). Восстанавливаем именно те
/// вопросы и в том же порядке, что были у человека.
final unfinishedSessionProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  ref.watch(appDataRefreshProvider);
  final category = ref.watch(
    appSettingsProvider.select((s) => s.ticketCategory),
  );
  final progress = ref.watch(progressDataSourceProvider);
  final saved = progress.loadUnfinishedSession(category);
  if (saved == null) return null;

  final ids = (saved['questionIds'] as List).cast<String>();
  final all = await ref
      .watch(questionsDataSourceProvider)
      .loadTickets(category);
  final byId = {for (final q in all) q.id: q};

  final questions = <Map<String, dynamic>>[];
  for (final id in ids) {
    final q = byId[id];
    if (q != null) questions.add(q.toMap());
  }
  // Половина вопросов потерялась — набор уже не тот, что был; лучше не
  // предлагать возврат, чем вернуть человека в поломанную сессию.
  if (questions.length < ids.length / 2) return null;

  final index = (saved['index'] as int? ?? 0).clamp(0, questions.length - 1);

  // Прерванный экзамен возвращается со всем своим состоянием: ответами,
  // остатком времени и доп. фазой. Если хоть один вопрос выпал из базы,
  // ответы перестают соответствовать позициям — тогда возвращать нельзя.
  if (saved['kind'] == 'exam') {
    if (questions.length != ids.length) return null;
    final answers =
        (saved['answers'] as List?)?.map((e) => e as int?).toList() ??
        List<int?>.filled(questions.length, null);
    if (answers.length != questions.length) return null;
    return {
      'kind': 'exam',
      'questions': questions,
      'index': index,
      'total': questions.length,
      'answers': answers,
      'remainingSeconds': saved['remainingSeconds'] as int? ?? 0,
      'totalSeconds': saved['totalSeconds'] as int? ?? 0,
      'additionalPhase': saved['additionalPhase'] as bool? ?? false,
      'additionalQuestionsCount':
          saved['additionalQuestionsCount'] as int? ?? 0,
      'initialWrongCount': saved['initialWrongCount'] as int? ?? 0,
    };
  }

  return {
    'kind': 'training',
    'usageFeature': saved['usageFeature'],
    'title': saved['title'] as String? ?? '',
    'questions': questions,
    'index': index,
    'total': questions.length,
  };
});

final ticketsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final category = ref.watch(
    appSettingsProvider.select((s) => s.ticketCategory),
  );
  final dataSource = ref.watch(questionsDataSourceProvider);
  final allQuestions = await dataSource.loadTickets(category);

  // Количество билетов определяется данными, а не константой:
  // у разных стран разный объём базы.
  final ticketNumbers = allQuestions.map((q) => q.ticketNumber).toSet().toList()
    ..sort();
  final List<Map<String, dynamic>> tickets = [];
  for (final n in ticketNumbers) {
    final ticketQuestions = allQuestions
        .where((q) => q.ticketNumber == n)
        .toList();
    tickets.add({'number': n, 'questions': ticketQuestions});
  }
  return tickets;
});

final topicsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final category = ref.watch(
    appSettingsProvider.select((s) => s.ticketCategory),
  );
  final dataSource = ref.watch(questionsDataSourceProvider);
  return await dataSource.loadTopics(category);
});

final signsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dataSource = ref.watch(questionsDataSourceProvider);
  return await dataSource.loadSigns();
});

final markupProvider = FutureProvider<Map<String, List<Map<String, String>>>>((
  ref,
) async {
  final dataSource = ref.watch(questionsDataSourceProvider);
  return await dataSource.loadMarkup();
});

final statsProvider = FutureProvider<Map<String, int>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final category = ref.watch(
    appSettingsProvider.select((s) => s.ticketCategory),
  );
  final dataSource = ref.watch(progressDataSourceProvider);
  final progress = await dataSource.getAllQuestionProgress(category);
  final tickets = await ref.watch(ticketsProvider.future);
  final correct = await dataSource.getCorrectAnswersCount(category);

  int passedTickets = 0;
  for (final ticket in tickets) {
    final questions = ticket['questions'] as List;
    int answeredCount = 0;
    int correctCount = 0;

    for (final q in questions) {
      final snapshot = progress[q.id as String];
      if (snapshot is Map<String, dynamic>) {
        answeredCount++;
        if (snapshot['isCorrect'] == true) {
          correctCount++;
        }
      }
    }

    if (answeredCount == questions.length &&
        correctCount >=
            CountryConfig.current.examRules.passThreshold(questions.length)) {
      passedTickets++;
    }
  }

  final totalQuestions = tickets.fold<int>(
    0,
    (sum, t) => sum + (t['questions'] as List).length,
  );

  return {
    'correctAnswers': correct,
    'answeredQuestions': progress.length,
    'wrongQuestions': progress.values.where((value) {
      return value is Map<String, dynamic> && value['isCorrect'] == false;
    }).length,
    'passedTickets': passedTickets,
    'totalQuestions': totalQuestions,
    'totalTickets': tickets.length,
  };
});

final ticketProgressProvider = FutureProvider<Map<int, int>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final category = ref.watch(
    appSettingsProvider.select((s) => s.ticketCategory),
  );
  final dataSource = ref.watch(progressDataSourceProvider);
  final progress = await dataSource.getAllQuestionProgress(category);
  final tickets = await ref.watch(ticketsProvider.future);
  final result = <int, int>{};

  for (final ticket in tickets) {
    final ticketNumber = ticket['number'] as int;
    final questions = ticket['questions'] as List;
    int correctCount = 0;

    for (final q in questions) {
      final snapshot = progress[q.id as String];
      if (snapshot is Map<String, dynamic> && snapshot['isCorrect'] == true) {
        correctCount++;
      }
    }

    result[ticketNumber] = correctCount;
  }

  return result;
});

final favoriteQuestionProvider = FutureProvider.family<bool, String>((
  ref,
  questionId,
) async {
  ref.watch(appDataRefreshProvider);
  final category = ref.watch(
    appSettingsProvider.select((s) => s.ticketCategory),
  );
  final dataSource = ref.watch(progressDataSourceProvider);
  return await dataSource.isFavorite(questionId, category);
});

final favoriteQuestionsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final category = ref.watch(
    appSettingsProvider.select((s) => s.ticketCategory),
  );
  final dataSource = ref.watch(progressDataSourceProvider);
  return await dataSource.getFavoriteQuestionIds(category);
});

final streakProvider = FutureProvider<Streak>((ref) async {
  ref.watch(appDataRefreshProvider);
  final dataSource = ref.watch(progressDataSourceProvider);
  return await dataSource.loadStreak();
});

/// Лучшее место игрока в недельном рейтинге игры. Сервер — источник правды,
/// на устройстве запоминается лучшее из виденных (место только улучшается),
/// поэтому без сети ачивка не пропадает.
final bestWeeklyRankProvider = FutureProvider.autoDispose<int?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final dataSource = ref.watch(progressDataSourceProvider);
  final cached = dataSource.getGameBestRank(user.id);
  final remote = await GameLeaderboardService.instance.fetchBestRank();
  if (remote != null && (cached == null || remote < cached)) {
    await dataSource.setGameBestRank(user.id, remote);
    return remote;
  }
  return cached;
});

final achievementsProvider =
    FutureProvider.autoDispose<List<AchievementProgress>>((ref) async {
      ref.watch(appDataRefreshProvider);
      final category = ref.watch(
        appSettingsProvider.select((s) => s.ticketCategory),
      );
      final trafficScore = ref.watch(
        trafficControllerProgressProvider.select((s) => s.bestScore),
      );
      final signScore = ref.watch(
        signSwiperProgressProvider.select((s) => s.bestScore),
      );
      final streak = await ref.watch(streakProvider.future);
      final stats = await ref.watch(statsProvider.future);
      final dataSource = ref.watch(progressDataSourceProvider);
      final questionProgress = await dataSource.getAllQuestionProgress(
        category,
      );
      final examResults = await dataSource.getExamResults(category);
      final gameBestScore = dataSource.getGameBestScore();
      // Не ждём сеть: сетка рисуется сразу по кэшу, а когда сервер ответит,
      // провайдер пересчитается.
      final user = ref.watch(currentUserProvider);
      final bestWeeklyRank = user == null
          ? null
          : ref.watch(bestWeeklyRankProvider).valueOrNull ??
                dataSource.getGameBestRank(user.id);

      return computeAchievements(
        longestStreak: streak.longest,
        stats: stats,
        questionProgress: questionProgress,
        examResults: examResults,
        gameBestScore: gameBestScore,
        bestWeeklyRank: bestWeeklyRank,
        trafficControllerBestScore: trafficScore,
        signSwiperBestScore: signScore,
      );
    });

final wrongQuestionIdsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final category = ref.watch(
    appSettingsProvider.select((s) => s.ticketCategory),
  );
  final dataSource = ref.watch(progressDataSourceProvider);
  final progress = await dataSource.getAllQuestionProgress(category);

  return progress.entries
      .where(
        (entry) =>
            entry.value is Map<String, dynamic> &&
            entry.value['isCorrect'] == false,
      )
      .map((entry) => entry.key)
      .toList();
});

final authAndPremiumStreamProvider = StreamProvider<int>((ref) async* {
  var count = 0;
  yield count;
  final controller = StreamController<int>();
  void listener() {
    if (!controller.isClosed) {
      count++;
      controller.add(count);
    }
  }

  AuthService.instance.addListener(listener);
  PremiumService.instance.addListener(listener);

  ref.onDispose(() {
    AuthService.instance.removeListener(listener);
    PremiumService.instance.removeListener(listener);
    controller.close();
  });

  yield* controller.stream;
});

final premiumServiceProvider = Provider<PremiumService>((ref) {
  return PremiumService.instance;
});

final isPremiumProvider = Provider<bool>((ref) {
  ref.watch(appDataRefreshProvider);
  ref.watch(authAndPremiumStreamProvider);
  return PremiumService.instance.isPremium;
});

final dailyCardsRemainingProvider = Provider<int>((ref) {
  ref.watch(appDataRefreshProvider);
  ref.watch(authAndPremiumStreamProvider);
  return PremiumService.instance.remainingFreeCards;
});

final dailyFreeLimitProvider = Provider<int>((ref) {
  ref.watch(appDataRefreshProvider);
  ref.watch(authAndPremiumStreamProvider);
  return PremiumService.instance.dailyFreeLimit;
});

final aiMessagesRemainingProvider = Provider<int>((ref) {
  ref.watch(appDataRefreshProvider);
  ref.watch(authAndPremiumStreamProvider);
  return PremiumService.instance.remainingAiMessages;
});

final aiMessagesLimitProvider = Provider<int>((ref) {
  ref.watch(appDataRefreshProvider);
  ref.watch(authAndPremiumStreamProvider);
  return PremiumService.instance.aiFreeLimit;
});

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final dataSource = ref.watch(questionsDataSourceProvider);
  final progressSource = ref.watch(progressDataSourceProvider);
  return FeedRepository(dataSource, progressSource);
});

final feedItemsProvider = FutureProvider<List<FeedItem>>((ref) async {
  final category = ref.watch(
    appSettingsProvider.select((s) => s.ticketCategory),
  );
  final repo = ref.watch(feedRepositoryProvider);
  return repo.generateFeedItems(category: category, count: 60);
});

final authServiceProvider = ChangeNotifierProvider<AuthService>((ref) {
  return AuthService.instance;
});

final currentUserProvider = Provider<UserProfile?>((ref) {
  final auth = ref.watch(authServiceProvider);
  return auth.currentUser;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  final auth = ref.watch(authServiceProvider);
  return auth.isAuthenticated;
});

final trafficControllerProgressProvider =
    StateNotifierProvider<
      TrafficControllerProgressController,
      TrafficControllerProgress
    >((ref) {
      final ds = ref.watch(progressDataSourceProvider);
      return TrafficControllerProgressController(ds);
    });

class TrafficControllerProgressController
    extends StateNotifier<TrafficControllerProgress> {
  TrafficControllerProgressController(this._dataSource)
    : super(_dataSource.getTrafficControllerProgress());

  final ProgressDataSource _dataSource;

  Future<void> recordGameResult({
    required int score,
    required int combo,
    required int solved,
  }) async {
    final newScore = score > state.bestScore ? score : state.bestScore;
    final newCombo = combo > state.maxCombo ? combo : state.maxCombo;
    final newSolved = state.totalSolved + solved;
    state = state.copyWith(
      bestScore: newScore,
      maxCombo: newCombo,
      totalSolved: newSolved,
    );
    await _dataSource.saveTrafficControllerProgress(state);
  }

  Future<void> incrementTraining() async {
    state = state.copyWith(trainingCount: state.trainingCount + 1);
    await _dataSource.saveTrafficControllerProgress(state);
  }
}

final signSwiperProgressProvider =
    StateNotifierProvider<SignSwiperProgressController, SignSwiperProgress>((
      ref,
    ) {
      final ds = ref.watch(progressDataSourceProvider);
      return SignSwiperProgressController(ds);
    });

class SignSwiperProgressController extends StateNotifier<SignSwiperProgress> {
  SignSwiperProgressController(this._dataSource)
    : super(_dataSource.getSignSwiperProgress());

  final ProgressDataSource _dataSource;

  Future<void> recordGameResult({
    required int score,
    required int combo,
    required int swiped,
  }) async {
    final newScore = score > state.bestScore ? score : state.bestScore;
    final newCombo = combo > state.maxCombo ? combo : state.maxCombo;
    final newSwiped = state.totalSwiped + swiped;
    state = state.copyWith(
      bestScore: newScore,
      maxCombo: newCombo,
      totalSwiped: newSwiped,
    );
    await _dataSource.saveSignSwiperProgress(state);
  }

  Future<void> incrementTraining({int swiped = 1}) async {
    state = state.copyWith(
      trainingCount: state.trainingCount + 1,
      totalSwiped: state.totalSwiped + swiped,
    );
    await _dataSource.saveSignSwiperProgress(state);
  }
}
