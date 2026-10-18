import 'package:shared_preferences/shared_preferences.dart';

/// Незавершённая оплата СБП в Android: человек ушёл в браузер и вернулся в
/// приложение. Номер заказа хранится, пока сервер не подтвердит оплату или
/// не отменит её. Обычная ссылка устаревает через [_maxAge]; неопределённый
/// результат хранится до подтверждённого завершения, включая перезапуски.
class PendingPayment {
  PendingPayment._();

  static const String _orderKey = 'pending_sbp_order';
  static const String _atKey = 'pending_sbp_at';
  static const String _ownerKey = 'pending_sbp_owner';
  static const String _keepKey = 'pending_sbp_keep_until_resolved';
  static const Duration _maxAge = Duration(hours: 2);

  static Future<void> remember(
    String order, {
    DateTime? now,
    String? ownerId,
    bool keepUntilResolved = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_orderKey, order);
    await prefs.setInt(_atKey, (now ?? DateTime.now()).millisecondsSinceEpoch);
    if (ownerId != null) {
      await prefs.setString(_ownerKey, ownerId);
    } else {
      await prefs.remove(_ownerKey);
    }
    await prefs.setBool(_keepKey, keepUntilResolved);
  }

  /// Номер заказа, если он ещё актуален; иначе запись удаляется.
  static Future<String?> current({DateTime? now, String? ownerId}) async {
    final prefs = await SharedPreferences.getInstance();
    final order = prefs.getString(_orderKey);
    if (order == null) return null;
    final owner = prefs.getString(_ownerKey);
    if (owner != null && owner != ownerId) return null;
    final at = prefs.getInt(_atKey) ?? 0;
    final age = (now ?? DateTime.now()).difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    if (age > _maxAge && prefs.getBool(_keepKey) != true) {
      await clear(ownerId: ownerId);
      return null;
    }
    return order;
  }

  static Future<void> clear({String? ownerId}) async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString(_ownerKey);
    if (owner != null && owner != ownerId) return;
    await prefs.remove(_orderKey);
    await prefs.remove(_atKey);
    await prefs.remove(_ownerKey);
    await prefs.remove(_keepKey);
  }
}
