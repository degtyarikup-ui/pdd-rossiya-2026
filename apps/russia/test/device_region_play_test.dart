import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/device_region.dart';

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DeviceRegion.resetPlayCountry();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DeviceRegion.resetPlayCountry();
  });

  test('страна аккаунта Play: заглавными и спрашивается один раз', () async {
    var calls = 0;
    DeviceRegion.readPlayCountry = () async {
      calls++;
      return 'ru';
    };
    expect(await DeviceRegion.playCountry(), 'RU');
    expect(await DeviceRegion.playCountry(), 'RU');
    expect(calls, 1);
  });

  test('ошибка магазина — null, следующий вызов спрашивает снова', () async {
    var calls = 0;
    DeviceRegion.readPlayCountry = () async {
      calls++;
      if (calls == 1) throw StateError('billing unavailable');
      return 'DE';
    };
    expect(await DeviceRegion.playCountry(), isNull);
    expect(await DeviceRegion.playCountry(), 'DE');
  });

  test('пустой ответ — null', () async {
    DeviceRegion.readPlayCountry = () async => '';
    expect(await DeviceRegion.playCountry(), isNull);
  });

  test('магазин молчит — null по таймауту, пейвол не зависает', () async {
    DeviceRegion.playTimeout = const Duration(milliseconds: 20);
    addTearDown(() => DeviceRegion.playTimeout = const Duration(seconds: 3));
    DeviceRegion.readPlayCountry = () => Completer<String>().future;
    expect(await DeviceRegion.playCountry(), isNull);
  });
}
