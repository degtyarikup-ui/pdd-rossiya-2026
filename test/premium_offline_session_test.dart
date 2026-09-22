import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'offline restart preserves premium only for the verified account owner',
    () async {
      final expiry = DateTime.now().add(const Duration(days: 2));
      final user = UserProfile(
        id: 'google_123',
        name: 'Test',
        email: '',
        provider: AuthProviderType.google,
        createdAt: DateTime(2026),
      );
      SharedPreferences.setMockInitialValues({
        'auth_user_profile': user.toJson(),
        'premium_owner_id': user.id,
        'premium_is_active': true,
        'premium_expires_at': expiry.millisecondsSinceEpoch,
      });
      FlutterSecureStorage.setMockInitialValues({
        'pdd_server_session': jsonEncode({
          'userId': user.id,
          'token': 'test-session',
          'expiresAt': expiry.toIso8601String(),
        }),
      });
      await http.runWithClient(() async {
        await PremiumService.instance.init();
        await AuthService.instance.init();
        expect(PremiumService.instance.isPremium, isTrue);
        await PremiumService.instance.onAuthChanged(
          UserProfile(
            id: 'google_other',
            name: 'Other',
            email: '',
            provider: AuthProviderType.google,
            createdAt: DateTime(2026),
          ),
        );
        expect(PremiumService.instance.isPremium, isFalse);
      }, () => MockClient((_) async => throw http.ClientException('offline')));
    },
  );
}
