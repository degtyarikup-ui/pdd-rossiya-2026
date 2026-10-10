import 'package:pdd_app/data/services/usage_reporter.dart';
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
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:pdd_app/data/services/notification_service.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/home/home_screen.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_screen.dart';
import 'package:pdd_app/presentation/screens/tickets/tickets_screen.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/data/services/web_oauth_redirect_stub.dart'
    if (dart.library.js_interop) 'package:pdd_app/data/services/web_oauth_redirect.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final webAuthReturn = takeWebOAuthReturn();

  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (previousFlutterError != null) {
      previousFlutterError(details);
    } else {
      FlutterError.presentError(details);
    }
    ErrorReporter.report(
      ErrorCategory.app,
      'flutter.framework',
      error: details.exception,
    );
  };
  final previousPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorReporter.report(ErrorCategory.app, 'dart.unhandled', error: error);
    return previousPlatformError?.call(error, stack) ?? false;
  };

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

  // До инициализации сервисов: они пишут в настройки, и свежая установка
  // иначе выглядит как обновление.
  await InstallReporter.captureLaunchState();

  final progressDataSource = ProgressDataSource();
  try {
    await progressDataSource.init().timeout(const Duration(seconds: 2));
  } catch (e) {
    debugPrint('ProgressDataSource init error: $e');
    ErrorReporter.report(ErrorCategory.app, 'startup.progress', error: e);
  }

  try {
    await PremiumService.instance.init().timeout(const Duration(seconds: 2));
  } catch (e) {
    debugPrint('PremiumService init error: $e');
    ErrorReporter.report(ErrorCategory.app, 'startup.premium', error: e);
  }

  try {
    await AuthService.instance.init().timeout(const Duration(seconds: 2));
  } catch (e) {
    debugPrint('AuthService init error: $e');
    ErrorReporter.report(ErrorCategory.app, 'startup.auth', error: e);
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
  unawaited(UsageReporter.instance.flush());
  unawaited(ErrorReporter.instance.flush());

  // Инициализация сервиса звуковых эффектов (правильный/неправильный ответ)
  unawaited(SoundEffectsService.instance.init());

  runApp(
    ProviderScope(
      overrides: [
        progressDataSourceProvider.overrideWithValue(progressDataSource),
      ],
      child: PddApp(webAuthReturn: webAuthReturn),
    ),
  );
}

/// Инициализация напоминаний о серии + первичное планирование под текущее
/// состояние стрика. Ошибки глушим — фича необязательна для работы приложения.
Future<void> _initStreakNotifications(ProgressDataSource ds) async {
  if (kIsWeb) return;
  try {
    await StreakNotifier.instance.init();
    await RemoteNotificationsService.instance.init();
    await RemoteNotificationsService.instance.setPushConsent(
      (await ds.loadAppSettings()).pushMessagesEnabled,
      requestPermission: false,
    );
    await StreakNotifier.instance.setUserStreakEnabled(
      (await ds.loadAppSettings()).notificationsEnabled,
    );
    await StreakNotifier.instance.requestPermission();
    await StreakNotifier.instance.refreshStreakReminder(await ds.loadStreak());
    // Тестовый показ уведомления через несколько секунд после запуска.
    // Включается только сборкой с --dart-define=NOTIF_TEST=true; в прод нет.
    if (kDebugMode && const bool.fromEnvironment('NOTIF_TEST')) {
      unawaited(StreakNotifier.instance.showTestReminder());
    }
  } catch (e) {
    debugPrint('streak notifications init failed: $e');
  }
}

class PddApp extends ConsumerStatefulWidget {
  const PddApp({super.key, this.webAuthReturn});
  final Map<String, String>? webAuthReturn;

  @override
  ConsumerState<PddApp> createState() => _PddAppState();
}

class _PddAppState extends ConsumerState<PddApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final returned = widget.webAuthReturn;
    if (returned != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigatorContext = _navigatorKey.currentContext;
        if (mounted && navigatorContext != null) {
          AuthModalSheet.show(
            navigatorContext,
            initialAction: () =>
                AuthService.instance.completeWebSignIn(returned),
          );
        }
      });
    }
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
    if (state == AppLifecycleState.resumed) {
      unawaited(UsageReporter.instance.flush());
      unawaited(ErrorReporter.instance.flush());
    }
    if (kIsWeb) return;
    if (state == AppLifecycleState.resumed) {
      IapService.instance.retryPendingPurchases();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.resumed) {
      unawaited(_refreshStreakReminder());
    }
  }

  Future<void> _refreshStreakReminder() async {
    try {
      final ds = ref.read(progressDataSourceProvider);
      await StreakNotifier.instance.setUserStreakEnabled(
        (await ds.loadAppSettings()).notificationsEnabled,
      );
      await StreakNotifier.instance.refreshStreakReminder(
        await ds.loadStreak(),
      );
    } catch (e) {
      debugPrint('streak reminder refresh failed: $e');
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);
    final settings = ref.read(appSettingsProvider);
    if (settings.languageCode == 'system') {
      updateAppLocale(Locale(settings.effectiveLanguageCode));
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = ref.watch(appSettingsProvider);
    updateAppLocale(Locale(appSettings.effectiveLanguageCode));
    HapticFeedbackHelper.setEnabled(appSettings.hapticsEnabled);

    final String initialScreen = kDebugMode
        ? const String.fromEnvironment('SCREEN', defaultValue: 'home')
        : 'home';
    Widget getInitialWidget() {
      if (widget.webAuthReturn != null) {
        return const HomeScreen(initialIndex: 3);
      }
      switch (initialScreen) {
        case 'game':
          return const HomeScreen(initialIndex: 1);
        case 'games':
          return const GamesHubScreen();
        case 'feed':
          return const HomeScreen(initialIndex: 2);
        case 'profile':
          return const HomeScreen(initialIndex: 3);
        case 'tickets':
          return const TicketsScreen();
        default:
          return const HomeScreen(initialIndex: 0);
      }
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: CountryConfig.current.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: appSettings.themeMode,
      navigatorObservers: [appRouteObserver],
      locale: Locale(appSettings.effectiveLanguageCode),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppMaxWidthFrame(child: child),
      home: getInitialWidget(),
    );
  }
}
