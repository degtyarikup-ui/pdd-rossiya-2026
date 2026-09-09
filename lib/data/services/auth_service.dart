import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  UserProfile? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  Future<void> init() async {
    if (_isInitialized) return;
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
            name: cachedName ?? (cachedEmail.isNotEmpty ? cachedEmail.split('@').first : user.name),
            email: cachedEmail,
            avatarUrl: user.avatarUrl,
            provider: user.provider,
            createdAt: user.createdAt,
          );
          await prefs.setString(_prefKeyUser, user.toJson());
        }
        _currentUser = user;
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

  Future<bool> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        clientId: kIsWeb || defaultTargetPlatform == TargetPlatform.iOS
            ? googleClientId
            : null,
      );
      final account = await googleSignIn.signIn();
      if (account != null) {
        _currentUser = UserProfile(
          id: 'google_${account.id}',
          name: account.displayName?.isNotEmpty == true
              ? account.displayName!
              : account.email.split('@').first,
          email: account.email,
          avatarUrl: account.photoUrl,
          provider: AuthProviderType.google,
          createdAt: DateTime.now(),
        );
        await _saveUser();
        notifyListeners();
        await PremiumService.instance.onAuthChanged(_currentUser);
        unawaited(ProgressSyncService.instance.syncWithServer());
        return true;
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
            redirectUri: Uri.parse('https://pdd-russia.app/auth/apple/callback'),
          ),
        );
      }

      final userIdentifier = credential.userIdentifier ?? '';
      final prefs = await SharedPreferences.getInstance();

      // 1. Имя пользователя (Apple возвращает fullName только при первом входе)
      String? rawName = [credential.givenName, credential.familyName]
          .where((s) => s != null && s.trim().isNotEmpty)
          .join(' ')
          .trim();
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
        if (email != null && email.isNotEmpty && !email.contains('privaterelay')) {
          final prefix = email.split('@').first;
          displayName = prefix.isNotEmpty
              ? prefix[0].toUpperCase() + prefix.substring(1)
              : 'Apple ID';
        } else {
          displayName = 'Apple ID';
        }
      }

      final finalEmail = email ?? '';

      _currentUser = UserProfile(
        id: 'apple_${userIdentifier.isNotEmpty ? userIdentifier : DateTime.now().millisecondsSinceEpoch}',
        name: displayName,
        email: finalEmail,
        avatarUrl: null,
        provider: AuthProviderType.apple,
        createdAt: DateTime.now(),
      );

      await _saveUser();
      notifyListeners();
      await PremiumService.instance.onAuthChanged(_currentUser);
      unawaited(ProgressSyncService.instance.syncWithServer());
      return true;
    } catch (e) {
      debugPrint('AuthService: apple sign in error: $e');
      return false;
    }
  }

  static const String yandexClientId = '94aa539db4634e44bf0b209d9a2205d2';

  Future<bool> signInWithYandex(BuildContext context) async {
    try {
      final profile = await YandexAuthSheet.show(context);
      if (profile != null) {
        _currentUser = profile;
        await _saveUser();
        notifyListeners();
        await PremiumService.instance.onAuthChanged(_currentUser);
        unawaited(ProgressSyncService.instance.syncWithServer());
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('AuthService: yandex sign in error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
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

  Future<void> deleteAccount() async {
    try {
      await signOut();
    } catch (e) {
      debugPrint('AuthService: delete account error: $e');
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
