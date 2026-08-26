import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/ads_repository.dart';
import 'package:pdd_app/data/repositories/feed_repository.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';

final questionsDataSourceProvider = Provider<QuestionsDataSource>((ref) {
  return QuestionsDataSource();
});

final progressDataSourceProvider = Provider<ProgressDataSource>((ref) {
  throw UnimplementedError('Must be overridden with actual instance');
});

final appDataRefreshProvider = StateProvider<int>((ref) => 0);

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
final unfinishedSessionProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(appDataRefreshProvider);
  final category =
      ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
  final progress = ref.watch(progressDataSourceProvider);
  final saved = progress.loadUnfinishedSession(category);
  if (saved == null) return null;

  final ids = (saved['questionIds'] as List).cast<String>();
  final all = await ref.watch(questionsDataSourceProvider).loadTickets(category);
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
    final answers = (saved['answers'] as List?)
            ?.map((e) => e as int?)
            .toList() ??
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
    'title': saved['title'] as String? ?? '',
    'questions': questions,
    'index': index,
    'total': questions.length,
  };
});

final ticketsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final category =
      ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
  final dataSource = ref.watch(questionsDataSourceProvider);
  final allQuestions = await dataSource.loadTickets(category);

  // Количество билетов определяется данными, а не константой:
  // у разных стран разный объём базы.
  final ticketNumbers = allQuestions.map((q) => q.ticketNumber).toSet().toList()
    ..sort();
  final List<Map<String, dynamic>> tickets = [];
  for (final n in ticketNumbers) {
    final ticketQuestions =
        allQuestions.where((q) => q.ticketNumber == n).toList();
    tickets.add({'number': n, 'questions': ticketQuestions});
  }
  return tickets;
});

final topicsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final category =
      ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
  final dataSource = ref.watch(questionsDataSourceProvider);
  return await dataSource.loadTopics(category);
});

final signsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dataSource = ref.watch(questionsDataSourceProvider);
  return await dataSource.loadSigns();
});

final markupProvider =
    FutureProvider<Map<String, List<Map<String, String>>>>((ref) async {
  final dataSource = ref.watch(questionsDataSourceProvider);
  return await dataSource.loadMarkup();
});

final statsProvider = FutureProvider<Map<String, int>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final category =
      ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
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
  final category =
      ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
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
  final category =
      ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
  final dataSource = ref.watch(progressDataSourceProvider);
  return await dataSource.isFavorite(questionId, category);
});

final favoriteQuestionsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final category =
      ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
  final dataSource = ref.watch(progressDataSourceProvider);
  return await dataSource.getFavoriteQuestionIds(category);
});

final streakProvider = FutureProvider<Streak>((ref) async {
  ref.watch(appDataRefreshProvider);
  final dataSource = ref.watch(progressDataSourceProvider);
  return await dataSource.loadStreak();
});

final wrongQuestionIdsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final category =
      ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
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

final adsRepositoryProvider = Provider<AdsRepository>((ref) {
  final repo = AdsRepository();
  repo.init();
  return repo;
});

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final dataSource = ref.watch(questionsDataSourceProvider);
  final adsRepo = ref.watch(adsRepositoryProvider);
  return FeedRepository(dataSource, adsRepo);
});

final feedItemsProvider = FutureProvider<List<FeedItem>>((ref) async {
  final category =
      ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
  final repo = ref.watch(feedRepositoryProvider);
  return repo.generateFeedItems(category: category, count: 60);
});
