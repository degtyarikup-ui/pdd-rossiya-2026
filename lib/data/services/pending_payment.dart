import 'package:shared_preferences/shared_preferences.dart';

/// Незавершённая оплата СБП в Android: человек ушёл в браузер и вернулся в
/// приложение. Номер заказа хранится, пока сервер не подтвердит оплату или
/// не отменит её; через [_maxAge] запись сама считается устаревшей.
class PendingPayment {
  PendingPayment._();

  static const String _orderKey = 'pending_sbp_order';
  static const String _atKey = 'pending_sbp_at';
  static const Duration _maxAge = Duration(hours: 2);

  static Future<void> remember(String order, {DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_orderKey, order);
    await prefs.setInt(_atKey, (now ?? DateTime.now()).millisecondsSinceEpoch);
  }

  /// Номер заказа, если он ещё актуален; иначе запись удаляется.
  static Future<String?> current({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final order = prefs.getString(_orderKey);
    if (order == null) return null;
    final at = prefs.getInt(_atKey) ?? 0;
    final age = (now ?? DateTime.now()).difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    if (age > _maxAge) {
      await clear();
      return null;
    }
    return order;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_orderKey);
    await prefs.remove(_atKey);
  }
}
