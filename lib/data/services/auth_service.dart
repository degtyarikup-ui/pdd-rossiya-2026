import 'dart:async';
import 'dart:convert';
import 'package:pdd_app/data/services/auth_session_store.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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
  void _beginSignIn(String provider) {
    _signInProvider = provider;
    lastFailure = AuthFailure.cancelled;
    lastDiagnosticId = null;
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
    ErrorReporter.report(
      ErrorCategory.auth,
      'auth.provider',
      error: error,
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
      await PremiumService.instance.onAuthChanged(_currentUser);
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

      // The web popup flow returns no userIdentifier: the token's `sub` is the
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
      } else if ((email == null || email.isEmpty) &&
          userIdentifier.isNotEmpty) {
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

  Future<bool> _completeSignIn(UserProfile profile, String? credential) async {
    _signInProvider = profile.provider.name;
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
    final response = await http
        .post(
          Uri.parse('${BackendConfig.notifierUrl}/api/auth/session'),
          headers: serverHeaders,
          body: jsonEncode({
            'provider': profile.provider.name,
            'credential': credential,
            'name': profile.name,
            'platform': metadata['platform'],
            'appVersion': metadata['version'],
            'device': metadata['device'],
          }),
        )
        .timeout(const Duration(seconds: 15));
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
    if (user.id != profile.id ||
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
    _sessionToken = token;
    _sessionExpiresAt = expiry;
    _currentUser = user;
    sessionIsTemporary = temporarySession;
    lastFailure = null;
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
