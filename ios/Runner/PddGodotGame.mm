#import "PddGodotGame.h"

#import <UIKit/UIKit.h>
#import <mach/mach.h>

// The game «Живой город» on Godot 4.7.2 (game_godot/). The engine comes from
// ios/Godot (scripts/godot_ios_assets.sh). PDD_GODOT_ENGINE is defined only for device
// builds (engine.xcconfig): the template's simulator slice has no arm64 objects, so
// simulator builds and builds without the engine keep the WebView game.
//
// The engine runs once per app process (apple_embedded_main cannot run twice), so
// the game screen is a window shown and hidden for each run:
// - start: the app writes request.json (the run's arguments) into the exchange
//   folder, boots the engine on the first run and shows the game window;
// - the game reads request.json when its scene starts (embedded_io.gd) and writes
//   summary.json on every finished run and on exit (host.gd);
// - the app polls summary.json; the exit event hides the window and answers Dart.

static PddGodotGame *gInstance = nil;

#if defined(PDD_GODOT_ENGINE)

static NSString *const kExchangeFolderName = @"pdd_game";
static NSString *const kPerformanceMemoryFileName = @"performance-memory.json";

// libgodot ships without headers. The declarations here follow Godot 4.7.2:
// platform/ios/main_ios.mm, drivers/apple_embedded/*.h, app_delegate_service.mm.

// Main::setup and the platform modules; 0 on success.
int apple_embedded_main(int argc, char **argv);

// Native plugin hooks the engine calls (the export template's dummy.cpp): the game has none.
void godot_apple_embedded_plugins_initialize() {}
void godot_apple_embedded_plugins_deinitialize() {}

@interface GDTView : UIView
- (void)startRendering;
- (void)stopRendering;
@end

@interface GDTViewController : UIViewController
@property(nonatomic, readonly, strong) GDTView *godotView;
@end

@interface GDTAppDelegateService : NSObject
@property(strong, class, nonatomic) GDTViewController *viewController;
- (void)sceneWillResignActive:(UIScene *)scene;
- (void)sceneDidBecomeActive:(UIScene *)scene;
- (void)sceneDidEnterBackground:(UIScene *)scene;
- (void)sceneWillEnterForeground:(UIScene *)scene;
@end

static BOOL gEngineStarted = NO;
static BOOL gEngineFailed = NO;
// Kept for the whole process: the renderer sets itself up on its first view.
static GDTViewController *gController = nil;
static GDTAppDelegateService *gEngineService = nil;
static UIWindow *gGameWindow = nil;
static UIWindow *gAppWindow = nil;
static NSTimer *gPollTimer = nil;
static NSTimer *gMemoryTimer = nil;
static FlutterResult gPending = nil;
static BOOL gGameClosing = NO;

/// Where the app and the game exchange requests and results: Library/Caches/pdd_game.
static NSString *ExchangeFolder(void) {
  NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
  return [caches stringByAppendingPathComponent:kExchangeFolderName];
}

static BOOL IsGameVisible(void) {
  return gGameWindow != nil && !gGameWindow.hidden && !gGameClosing;
}

static void StopPerformanceMemorySampling(void) {
  [gMemoryTimer invalidate];
  gMemoryTimer = nil;
}

/// iOS's physical footprint covers this whole process (Flutter and Godot together).
/// It is a different metric from Android PSS; release Godot has no static-memory counter.
static void SamplePerformanceMemory(void) {
  if (!IsGameVisible() ||
      gGameWindow.windowScene.activationState != UISceneActivationStateForegroundActive) {
    return;
  }
  task_vm_info_data_t memory = {};
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  kern_return_t status = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&memory, &count);
  id footprint = NSNull.null;
  if (status == KERN_SUCCESS && count >= TASK_VM_INFO_REV1_COUNT) {
    footprint = @((double)memory.phys_footprint / 1048576.0);
  }
  NSProcessInfo *process = NSProcessInfo.processInfo;
  NSData *sample = [NSJSONSerialization dataWithJSONObject:@{
    @"footprint_mb" : footprint,
    // Apple's current thermal pressure (nominal/fair/serious/critical = 0/1/2/3),
    // sampled beside memory so a falling FPS is not mistaken for an unmeasured leak.
    @"thermal_state" : @((NSInteger)process.thermalState),
    @"low_power" : @(process.lowPowerModeEnabled),
    @"sample_time" : @(NSDate.date.timeIntervalSince1970),
  } options:0 error:nil];
  [sample writeToFile:[ExchangeFolder() stringByAppendingPathComponent:kPerformanceMemoryFileName]
             options:NSDataWritingAtomic
               error:nil];
}

