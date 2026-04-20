import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/app_config.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/auth_repository.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/progress_cloud_sync.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/screens/auth/auth_wrapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  var isSupabaseAvailable = true;

  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  } catch (e, stackTrace) {
    isSupabaseAvailable = false;
    if (kDebugMode) {
      debugPrint('Supabase initialization failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        progressDataSourceProvider.overrideWithValue(progressDataSource),
        supabaseAvailableProvider.overrideWithValue(isSupabaseAvailable),
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
      title: 'ПДД Россия 2026',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const ProgressCloudHost(child: AuthWrapper()),
    );
  }
}
