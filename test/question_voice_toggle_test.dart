import 'helpers/achievement_awards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/exam/exam_screen.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/question_voice_toggle.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingTts implements TtsService {
  final questions = <String?>[];
  var stops = 0;

  @override
  Future<void> speakQuestion({
    String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async => questions.add(rawQuestionId);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> updateLanguage(String lang) async {}

  @override
  Future<Duration?> speakOrPlayFeedItem({
    required String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async => null;
}

List<Map<String, dynamic>> _questions() => List.generate(
  60,
  (i) => {
    'id': 'q$i',
    'question': 'Тестовый вопрос ${i + 1}',
    'answers': [
      {'text': 'Первый ответ', 'correct': true},
      {'text': 'Второй ответ', 'correct': false},
    ],
    'ticketNumber': i ~/ 20 + 1,
  },
);

Widget _training() =>
    TrainingScreen(questions: _questions(), title: appL10n.examAdditionalTitle);

Future<void> _show(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen, {
  bool dark = false,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [dark ? AppThemeColors.dark : AppThemeColors.light],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  Future<(ProgressDataSource, ProviderContainer, _RecordingTts)> setup(
    WidgetTester tester, {
    String language = 'ru',
    bool voiceEnabled = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final source = ProgressDataSource();
    await source.init();
    await source.saveAppSettings(
      AppSettings(languageCode: language, voiceEnabled: voiceEnabled),
    );
    updateAppLocale(Locale(language));
    final tts = _RecordingTts();
    final container = ProviderContainer(
      overrides: [
        noAchievementAwards,
        progressDataSourceProvider.overrideWithValue(source),
        ttsServiceProvider.overrideWithValue(tts),
      ],
    );
    await container.read(appSettingsProvider.notifier).ready;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      container.dispose();
      updateAppLocale(const Locale('ru'));
    });
    return (source, container, tts);
  }

  for (final exam in [false, true]) {
    for (final language in ['ru', 'en', 'kk']) {
      testWidgets(
        'voice toggle playback and narrow header: exam=$exam $language',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final (source, container, tts) = await setup(
            tester,
            language: language,
          );
          await _show(
            tester,
            container,
            exam ? ExamScreen(allQuestions: _questions()) : _training(),
            dark: language == 'en',
          );

          expect(find.byTooltip(appL10n.gameVoiceOff), findsOneWidget);
          expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
          expect(tts.questions, isEmpty);
          expect(tester.getTopRight(find.byType(QuestionVoiceToggle)).dx, 300);
          expect(tester.takeException(), isNull);

          await tester.tap(find.byType(QuestionVoiceToggle));
          await tester.pumpAndSettle();
          expect(container.read(appSettingsProvider).voiceEnabled, isTrue);
          expect((await source.loadAppSettings()).voiceEnabled, isTrue);
          expect(find.byTooltip(appL10n.gameVoiceOn), findsOneWidget);
          expect(tts.questions, hasLength(1));

          // Timer rebuilds must not restart the current question.
          await tester.pump(const Duration(seconds: 1));
          expect(tts.questions, hasLength(1));
          tester
              .widget<PageView>(find.byType(PageView))
              .controller!
              .jumpToPage(1);
          await tester.pumpAndSettle();
          expect(tts.questions, hasLength(2));
          expect(tts.questions.first, isNot(tts.questions.last));

          final stopsBefore = tts.stops;
          await tester.tap(find.byType(QuestionVoiceToggle));
          await tester.pumpAndSettle();
          expect(tts.stops, greaterThan(stopsBefore));
          expect(container.read(appSettingsProvider).voiceEnabled, isFalse);
          expect((await source.loadAppSettings()).voiceEnabled, isFalse);
          tester
              .widget<PageView>(find.byType(PageView))
              .controller!
              .jumpToPage(2);
          await tester.pumpAndSettle();
          expect(tts.questions, hasLength(2));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('exam, training and Settings share persisted voice preference', (
    tester,
  ) async {
    final (source, container, tts) = await setup(tester);
    expect(const AppSettings().voiceEnabled, isFalse);
    expect(AppSettings.fromJson({}).voiceEnabled, isFalse);
    await _show(tester, container, ExamScreen(allQuestions: _questions()));
    await tester.tap(find.byType(QuestionVoiceToggle));
    await tester.pumpAndSettle();

    await _show(tester, container, _training());
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(tts.questions, hasLength(2));

    await _show(tester, container, const SettingsScreen());
    final voiceSwitch = find.descendant(
      of: find
          .ancestor(
            of: find.text(appL10n.voiceOverQuestions),
            matching: find.byType(Row),
          )
          .first,
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(voiceSwitch).value, isTrue);
    await tester.ensureVisible(voiceSwitch);
    await tester.pumpAndSettle();
    await tester.tap(voiceSwitch);
    await tester.pumpAndSettle();

    await _show(tester, container, _training());
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    expect(tts.questions, hasLength(2));
    expect((await source.loadAppSettings()).voiceEnabled, isFalse);

    await tester.tap(find.byType(QuestionVoiceToggle));
    await tester.pumpAndSettle();
    final reloaded = ProviderContainer(
      overrides: [
        noAchievementAwards,
        progressDataSourceProvider.overrideWithValue(source),
      ],
    );
    addTearDown(reloaded.dispose);
    await reloaded.read(appSettingsProvider.notifier).ready;
    expect(reloaded.read(appSettingsProvider).voiceEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
