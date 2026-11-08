#import <Flutter/Flutter.h>

/// Channel `pdd/godot_game` (Dart: lib/presentation/screens/game/godot_game.dart),
/// the iOS counterpart of GodotGameBridge.kt: `available` — the engine and the game
/// pack are in this build; `start(args)` shows the game over the app and answers with
/// the run's summary (JSON) or null when the player left without one.
@interface PddGodotGame : NSObject <FlutterSceneLifeCycleDelegate>

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar
    NS_SWIFT_NAME(register(with:));

@end
