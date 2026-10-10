import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сообщения об ошибках входа и оплаты, которые видит пользователь: простые
/// слова, без технических терминов, одинаковый набор на всех трёх языках.
void main() {
  const keys = [
    'authErrorCancelled',
    'authErrorProvider',
    'authErrorNetwork',
    'authErrorTimeout',
    'authErrorAppKey',
    'authErrorCredential',
    'authErrorServer',
    'authErrorResponse',
    'authFailed',
    'purchaseVerificationPending',
    'webPayFailed',
    'webPayPending',
    'webPayCanceled',
    'paySuccessActivated',
    'payRestoreSuccess',
    'payRestoreNone',
    'payErrorPricesLoading',
    'payErrorStoreUnavailable',
    'payErrorStoreRefused',
    'payErrorGeneric',
    'payErrorUnexpected',
  ];
  Map<String, dynamic> load(String lang) =>
      jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
          as Map<String, dynamic>;
  final ru = load('ru');
  final en = load('en');
  final kk = load('kk');

  test('каждое сообщение есть на русском, английском и казахском', () {
    for (final key in keys) {
      for (final (lang, arb) in [('ru', ru), ('en', en), ('kk', kk)]) {
        expect(
          (arb[key] as String?)?.trim() ?? '',
          isNotEmpty,
          reason: '$key / $lang',
        );
      }
    }
  });

  test('в русских сообщениях нет технических слов', () {
    final technical = RegExp(
      r'сервер|токен|сесси|сборк|\bAPI\b|exception|исключени|код ошибки|таймаут|timeout',
      caseSensitive: false,
    );
    for (final key in keys) {
      expect(
        technical.hasMatch(ru[key] as String),
        isFalse,
        reason: '$key: ${ru[key]}',
      );
    }
  });

  test('английские сообщения без кириллицы, казахские без английских слов', () {
    final cyrillic = RegExp('[А-Яа-яЁё]');
    // Названия магазинов и сети — единственные допустимые латинские слова.
    final allowed = RegExp(r'Wi‑Fi|Google Play|App Store|\{store\}');
    final latin = RegExp('[A-Za-z]');
    for (final key in keys) {
      final english = en[key] as String;
      expect(cyrillic.hasMatch(english), isFalse, reason: 'en $key');
      final kazakh = (kk[key] as String).replaceAll(allowed, '');
      expect(latin.hasMatch(kazakh), isFalse, reason: 'kk $key: $kazakh');
    }
  });

  test('сообщения про магазин везде содержат его название', () {
    for (final key in ['payErrorStoreUnavailable', 'payErrorStoreRefused']) {
      for (final arb in [ru, en, kk]) {
        expect(arb[key] as String, contains('{store}'), reason: key);
      }
    }
  });

  test('общий сбой покупки ведёт к «Восстановить» и не обещает, что деньги не списаны', () {
    // Общий сбой покупки и сбой подтверждения: можно потерять деньги и доступ,
    // поэтому текст ведёт к «Восстановить», а не обещает, что денег не списали.
    expect(ru['payErrorGeneric'] as String, contains('Восстановить'));
    expect(ru['purchaseVerificationPending'] as String, contains('повторно'));
    expect(
      ru['purchaseVerificationPending'] as String,
      contains('Восстановить'),
    );
  });
}
