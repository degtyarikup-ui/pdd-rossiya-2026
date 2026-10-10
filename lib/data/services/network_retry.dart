import 'dart:async';

import 'package:http/http.dart' as http;

/// Несколько коротких попыток вместо одной долгой. Помогает, когда связь
/// пропала на секунду, телефон экономит заряд или маршрут до сервера
/// временно плохой: вторая попытка обычно проходит быстрее, чем человек
/// успевает увидеть ошибку. Повторяются только таймаут и сетевая ошибка —
/// ответ сервера (любой статус) возвращается как есть.
///
/// Только для безопасных повторов: запрос не должен ничего менять на
/// сервере дважды (например, выдача сессии входа).
Future<http.Response> sendWithRetry(
  Future<http.Response> Function() send, {
  List<Duration> attempts = const [
    Duration(seconds: 8),
    Duration(seconds: 8),
    Duration(seconds: 10),
  ],
  Duration pause = const Duration(seconds: 1),
  bool Function()? stillWanted,
}) async {
  Object? lastError;
  for (var i = 0; i < attempts.length; i++) {
    if (i > 0) {
      if (stillWanted != null && !stillWanted()) break;
      await Future<void>.delayed(pause);
    }
    try {
      return await send().timeout(attempts[i]);
    } on TimeoutException catch (error) {
      lastError = error;
    } on http.ClientException catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? TimeoutException('request not sent');
}
