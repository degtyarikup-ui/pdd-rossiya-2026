import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/layout/app_max_width_frame.dart';
import 'package:pdd_app/core/navigation/route_observer.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  final progressDataSource = ProgressDataSource();
  await progressDataSource.init();

  runApp(
    ProviderScope(
      overrides: [
        progressDataSourceProvider.overrideWithValue(progressDataSource),
      ],
      child: const PddApp(),
    ),
  );
}

class PddApp extends ConsumerWidget {
  const PddApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettings = ref.watch(appSettingsProvider);
    HapticFeedbackHelper.setEnabled(appSettings.hapticsEnabled);

    return MaterialApp(
      title: CountryConfig.current.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorObservers: [appRouteObserver],
      builder: (context, child) => AppMaxWidthFrame(child: child),
      home: const HomeScreen(),
    );
  }
}
