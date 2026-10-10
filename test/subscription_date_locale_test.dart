import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

// Дата окончания подписки показывается на языке приложения. Без
// initializeDateFormatting intl падает с LocaleDataException.
void main() {
  final expiry = DateTime(2026, 11, 3, 14, 5);

  test('formats the expiry date in the app language after init', () async {
    await initializeDateFormatting('kk');
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');

    expect(DateFormat('d MMMM yyyy, HH:mm', 'en').format(expiry),
        '3 November 2026, 14:05');
    expect(DateFormat('d MMMM yyyy, HH:mm', 'ru').format(expiry),
        '3 ноября 2026, 14:05');
    expect(DateFormat('d MMMM yyyy, HH:mm', 'kk').format(expiry),
        contains('қараша'));
  });

  test('numeric fallback works without locale data', () {
    expect(DateFormat('dd.MM.yyyy HH:mm').format(expiry), '03.11.2026 14:05');
  });
}
