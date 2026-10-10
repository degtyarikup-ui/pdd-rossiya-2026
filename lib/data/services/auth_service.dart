import 'dart:async';
import 'dart:convert';
import 'package:pdd_app/data/services/auth_session_store.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/presentation/widgets/yandex_auth_sheet.dart';
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

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._internal();
  AuthService._internal() : _writeSession = AuthSessionStore.write;
  @visibleForTesting
  AuthService.forTesting({
    required Future<void> Function(Map<String, dynamic>) writeSession,
  }) : _writeSession = writeSession;
  final Future<void> Function(Map<String, dynamic>) _writeSession;
  AuthFailure? lastFailure;
  String? lastDiagnosticId;
  bool sessionIsTemporary = false;

  String _signInProvider = 'unknown';
  // Сколько попыток сделал последний запрос выдачи сессии и где он удался —
  // для отчётов о сбоях и о входе «не с первого раза».
  RetryStats? _lastRetryStats;
  void _beginSignIn(String provider) {
    _signInProvider = provider;
    lastFailure = AuthFailure.cancelled;
    lastDiagnosticId = null;
    _lastRetryStats = null;
  }

  void _recordSignInError(Object error) {
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
        : error is http.ClientException
        ? AuthFailure.network
        : error is FormatException || error is TypeError
        ? AuthFailure.response
        : AuthFailure.provider;
    // Для сбоев связи в код добавляется число попыток (timeout:3x): так в
    // уведомлении видно, что повторы и запасной адрес не помогли.
    final tries = _lastRetryStats?.attempts ?? 0;
    final networkLike =
        error is TimeoutException || error is http.ClientException;
    ErrorReporter.report(
      ErrorCategory.auth,
      'auth.provider',
      error: error,
      code: networkLike && tries > 0
          ? '${ErrorReporter.codeFor(error)}:${tries}x'
          : null,
      provider: _signInProvider,
    );
  }

  @visibleForTesting
  Future<bool> completeSignInForTesting(
    UserProfile profile,
    String credential,
  ) => _completeSignIn(profile, credential);

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
      const bool.fromEnvironment('GAME_DEBUG') && (kDebugMode || _devPackage);
  static bool _devPackage = false;

  Future<bool> signInDebug() async {
    if (!debugSignInAvailable) return false;
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

  Future<bool> signInWithGoogle() async {
    _beginSignIn('google');
    try {
      if (kIsWeb) {
        throw StateError('Web sign-in must use the Google Identity button');
      }
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        clientId: defaultTargetPlatform == TargetPlatform.iOS
            ? googleClientId
            : null,
        // Android continues to use its existing access-token flow.
      );
      final account = await googleSignIn.signIn();
      return account == null ? false : await _completeGoogleAccount(account);
    } catch (e) {
      _recordSignInError(e);
      return false;
    }
  }

  /// Receives an account from Google's official web Identity button.
  Future<bool> signInWithGoogleWebAccount(GoogleSignInAccount account) async {
    _beginSignIn('google');
    try {
      return await _completeGoogleAccount(account);
    } catch (e) {
      _recordSignInError(e);
      return false;
    }
  }

  Future<bool> signInWithGoogleWeb(Future<String> Function() request) async {
    _beginSignIn('google');
    try {
      // request opens Google's window synchronously from the button gesture.
      return await _completeCredential('google', await request());
    } catch (e) {
      _recordSignInError(e);
      return false;
    }
  }

  /// The server resolves the account from Google's verified OAuth token.
  Future<bool> signInWithGoogleWebToken(String credential) async {
    _beginSignIn('google');
    try {
      return await _completeCredential('google', credential);
    } catch (e) {
      _recordSignInError(e);
      return false;
    }
  }

  Future<bool> _completeGoogleAccount(GoogleSignInAccount account) async {
    final authentication = await account.authentication;
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
    return _completeSignIn(profile, credential);
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

  Future<bool> signInWithApple() async {
    _beginSignIn('apple');
    try {
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
        credential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
      } else {
        credential = await SignInWithApple.getAppleIDCredential(
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
        );
      }

      return await _completeAppleSignIn(credential);
    } catch (e) {
      _recordSignInError(e);
      return false;
    }
  }

  Future<bool> _completeAppleSignIn(
    AuthorizationCredentialAppleID credential,
  ) async {
    // The web flow returns no userIdentifier: the token's `sub` is the
    // same Apple user id (the server verifies it and keys the account by it).
    final userIdentifier =
        credential.userIdentifier ??
        jwtClaim(credential.identityToken, 'sub') ??
        '';
    if (userIdentifier.isEmpty || credential.identityToken == null) {
      lastFailure = AuthFailure.provider;
      ErrorReporter.report(
        ErrorCategory.auth,
        'auth.provider',
        code: 'missing_credential',
        provider: 'apple',
      );
      return false;
    }
    final prefs = await SharedPreferences.getInstance();

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

    return await _completeSignIn(profile, credential.identityToken);
  }

  Future<bool> completeWebSignIn(Map<String, String> params) async {
    final provider = params['provider'] ?? 'unknown';
    _beginSignIn(provider);
    try {
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
        final profile = await YandexAuthSheet.profileForToken(token);
        if (profile == null) {
          lastFailure = AuthFailure.provider;
          return false;
        }
        return await _completeSignIn(profile, token);
      }
      lastFailure = AuthFailure.response;
      return false;
    } catch (e) {
      _recordSignInError(e);
      return false;
    }
  }

  static const String yandexClientId = '94aa539db4634e44bf0b209d9a2205d2';

  Future<bool> signInWithYandex(BuildContext context) async {
    _beginSignIn('yandex');
    try {
      final result = await YandexAuthSheet.show(context);
      if (result != null) {
        return await _completeSignIn(result.profile, result.token);
      }
      return false;
    } catch (e) {
      _recordSignInError(e);
      return false;
    }
  }

  Future<bool> _completeSignIn(UserProfile profile, String? credential) =>
      _completeCredential(
        profile.provider.name,
        credential,
        expectedUserId: profile.id,
        name: profile.name,
      );

  Future<bool> _completeCredential(
    String provider,
    String? credential, {
    String? expectedUserId,
    String? name,
  }) async {
    _signInProvider = provider;
    if (credential == null ||
        credential.isEmpty ||
        !BackendConfig.hasNotifier) {
      lastFailure = AuthFailure.provider;
      ErrorReporter.report(
        ErrorCategory.auth,
        'auth.session',
        code: 'missing_credential',
        provider: _signInProvider,
      );
      return false;
    }
    final revision = _accountRevision;
    Map<String, dynamic> metadata = {};
    try {
      metadata = await InstallReporter.clientMetadata().timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {}
    // Сессия выдаётся без записи на сервере — повторить запрос безопасно.
    final stats = RetryStats();
    _lastRetryStats = stats;
    final response = await sendWithRetry(
      (host) => http.post(
        Uri.parse('$host/api/auth/session'),
        headers: serverHeaders,
        body: jsonEncode({
          'provider': provider,
          'credential': credential,
          'name': ?name,
          'platform': metadata['platform'],
          'appVersion': metadata['version'],
          'device': metadata['device'],
        }),
      ),
      hosts: BackendConfig.notifierHosts,
      stillWanted: () => revision == _accountRevision,
      stats: stats,
    );
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
    if (revision != _accountRevision) return false;
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
      ErrorReporter.report(
        ErrorCategory.auth,
        'auth.session',
        code: 'invalid_response',
        provider: _signInProvider,
      );
      return false;
    }
    var temporarySession = false;
    try {
      await _writeSession({
        'userId': user.id,
        'token': token,
        'expiresAt': expiry.toIso8601String(),
      }).timeout(const Duration(seconds: 5));
    } catch (_) {
      // The server has verified identity. A broken Android keystore must not
      // discard this login; keep the token in memory, never in preferences.
      temporarySession = true;
      debugPrint(
        'AuthService: session storage unavailable; using memory session',
      );
    }
    if (revision != _accountRevision) return false;
    final avatarPrefs = await SharedPreferences.getInstance();
    if (revision != _accountRevision) return false;
    _sessionToken = token;
    _sessionExpiresAt = expiry;
    _currentUser = user.withAvatarChoice(
      avatarPrefs.getBool('default_avatar_${user.id}') ?? false,
    );
    sessionIsTemporary = temporarySession;
    lastFailure = null;
    // Вход удался, но потребовался повтор или запасной адрес — это сигнал о
    // плохой связи у части пользователей, хотя на экране ошибки не было.
    if (stats.neededRecovery) {
      ErrorReporter.report(
        ErrorCategory.auth,
        'auth.recovered',
        code: stats.host == BackendConfig.notifierUrl
            ? 'retry_ok:${stats.attempts}x'
            : 'fallback_ok:${stats.attempts}x',
        provider: _signInProvider,
      );
    }
    _accountRevision++;
    await _saveUser();
    notifyListeners();
    await PremiumService.instance.onAuthChanged(user);
    unawaited(ProgressSyncService.instance.syncWithServer());
    return true;
  }

  Future<void> signOut() async {
    final oldHeaders = serverHeaders;
    final hadSession = hasServerSession;
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
      await AuthSessionStore.clear();
    } catch (_) {}
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await YandexNativeAuth.signOut();
      } catch (_) {}
    }
    try {
      try {
        final googleSignIn = GoogleSignIn(
          clientId: kIsWeb ? googleWebClientId : null,
        );
        if (kIsWeb || await googleSignIn.isSignedIn()) {
          await googleSignIn.signOut();
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
  }

  /// Removes the account on the server (profile, synced progress, game
  /// score) and signs out locally. Returns whether the server confirmed.
  Future<bool> deleteAccount() async {
    var deleted = false;
    final user = _currentUser;
    final revision = _accountRevision;
    try {
      if (user != null && BackendConfig.hasNotifier) {
        final resp = await http
            .post(
              Uri.parse('${BackendConfig.notifierUrl}/api/user/delete'),
              headers: serverHeaders,
              body: jsonEncode({'userId': user.id}),
            )
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          deleted =
              body is Map && body['ok'] == true && body['deleted'] == user.id;
        }
      }
    } catch (e) {
      debugPrint('AuthService: delete account error: $e');
    }
    if (!deleted) return false;
    if (revision != _accountRevision) return true;
    try {
      await signOut();
    } catch (e) {
      debugPrint('AuthService: sign out after delete error: $e');
    }
    return deleted;
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
