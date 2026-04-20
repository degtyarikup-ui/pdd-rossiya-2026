import 'package:flutter/foundation.dart';

/// Текст для UI без сырого исключения (в логах могут быть URL, внутренние коды).
String dataLoadErrorMessage(Object? error) {
  if (kDebugMode && error != null) {
    debugPrint('Data load error: $error');
  }
  return 'Не удалось загрузить данные. Проверьте подключение и попробуйте снова.';
}
