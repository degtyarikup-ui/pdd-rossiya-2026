import 'dart:async';

import 'package:pdd_app/presentation/screens/game/godot_game.dart';

/// Общая настройка всех тестов: картинки наград для игры не пишутся на диск
/// (реальный ввод-вывод не завершается в замороженном времени testWidgets).
/// Выбор картинок проверяет `nativeAwardArt` в achievement_awards_test.dart.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GodotGame.prepareArt = (_) async => '';
  await testMain();
}
