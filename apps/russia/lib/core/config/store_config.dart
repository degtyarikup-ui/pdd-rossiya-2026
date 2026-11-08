/// Где распространяется Android-сборка. Задаётся при сборке:
/// `--dart-define=STORE=rustore` для RuStore, по умолчанию — Google Play.
/// От этого зависит, как оплачивать Премиум на Android (см. payment_mode.dart).
enum AppStore { googlePlay, rustore }

class StoreConfig {
  StoreConfig._();

  static const String _store = String.fromEnvironment(
    'STORE',
    defaultValue: 'play',
  );

  static AppStore get current =>
      _store == 'rustore' ? AppStore.rustore : AppStore.googlePlay;
}
