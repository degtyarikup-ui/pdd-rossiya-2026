import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/keyboard_dismiss.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/repositories/auth_repository.dart';
import 'package:pdd_app/presentation/screens/auth/login_screen.dart';
import 'package:pdd_app/presentation/screens/home/home_screen.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuestMode = ref.watch(guestModeProvider);
    final isSupabaseAvailable = ref.watch(supabaseAvailableProvider);

    if (isGuestMode) {
      return const _HomeWithKeyboardCleanup();
    }

    if (!isSupabaseAvailable) {
      return const LoginScreen();
    }

    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user != null) {
          return const _HomeWithKeyboardCleanup();
        }
        return const LoginScreen();
      },
      loading: () => const _LoadingScreen(),
      error: (e, _) => const LoginScreen(),
    );
  }
}

/// После ухода с [LoginScreen] на iOS иногда остаётся input accessory — чистим на первом кадре дома.
class _HomeWithKeyboardCleanup extends StatefulWidget {
  const _HomeWithKeyboardCleanup();

  @override
  State<_HomeWithKeyboardCleanup> createState() =>
      _HomeWithKeyboardCleanupState();
}

class _HomeWithKeyboardCleanupState extends State<_HomeWithKeyboardCleanup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      dismissKeyboardAndInputChromeAfterRouteChange();
    });
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.14),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.school, color: AppColors.white, size: 36),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            const Text(
              'ПДД Россия 2026',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingM),
            const CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: AppDimensions.spacingM),
            const Text(
              'Подготавливаем локальные данные и ваш прогресс.',
              style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}