static void StartPerformanceMemorySampling(NSArray *arguments) {
  StopPerformanceMemorySampling();
  if (![arguments containsObject:@"--perf"]) {
    return;
  }
  SamplePerformanceMemory();
  gMemoryTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                repeats:YES
                                                  block:^(NSTimer *timer) {
                                                    SamplePerformanceMemory();
                                                  }];
  gMemoryTimer.tolerance = 0.5;
}

/// The pack is the bundle's <executable>.pck: the engine looks for it by that name.
static BOOL GamePackInBundle(void) {
  NSString *executable = [[NSBundle mainBundle].executablePath lastPathComponent];
  return [[NSBundle mainBundle] pathForResource:executable ofType:@"pck"] != nil;
}

static BOOL IsEngineAvailable(void) {
  return !gEngineFailed && GamePackInBundle();
}

static UIWindowScene *ActiveWindowScene(void) {
  UIWindowScene *fallback = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    if (windowScene.activationState == UISceneActivationStateForegroundActive) {
      return windowScene;
    }
    if (!fallback) {
      fallback = windowScene;
    }
  }
  return fallback;
}

/// The engine's display server reads its controller when the engine starts, so the
/// controller is created and registered before the engine boots.
static GDTViewController *GameController(void) {
  if (!gController) {
    gController = [[GDTViewController alloc] init];
    GDTAppDelegateService.viewController = gController;
  }
  return gController;
}

static GDTAppDelegateService *EngineService(void) {
  if (!gEngineService) {
    gEngineService = [[GDTAppDelegateService alloc] init];
  }
  return gEngineService;
}

/// Once per process. The engine changes into the folder of argv[0], so argv[0] is the
/// executable's full path. The argument strings are never freed: the engine keeps them.
static BOOL BootEngine(NSString *exchange) {
  if (gEngineStarted) {
    return YES;
  }
  if (gEngineFailed) {
    return NO;
  }
  (void)GameController();
  NSArray<NSString *> *args = @[
    [NSBundle mainBundle].executablePath,
    @"--",
    [@"--pdd-io=" stringByAppendingString:exchange],
  ];
  int argc = (int)args.count;
  char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
  for (int i = 0; i < argc; i++) {
    argv[i] = strdup(args[i].UTF8String);
  }
  if (apple_embedded_main(argc, argv) != 0) {
    gEngineFailed = YES;
    return NO;
  }
  gEngineStarted = YES;
  return YES;
}

static BOOL ShowGame(void) {
  UIWindowScene *scene = ActiveWindowScene();
  if (!scene) {
    return NO;
  }
  // A window of its own: the engine's UIKit controller would otherwise write its
  // preferences into the Flutter root controller's class.
  gAppWindow = scene.keyWindow;
  if (!gAppWindow) {
    gAppWindow = scene.windows.firstObject;
  }
  gGameWindow = [[UIWindow alloc] initWithWindowScene:scene];
  gGameWindow.windowLevel = UIWindowLevelNormal + 1;
  gGameWindow.rootViewController = GameController();
  [gGameWindow makeKeyAndVisible];
  if (scene.activationState == UISceneActivationStateForegroundActive) {
    [EngineService() sceneDidBecomeActive:scene];
  }
  [gController.godotView startRendering];
  return YES;
}

static void HideGame(dispatch_block_t completion) {
  StopPerformanceMemorySampling();
  gGameClosing = YES;
  UIWindow *closingWindow = gGameWindow;
  // Stop at the opaque frame presented by Host.exit before UIKit changes focus/layout.
  // Leaving the live renderer visible while detaching its controller caused a last
  // resize/repaint of the game immediately before returning to Flutter.
  [gController.godotView stopRendering];
  [EngineService() sceneWillResignActive:closingWindow.windowScene];
  [gAppWindow makeKeyAndVisible];
  [UIView animateWithDuration:0.12
                        delay:0
                      options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                   animations:^{ closingWindow.alpha = 0; }
                   completion:^(BOOL finished) {
                     closingWindow.hidden = YES;
                     closingWindow.rootViewController = nil;
                     gGameWindow = nil;
                     gAppWindow = nil;
                     gGameClosing = NO;
                     if (completion) completion();
                   }];
}

#endif

@implementation PddGodotGame

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  gInstance = [[PddGodotGame alloc] init];
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"pdd/godot_game"
                                                              binaryMessenger:registrar.messenger];
  [channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    [gInstance handleCall:call result:result];
  }];
  [registrar addSceneDelegate:gInstance];
}

