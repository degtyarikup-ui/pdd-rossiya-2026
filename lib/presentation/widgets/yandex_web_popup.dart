import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Открывает окно входа Яндекса и ждёт, пока `yandex-auth.html` (тот же
/// сайт) пришлёт фрагмент адреса возврата: `access_token=…&state=…` или
/// `error=…`. null — окно закрыли, заблокировали или истекло 5 минут.
Future<String?> openYandexPopup(String url) async {
  final popup = web.window.open(url, 'yandex_oauth', 'width=520,height=720');
  if (popup == null) return null;
  final done = Completer<String?>();
  final origin = web.window.location.origin;
  final listener = (web.MessageEvent event) {
    if (event.origin != origin) return;
    final data = event.data.dartify();
    if (data is Map && data['type'] == 'yandex-oauth' && data['fragment'] is String) {
      if (!done.isCompleted) done.complete(data['fragment'] as String);
    }
  }.toJS;
  web.window.addEventListener('message', listener);
  final watch = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (popup.closed && !done.isCompleted) {
      // Сообщение могло прийти в тот же миг — даём ему долю секунды.
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!done.isCompleted) done.complete(null);
      });
    }
  });
  try {
    return await done.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => null,
    );
  } finally {
    watch.cancel();
    web.window.removeEventListener('message', listener);
    if (!popup.closed) popup.close();
  }
}
