import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeMode in AppSettings', () {
    test('default themeMode is ThemeMode.system', () {
      const settings = AppSettings();
      expect(settings.themeMode, ThemeMode.system);
    });

    test('toJson and fromJson preserves themeMode', () {
      const settingsLight = AppSettings(themeMode: ThemeMode.light);
      final jsonLight = settingsLight.toJson();
      expect(jsonLight['themeMode'], 'light');
      expect(AppSettings.fromJson(jsonLight).themeMode, ThemeMode.light);

      const settingsDark = AppSettings(themeMode: ThemeMode.dark);
      final jsonDark = settingsDark.toJson();
      expect(jsonDark['themeMode'], 'dark');
      expect(AppSettings.fromJson(jsonDark).themeMode, ThemeMode.dark);

      const settingsSystem = AppSettings(themeMode: ThemeMode.system);
      final jsonSystem = settingsSystem.toJson();
      expect(jsonSystem['themeMode'], 'system');
      expect(AppSettings.fromJson(jsonSystem).themeMode, ThemeMode.system);
    });

    test('fromJson handles invalid or missing themeMode by falling back to system', () {
      final jsonEmpty = <String, dynamic>{};
      expect(AppSettings.fromJson(jsonEmpty).themeMode, ThemeMode.system);

      final jsonInvalid = <String, dynamic>{'themeMode': 'unknown_value'};
      expect(AppSettings.fromJson(jsonInvalid).themeMode, ThemeMode.system);
    });

    test('copyWith updates themeMode', () {
      const settings = AppSettings();
      final updated = settings.copyWith(themeMode: ThemeMode.dark);
      expect(updated.themeMode, ThemeMode.dark);
    });
  });

  group('AppTheme palettes and extensions', () {
    test('lightTheme has Light Brightness and AppThemeColors.light', () {
      final theme = AppTheme.lightTheme;
      expect(theme.brightness, Brightness.light);
      final colors = theme.extension<AppThemeColors>();
      expect(colors, isNotNull);
      expect(colors, AppThemeColors.light);
      expect(colors!.background, AppColors.background);
    });

    test('darkTheme has Dark Brightness and AppThemeColors.dark', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      final colors = theme.extension<AppThemeColors>();
      expect(colors, isNotNull);
      expect(colors, AppThemeColors.dark);
      expect(colors!.background, const Color(0xFF121214));
      expect(colors.primaryText, const Color(0xFFF2F3F7));
    });
  });

  group('AppSettingsController setThemeMode', () {
    test('setThemeMode updates state and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final data = ProgressDataSource();
      await data.init();

      final container = ProviderContainer(
        overrides: [
          progressDataSourceProvider.overrideWithValue(data),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appSettingsProvider.notifier).ready;
      expect(container.read(appSettingsProvider).themeMode, ThemeMode.system);

      await container.read(appSettingsProvider.notifier).setThemeMode(ThemeMode.dark);
      expect(container.read(appSettingsProvider).themeMode, ThemeMode.dark);

      await container.read(appSettingsProvider.notifier).setThemeMode(ThemeMode.light);
      expect(container.read(appSettingsProvider).themeMode, ThemeMode.light);
    });
  });

  group('SettingsScreen theme selector UI', () {
    testWidgets('shows theme tile and allows changing theme mode via bottom sheet', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final data = ProgressDataSource();
      await data.init();

      final container = ProviderContainer(
        overrides: [
          progressDataSourceProvider.overrideWithValue(data),
        ],
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Theme tile is present with default "Как на устройстве"
      expect(find.text(appL10n.themeSetting), findsOneWidget);
      expect(find.text(appL10n.themeSystem), findsOneWidget);

      // Tap theme tile to open modal sheet
      await tester.tap(find.text(appL10n.themeSetting));
      await tester.pumpAndSettle();

      // Modal bottom sheet is opened with 3 options
      expect(find.text(appL10n.themeLight), findsOneWidget);
      expect(find.text(appL10n.themeDark), findsOneWidget);

      // Select Dark Theme
      await tester.tap(find.text(appL10n.themeDark));
      await tester.pumpAndSettle();

      // Check that themeMode is updated
      expect(container.read(appSettingsProvider).themeMode, ThemeMode.dark);
    });
  });
}
