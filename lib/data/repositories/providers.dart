import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
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
  }

  Future<void> setHapticsEnabled(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
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

  Future<void> setVehicleOnboardingCompleted(bool value) async {
    state = state.copyWith(vehicleOnboardingCompleted: value);
    await _dataSource.saveAppSettings(state);
  }

  /// Онбординг: категория билетов + больше не показывать окно.
  Future<void> finishVehicleOnboarding(TicketCategory category) async {
    state = state.copyWith(
      ticketCategory: category,
      vehicleOnboardingCompleted: true,
    );
    await _dataSource.saveAppSettings(state);
  }
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

final ticketsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final category =
      ref.watch(appSettingsProvider.select((s) => s.ticketCategory));
  final dataSource = ref.watch(questionsDataSourceProvider);
  final allQuestions = await dataSource.loadTickets(category);

  final List<Map<String, dynamic>> tickets = [];
  for (int i = 1; i <= 40; i++) {
    final ticketQuestions = allQuestions
        .where((q) => q.ticketNumber == i)
        .toList();
    tickets.add({'number': i, 'questions': ticketQuestions});
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

    if (answeredCount == questions.length && correctCount >= 18) {
      passedTickets++;
    }
  }

  return {
    'correctAnswers': correct,
    'answeredQuestions': progress.length,
    'wrongQuestions': progress.values.where((value) {
      return value is Map<String, dynamic> && value['isCorrect'] == false;
    }).length,
    'passedTickets': passedTickets,
    'totalQuestions': 800,
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