- (void)handleCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"available"]) {
#if defined(PDD_GODOT_ENGINE)
    result(@(IsEngineAvailable()));
#else
    result(@NO);
#endif
  } else if ([call.method isEqualToString:@"start"]) {
    [self startWithArguments:call.arguments result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)startWithArguments:(id)arguments result:(FlutterResult)result {
#if defined(PDD_GODOT_ENGINE)
  if (!IsEngineAvailable()) {
    result(nil);
    return;
  }
  NSArray *gameArgs = nil;
  if ([arguments isKindOfClass:[NSDictionary class]]) {
    gameArgs = ((NSDictionary *)arguments)[@"args"];
  }
  NSString *exchange = ExchangeFolder();
  if (![self prepareExchange:exchange arguments:gameArgs]) {
    result(nil);
    return;
  }
  // A new start replaces a run that is still waiting, as on Android.
  if (gPending) {
    FlutterResult previous = gPending;
    gPending = nil;
    previous(nil);
  }
  if (!BootEngine(exchange) || !ShowGame()) {
    result(nil);
    return;
  }
  StartPerformanceMemorySampling(gameArgs);
  gPending = result;
  gPollTimer = [NSTimer scheduledTimerWithTimeInterval:0.04
                                               repeats:YES
                                                 block:^(NSTimer *timer) {
                                                   [self pollSummary];
                                                 }];
#else
  result(nil);
#endif
}

#if defined(PDD_GODOT_ENGINE)

- (BOOL)prepareExchange:(NSString *)folder arguments:(NSArray *)args {
  StopPerformanceMemorySampling();
  NSFileManager *files = NSFileManager.defaultManager;
  if (![files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil]) {
    return NO;
  }
  // No run is going on in the engine now, so a leftover summary belongs to the last run.
  [files removeItemAtPath:[folder stringByAppendingPathComponent:@"summary.json"] error:nil];
  [files removeItemAtPath:[folder stringByAppendingPathComponent:kPerformanceMemoryFileName] error:nil];
  NSMutableArray *gameArgs = [NSMutableArray arrayWithArray:args ? args : @[]];
  for (NSString *category in @[@"ab", @"cd"]) {
    NSString *pictures = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:
        [@"Frameworks/App.framework/flutter_assets/assets/countries/ru/images/questions_"
            stringByAppendingString:category]];
    [gameArgs addObject:[@"--question-images-dir=" stringByAppendingString:pictures]];
  }
  NSString *questionAudio = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:
      @"Frameworks/App.framework/flutter_assets/assets/audio/game_questions"];
  [gameArgs addObject:[@"--question-audio-dir=" stringByAppendingString:questionAudio]];
  NSData *request = [NSJSONSerialization dataWithJSONObject:@{ @"args" : gameArgs } options:0 error:nil];
  return request != nil &&
         [request writeToFile:[folder stringByAppendingPathComponent:@"request.json"]
                      options:NSDataWritingAtomic
                        error:nil];
}

/// Runs every 40 ms while a run is shown. «run_finished» keeps the game open; the exit
/// event carries the final summary and closes the game.
- (void)pollSummary {
  NSString *path = [ExchangeFolder() stringByAppendingPathComponent:@"summary.json"];
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (!data) {
    return;
  }
  id message = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![message isKindOfClass:[NSDictionary class]]) {
    return;
  }
  NSDictionary *dict = (NSDictionary *)message;
  if (![dict[@"event"] isEqual:@"exit"]) {
    return;
  }
  NSString *json = nil;
  id summary = dict[@"summary"];
  if ([summary isKindOfClass:[NSDictionary class]]) {
    NSData *summaryData = [NSJSONSerialization dataWithJSONObject:summary options:0 error:nil];
    if (summaryData) {
      json = [[NSString alloc] initWithData:summaryData encoding:NSUTF8StringEncoding];
    }
  }
  [gPollTimer invalidate];
  gPollTimer = nil;
  FlutterResult result = gPending;
  gPending = nil;
  HideGame(^{ if (result) result(json); });
}

// The engine's lifecycle hooks, passed on as the template's app delegate does.
- (void)sceneWillResignActive:(UIScene *)scene {
  if (gEngineStarted && IsGameVisible()) {
    [EngineService() sceneWillResignActive:scene];
  }
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
  // Godot's focus-in starts its renderer and audio, including after backgrounding.
  // A hidden game must stay stopped while the player uses the Flutter screens.
  if (gEngineStarted && IsGameVisible()) {
    [EngineService() sceneDidBecomeActive:scene];
  }
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
  if (gEngineStarted && IsGameVisible()) {
    [EngineService() sceneDidEnterBackground:scene];
  }
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
  if (gEngineStarted && IsGameVisible()) {
    [EngineService() sceneWillEnterForeground:scene];
  }
}

#endif

@end
