import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/pending_payment.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('незавершённый заказ запоминается и возвращается', () async {
    final now = DateTime(2026, 10, 9, 12);
    await PendingPayment.remember('order-1', now: now);
    expect(await PendingPayment.current(now: now), 'order-1');
    expect(
      await PendingPayment.current(now: now.add(const Duration(hours: 1))),
      'order-1',
    );
  });

  test('заказ старше двух часов считается устаревшим и удаляется', () async {
    final now = DateTime(2026, 10, 9, 12);
    await PendingPayment.remember('order-1', now: now);
    expect(
      await PendingPayment.current(now: now.add(const Duration(hours: 3))),
      isNull,
    );
    expect(await PendingPayment.current(now: now), isNull);
  });

  test('после clear заказа нет', () async {
    final now = DateTime(2026, 10, 9, 12);
    await PendingPayment.remember('order-1', now: now);
    await PendingPayment.clear();
    expect(await PendingPayment.current(now: now), isNull);
  });

  test('без записи возвращается null', () async {
    expect(await PendingPayment.current(), isNull);
  });
}
