import 'dart:async';
import 'dart:convert';
import 'package:pdd_app/data/services/auth_session_store.dart';
import 'package:flutter/foundation.dart';
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

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

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
    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        clientId: kIsWeb || defaultTargetPlatform == TargetPlatform.iOS
            ? googleClientId
            : null,
        // No Web OAuth client exists for Android, so no ID token: Android
        // sends the access token and the server checks it with Google.
      );
      final account = await googleSignIn.signIn();
      if (account != null) {
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
        final credential = defaultTargetPlatform == TargetPlatform.android
            ? authentication.accessToken
            : authentication.idToken;
        return await _completeSignIn(profile, credential);
      }
      return false;
    } catch (e) {
      debugPrint('AuthService: google sign in error: $e');
      return false;
    }
  }

  /// Извлечение email из identityToken (JWT) от Apple
  static String? _extractEmailFromJwt(String? identityToken) {
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
      final email = map['email'] as String?;
      if (email != null && email.isNotEmpty) {
        return email;
      }
    } catch (e) {
      debugPrint('AuthService: error decoding Apple identityToken: $e');
    }
    return null;
  }

  Future<bool> signInWithApple() async {
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

      final userIdentifier = credential.userIdentifier ?? '';
      if (userIdentifier.isEmpty || credential.identityToken == null) {
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
      debugPrint('AuthService: apple sign in error: $e');
      return false;
    }
  }

  static const String yandexClientId = '94aa539db4634e44bf0b209d9a2205d2';

  Future<bool> signInWithYandex(BuildContext context) async {
    try {
      final result = await YandexAuthSheet.show(context);
      if (result != null) {
        return await _completeSignIn(result.profile, result.token);
      }
      return false;
    } catch (e) {
      debugPrint('AuthService: yandex sign in error: $e');
      return false;
    }
  }

  Future<bool> _completeSignIn(UserProfile profile, String? credential) async {
    if (credential == null ||
        credential.isEmpty ||
        !BackendConfig.hasNotifier) {
      return false;
    }
    final revision = _accountRevision;
    final response = await http
        .post(
          Uri.parse('${BackendConfig.notifierUrl}/api/auth/session'),
          headers: serverHeaders,
          body: jsonEncode({
            'provider': profile.provider.name,
            'credential': credential,
            'name': profile.name,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || revision != _accountRevision) {
      return false;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final user = UserProfile.fromMap(
      Map<String, dynamic>.from(data['user'] as Map),
    );
    final token = data['token'] as String;
    final expiry = DateTime.parse(data['expiresAt'] as String);
    if (user.id != profile.id || !expiry.isAfter(DateTime.now())) return false;
    await AuthSessionStore.write({
      'userId': user.id,
      'token': token,
      'expiresAt': expiry.toIso8601String(),
    });
    if (revision != _accountRevision) return false;
    _sessionToken = token;
    _sessionExpiresAt = expiry;
    _currentUser = user;
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
        final googleSignIn = GoogleSignIn();
        if (await googleSignIn.isSignedIn()) {
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
