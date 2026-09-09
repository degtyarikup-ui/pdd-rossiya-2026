import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PremiumService Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AuthService.instance.signOut();
      final service = PremiumService.instance;
      await service.init();
    });

    test('Unauthenticated guest user has 5 daily feed cards and 10 AI messages', () async {
      final service = PremiumService.instance;
      expect(AuthService.instance.isAuthenticated, false);
      expect(service.dailyFreeLimit, 5);
      expect(service.isPremium, false);
      expect(service.dailyCardsCount, 0);
      expect(service.remainingFreeCards, 5);
      expect(service.canAccessFeed, true);
      expect(service.aiFreeLimit, 10);
      expect(service.aiMessagesCount, 0);
      expect(service.remainingAiMessages, 10);
      expect(service.canSendAiMessage, true);
    });

    test('Guest user feed limit reaches 0 after 5 cards', () async {
      final service = PremiumService.instance;

      for (int i = 0; i < 4; i++) {
        await service.recordCardCompleted();
      }
      expect(service.dailyCardsCount, 4);
      expect(service.remainingFreeCards, 1);
      expect(service.canAccessFeed, true);

      await service.recordCardCompleted();
      expect(service.dailyCardsCount, 5);
      expect(service.remainingFreeCards, 0);
      expect(service.canAccessFeed, false);
    });

    test('AI messages limit is 10 and independent from feed cards', () async {
      final service = PremiumService.instance;

      // Guest exhausts feed cards
      for (int i = 0; i < 5; i++) {
        await service.recordCardCompleted();
      }
      expect(service.remainingFreeCards, 0);
      expect(service.canAccessFeed, false);

      // AI messages are independent and still 10
      expect(service.remainingAiMessages, 10);
      expect(service.canSendAiMessage, true);

      // Send 10 AI messages
      for (int i = 0; i < 9; i++) {
        await service.recordAiMessageSent();
      }
      expect(service.aiMessagesCount, 9);
      expect(service.remainingAiMessages, 1);
      expect(service.canSendAiMessage, true);

      await service.recordAiMessageSent();
      expect(service.aiMessagesCount, 10);
      expect(service.remainingAiMessages, 0);
      expect(service.canSendAiMessage, false);
    });

    test('Authenticated user has 10 daily cards and fresh 10 AI messages', () async {
      final service = PremiumService.instance;

      // Guest used all 5 cards and 10 AI messages
      for (int i = 0; i < 5; i++) {
        await service.recordCardCompleted();
      }
      for (int i = 0; i < 10; i++) {
        await service.recordAiMessageSent();
      }
      expect(service.remainingFreeCards, 0);
      expect(service.remainingAiMessages, 0);

      // User logs in
      final testUser = UserProfile(
        id: 'test_user_123',
        name: 'Test User',
        email: 'test@example.com',
        provider: AuthProviderType.google,
        createdAt: DateTime.now(),
      );

      await service.onAuthChanged(testUser);

      // Authenticated user should have fresh 10 feed cards and 10 AI messages
      expect(service.dailyFreeLimit, 10);
      expect(service.dailyCardsCount, 0);
      expect(service.remainingFreeCards, 10);
      expect(service.canAccessFeed, true);

      expect(service.aiFreeLimit, 10);
      expect(service.aiMessagesCount, 0);
      expect(service.remainingAiMessages, 10);
      expect(service.canSendAiMessage, true);

      // User answers 3 cards and sends 2 AI messages
      await service.recordCardCompleted();
      await service.recordCardCompleted();
      await service.recordCardCompleted();
      await service.recordAiMessageSent();
      await service.recordAiMessageSent();
      expect(service.dailyCardsCount, 3);
      expect(service.remainingFreeCards, 7);
      expect(service.aiMessagesCount, 2);
      expect(service.remainingAiMessages, 8);

      // User logs out -> returns to guest state (5 cards used, 10 AI used)
      await service.onAuthChanged(null);
      expect(service.dailyFreeLimit, 5);
      expect(service.dailyCardsCount, 5);
      expect(service.remainingFreeCards, 0);
      expect(service.aiMessagesCount, 10);
      expect(service.remainingAiMessages, 0);

      // User logs back in -> restores user state (3 cards used, 2 AI used)
      await service.onAuthChanged(testUser);
      expect(service.dailyFreeLimit, 10);
      expect(service.dailyCardsCount, 3);
      expect(service.remainingFreeCards, 7);
      expect(service.aiMessagesCount, 2);
      expect(service.remainingAiMessages, 8);
    });

    test('Purchasing weekly premium unlocks unlimited access', () async {
      final service = PremiumService.instance;
      final success = await service.purchase(PremiumTier.weekly);

      expect(success, true);
      expect(service.isPremium, true);
      expect(service.canAccessFeed, true);
      expect(service.canSendAiMessage, true);
      expect(service.expiresAt, isNotNull);
      expect(
        service.expiresAt!.isAfter(DateTime.now().add(const Duration(days: 6))),
        true,
      );
    });

    test('Purchasing 3-month premium unlocks 90 days access', () async {
      final service = PremiumService.instance;
      final success = await service.purchase(PremiumTier.threeMonths);

      expect(success, true);
      expect(service.isPremium, true);
      expect(service.canAccessFeed, true);
      expect(service.canSendAiMessage, true);
      expect(service.expiresAt, isNotNull);
      expect(
        service.expiresAt!.isAfter(DateTime.now().add(const Duration(days: 89))),
        true,
      );
    });
  });
}
