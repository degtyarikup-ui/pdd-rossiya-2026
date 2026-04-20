import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic>? _embeddedApiError(String raw) {
  final t = raw.trim();
  if (!t.startsWith('{')) return null;
  try {
    final v = jsonDecode(t);
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
  } catch (_) {}
  return null;
}

String? _embeddedString(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is String) return v;
  if (v != null) return v.toString();
  return null;
}

bool _isConfirmationEmailFailure(String lower) {
  return (lower.contains('confirmation') && lower.contains('email')) ||
      lower.contains('sending confirmation') ||
      lower.contains('confirmation email');
}

/// Короткие сообщения для пользователя вместо сырого [AuthException].
String authErrorMessageForUser(Object error) {
  if (error is AuthException) {
    final msg = error.message.trim();

    final embedded = _embeddedApiError(msg);
    if (embedded != null) {
      final innerRaw = _embeddedString(embedded, 'message') ?? '';
      final innerLower = innerRaw.toLowerCase();
      if (_isConfirmationEmailFailure(innerLower)) {
        return 'Не удалось отправить письмо с подтверждением. Попробуйте позже.';
      }
      final innerCode = _embeddedString(embedded, 'code');
      if (innerCode == 'unexpected_failure') {
        return 'Сервис временно недоступен. Попробуйте позже.';
      }
      return 'Не удалось выполнить операцию. Попробуйте позже.';
    }

    switch (error.code) {
      case 'invalid_credentials':
      case 'user_not_found':
        return 'Неверный email или пароль';
      case 'email_not_confirmed':
        return 'Подтвердите email по ссылке из письма';
      case 'user_already_registered':
      case 'email_exists':
        return 'Этот email уже зарегистрирован. Войдите или сбросьте пароль.';
      case 'weak_password':
        return 'Пароль слишком слабый. Используйте более сложный пароль.';
      case 'signup_disabled':
        return 'Регистрация новых аккаунтов временно отключена.';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
      case 'over_sms_send_rate_limit':
        return 'Слишком много попыток. Попробуйте позже.';
      case 'unexpected_failure':
        return 'Сервис временно недоступен. Попробуйте позже.';
      default:
        break;
    }

    if (msg.isNotEmpty) {
      final lower = msg.toLowerCase();
      if (lower.contains('invalid login credentials') ||
          lower.contains('invalid credentials')) {
        return 'Неверный email или пароль';
      }
      if (_isConfirmationEmailFailure(lower)) {
        return 'Не удалось отправить письмо с подтверждением. Попробуйте позже.';
      }
      if (!_looksLikeRawException(msg) && !msg.startsWith('{')) {
        return msg;
      }
    }
  }

  return 'Не удалось выполнить операцию. Попробуйте ещё раз.';
}

bool _looksLikeRawException(String msg) {
  return msg.contains('AuthApiException') ||
      msg.contains('AuthException(') ||
      msg.contains('AuthRetryableFetchException') ||
      msg.contains('AuthUnknownException');
}
