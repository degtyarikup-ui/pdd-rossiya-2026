import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/utils/keyboard_dismiss.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pdd_app/core/config/app_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/auth_error_messages.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/auth_repository.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authLoadingProvider = StateProvider<bool>((ref) => false);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLogin = true;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _clearedGlobalLoadingOnAttach = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_clearedGlobalLoadingOnAttach) {
      _clearedGlobalLoadingOnAttach = true;
      ref.read(authLoadingProvider.notifier).state = false;
    }
  }

  @override
  void deactivate() {
    dismissKeyboardAndInputChromeAfterRouteChange();
    super.deactivate();
  }

  @override
  void dispose() {
    ref.read(authLoadingProvider.notifier).state = false;
    dismissKeyboardAndInputChrome();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showMessage(
    String message, {
    Color backgroundColor = AppColors.red,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(height: 1.35),
        ),
        backgroundColor: backgroundColor,
        duration: duration,
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    if (!ref.read(supabaseAvailableProvider)) {
      _showMessage(
        'Облачный вход сейчас недоступен. Можно продолжить в локальном режиме.',
        backgroundColor: AppColors.accent,
      );
      return;
    }

    HapticFeedbackHelper.tap();
    ref.read(authLoadingProvider.notifier).state = true;

    try {
      final webId = GoogleOAuthConfig.webClientId.trim();
      final googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: webId.isEmpty ? null : webId,
      );

      // Без signOut() плагин при уже выбранном аккаунте сразу возвращает его,
      // не показывая выбор Google-профиля (см. GoogleSignIn.signIn()).
      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        ref.read(authLoadingProvider.notifier).state = false;
        return;
      }

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null) {
        throw AuthException('Нет доступа к Google аккаунту');
      }

      final credentials = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken ?? '',
        accessToken: accessToken,
      );

      if (credentials.user == null) {
        throw AuthException('Ошибка авторизации');
      }

      dismissKeyboardAndInputChromeAfterRouteChange();
      await ref.read(guestModeProvider.notifier).exitGuestMode();
      widget.onClose?.call();
    } catch (e) {
      _showMessage(authErrorMessageForUser(e));
    } finally {
      if (mounted) {
        ref.read(authLoadingProvider.notifier).state = false;
      }
    }
  }

  Future<void> _submitEmail() async {
    if (!ref.read(supabaseAvailableProvider)) {
      _showMessage(
        'Сейчас доступен только локальный режим без аккаунта.',
        backgroundColor: AppColors.accent,
      );
      return;
    }

    HapticFeedbackHelper.tap();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Заполните все поля');
      return;
    }

    if (password.length < 6) {
      _showMessage('Пароль минимум 6 символов');
      return;
    }

    if (!_isLogin && password != confirmPassword) {
      _showMessage('Пароли не совпадают');
      return;
    }

    ref.read(authLoadingProvider.notifier).state = true;

    try {
      final client = Supabase.instance.client;

      if (_isLogin) {
        await client.auth.signInWithPassword(email: email, password: password);
      } else {
        final response = await client.auth.signUp(email: email, password: password);
        if (response.session != null) {
          _showMessage(
            'Регистрация завершена, вы вошли в аккаунт',
            backgroundColor: AppColors.green,
          );
        } else if (response.user != null) {
          _showMessage(
            'Письмо с подтверждением отправлено на почту.\n\n'
            'После перехода по ссылке откройте приложение и войдите с тем же email и паролем.\n\n'
            'Если страница по ссылке не открылась — всё равно попробуйте войти: '
            'подтверждение могло уже пройти.',
            backgroundColor: AppColors.green,
            duration: const Duration(seconds: 12),
          );
        }
      }

      if (client.auth.currentSession != null) {
        dismissKeyboardAndInputChromeAfterRouteChange();
        await ref.read(guestModeProvider.notifier).exitGuestMode();
        widget.onClose?.call();
      }
    } catch (e) {
      _showMessage(authErrorMessageForUser(e));
    } finally {
      if (mounted) {
        ref.read(authLoadingProvider.notifier).state = false;
      }
    }
  }

  Future<void> _continueAsGuest() async {
    HapticFeedbackHelper.tap();
    dismissKeyboardAndInputChromeAfterRouteChange();
    // После выхода из аккаунта локальный кэш мог остаться от прошлого user_id;
    // без очистки гость видит чужую статистику.
    final ds = ref.read(progressDataSourceProvider);
    if (ds.storedProgressOwnerId != null) {
      await ds.clearAllProgressForAccountSwitch();
      await ds.setStoredProgressOwnerId(null);
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(statsProvider);
      ref.invalidate(ticketProgressProvider);
      ref.invalidate(favoriteQuestionsProvider);
      ref.invalidate(wrongQuestionIdsProvider);
    }
    await ref.read(guestModeProvider.notifier).enterGuestMode();
  }

  Future<void> _handleClose() async {
    if (widget.onClose != null) {
      HapticFeedbackHelper.tap();
      dismissKeyboardAndInputChromeAfterRouteChange();
      widget.onClose!.call();
      return;
    }

    await _continueAsGuest();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authLoadingProvider);
    final isSupabaseAvailable = ref.watch(supabaseAvailableProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
            return SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                20,
                AppDimensions.screenPadding,
                32 + keyboardBottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: AppChromeIconButton(
                          icon: Icons.close_rounded,
                          onTap: _handleClose,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spacingL),
                      _buildAuthCard(
                        context: context,
                        textTheme: textTheme,
                        isLoading: isLoading,
                        isSupabaseAvailable: isSupabaseAvailable,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAuthCard({
    required BuildContext context,
    required TextTheme textTheme,
    required bool isLoading,
    required bool isSupabaseAvailable,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isLogin ? 'Вход в аккаунт' : 'Создание аккаунта',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: AppDimensions.spacingS),
          Text(
            isSupabaseAvailable
                ? 'Email и Google-вход доступны в этой сборке.'
                : 'Авторизация временно недоступна в этой сборке.',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.secondaryText,
              height: 1.4,
            ),
          ),
          if (isSupabaseAvailable) ...[
            const SizedBox(height: AppDimensions.spacingL),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'name@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingM),
            TextField(
              controller: _passwordController,
              obscureText: !_showPassword,
              textInputAction:
                  _isLogin ? TextInputAction.done : TextInputAction.next,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              onSubmitted: (_) {
                if (_isLogin) {
                  FocusManager.instance.primaryFocus?.unfocus();
                }
              },
              decoration: InputDecoration(
                labelText: 'Пароль',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _showPassword = !_showPassword);
                  },
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            if (!_isLogin) ...[
              const SizedBox(height: AppDimensions.spacingM),
              TextField(
                controller: _confirmPasswordController,
                obscureText: !_showConfirmPassword,
                textInputAction: TextInputAction.done,
                scrollPadding: const EdgeInsets.only(bottom: 120),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  labelText: 'Повторите пароль',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _showConfirmPassword = !_showConfirmPassword;
                      });
                    },
                    icon: Icon(
                      _showConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppDimensions.spacingL),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading ? null : _submitEmail,
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : Text(_isLogin ? 'Войти' : 'Зарегистрироваться'),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.divider)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'или',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: AppColors.divider)),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingL),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: isLoading ? null : _signInWithGoogle,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/images/Google__G__logo.svg',
                      height: 20,
                      width: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text('Войти через Google'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingM),
            Center(
              child: TextButton(
                onPressed: () {
                  HapticFeedbackHelper.tap();
                  setState(() => _isLogin = !_isLogin);
                },
                child: Text(
                  _isLogin
                      ? 'Нет аккаунта? Зарегистрироваться'
                      : 'Уже есть аккаунт? Войти',
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: AppDimensions.spacingL),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDimensions.spacingL),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.cloud_off_outlined, color: AppColors.accent),
                  SizedBox(width: AppDimensions.spacingM),
                  Expanded(
                    child: Text(
                      'Локальный режим работает без облачной синхронизации. Прогресс и избранное сохраняются на этом устройстве.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
