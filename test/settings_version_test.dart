import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/build_info.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/gen/app_localizations.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SettingsScreen displays current app version at the bottom', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    PackageInfo.setMockInitialValues(
      appName: 'PDD Russia',
      packageName: 'ru.pdd.pdd_app',
      version: '2.2.3',
      buildNumber: '61',
      buildSignature: '',
    );

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
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify version text is displayed
    expect(find.text('Версия 2.2.3 (61)'), findsOneWidget);
  });

  testWidgets('SettingsScreen displays git commit hash for test builds', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    PackageInfo.setMockInitialValues(
      appName: 'PDD Russia Dev',
      packageName: 'ru.pdd.pdd_app.dev',
      version: '2.2.3',
      buildNumber: '61',
      buildSignature: '',
    );

    BuildInfo.overrideCommitForTesting('daea25ee');
    addTearDown(() => BuildInfo.overrideCommitForTesting(null));

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
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Версия 2.2.3 (61) · daea25ee'), findsOneWidget);
  });
}
