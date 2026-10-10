import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(() {
    updateAppLocale(const Locale('ru'));
  });

  group('languageCode and system language detection in AppSettings', () {
    test('default languageCode is system', () {
      const settings = AppSettings();
      expect(settings.languageCode, 'system');
      expect(settings.effectiveLanguageCode, isNotEmpty);
    });

    test('detectSystemLanguage correctly maps locales', () {
      expect(AppSettings.detectSystemLanguage(const Locale('en')), 'en');
      expect(AppSettings.detectSystemLanguage(const Locale('en', 'US')), 'en');
      expect(AppSettings.detectSystemLanguage(const Locale('kk')), 'kk');
      expect(AppSettings.detectSystemLanguage(const Locale('kk', 'KZ')), 'kk');
      expect(AppSettings.detectSystemLanguage(const Locale('ru')), 'ru');
      expect(AppSettings.detectSystemLanguage(const Locale('ru', 'RU')), 'ru');
      // Unknown or other language defaults to ru
      expect(AppSettings.detectSystemLanguage(const Locale('fr')), 'ru');
      expect(AppSettings.detectSystemLanguage(const Locale('de')), 'ru');
    });

    test('effectiveLanguageCode uses explicit selection or system', () {
      const settingsSystem = AppSettings(languageCode: 'system');
      expect(settingsSystem.effectiveLanguageCode, AppSettings.detectSystemLanguage());

      const settingsEn = AppSettings(languageCode: 'en');
      expect(settingsEn.effectiveLanguageCode, 'en');

      const settingsKk = AppSettings(languageCode: 'kk');
      expect(settingsKk.effectiveLanguageCode, 'kk');

      const settingsRu = AppSettings(languageCode: 'ru');
      expect(settingsRu.effectiveLanguageCode, 'ru');
    });

    test('toJson and fromJson preserves languageCode', () {
      const settingsSystem = AppSettings(languageCode: 'system');
      final jsonSystem = settingsSystem.toJson();
      expect(jsonSystem['languageCode'], 'system');
      expect(AppSettings.fromJson(jsonSystem).languageCode, 'system');

      const settingsEn = AppSettings(languageCode: 'en');
      final jsonEn = settingsEn.toJson();
      expect(jsonEn['languageCode'], 'en');
      expect(AppSettings.fromJson(jsonEn).languageCode, 'en');

      const settingsKk = AppSettings(languageCode: 'kk');
      final jsonKk = settingsKk.toJson();
      expect(jsonKk['languageCode'], 'kk');
      expect(AppSettings.fromJson(jsonKk).languageCode, 'kk');

      const settingsRu = AppSettings(languageCode: 'ru');
      final jsonRu = settingsRu.toJson();
      expect(jsonRu['languageCode'], 'ru');
      expect(AppSettings.fromJson(jsonRu).languageCode, 'ru');
    });

    test('fromJson falls back to system when missing', () {
      final jsonEmpty = <String, dynamic>{};
      expect(AppSettings.fromJson(jsonEmpty).languageCode, 'system');
    });

    test('copyWith updates languageCode', () {
      const settings = AppSettings();
      final updated = settings.copyWith(languageCode: 'en');
      expect(updated.languageCode, 'en');
    });
  });

  group('AppSettingsController setLanguageCode', () {
    test('setLanguageCode updates state, persists, and updates appL10n', () async {
      SharedPreferences.setMockInitialValues({});
      final data = ProgressDataSource();
      await data.init();

      final container = ProviderContainer(
        overrides: [progressDataSourceProvider.overrideWithValue(data)],
      );
      addTearDown(container.dispose);

      await container.read(appSettingsProvider.notifier).ready;
      expect(container.read(appSettingsProvider).languageCode, 'system');

      await container
          .read(appSettingsProvider.notifier)
          .setLanguageCode('en');
      expect(container.read(appSettingsProvider).languageCode, 'en');
      expect(appL10n.tickets, 'Tickets');

      await container
          .read(appSettingsProvider.notifier)
          .setLanguageCode('kk');
      expect(container.read(appSettingsProvider).languageCode, 'kk');
      expect(appL10n.tickets, 'Билеттер');

      await container
          .read(appSettingsProvider.notifier)
          .setLanguageCode('ru');
      expect(container.read(appSettingsProvider).languageCode, 'ru');
      expect(appL10n.tickets, 'Билеты');

      // Set back to system
      await container
          .read(appSettingsProvider.notifier)
          .setLanguageCode('system');
      expect(container.read(appSettingsProvider).languageCode, 'system');
    });
  });

  group('Multi-language localizations lookup', () {
    test('all three languages provide correct strings and plurals', () {
      final ru = lookupAppLocalizations(const Locale('ru'));
      final en = lookupAppLocalizations(const Locale('en'));
      final kk = lookupAppLocalizations(const Locale('kk'));

      expect(ru.exam, 'Экзамен');
      expect(en.exam, 'Exam');
      expect(kk.exam, 'Емтихан');

      expect(ru.pdd, 'ПДД');
      expect(en.pdd, 'Traffic Rules');
      expect(kk.pdd, 'Жол жүрісі қағидалары');

      expect(ru.interfaceSection, 'Интерфейс');
      expect(en.interfaceSection, 'Interface');
      expect(kk.interfaceSection, 'Интерфейс');

      expect(ru.languageSystem, 'По умолчанию (системный)');
      expect(en.languageSystem, 'System default');
      expect(kk.languageSystem, 'Әдепкі (жүйелік)');

      // Plural verification
      expect(ru.progressStreakDays(1), '1 день');
      expect(ru.progressStreakDays(2), '2 дня');
      expect(ru.progressStreakDays(5), '5 дней');

      expect(en.progressStreakDays(1), '1 day');
      expect(en.progressStreakDays(2), '2 days');
      expect(en.progressStreakDays(5), '5 days');

      expect(kk.progressStreakDays(1), '1 күн');
      expect(kk.progressStreakDays(5), '5 күн');
    });
  });

  group('SettingsScreen language selector UI', () {
    testWidgets(
      'shows language tile and allows changing language via bottom sheet',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        SharedPreferences.setMockInitialValues({});
        final data = ProgressDataSource();
        await data.init();

        final container = ProviderContainer(
          overrides: [progressDataSourceProvider.overrideWithValue(data)],
        );
        addTearDown(container.dispose);

        await container.read(appSettingsProvider.notifier).ready;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: container.read(appSettingsProvider).themeMode,
              locale: Locale(container.read(appSettingsProvider).effectiveLanguageCode),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const SettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Interface section title is present
        expect(find.text(appL10n.interfaceSection), findsOneWidget);

        // Language tile is present
        expect(find.text(appL10n.languageSetting), findsOneWidget);

        // Tap language tile to open modal sheet
        await tester.tap(find.text(appL10n.languageSetting));
        await tester.pumpAndSettle();

        // Modal bottom sheet is opened with System default and language options
        expect(find.text(appL10n.languageSystem), findsOneWidget);
        expect(find.text('Русский'), findsOneWidget);
        expect(find.text('English'), findsOneWidget);
        expect(find.text('Қазақша'), findsOneWidget);

        // Select English
        await tester.tap(find.text('English'));
        await tester.pumpAndSettle();

        // Check that languageCode is updated to en
        expect(container.read(appSettingsProvider).languageCode, 'en');
        expect(appL10n.tickets, 'Tickets');

        // Open modal again and select System default
        await tester.tap(find.text(appL10n.languageSetting));
        await tester.pumpAndSettle();

        await tester.tap(find.text(appL10n.languageSystem));
        await tester.pumpAndSettle();

        expect(container.read(appSettingsProvider).languageCode, 'system');
      },
    );
  });
}
