import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/services/premium_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'exhausted feed becomes available next day before any new completion or login',
    () async {
      var now = DateTime(2026, 10, 18, 23, 59);
      PremiumService.currentTime = () => now;
      addTearDown(() => PremiumService.currentTime = DateTime.now);
      SharedPreferences.setMockInitialValues({
        'premium_daily_date_guest': '2026-10-18',
        'premium_daily_cards_guest': 5,
      });
      final premium = PremiumService.instance;
      await premium.init();
      expect(premium.canAccessFeed, isFalse);
      now = DateTime(2026, 10, 19, 0, 1);
      expect(premium.canAccessFeed, isTrue);
      expect(premium.remainingFreeCards, 5);
      var changes = 0;
      premium.addListener(() {
        changes++;
      });
      await premium.refreshDailyLimits();
      expect(changes, 1);
      await premium.recordCardCompleted();
      expect(premium.remainingFreeCards, 4);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('premium_daily_date_guest'), '2026-10-19');
      expect(prefs.getInt('premium_daily_cards_guest'), 1);
    },
  );
}
