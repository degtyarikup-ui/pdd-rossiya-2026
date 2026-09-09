import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/layout/app_max_width_frame.dart';
import 'package:pdd_app/core/navigation/route_observer.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:pdd_app/data/services/notification_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/home/home_screen.dart';
import 'package:pdd_app/presentation/screens/tickets/tickets_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  } catch (e) {
    debugPrint('SystemChrome config error: $e');
  }

  final progressDataSource = ProgressDataSource();
  try {
    await progressDataSource.init().timeout(const Duration(seconds: 2));
  } catch (e) {
    debugPrint('ProgressDataSource init error: $e');
  }

  try {
    await PremiumService.instance.init().timeout(const Duration(seconds: 2));
  } catch (e) {
    debugPrint('PremiumService init error: $e');
  }

  try {
    await AuthService.instance.init().timeout(const Duration(seconds: 2));
  } catch (e) {
    debugPrint('AuthService init error: $e');
  }

  // Инициализация облачной синхронизации прогресса
  ProgressSyncService.instance.init(progressDataSource);
  if (AuthService.instance.isAuthenticated) {
    unawaited(ProgressSyncService.instance.syncWithServer());
  }

  unawaited(IapService.instance.init());

  // Локальные напоминания о серии (fire-and-forget, не блокируют старт).
  unawaited(_initStreakNotifications(progressDataSource));

  // Уведомление о новой установке в Telegram (fire-and-forget, не блокирует старт).
  unawaited(InstallReporter.reportIfNeeded());

  // Инициализация сервиса звуковых эффектов (правильный/неправильный ответ)
  unawaited(SoundEffectsService.instance.init());

  runApp(
    ProviderScope(
      overrides: [
        progressDataSourceProvider.overrideWithValue(progressDataSource),
      ],
      child: const PddApp(),
    ),
  );
}

/// Инициализация напоминаний о серии + первичное планирование под текущее
/// состояние стрика. Ошибки глушим — фича необязательна для работы приложения.
Future<void> _initStreakNotifications(ProgressDataSource ds) async {
  if (kIsWeb) return;
  try {
    await StreakNotifier.instance.init();
    await StreakNotifier.instance.requestPermission();
    await StreakNotifier.instance.refreshStreakReminder(await ds.loadStreak());
    // Тестовый показ уведомления через несколько секунд после запуска.
    // Включается только сборкой с --dart-define=NOTIF_TEST=true; в прод нет.
    if (const bool.fromEnvironment('NOTIF_TEST')) {
      unawaited(StreakNotifier.instance.showTestReminder());
    }
  } catch (e) {
    debugPrint('streak notifications init failed: $e');
  }
}

class PddApp extends ConsumerStatefulWidget {
  const PddApp({super.key});

  @override
  ConsumerState<PddApp> createState() => _PddAppState();
}

class _PddAppState extends ConsumerState<PddApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      TtsService.instance.stop().ignore();
    }
    // Пересчитываем напоминание при уходе в фон (учитывает сегодняшнюю
    // тренировку) и при возврате (держит расписание свежим).
    if (kIsWeb) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.resumed) {
      unawaited(_refreshStreakReminder());
    }
  }

  Future<void> _refreshStreakReminder() async {
    try {
      final ds = ref.read(progressDataSourceProvider);
      await StreakNotifier.instance.refreshStreakReminder(await ds.loadStreak());
    } catch (e) {
      debugPrint('streak reminder refresh failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = ref.watch(appSettingsProvider);
    HapticFeedbackHelper.setEnabled(appSettings.hapticsEnabled);

    final String initialScreen = const String.fromEnvironment('SCREEN', defaultValue: 'home');
    Widget getInitialWidget() {
      switch (initialScreen) {
        case 'feed':
          return const HomeScreen(initialIndex: 1);
        case 'pdd':
          return const HomeScreen(initialIndex: 2);
        case 'tickets':
          return const TicketsScreen();
        default:
          return const HomeScreen(initialIndex: 0);
      }
    }

    return MaterialApp(
      title: CountryConfig.current.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: appSettings.themeMode,
      navigatorObservers: [appRouteObserver],
      // Язык фиксирован конфигом страны (рантайм-переключателя нет).
      locale: Locale(CountryConfig.current.language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppMaxWidthFrame(child: child),
      home: getInitialWidget(),
    );
  }
}
