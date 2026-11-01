import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

/// Какой адрес воркера сейчас работает лучше. Запоминается на неделю: в сети,
/// где основной адрес заблокирован, каждый запуск иначе сначала ждал его
/// таймаута (8 с на вход, синхронизацию и отчёты) и только потом шёл на запасной.
class NotifierRoute {
  NotifierRoute._();

  static const _storageKey = 'notifier_route_v1';
  static const _keepFor = Duration(days: 7);
  static String? _preferred;

  /// Восстанавливает адрес, сработавший в прошлый запуск. Адрес, сработавший
  /// уже в этом запуске, важнее сохранённого.
  static Future<void> restore() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        _storageKey,
      );
      final data = raw == null ? null : jsonDecode(raw);
      if (_preferred != null || data is! Map) return;
      final host = data['host'], at = data['at'];
      if (host is String &&
          at is int &&
          DateTime.now().millisecondsSinceEpoch - at <
              _keepFor.inMilliseconds) {
        _preferred = host;
      }
    } catch (_) {
      // Без сохранённого адреса приложение просто начнёт с основного.
    }
  }

  static void remember(String host) {
    if (_preferred == host) return;
    _preferred = host;
    unawaited(_save(host));
  }

  static Future<void> _save(String host) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _storageKey,
        jsonEncode({'host': host, 'at': DateTime.now().millisecondsSinceEpoch}),
      );
    } catch (_) {}
  }

  static int preferredIndex(List<String> hosts) {
    final i = _preferred == null ? -1 : hosts.indexOf(_preferred!);
    return i < 0 ? 0 : i;
  }

  /// Только память текущего запуска; сохранённый адрес не трогает.
  static void reset() => _preferred = null;
}
