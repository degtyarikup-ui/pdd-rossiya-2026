import 'dart:async';

import 'package:http/http.dart' as http;

/// Что произошло во время [sendWithRetry]: сколько попыток сделано и на
/// каком адресе запрос удался. Нужно для отчётов о сбоях входа.
class RetryStats {
  int attempts = 0;
  String? host;

  /// Запрос удался не с первой попытки или не на основном адресе.
  bool get neededRecovery => host != null && (attempts > 1);
}

/// Несколько коротких попыток вместо одной долгой. Помогает, когда связь
/// пропала на секунду или маршрут до сервера временно плохой: вторая попытка
/// (на запасном адресе, если он есть) обычно проходит быстрее, чем человек
/// успевает увидеть ошибку. Повторяются только таймаут и сетевая ошибка —
/// ответ сервера (любой статус) возвращается как есть.
///
/// Адреса чередуются: основной, запасной, основной… Адрес, на котором
/// запрос удался, пробуется первым в следующий раз ([preferred]).
///
/// Только для безопасных повторов: запрос не должен ничего менять на
/// сервере дважды (например, выдача сессии входа).
Future<http.Response> sendWithRetry(
  Future<http.Response> Function(String host) send, {
  required List<String> hosts,
  List<Duration> attempts = const [
    Duration(seconds: 8),
    Duration(seconds: 8),
    Duration(seconds: 10),
  ],
  Duration pause = const Duration(seconds: 1),
  bool Function()? stillWanted,
  RetryStats? stats,
}) async {
  assert(hosts.isNotEmpty);
  final start = NotifierRoute.preferredIndex(hosts);
  Object? lastError;
  for (var i = 0; i < attempts.length; i++) {
    if (i > 0) {
      if (stillWanted != null && !stillWanted()) break;
      await Future<void>.delayed(pause);
    }
    final host = hosts[(start + i) % hosts.length];
    stats?.attempts = i + 1;
    try {
      final response = await send(host).timeout(attempts[i]);
      stats?.host = host;
      NotifierRoute.remember(host);
      return response;
    } on TimeoutException catch (error) {
      lastError = error;
    } on http.ClientException catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? TimeoutException('request not sent');
}

/// Какой адрес воркера сейчас работает лучше. Хранится в памяти: после
/// перезапуска приложение снова начинает с основного.
class NotifierRoute {
  NotifierRoute._();

  static String? _preferred;

  static void remember(String host) => _preferred = host;

  static int preferredIndex(List<String> hosts) {
    final i = _preferred == null ? -1 : hosts.indexOf(_preferred!);
    return i < 0 ? 0 : i;
  }

  static void reset() => _preferred = null;
}
