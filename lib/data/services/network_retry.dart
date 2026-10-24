import 'dart:async';

import 'package:http/http.dart' as http;
import 'network_errors_stub.dart' if (dart.library.io) 'network_errors_io.dart';

bool isRetryableNetworkError(Object error) =>
    error is TimeoutException ||
    error is http.ClientException ||
    isPlatformNetworkError(error);

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
/// ответы сервера возвращаются как есть, если безопасный вызывающий код явно
/// не указал временные статусы в [retryStatusCodes].
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
  Set<int> retryStatusCodes = const {},
}) async {
  assert(hosts.isNotEmpty);
  final start = NotifierRoute.preferredIndex(hosts);
  Object? lastError;
  var nextPause = pause;
  for (var i = 0; i < attempts.length; i++) {
    if (i > 0) {
      if (stillWanted != null && !stillWanted()) break;
      await Future<void>.delayed(nextPause);
      if (stillWanted != null && !stillWanted()) break;
    }
    final host = hosts[(start + i) % hosts.length];
    stats?.attempts = i + 1;
    try {
      final response = await send(host).timeout(attempts[i]);
      if (retryStatusCodes.contains(response.statusCode)) {
        // Keep login bounded. A longer or date-based Retry-After is returned to
        // the caller instead of retrying early or holding its UI indefinitely.
        final retryAfter = response.headers['retry-after'];
        final seconds = retryAfter == null ? 0 : int.tryParse(retryAfter);
        if (i + 1 < attempts.length &&
            seconds != null &&
            seconds >= 0 &&
            seconds <= 2) {
          final requested = Duration(seconds: seconds);
          nextPause = requested > pause ? requested : pause;
          continue;
        }
        return response;
      }
      stats?.host = host;
      NotifierRoute.remember(host);
      return response;
    } on TimeoutException catch (error) {
      lastError = error;
      nextPause = pause;
    } on http.ClientException catch (error) {
      lastError = error;
      nextPause = pause;
    } catch (error) {
      if (!isPlatformNetworkError(error)) rethrow;
      lastError = error;
      nextPause = pause;
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
