import 'package:flutter/foundation.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Текст для UI без сырого исключения (в логах могут быть URL, внутренние коды).
String dataLoadErrorMessage(Object? error) {
  if (kDebugMode && error != null) {
    debugPrint('Data load error: $error');
  }
  // Текст — из ARB: в сербской сборке русская фраза выглядела как чужая
  // ошибка приложения, а не как сообщение для пользователя.
  return appL10n.dataLoadError;
}
