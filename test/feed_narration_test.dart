import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/screens/feed/widgets/feed_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FeedNarration implements TtsService {
  int starts = 0;
  int pauses = 0;
  int resumes = 0;
  Duration remaining = const Duration(seconds: 20);

  @override
  final ValueNotifier<NarrationStatus> status = ValueNotifier(
    NarrationStatus.idle,
  );

  @override
  Future<Duration?> speakOrPlayFeedItem({
    required String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {
    starts++;
    return remaining;
  }

  @override
  Future<Duration?> remainingPlaybackDuration() async => remaining;

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> setAppActive(bool active) async {}

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _paused = StateProvider<bool>((ref) => false);
final _premium = StateProvider<bool>((ref) => true);

void main() {
  Future<(ProviderContainer, _FeedNarration)> showCard(
    WidgetTester tester, {
    required ValueChanged<int> onTick,
    required ValueChanged<int> onAnswer,
    bool premium = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final source = ProgressDataSource();
    await source.init();
    await source.saveAppSettings(
      const AppSettings(voiceEnabled: true, languageCode: 'ru'),
    );
    SoundEffectsService.instance.setEnabled(false);
    HapticFeedbackHelper.setEnabled(false);
    final narration = _FeedNarration();
    final container = ProviderContainer(
      overrides: [
        progressDataSourceProvider.overrideWithValue(source),
        ttsServiceProvider.overrideWithValue(narration),
        _premium.overrideWith((ref) => premium),
        isPremiumProvider.overrideWith((ref) => ref.watch(_premium)),
      ],
    );
    await container.read(appSettingsProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final settings = ref.watch(appSettingsProvider);
                return FeedCard(
                  item: const FeedItem(
                    id: 'question',
                    rawQuestionId: 'question',
                    type: FeedItemType.ticketQuestion,
                    questionText: 'Question?',
                    answers: ['Yes', 'No'],
                    correctAnswerIndex: 0,
                  ),
                  isCurrent: true,
                  voiceEnabled: settings.voiceEnabled,
                  voiceSpeed: settings.voiceSpeed,
                  isPaused: ref.watch(_paused),
                  onAutoNext: () {},
                  onPrevious: () {},
                  onTimerTick: (_, remaining) => onTick(remaining),
                  onAnswerRecorded: onAnswer,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      container.dispose();
      SoundEffectsService.instance.setEnabled(true);
      HapticFeedbackHelper.setEnabled(true);
    });
    return (container, narration);
  }

  testWidgets(
    'recording duration extends feed deadline and speed never restarts it',
    (tester) async {
      var remaining = 0;
      int? answer;
      final (container, narration) = await showCard(
        tester,
        onTick: (value) => remaining = value,
        onAnswer: (value) => answer = value,
      );
      expect(narration.starts, 1);
      expect(remaining, 22);
      await tester.pump(const Duration(seconds: 12));
      expect(answer, isNull);

      narration.remaining = const Duration(seconds: 6);
      await container.read(appSettingsProvider.notifier).setVoiceSpeed(1.5);
      await tester.pump();
      await tester.pump();
      expect(narration.starts, 1);
      expect(remaining, 8);
      await tester.pump(const Duration(seconds: 7));
      expect(answer, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(answer, -1);
    },
  );

  testWidgets('opening controls freezes countdown and resumes the recording', (
    tester,
  ) async {
    var remaining = 0;
    int? answer;
    final (container, narration) = await showCard(
      tester,
      onTick: (value) => remaining = value,
      onAnswer: (value) => answer = value,
    );
    await tester.pump(const Duration(seconds: 3));
    container.read(_paused.notifier).state = true;
    await tester.pump();
    final pausedRemaining = remaining;
    expect(narration.pauses, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(remaining, pausedRemaining);
    expect(answer, isNull);
    narration.remaining = const Duration(seconds: 17);
    container.read(_paused.notifier).state = false;
    await tester.pump();
    await tester.pump();
    expect(narration.resumes, 1);
    expect(narration.starts, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(remaining, lessThan(pausedRemaining));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'free feed never requests narration even with a saved enabled flag',
    (tester) async {
      final (_, narration) = await showCard(
        tester,
        premium: false,
        onTick: (_) {},
        onAnswer: (_) {},
      );
      expect(narration.starts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'slow device voice finishes before the final two-second answer allowance',
    (tester) async {
      int? answer;
      var remaining = 0;
      final (_, narration) = await showCard(
        tester,
        onTick: (value) => remaining = value,
        onAnswer: (value) => answer = value,
      );
      narration.status.value = NarrationStatus.playing;
      await tester.pump(const Duration(seconds: 23));
      expect(answer, isNull);
      expect(remaining, 2);
      await tester.pump(const Duration(seconds: 12));
      expect(answer, isNull);

      narration.status.value = NarrationStatus.idle;
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(answer, isNull);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(answer, -1);
      expect(narration.starts, 1);
    },
  );

  testWidgets(
    'missing native completion cannot leave the feed waiting forever',
    (tester) async {
      int? answer;
      final (_, narration) = await showCard(
        tester,
        onTick: (_) {},
        onAnswer: (value) => answer = value,
      );
      narration.status.value = NarrationStatus.playing;
      await tester.pump(const Duration(seconds: 23));
      expect(answer, isNull);
      // The bounded grace waits at most three estimated narration durations.
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(answer, -1);
    },
  );
}
