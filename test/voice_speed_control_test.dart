import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_benefits_screen.dart';
import 'package:pdd_app/presentation/widgets/question_voice_toggle.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StatusNarration extends Fake implements TtsService {
  @override
  final ValueNotifier<NarrationStatus> status = ValueNotifier(
    NarrationStatus.idle,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Onest');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      font.addFont(rootBundle.load('assets/fonts/Onest-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  const captureKey = ValueKey('voice-review');
  setUp(() => HapticFeedbackHelper.setEnabled(true));
  tearDown(() => updateAppLocale(const Locale('ru')));

  Future<(ProviderContainer, ProgressDataSource)> mount(
    WidgetTester tester, {
    bool premium = true,
    String language = 'ru',
    bool dark = false,
    double textScale = 1,
    bool reducedMotion = false,
    ValueChanged<bool>? onSheetVisibilityChanged,
    bool settings = false,
    TtsService? narration,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final source = ProgressDataSource();
    await source.init();
    await source.saveAppSettings(AppSettings(languageCode: language));
    final container = ProviderContainer(
      overrides: [
        progressDataSourceProvider.overrideWithValue(source),
        isPremiumProvider.overrideWithValue(premium),
        if (narration != null) ttsServiceProvider.overrideWithValue(narration),
      ],
    );
    await container.read(appSettingsProvider.notifier).ready;
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      container.dispose();
    });
    updateAppLocale(Locale(language));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: reducedMotion,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: settings
                      ? const QuestionVoiceSettingsTile()
                      : Align(
                          alignment: Alignment.topRight,
                          child: QuestionVoiceToggle(
                            onSheetVisibilityChanged: onSheetVisibilityChanged,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, source);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('VOICE_CAPTURE')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = Directory('scratch/voice-review')
        ..createSync(recursive: true);
      File(
        '${dir.path}/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final language in ['ru', 'en', 'kk']) {
    testWidgets(
      'hold selects all eight persisted speeds without enabling voice: $language',
      (tester) async {
        final visibility = <bool>[];
        final (container, source) = await mount(
          tester,
          language: language,
          dark: language == 'en',
          textScale: language == 'kk' ? 2 : 1,
          reducedMotion: language == 'kk',
          onSheetVisibilityChanged: visibility.add,
        );
        expect(find.text('1x'), findsOneWidget);
        expect(find.byIcon(Icons.voice_over_off_rounded), findsOneWidget);
        await tester.longPress(find.byType(QuestionVoiceToggle));
        await tester.pumpAndSettle();
        expect(container.read(appSettingsProvider).voiceEnabled, isFalse);
        expect(visibility, [true]);
        expect(find.byType(Slider), findsOneWidget);
        final speedButtons = AppSettings.voiceSpeeds
            .map((speed) => find.byKey(ValueKey('voice-speed-$speed')))
            .toList();
        expect(
          speedButtons.map((button) => tester.getCenter(button).dy).toSet(),
          hasLength(1),
        );
        for (final (index, speed) in AppSettings.voiceSpeeds.indexed) {
          await tester.tap(speedButtons[index]);
          await tester.pumpAndSettle();
          expect(container.read(appSettingsProvider).voiceSpeed, speed);
          expect((await source.loadAppSettings()).voiceSpeed, speed);
        }
        final slider = tester.widget<Slider>(find.byType(Slider));
        expect(
          slider.semanticFormatterCallback!(0),
          appL10n.voiceSpeedValue('0.8'),
        );
        expect(
          slider.semanticFormatterCallback!(7),
          appL10n.voiceSpeedValue('1.5'),
        );
        await capture(tester, 'speed-$language');
        expect(tester.takeException(), isNull);
        // Bottom sheets close with Back or a swipe; no duplicate close icon.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(visibility, [true, false]);
        expect(container.read(appSettingsProvider).voiceEnabled, isFalse);
        await tester.tap(find.byType(QuestionVoiceToggle));
        await tester.pumpAndSettle();
        expect(container.read(appSettingsProvider).voiceEnabled, isTrue);
      },
    );
  }

  testWidgets(
    'free narration shows a lock and a contextual paywall, no speed picker',
    (tester) async {
      final (container, _) = await mount(
        tester,
        premium: false,
        reducedMotion: true,
      );
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.byIcon(Icons.record_voice_over_rounded), findsOneWidget);
      await capture(tester, 'locked');
      await tester.tap(find.byType(QuestionVoiceToggle));
      await tester.pumpAndSettle();
      expect(find.byType(PremiumBenefitsScreen), findsOneWidget);
      expect(find.text(appL10n.voicePremiumRequired), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(container.read(appSettingsProvider).voiceEnabled, isFalse);
    },
  );

  testWidgets(
    'Settings exposes speed with ordinary tap and honours disabled haptics',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester, settings: true);
      HapticFeedbackHelper.setEnabled(false);
      await tester.tap(find.byKey(const ValueKey('voice-speed-setting')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('voice-speed-1.5')));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'HapticFeedback.vibrate'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing device voice reports an actionable message without another tap',
    (tester) async {
      final narration = _StatusNarration();
      await mount(tester, language: 'kk', narration: narration);
      narration.status.value = NarrationStatus.voiceUnavailable;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(appL10n.gameVoiceUnavailable), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text(appL10n.gameVoiceUnavailable), findsNothing);
    },
  );
}
