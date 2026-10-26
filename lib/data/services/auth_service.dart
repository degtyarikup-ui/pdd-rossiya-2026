import 'dart:async';
import 'dart:convert';
import 'package:pdd_app/data/services/auth_session_store.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:pdd_app/data/services/notifier_api.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/presentation/widgets/yandex_auth_sheet.dart';
import 'package:pdd_app/presentation/widgets/telegram_auth_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:pdd_app/data/services/web_oauth_state.dart';
import 'package:pdd_app/data/services/yandex_native_auth.dart';
import 'package:pdd_app/data/services/web_oauth_redirect_stub.dart'
    if (dart.library.js_interop) 'package:pdd_app/data/services/web_oauth_redirect.dart';

enum AuthFailure {
  cancelled,
  provider,
  network,
  timeout,
  appKey,
  credential,
  server,
  response,
}

class _SignInAttempt {
  _SignInAttempt(this.id, this.provider, this.revision, this.previousSession)
    : client = http.Client();
  final int id;
  final String provider;
  final int revision;
  final Map<String, dynamic>? previousSession;
  final http.Client client;
  final RetryStats stats = RetryStats();
  final Completer<void> cancelled = Completer<void>();
  bool providerPending = false;
  bool persistenceQueued = false;
  bool rollbackQueued = false;
  bool committed = false;
  int? committedRevision;
}

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._internal();
  AuthService._internal()
    : _writeSession = AuthSessionStore.write,
      _clearSession = AuthSessionStore.clear,
      _errorReporter = null;
  @visibleForTesting
  AuthService.forTesting({
    required Future<void> Function(Map<String, dynamic>) writeSession,
    Future<void> Function()? clearSession,
    ErrorReporter? errorReporter,
  }) : _writeSession = writeSession,
       _clearSession = clearSession ?? AuthSessionStore.clear,
       _errorReporter = errorReporter;
  final Future<void> Function(Map<String, dynamic>) _writeSession;
  final Future<void> Function() _clearSession;
  final ErrorReporter? _errorReporter;
  AuthFailure? lastFailure;
  String? lastDiagnosticId;
  bool sessionIsTemporary = false;
  Uri? appleManualRevocationUrl;
  bool appleRevocationPending = false;

  _SignInAttempt? _activeSignIn;
  _SignInAttempt? _providerHold;
  Timer? _providerHoldTimer;
  int _nextSignInId = 0;
  bool _signingOut = false;
  bool _deletingAccount = false;
  Future<void> _sessionWrites = Future<void>.value();
  final ValueNotifier<bool> _signInBusy = ValueNotifier(false);
  ValueListenable<bool> get signInBusy => _signInBusy;
  bool get isSigningIn =>
      _activeSignIn != null ||
      _providerHold != null ||
      _signingOut ||
      _deletingAccount;
  int? get activeSignInId => _activeSignIn?.id;

  bool _wanted(_SignInAttempt attempt) =>
      identical(_activeSignIn, attempt) &&
      !attempt.cancelled.isCompleted &&
      attempt.revision == _accountRevision;

  void _updateSignInBusy() => _signInBusy.value = isSigningIn;

  void _reportAuth(
    _SignInAttempt attempt,
    String operation, {
    Object? error,
    String? code,
  }) {
    final reporter = _errorReporter;
    if (reporter == null) {
      ErrorReporter.report(
        ErrorCategory.auth,
        operation,
        error: error,
        code: code,
        provider: attempt.provider,
      );
    } else {
      unawaited(
        reporter.record(
          ErrorCategory.auth,
          operation,
          code:
              code ??
              (error == null
                  ? 'operation_failed'
                  : ErrorReporter.codeFor(error)),
          provider: attempt.provider,
        ),
      );
    }
  }

  Future<void> _queueSessionOperation(Future<void> Function() operation) {
    final result = _sessionWrites.then((_) => operation());
    // Keep the actual write pending even when its caller's UI timeout expires.
    _sessionWrites = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    return result;
  }

  void _rollbackCancelledWrite(_SignInAttempt attempt) {
    if (!attempt.persistenceQueued ||
        attempt.rollbackQueued ||
        attempt.committed) {
      return;
    }
    attempt.rollbackQueued = true;
    unawaited(
      _queueSessionOperation(() async {
        if (_accountRevision != attempt.revision) return;
        final previous = attempt.previousSession;
        if (previous == null) {
          await _clearSession();
        } else {
          await _writeSession(previous);
        }
      }).catchError((Object _) {}),
    );
  }

  /// Closing a sheet cancels its own result, never another sheet's attempt.
  /// SDKs without a cancel API get a bounded grace period before another SSO.
  void cancelSignIn([int? attemptId]) {
    final attempt = _activeSignIn;
    if (attempt == null ||
        (attemptId != null && attempt.id != attemptId) ||
        attempt.committed) {
      return;
    }
    if (!attempt.cancelled.isCompleted) attempt.cancelled.complete();
    attempt.client.close();
    _rollbackCancelledWrite(attempt);
    lastFailure = AuthFailure.cancelled;
    if (attempt.providerPending) {
      _providerHold = attempt;
      _providerHoldTimer?.cancel();
      _providerHoldTimer = Timer(
        const Duration(seconds: 15),
        () => _releaseProviderHold(attempt),
      );
    }
  }

  void _releaseProviderHold(_SignInAttempt attempt) {
    if (!identical(_providerHold, attempt)) return;
    _providerHold = null;
    _providerHoldTimer?.cancel();
    _providerHoldTimer = null;
    _updateSignInBusy();
  }

  Future<T> _providerRequest<T>(
    _SignInAttempt attempt,
    Future<T> Function() request,
  ) async {
    attempt.providerPending = true;
    try {
      // The request still starts synchronously from the browser button gesture.
      return await request().timeout(const Duration(minutes: 2));
    } finally {
      attempt.providerPending = false;
      _releaseProviderHold(attempt);
    }
  }

  Future<bool> _runSignIn(
    String provider,
    Future<bool> Function(_SignInAttempt) action,
  ) async {
    if (isSigningIn) return false;
    final attempt = _SignInAttempt(
      ++_nextSignInId,
      provider,
      _accountRevision,
      hasServerSession && _currentUser != null
          ? {
              'userId': _currentUser!.id,
              'token': _sessionToken,
              'expiresAt': _sessionExpiresAt!.toIso8601String(),
            }
          : null,
    );
    _activeSignIn = attempt;
    lastFailure = AuthFailure.cancelled;
    lastDiagnosticId = null;
    _updateSignInBusy();
    final operation = () async {
      try {
        return await action(attempt);
      } catch (error) {
        if (_wanted(attempt)) _recordSignInError(error, attempt);
        return false;
      }
    }();
    try {
      return await Future.any([
        operation,
        attempt.cancelled.future.then((_) => false),
      ]);
    } finally {
      if (identical(_activeSignIn, attempt)) _activeSignIn = null;
      attempt.client.close();
      _updateSignInBusy();
    }
  }

  void _recordSignInError(Object error, _SignInAttempt attempt) {
    if ((error is SignInWithAppleAuthorizationException &&
            error.code == AuthorizationErrorCode.canceled) ||
        (error is PlatformException &&
            [
              'sign_in_canceled',
              'sign_in_cancelled',
              'canceled',
              'cancelled',
            ].contains(error.code))) {
      lastFailure = AuthFailure.cancelled;
      return;
    }
    lastFailure = error is TimeoutException
        ? AuthFailure.timeout
        : isRetryableNetworkError(error)
        ? AuthFailure.network
        : error is FormatException || error is TypeError
        ? AuthFailure.response
        : AuthFailure.provider;
    // Для сбоев связи в код добавляется число попыток (timeout:3x): так в
    // уведомлении видно, что повторы и запасной адрес не помогли.
    final tries = attempt.stats.attempts;
    final networkLike = isRetryableNetworkError(error);
    _reportAuth(
      attempt,
      tries > 0 ? 'auth.session' : 'auth.provider',
      error: error,
      code: networkLike && tries > 0
          ? '${error is TimeoutException ? 'timeout' : 'network'}:${tries}x'
          : null,
    );
  }

  @visibleForTesting
  Future<bool> completeSignInForTesting(
    UserProfile profile,
    String credential,
  ) => _runSignIn(
    profile.provider.name,
    (attempt) => _completeSignIn(attempt, profile, credential),
  );

  static const String _prefKeyUser = 'auth_user_profile';

  UserProfile? _currentUser;
  bool _isInitialized = false;
  String? _sessionToken;
  DateTime? _sessionExpiresAt;
  int _accountRevision = 0;
  int get accountRevision => _accountRevision;
  bool get hasServerSession =>
      _sessionToken != null &&
      _sessionExpiresAt != null &&
      DateTime.now().isBefore(_sessionExpiresAt!);
  Map<String, String> get serverHeaders => {
    'content-type': 'application/json',
    if (BackendConfig.notifierSecret.isNotEmpty)
      'x-install-secret': BackendConfig.notifierSecret,
    if (hasServerSession) 'authorization': 'Bearer $_sessionToken',
  };

  UserProfile? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  Future<void> init() async {
    if (_isInitialized) return;
    if (const bool.fromEnvironment('GAME_DEBUG')) {
      try {
        _devPackage = (await PackageInfo.fromPlatform()).packageName.endsWith(
          '.dev',
        );
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_prefKeyUser);
      if (userJson != null && userJson.isNotEmpty) {
        var user = UserProfile.fromJson(userJson);
        // Миграция/очистка от старых заглушек
        if (user.email == 'apple.user@icloud.com') {
          final rawId = user.id.replaceFirst('apple_', '');
          final cachedEmail = prefs.getString('apple_email_$rawId') ?? '';
          final cachedName = prefs.getString('apple_name_$rawId');
          user = UserProfile(
            id: user.id,
            name:
                cachedName ??
                (cachedEmail.isNotEmpty
                    ? cachedEmail.split('@').first
                    : user.name),
            email: cachedEmail,
            avatarUrl: user.avatarUrl,
            provider: user.provider,
            createdAt: user.createdAt,
          );
          await prefs.setString(_prefKeyUser, user.toJson());
        }
        if (!debugSignInAvailable && user.id == 'debug_tester') {
          await prefs.remove(_prefKeyUser);
        } else if (debugSignInAvailable && user.id == 'debug_tester') {
          _currentUser = user;
        } else {
          Map<String, dynamic>? session;
          try {
            session = await AuthSessionStore.read();
          } catch (_) {}
          final expiry = DateTime.tryParse(
            session?['expiresAt'] as String? ?? '',
          );
          if (session?['userId'] == user.id &&
              session?['token'] is String &&
              expiry != null &&
              expiry.isAfter(DateTime.now())) {
            _sessionToken = session!['token'] as String;
            _sessionExpiresAt = expiry;
            _currentUser = user;
          } else {
            // Legacy cached profiles are not proof of identity. Re-login is
            // required once after this update; local progress is preserved.
            await prefs.remove(_prefKeyUser);
          }
        }
      }
      _isInitialized = true;
      notifyListeners();
      await PremiumService.instance.onAuthChanged(
        _currentUser,
        waitForSync: false,
      );
    } catch (e) {
      debugPrint('AuthService: init error: $e');
    }
  }

  static const String googleClientId =
      '513938972930-3lclc5epsnm12druv86ut2o89pj71cu9.apps.googleusercontent.com';

  // A browser must use a Web application OAuth client, never the iOS client.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '513938972930-a7sh1di6odgf77ijltu31lvpuhijcis1.apps.googleusercontent.com',
  );

  /// Debug builds only (`--dart-define=GAME_DEBUG=true`): a local account
  /// without an OAuth provider, so a dev-signed APK (its package and SHA-1
  /// are not registered with Google/Yandex) can still exercise the
  /// signed-in features. Never available in store builds.
  /// Also the side-by-side test install (`-Pdev`, package `*.dev`), which is
  /// a release build: the store package never ends in `.dev`.
  static bool get debugSignInAvailable =>
      const bool.fromEnvironment('GAME_DEBUG') &&
      (kDebugMode ||
          _devPackage ||
          // iOS has no `.dev` package: a test build on a phone is made with
          // both defines, the store build never gets either.
          const bool.fromEnvironment('GAME_DEBUG_DEVICE'));
  static bool _devPackage = false;

  Future<bool> signInDebug() async {
    if (!debugSignInAvailable) return false;
    cancelSignIn();
    _accountRevision++;
    _currentUser = UserProfile(
      id: 'debug_tester',
      name: 'Тестировщик',
      email: 'tester@example.com',
      avatarUrl: null,
      provider: AuthProviderType.google,
      createdAt: DateTime.now(),
    );
    await _saveUser();
    notifyListeners();
    await PremiumService.instance.onAuthChanged(_currentUser);
    return true;
  }

  Future<bool> signInWithGoogle() => _runSignIn('google', (attempt) async {
    if (kIsWeb) {
      throw StateError('Web sign-in must use the Google Identity button');
    }
    final googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? googleClientId
          : null,
      // No serverClientId on Android: the app's Android OAuth clients live
      // in other Cloud projects than the Web client, and Google rejects
      // the pair (DEVELOPER_ERROR). Android sends an access token instead.
    );
    final account = await _providerRequest(attempt, googleSignIn.signIn);
    return account == null || !_wanted(attempt)
        ? false
        : await _completeGoogleAccount(attempt, account);
  });

  /// Receives an account from Google's official web Identity button.
  Future<bool> signInWithGoogleWebAccount(GoogleSignInAccount account) =>
      _runSignIn(
        'google',
        (attempt) => _completeGoogleAccount(attempt, account),
      );

  Future<bool> signInWithGoogleWeb(Future<String> Function() request) =>
      _runSignIn('google', (attempt) async {
        // request opens Google's window synchronously from the button gesture.
        final credential = await _providerRequest(attempt, request);
        return _wanted(attempt)
            ? await _completeCredential(attempt, credential)
            : false;
      });

  /// The server resolves the account from Google's verified OAuth token.
  Future<bool> signInWithGoogleWebToken(String credential) => _runSignIn(
    'google',
    (attempt) => _completeCredential(attempt, credential),
  );

  Future<bool> _completeGoogleAccount(
    _SignInAttempt attempt,
    GoogleSignInAccount account,
  ) async {
    if (!_wanted(attempt)) return false;
    final authentication = await _providerRequest(
      attempt,
      () => account.authentication,
    );
    if (!_wanted(attempt)) return false;
    final profile = UserProfile(
      id: 'google_${account.id}',
      name: account.displayName?.isNotEmpty == true
          ? account.displayName!
          : account.email.split('@').first,
      email: account.email,
      avatarUrl: account.photoUrl,
      provider: AuthProviderType.google,
      createdAt: DateTime.now(),
    );
    // Web always sends a signed ID token, including on Android browsers.
    final credential =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? authentication.accessToken
        : authentication.idToken;
    return _completeSignIn(attempt, profile, credential);
  }

  /// Извлечение email из identityToken (JWT) от Apple
  static String? _extractEmailFromJwt(String? identityToken) =>
      jwtClaim(identityToken, 'email');

  /// A string claim of an identity token (payload only: the server verifies
  /// the signature). Null when the token or the claim is missing.
  @visibleForTesting
  static String? jwtClaim(String? identityToken, String claim) {
    if (identityToken == null || identityToken.isEmpty) return null;
    try {
      final parts = identityToken.split('.');
      if (parts.length < 2) return null;
      var payload = parts[1];
      // Normalize base64 padding
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      final value = map[claim] as String?;
      if (value != null && value.isNotEmpty) {
        return value;
      }
    } catch (e) {
      debugPrint('AuthService: error decoding Apple identityToken: $e');
    }
    return null;
  }

  Future<bool> signInWithApple() => _runSignIn('apple', (attempt) async {
    if (kIsWeb) {
      final state = newWebOAuthState();
      await startWebOAuth(
        'apple',
        Uri.https('appleid.apple.com', '/auth/authorize', {
          'client_id': 'ru.pdd.pddapp.auth',
          'redirect_uri': '${BackendConfig.notifierUrl}/auth/apple/callback',
          'response_type': 'code id_token',
          'response_mode': 'form_post',
          'scope': 'name email',
          'state': state,
          'nonce': newWebOAuthState(),
        }),
      );
    }
    final AuthorizationCredentialAppleID credential;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      credential = await _providerRequest(
        attempt,
        () => SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        ),
      );
    } else {
      credential = await _providerRequest(
        attempt,
        () => SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          webAuthenticationOptions: WebAuthenticationOptions(
            clientId: 'ru.pdd.pddapp.auth',
            redirectUri: Uri.parse(
              'https://pdd-russia.app/auth/apple/callback',
            ),
          ),
        ),
      );
    }

    return _wanted(attempt)
        ? await _completeAppleSignIn(attempt, credential)
        : false;
  });

  Future<bool> _completeAppleSignIn(
    _SignInAttempt attempt,
    AuthorizationCredentialAppleID credential,
  ) async {
    if (!_wanted(attempt)) return false;
    // The web flow returns no userIdentifier: the token's `sub` is the
    // same Apple user id (the server verifies it and keys the account by it).
    final userIdentifier =
        credential.userIdentifier ??
        jwtClaim(credential.identityToken, 'sub') ??
        '';
    if (userIdentifier.isEmpty || credential.identityToken == null) {
      lastFailure = AuthFailure.provider;
      _reportAuth(attempt, 'auth.provider', code: 'missing_credential');
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!_wanted(attempt)) return false;

    // 1. Имя пользователя (Apple возвращает fullName только при первом входе)
    String? rawName = [
      credential.givenName,
      credential.familyName,
    ].where((s) => s != null && s.trim().isNotEmpty).join(' ').trim();
    if (rawName.isNotEmpty && userIdentifier.isNotEmpty) {
      await prefs.setString('apple_name_$userIdentifier', rawName);
    } else if (rawName.isEmpty && userIdentifier.isNotEmpty) {
      rawName = prefs.getString('apple_name_$userIdentifier') ?? '';
    }

    // 2. Email пользователя (из credential, JWT identityToken или кэша)
    String? email = credential.email?.trim();
    if (email == null || email.isEmpty) {
      email = _extractEmailFromJwt(credential.identityToken);
    }
    if (email != null && email.isNotEmpty && userIdentifier.isNotEmpty) {
      await prefs.setString('apple_email_$userIdentifier', email);
    } else if ((email == null || email.isEmpty) && userIdentifier.isNotEmpty) {
      email = prefs.getString('apple_email_$userIdentifier') ?? '';
    }

    // 3. Формирование отображаемого имени
    String displayName = rawName.isNotEmpty ? rawName : '';
    if (displayName.isEmpty) {
      if (email != null &&
          email.isNotEmpty &&
          !email.contains('privaterelay')) {
        final prefix = email.split('@').first;
        displayName = prefix.isNotEmpty
            ? prefix[0].toUpperCase() + prefix.substring(1)
            : 'Apple ID';
      } else {
        displayName = 'Apple ID';
      }
    }

    final finalEmail = email ?? '';

    final profile = UserProfile(
      id: 'apple_$userIdentifier',
      name: displayName,
      email: finalEmail,
      avatarUrl: null,
      provider: AuthProviderType.apple,
      createdAt: DateTime.now(),
    );

    return await _completeCredential(
      attempt,
      credential.identityToken,
      expectedUserId: profile.id,
      name: profile.name,
      authorizationCode: credential.authorizationCode,
    );
  }

  Future<bool> completeWebSignIn(Map<String, String> params) {
    final provider = params['provider'] ?? 'unknown';
    return _runSignIn(provider, (attempt) async {
      if (params['error'] != null) {
        lastFailure = params['error'] == 'access_denied'
            ? AuthFailure.cancelled
            : params['error'] == 'invalid_state'
            ? AuthFailure.response
            : AuthFailure.provider;
        return false;
      }
      if (provider == 'apple') {
        final token = params['id_token'];
        final nonce = params['expected_nonce'];
        if (nonce == null ||
            nonce.isEmpty ||
            jwtClaim(token, 'nonce') != nonce) {
          lastFailure = AuthFailure.response;
          return false;
        }
        return await _completeAppleSignIn(
          attempt,
          AuthorizationCredentialAppleID(
            authorizationCode: params['code'] ?? '',
            identityToken: token,
            userIdentifier: null,
            givenName: params['firstName'],
            familyName: params['lastName'],
            email: null,
            state: params['state'],
          ),
        );
      }
      if (provider == 'yandex') {
        final token = params['access_token'];
        if (token == null || token.isEmpty) {
          lastFailure = AuthFailure.provider;
          return false;
        }
        return await _completeCredential(attempt, token);
      }
      lastFailure = AuthFailure.response;
      return false;
    });
  }

  static const String yandexClientId = '94aa539db4634e44bf0b209d9a2205d2';

  Future<bool> signInWithYandex(BuildContext context) =>
      _runSignIn('yandex', (attempt) async {
        final result = await _providerRequest(
          attempt,
          () => YandexAuthSheet.show(context),
        );
        if (result != null) {
          return _wanted(attempt)
              ? await _completeCredential(attempt, result.token)
              : false;
        }
        return false;
      });

  Future<bool> signInWithTelegram(BuildContext context) =>
      _runSignIn('telegram', (attempt) async {
        final result = await _providerRequest(
          attempt,
          () => TelegramAuthSheet.show(context),
        );
        if (result != null) {
          if (!_wanted(attempt)) return false;
          return await _acceptServerSession(
            attempt,
            user: result.user,
            token: result.token,
            expiresAt: result.expiresAt,
          );
        }
        return false;
      });

  Future<bool> completeServerSession({
    required UserProfile user,
    required String token,
    required DateTime expiresAt,
  }) => _runSignIn(
    user.provider.name,
    (attempt) => _acceptServerSession(
      attempt,
      user: user,
      token: token,
      expiresAt: expiresAt,
    ),
  );

  Future<bool> _acceptServerSession(
    _SignInAttempt attempt, {
    required UserProfile user,
    required String token,
    required DateTime expiresAt,
  }) async {
    if (!_wanted(attempt)) return false;
    if (user.provider.name != attempt.provider ||
        !user.id.startsWith('${attempt.provider}_') ||
        user.id.length <= attempt.provider.length + 1 ||
        token.isEmpty ||
        !expiresAt.isAfter(DateTime.now())) {
      lastFailure = AuthFailure.response;
      _reportAuth(attempt, 'auth.session', code: 'invalid_response');
      return false;
    }
    final avatarPrefs = await SharedPreferences.getInstance();
    if (!_wanted(attempt)) return false;
    var temporarySession = false;
    attempt.persistenceQueued = true;
    try {
      await _queueSessionOperation(() async {
        // A UI timeout can already have committed this verified session in
        // memory. Persist it later only while it is still the current account.
        final stillCurrent =
            attempt.committed &&
            attempt.committedRevision == _accountRevision &&
            _currentUser?.id == user.id;
        if (!_wanted(attempt) && !stillCurrent) return;
        await _writeSession({
          'userId': user.id,
          'token': token,
          'expiresAt': expiresAt.toIso8601String(),
        });
      }).timeout(const Duration(seconds: 5));
    } catch (_) {
      temporarySession = true;
      debugPrint(
        'AuthService: session storage unavailable; using memory session',
      );
    }
    if (!_wanted(attempt)) {
      _rollbackCancelledWrite(attempt);
      return false;
    }
    _sessionToken = token;
    _sessionExpiresAt = expiresAt;
    _currentUser = user.withAvatarChoice(
      avatarPrefs.getBool('default_avatar_${user.id}') ?? false,
    );
    sessionIsTemporary = temporarySession;
    lastFailure = null;
    attempt.committed = true;
    final committedRevision = ++_accountRevision;
    attempt.committedRevision = committedRevision;
    await _saveUser();
    if (_accountRevision != committedRevision) return false;
    notifyListeners();
    await PremiumService.instance.onAuthChanged(user);
    if (_accountRevision != committedRevision) return false;
    unawaited(ProgressSyncService.instance.syncWithServer());
    return true;
  }

  Future<bool> _completeSignIn(
    _SignInAttempt attempt,
    UserProfile profile,
    String? credential,
  ) => _completeCredential(
    attempt,
    credential,
    expectedUserId: profile.id,
    name: profile.name,
  );

  Future<bool> _completeCredential(
    _SignInAttempt attempt,
    String? credential, {
    String? expectedUserId,
    String? name,
    String? authorizationCode,
  }) async {
    if (!_wanted(attempt)) return false;
    final provider = attempt.provider;
    if (credential == null ||
        credential.isEmpty ||
        !BackendConfig.hasNotifier) {
      lastFailure = AuthFailure.provider;
      _reportAuth(attempt, 'auth.session', code: 'missing_credential');
      return false;
    }
    Map<String, dynamic> metadata = {};
    try {
      metadata = await InstallReporter.clientMetadata().timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {}
    if (!_wanted(attempt)) return false;
    // Сессия выдаётся без записи на сервере — повторить запрос безопасно.
    final stats = attempt.stats;
    final response = await sendWithRetry(
      (host) => attempt.client.post(
        Uri.parse('$host/api/auth/session'),
        headers: serverHeaders,
        body: jsonEncode({
          'provider': provider,
          'credential': credential,
          'name': ?name,
          if (authorizationCode != null && authorizationCode.isNotEmpty)
            'authorizationCode': authorizationCode,
          'platform': metadata['platform'],
          'appVersion': metadata['version'],
          'device': metadata['device'],
        }),
      ),
      hosts: BackendConfig.notifierHosts,
      stillWanted: () => _wanted(attempt),
      stats: stats,
      // Only session issuance is safe to retry. A temporary provider/JWKS
      // outage must not be shown as rejected credentials after one HTTP reply.
      retryStatusCodes: const {500, 502, 503, 504},
    );
    if (!_wanted(attempt)) return false;
    final diagnosticId = response.headers['x-auth-diagnostic-id'];
    if (diagnosticId != null &&
        RegExp(r'^[a-f0-9-]{36}$').hasMatch(diagnosticId)) {
      lastDiagnosticId = diagnosticId;
    }
    if (response.statusCode != 200) {
      lastFailure = response.statusCode == 403
          ? AuthFailure.appKey
          : response.statusCode == 401
          ? AuthFailure.credential
          : AuthFailure.server;
      return false;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final user = UserProfile.fromMap(
      Map<String, dynamic>.from(data['user'] as Map),
    );
    final token = data['token'] as String;
    final expiry = DateTime.parse(data['expiresAt'] as String);
    if (user.provider.name != provider ||
        !user.id.startsWith('${provider}_') ||
        user.id.length <= provider.length + 1 ||
        (expectedUserId != null && user.id != expectedUserId) ||
        token.isEmpty ||
        !expiry.isAfter(DateTime.now())) {
      lastFailure = AuthFailure.response;
      _reportAuth(attempt, 'auth.session', code: 'invalid_response');
      return false;
    }
    final accepted = await _acceptServerSession(
      attempt,
      user: user,
      token: token,
      expiresAt: expiry,
    );
    if (!accepted) return false;
    // Вход удался, но потребовался повтор или запасной адрес — это сигнал о
    // плохой связи у части пользователей, хотя на экране ошибки не было.
    if (stats.neededRecovery) {
      _reportAuth(
        attempt,
        'auth.recovered',
        code: stats.host == BackendConfig.notifierUrl
            ? 'retry_ok:${stats.attempts}x'
            : 'fallback_ok:${stats.attempts}x',
      );
    }
    return true;
  }

  Future<void> signOut() async {
    if (_signingOut) return;
    final oldHeaders = serverHeaders;
    final hadSession = hasServerSession;
    cancelSignIn();
    _signingOut = true;
    _updateSignInBusy();
    try {
      _accountRevision++;
      _sessionToken = null;
      _sessionExpiresAt = null;
      _currentUser = null;
      sessionIsTemporary = false;
      ProgressSyncService.instance.cancel();
      if (hadSession) {
        unawaited(
          http
              .post(
                Uri.parse('${BackendConfig.notifierUrl}/api/auth/logout'),
                headers: oldHeaders,
              )
              .timeout(const Duration(seconds: 8))
              .catchError((_) => http.Response('', 503)),
        );
      }
      try {
        await _queueSessionOperation(
          _clearSession,
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          await YandexNativeAuth.signOut().timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      try {
        try {
          final googleSignIn = GoogleSignIn(
            clientId: kIsWeb ? googleWebClientId : null,
          );
          if (kIsWeb ||
              await googleSignIn.isSignedIn().timeout(
                const Duration(seconds: 5),
              )) {
            await googleSignIn.signOut().timeout(const Duration(seconds: 5));
          }
        } catch (_) {}
        _currentUser = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefKeyUser);
        notifyListeners();
        await PremiumService.instance.onAuthChanged(null);
      } catch (e) {
        debugPrint('AuthService: sign out error: $e');
      }
    } finally {
      _signingOut = false;
      _updateSignInBusy();
    }
  }

  /// Removes the account on the server (profile, synced progress, game
  /// score) and signs out locally. Returns whether the server confirmed.
  Future<bool> deleteAccount() async {
    if (_deletingAccount || _currentUser == null) return false;
    cancelSignIn();
    _deletingAccount = true;
    _updateSignInBusy();
    try {
      var deleted = false;
      var requiresAppleRevocation = false;
      var pendingAppleRevocation = false;
      appleManualRevocationUrl = null;
      appleRevocationPending = false;
      final user = _currentUser;
      final revision = _accountRevision;
      try {
        if (user != null && BackendConfig.hasNotifier) {
          final resp = await http
              .post(
                NotifierApi.uri('/api/user/delete'),
                headers: serverHeaders,
                body: jsonEncode({'userId': user.id}),
              )
              .timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            final body = jsonDecode(resp.body);
            deleted =
                body is Map && body['ok'] == true && body['deleted'] == user.id;
            requiresAppleRevocation =
                deleted &&
                user.provider == AuthProviderType.apple &&
                body['appleRevocation'] == 'manual_required';
            pendingAppleRevocation =
                deleted &&
                user.provider == AuthProviderType.apple &&
                body['appleRevocation'] == 'pending';
          }
        }
      } catch (e) {
        debugPrint('AuthService: delete account error: $e');
      }
      if (!deleted) return false;
      if (revision != _accountRevision) return true;
      appleRevocationPending = pendingAppleRevocation;
      if (requiresAppleRevocation) {
        // Use a fixed Apple URL; never open an arbitrary URL from a response.
        appleManualRevocationUrl = Uri.parse(
          'https://account.apple.com/account/manage',
        );
      }
      try {
        await signOut();
      } catch (e) {
        debugPrint('AuthService: sign out after delete error: $e');
      }
      return deleted;
    } finally {
      _deletingAccount = false;
      _updateSignInBusy();
    }
  }

  Future<void> setDefaultAvatar(bool useDefault) async {
    final user = _currentUser;
    if (user == null || user.avatarUrl?.isNotEmpty != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('default_avatar_${user.id}', useDefault);
    if (_currentUser?.id != user.id) return;
    _currentUser = user.withAvatarChoice(useDefault);
    await _saveUser();
    notifyListeners();
    if (hasServerSession && BackendConfig.hasNotifier) {
      try {
        await http
            .post(
              Uri.parse('${BackendConfig.notifierUrl}/api/user/sync'),
              headers: serverHeaders,
              body: jsonEncode(_currentUser!.toMap()),
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
  }

  Future<void> _saveUser() async {
    if (_currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyUser, _currentUser!.toJson());
    } catch (e) {
      debugPrint('AuthService: save user error: $e');
    }
  }
}
