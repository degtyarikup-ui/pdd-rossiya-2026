import 'package:flutter/material.dart';

/// Глобальный наблюдатель за переходами между маршрутами.
///
/// Регистрируется в `MaterialApp.navigatorObservers`. Экраны могут
/// подписаться на события (didPush/didPop/didPopNext) через `RouteAware`,
/// чтобы реагировать на возврат к ним поверх стека (например, показать
/// поздравление после возвращения с тренировки).
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
