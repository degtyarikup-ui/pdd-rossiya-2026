import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/game_situation.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_controls_overlay.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_explanation_sheet.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_hud.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_lobby.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_over_dialog.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_question_card.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_reveal_overlay.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_debug_sheet.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_leaderboard_sheet.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/data/services/game_fuel_service.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';

class GameScreen extends ConsumerStatefulWidget {
  final VoidCallback? onExit;

  /// False while another bottom tab is shown: the run is kept (paused), so a
  /// stray tap on the tab bar never throws the session away.
  final bool visible;

  const GameScreen({super.key, this.onExit, this.visible = true});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  WebViewController? _webViewController;
  late GameController _game;
  bool _configured = false;
  bool _active = true;

  /// The start screen (garage) is shown instead of a run: on opening the tab
  /// and after «To menu» at the end of a run. The engine then renders the
  /// garage and the run is paused.
  bool _inLobby = true;
  final _hudKey = GlobalKey();
  final _bottomKey = GlobalKey();
  final _cardKey = GlobalKey();
  String? _lastInsets;
  bool _failed = false;
  bool _disposing = false;
  Timer? _readyTimer;
  bool _restarting = false;
  Future<void>? _initialization;
  Future<void>? _cleanup;
  String _vehicleId = 'hatch';
  String _vehiclePaint = 'red';
  bool _garageOpen = false;
  // Engine-rendered car previews for the garage, per model+paint.
  final _thumbnails = <String, Uint8List>{};
  // A freshly unlocked car being shown in the 3D garage.
  GameCar? _reveal;
  bool _revealShown = false;
  int? _bestScore;
  bool _newRecord = false;
  String? _weatherOverride;
  String? _seasonOverride;
  bool _locked = false;
  bool _outOfFuel = false;
  bool _fuelLoaded = false;
  bool _debugUnlimitedFuel = false;
  Timer? _fuelTimer;
  int _correctBurst = 0;
  // Weekly rating: the run's score is reported as it grows (premium runs
  // never end; a closed app must not lose points), not only at game over.
  int _liveScore = 0;
  int _reportedScore = 0;
  bool _runCounted = false;
  bool _reporting = false;
  Timer? _reportTimer;
  int _bestBeforeRun = 0;
  List<Question>? _abQuestions;
  Offset _burstOrigin = const Offset(0.5, 0.72);
  Timer? _burstTimer;
  // First session: clear weather in the engine and a "this is the gas" hint
  // until the pedal is pressed for the first time.
  bool _firstRun = false;
  bool _showGasHint = false;
  static const _seenKey = 'game_seen';
  static const _bestScoreKey = 'game_best_score';
  static const _debugUnlimitedFuelKey = 'game_debug_unlimited_fuel';

  Future<void> _stopWebView() {
    return _cleanup ??= _stopAndDetach(_webViewController, _initialization);
  }

  // Retain the native controller until its handler has been detached. Each
  // operation is attempted even when the document or a previous command failed.
  static Future<void> _stopAndDetach(
    WebViewController? controller,
    Future<void>? initialization,
  ) async {
    if (controller == null) return;
    await initialization;
    for (final command in [
      'window.game?.setGas?.(false);',
      'window.game?.setBrake?.(false);',
      'window.game?.setPaused?.(true);',
    ]) {
      try {
        await controller.runJavaScript(command);
      } catch (_) {
        /* Continue detaching. */
      }
    }
    try {
      await controller.removeJavaScriptChannel('FlutterChannel');
    } catch (_) {
      debugPrint('Game channel cleanup failed');
    }
  }

  void _bridgeFailed(String sessionId) {
    if (!mounted || _disposing || _failed || !_game.acceptsSession(sessionId)) {
      return;
    }
    setState(() => _failed = true);
    _readyTimer?.cancel();
    _game.setPaused(true);
    _send('setPaused', [true]);
  }

  void _send(String method, List<Object?> args) {
    if (!_configured || _restarting || _disposing) return;
    final sessionId = _game.sessionId;
    _webViewController
        ?.runJavaScript(
          'if (!window.game || typeof window.game.$method !== "function") { throw new Error("Game API unavailable"); } window.game.$method(${args.map(jsonEncode).join(',')});',
        )
        .catchError((Object error) {
          debugPrint('Game command failed: $method');
          _bridgeFailed(sessionId);
        });
  }

  void _configure() {
    if (_inLobby) _send('showLobby', [_vehicleId, _vehiclePaint]);
    _send('configure', [
      {
        'country': CountryConfig.current.code,
        'sessionId': _game.sessionId,
        'soundEnabled': SoundEffectsService.instance.isEnabled,
        'firstRun': _firstRun,
        'labels': {
          'player': appL10n.gameYou,
          'stop': appL10n.gameStop,
          'oncoming': appL10n.gameOncoming,
          'resolving': appL10n.gameResolving,
        },
      },
    ]);
    _send('setPaused', [_enginePaused]);
    _send('selectVehicle', [_vehicleId, _vehiclePaint]);
    _send('setAttract', [_locked || _outOfFuel]);
    if (_weatherOverride != null) _send('setWeather', [_weatherOverride]);
    if (_seasonOverride != null) _send('setSeason', [_seasonOverride]);
  }

  // Regeneration happens on a clock: re-read the tank when a unit is due.
  void _scheduleFuelTick() {
    _fuelTimer?.cancel();
    final at = GameFuelService.instance.nextRefillAt;
    if (at == null) return;
    _fuelTimer = Timer(
      at.difference(DateTime.now()) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        final fuel = GameFuelService.instance.refresh();
        final s = ref.read(gameControllerProvider);
        if (!s.fuelUnlimited && fuel > s.fuel) {
          if (s.phase != GamePhase.gameOver) {
            _game.configureFuel(fuel: fuel, unlimited: false);
          } else {
            setState(() {});
          }
        }
        _scheduleFuelTick();
      },
    );
  }

  Future<void> _openLeaderboard() async {
    if (_garageOpen) return;
    HapticFeedbackHelper.tap();
    _garageOpen = true; // reuse the pause bookkeeping of the garage
    _game.setPaused(true);
    _send('setPaused', [true]);
    try {
      await GameLeaderboardSheet.show(context);
    } finally {
      _garageOpen = false;
      if (mounted && !_disposing) {
        _game.setPaused(
          _inLobby ||
              !_active ||
              _failed ||
              _locked ||
              ref.read(gameControllerProvider).phase == GamePhase.gameOver,
        );
        _send('setPaused', [_enginePaused]);
      }
    }
  }

  Future<void> _setDebugUnlimitedFuel(bool enabled) async {
    if (!AuthService.debugSignInAvailable) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debugUnlimitedFuelKey, enabled);
    if (!mounted) return;
    setState(() => _debugUnlimitedFuel = enabled);
    _game.configureFuel(
      fuel: GameFuelService.instance.refresh(),
      unlimited: enabled || ref.read(isPremiumProvider),
    );
    _scheduleFuelTick();
  }

  // Dev APK only: long-press the fuel gauge or garage to open controls.
  Future<void> _openDebug() async {
    if (!AuthService.debugSignInAvailable || !_configured) return;
    HapticFeedbackHelper.confirm();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => GameDebugSheet(
        weatherOverride: _weatherOverride,
        seasonOverride: _seasonOverride,
        unlimitedFuel: _debugUnlimitedFuel,
        onWeatherChanged: (kind) {
          _weatherOverride = kind;
          _send('setWeather', [kind]);
        },
        onSeasonChanged: (kind) {
          _seasonOverride = kind;
          _send('setSeason', [kind]);
        },
        onUnlimitedFuelChanged: _setDebugUnlimitedFuel,
      ),
    );
  }

  /// Sends the score gained since the last report. Safe to call often.
  Future<void> _reportProgress() async {
    if (_reporting) return;
    final score = _liveScore;
    final delta = score - _reportedScore;
    if (delta == 0 && (_runCounted || score == 0)) return;
    _reporting = true;
    final ok = await GameLeaderboardService.instance.reportProgress(
      delta: delta,
      runScore: score,
      newRun: !_runCounted,
    );
    _reporting = false;
    if (ok) {
      _reportedScore = score;
      _runCounted = true;
    }
    // Premium runs never reach game over: keep the personal best anyway.
    if (score > (_bestScore ?? 0)) {
      _bestScore = score;
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setInt(_bestScoreKey, score))
          .catchError((_) => false);
    }
  }

  bool _appResumed = true;

  @override
  void didUpdateWidget(GameScreen old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) _applyActive();
  }

  void _applyActive() {
    if (!widget.visible) {
      unawaited(_reportProgress());
      _send('setGas', [false]);
      _send('setBrake', [false]);
      _send('setSteering', [0]);
    }
    _active = _appResumed && widget.visible;
    _game.setPaused(
      _inLobby || !_active || _failed || _garageOpen || _locked || _outOfFuel,
    );
    _send('setPaused', [_enginePaused]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_reportProgress());
    _appResumed = state == AppLifecycleState.resumed;
    _active = _appResumed && widget.visible;
    _game.setPaused(
      _inLobby || !_active || _failed || _garageOpen || _locked || _outOfFuel,
    );
    // JS pauses on document.hidden; Flutter explicitly resumes the renderer.
    // A completed run must remain paused even after the app regains focus.
    _send('setPaused', [_enginePaused]);
  }

  @override
  void dispose() {
    _disposing = true;
    _reportTimer?.cancel();
    unawaited(_reportProgress());
    if (_reveal != null) ref.read(fullscreenProvider.notifier).state = false;
    _readyTimer?.cancel();
    _fuelTimer?.cancel();
    _burstTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopWebView());
    _game.onStopGas = null;
    _game.onSituationResolvedToEngine = null;
    _game.onTrafficReleaseToEngine = null;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _reportTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_reportProgress()),
    );
    _appResumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _active = _appResumed && widget.visible;
    WidgetsBinding.instance.addObserver(this);
    _game = ref.read(gameControllerProvider.notifier);
    _game.onStopGas = () {
      _send('setGas', [false]);
      _send('setBrake', [false]);
    };
    _initialization = _initWebView();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) _syncTheme();
  }

  Future<void> _initWebView() async {
    if (kIsWeb || !CountryConfig.current.hasVerifiedGame) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await GameGarageService.instance.load();
      final saved = prefs.getString('game_vehicle');
      final savedPaint = prefs.getString('game_vehicle_paint') ?? 'red';
      if (saved != null &&
          gameVehicleIds.contains(saved) &&
          (saved != _vehicleId || savedPaint != _vehiclePaint) &&
          mounted) {
        setState(() {
          _vehicleId = saved;
          _vehiclePaint = savedPaint;
        });
      }
      _bestScore ??= prefs.getInt(_bestScoreKey) ?? 0;
      _bestBeforeRun = _bestScore ?? 0;
      _debugUnlimitedFuel =
          AuthService.debugSignInAvailable &&
          (prefs.getBool(_debugUnlimitedFuelKey) ?? false);
      if (!_fuelLoaded) {
        final fuel = await GameFuelService.instance.load();
        _fuelLoaded = true;
        if (mounted) {
          _game.configureFuel(
            fuel: fuel,
            unlimited: _debugUnlimitedFuel || ref.read(isPremiumProvider),
          );
          _scheduleFuelTick();
        }
      }
      if (!prefs.containsKey(_seenKey) && mounted) {
        setState(() {
          _firstRun = true;
          _showGasHint = true;
        });
      }
    } catch (_) {
      /* A unavailable preference store must not block the game. */
    }
    if (!mounted || _disposing) return;

    final sessionId = _game.sessionId;
    _readyTimer?.cancel();
    var activeSeconds = 0;
    // Count foreground time only; backgrounding must not fail a slow startup.
    _readyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted ||
          !_game.acceptsSession(sessionId) ||
          _configured ||
          _failed) {
        timer.cancel();
        return;
      }
      if (_active && ++activeSeconds >= 30) {
        timer.cancel();
        _bridgeFailed(sessionId);
      }
    });
    try {
      final controller = WebViewController();
      // Preferences load asynchronously: rebuild to mount the native view
      // before the engine reports ready (not only after that report).
      setState(() => _webViewController = controller);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (controller.platform is AndroidWebViewController) {
        await (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }
      // Match the app theme so nothing flashes white behind the loader.
      await controller.setBackgroundColor(
        mounted && Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF252B30)
            : const Color(0xFFF8F8FA),
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame != false) _bridgeFailed(sessionId);
          },
        ),
      );
      await controller.addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (message) => _handleJsMessage(message, sessionId),
      );
      if (!mounted || !_game.acceptsSession(sessionId)) return;
      await controller.loadFlutterAsset('assets/game/index.html');
    } catch (_) {
      _bridgeFailed(sessionId);
    }

    if (!mounted || !_game.acceptsSession(sessionId)) return;
    // Connect controller callback for engine communication
    ref.read(gameControllerProvider.notifier).onTrafficReleaseToEngine = (id) {
      _send('releaseTraffic', [id]);
    };
    ref
        .read(gameControllerProvider.notifier)
        .onSituationResolvedToEngine = (isCorrect, situationId) {
      _send('proceedAfterAnswer', [isCorrect, situationId]);
    };
  }

  void _handleJsMessage(JavaScriptMessage message, String sourceSessionId) {
    if (!mounted ||
        _disposing ||
        _restarting ||
        _failed ||
        !_game.acceptsSession(sourceSessionId)) {
      return;
    }
    try {
      final data = json.decode(message.message);
      if (data is! Map) return;

      final event = data['event'] as String?;
      final gameNotifier = ref.read(gameControllerProvider.notifier);
      if (data['sessionId'] != null &&
          !gameNotifier.acceptsSession(data['sessionId'])) {
        return;
      }
      if (event == 'engine_error') {
        _bridgeFailed(sourceSessionId);
        return;
      }
      if (event == 'ready' && !_configured) {
        _readyTimer?.cancel();
        _configured = true;
        gameNotifier.setPaused(
          _inLobby || !_active || _garageOpen || _locked || _outOfFuel,
        );
        _configure();
      }

      if (event == 'ready') {
        _lastInsets = null;
        gameNotifier.onEngineReady();
        _syncTheme();
      } else if (event == 'approach_situation') {
        final sitMap = data['situation'] as Map<String, dynamic>?;
        if (sitMap != null) {
          final sit = GameSituation.fromJson(sitMap);
          gameNotifier.onApproachSituation(sit);
        }
      } else if (event == 'telemetry') {
        final speed = data['speedKmH'];
        final dist = data['distanceM'];
        final limit = data['limitKmH'];
        if (speed is num && speed.isFinite && dist is num && dist.isFinite) {
          gameNotifier.updateTelemetry(
            speedKmH: speed.toInt(),
            distanceM: dist.toInt(),
            limitKmH: limit is num && limit > 0 ? limit.toInt() : null,
          );
        }
      } else if (event == 'situation_cleared') {
        if (data['situationId'] is String) {
          gameNotifier.onSituationClearedFromEngine(data['situationId']);
        }
      } else if (event == 'lane_changed') {
        if (data['lane'] is String && data['oncoming'] is bool) {
          gameNotifier.updateLane(data['lane'], data['oncoming']);
        }
      } else if (event == 'violation') {
        if (data['type'] is String && data['episode'] is int) {
          final type = data['type'] as String;
          final episode = data['episode'] as int;
          gameNotifier.recordViolation(type, episode);
          final activeSit = ref.read(gameControllerProvider).currentSituation;
          if (activeSit != null &&
              (type == 'priority' || type == 'wrong_maneuver')) {
            unawaited(
              _recordMistake(
                activeSit,
                null,
                episodeKey: '${activeSit.id}_viol_$episode',
              ),
            );
          }
        }
      } else if (event == 'maneuver_reset') {
        gameNotifier.setRecovering(true);
        _send('setGas', [false]);
        _send('setBrake', [false]);
        _send('setSteering', [0]);
      } else if (event == 'maneuver_ready') {
        gameNotifier.setRecovering(false);
      } else if (event == 'vehicle_selected') {
        // The car the engine actually drives: the HUD button always shows it.
        final id = data['vehicleId'];
        final paint = data['paint'];
        if (id is String && gameVehicleIds.contains(id)) {
          setState(() {
            _vehicleId = id;
            if (paint is String && gamePaintColors.containsKey(paint)) {
              _vehiclePaint = paint;
            }
          });
          unawaited(_saveVehicle(id, _vehiclePaint));
        }
      } else if (event == 'reveal_shown') {
        if (_reveal != null && !_revealShown) {
          HapticFeedbackHelper.success();
          setState(() => _revealShown = true);
        }
      }
    } catch (e) {
      debugPrint('Game JS Message Error: $e');
    }
  }

  void _syncTheme() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _send('setTheme', [isDark]);
  }

  void _handleGas(bool isPressed) {
    if (isPressed && !ref.read(gameControllerProvider).controlsEnabled) return;
    if (isPressed && _showGasHint) {
      setState(() => _showGasHint = false);
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setBool(_seenKey, true))
          .catchError((_) => false);
    }
    _send('setGas', [isPressed]);
  }

  void _handleSwitchLane(String direction) {
    if (!ref.read(gameControllerProvider).controlsEnabled) return;
    _send('switchLane', [direction]);
  }

  Future<void> _openGarage() async {
    if (_garageOpen || !_configured || _failed) return;
    HapticFeedbackHelper.tap();
    _garageOpen = true;
    _game.setPaused(true);
    _send('setPaused', [true]);
    _send('selectVehicle', [_vehicleId, _vehiclePaint]);
    try {
      final garage = GameGarageService.instance;
      final selected = await showModalBottomSheet<GameCar>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => GameGarage(
          selected: GameCar(_vehicleId, _vehiclePaint),
          cars: garage.cars,
          premium: ref.read(isPremiumProvider),
          correctUntilNext: garage.correctUntilNext,
          thumbnail: _thumbnail,
          thumbnailCache: _thumbnails,
        ),
      );
      if (!mounted ||
          selected == null ||
          !gameVehicleIds.contains(selected.id)) {
        return;
      }
      _selectCar(selected);
    } finally {
      _garageOpen = false;
      if (mounted && !_disposing) {
        final paused =
            _inLobby ||
            !_active ||
            _failed ||
            _locked ||
            ref.read(gameControllerProvider).phase == GamePhase.gameOver;
        _game.setPaused(paused);
        _send('setPaused', [paused]);
      }
    }
  }

  final Set<String> _recordedMistakeKeys = <String>{};

  /// A wrong answer in the game lands in «Ошибки» as the very ticket
  /// question the road situation was built from («Билет N · Вопрос M»).
  Future<void> _recordMistake(
    GameSituation situation,
    int? selected, {
    String? episodeKey,
  }) async {
    final key =
        episodeKey ??
        '${situation.id}_${situation.sourceQuestionId ?? situation.ticket}';
    if (_recordedMistakeKeys.contains(key)) return;
    _recordedMistakeKeys.add(key);

    if (situation.country != null &&
        situation.country != CountryConfig.current.code) {
      return;
    }

    try {
      String? questionId = situation.sourceQuestionId;
      if (questionId == null || questionId.isEmpty) {
        final m = RegExp(r'(\d+)\D+(\d+)').firstMatch(situation.ticket);
        if (m == null) return;
        final ticket = int.parse(m.group(1)!), number = int.parse(m.group(2)!);
        _abQuestions ??= await ref
            .read(questionsDataSourceProvider)
            .loadTickets(TicketCategory.ab);
        final inTicket = _abQuestions!
            .where((q) => q.ticketNumber == ticket)
            .toList();
        if (number < 1 || number > inTicket.length) return;
        questionId = inTicket[number - 1].id;
      }

      await ref
          .read(progressDataSourceProvider)
          .saveAnswer(
            questionId: questionId,
            isCorrect: false,
            selectedAnswerIndex: selected ?? -1,
            category: TicketCategory.ab,
          );
      ref.read(appDataRefreshProvider.notifier).state++;
    } catch (e) {
      debugPrint('Game mistake not saved: $e');
    }
  }

  void _selectCar(GameCar car) {
    setState(() {
      _vehicleId = car.id;
      _vehiclePaint = car.paint;
    });
    _send('selectVehicle', [car.id, car.paint]);
    if (_inLobby) _send('showLobby', [car.id, car.paint]);
    unawaited(_saveVehicle(car.id, car.paint));
  }

  /// «Start the drive» on the garage screen: a fresh world after a finished
  /// run, else the world already loaded behind the garage.
  void _startFromLobby() {
    if (!_inLobby) return;
    HapticFeedbackHelper.confirm();
    final ended = ref.read(gameControllerProvider).phase == GamePhase.gameOver;
    setState(() => _inLobby = false);
    _send('hideLobby', []);
    if (ended) {
      unawaited(_handleRestart());
      return;
    }
    _game.setPaused(
      !_active || _failed || _garageOpen || _locked || _outOfFuel,
    );
    _send('setPaused', [_enginePaused]);
  }

  void _openLobby() {
    setState(() => _inLobby = true);
    _game.setPaused(true);
    _send('setGas', [false]);
    _send('setBrake', [false]);
    _send('setSteering', [0]);
    _send('setPaused', [true]);
    _send('showLobby', [_vehicleId, _vehiclePaint]);
  }

  Future<void> _saveVehicle(String id, String paint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('game_vehicle', id);
      await prefs.setString('game_vehicle_paint', paint);
    } catch (_) {
      /* Keep the selected model for this session. */
    }
  }

  /// Asks the engine for a PNG of the car (a data URL), for the garage list.
  Future<String> _thumbnail(String id, String paint) async {
    final controller = _webViewController;
    if (controller == null || !_configured) return '';
    final result = await controller.runJavaScriptReturningResult(
      'window.game?.thumbnail?.(${jsonEncode(id)}, ${jsonEncode(paint)}) || ""',
    );
    var text = result.toString();
    // Android returns the JS string JSON-quoted.
    if (text.startsWith('"')) text = jsonDecode(text) as String;
    return text;
  }

  /// A correct answer counts towards the next car; when it arrives, the
  /// garage doors open over the paused scene.
  Future<void> _countCorrect() async {
    // Premium already opens every car and paint: nothing to hand out, no
    // garage ceremony interrupting the run.
    if (ref.read(isPremiumProvider)) return;
    final unlocked = await GameGarageService.instance.recordCorrect();
    if (unlocked == null || !mounted || _reveal != null) return;
    // A new car must not be lost with the device.
    unawaited(ProgressSyncService.instance.syncWithServer());
    _showReveal(unlocked);
  }

  void _showReveal(GameCar car) {
    setState(() {
      _reveal = car;
      _revealShown = false;
    });
    _game.setPaused(true);
    ref.read(fullscreenProvider.notifier).state = true;
    _send('setGas', [false]);
    _send('setBrake', [false]);
    _send('showReveal', [car.id, car.paint]);
  }

  void _closeReveal({required bool choose}) {
    final car = _reveal;
    if (car == null) return;
    if (choose) {
      HapticFeedbackHelper.confirm();
    } else {
      HapticFeedbackHelper.tap();
    }
    setState(() {
      _reveal = null;
      _revealShown = false;
    });
    _send('hideReveal', []);
    ref.read(fullscreenProvider.notifier).state = false;
    if (choose) _selectCar(car);
    _game.setPaused(
      _inLobby ||
          !_active ||
          _failed ||
          _garageOpen ||
          _locked ||
          _outOfFuel ||
          ref.read(gameControllerProvider).phase == GamePhase.gameOver,
    );
    _send('setPaused', [_enginePaused]);
  }

  /// Whether the three.js loop should stop. A signed-out visitor keeps the
  /// engine running: the street stays alive around the parked car.
  bool get _enginePaused =>
      _inLobby ||
      !_active ||
      _failed ||
      _garageOpen ||
      ref.read(gameControllerProvider).phase == GamePhase.gameOver;

  Future<void> _handleRestart() async {
    if (_restarting || _disposing) return;
    final tank = GameFuelService.instance.refresh();
    final premium = ref.read(isPremiumProvider);
    final unlimited = premium || _debugUnlimitedFuel;
    if (!unlimited && tank <= 0) return;
    HapticFeedbackHelper.confirm();
    _game.configureFuel(fuel: tank, unlimited: unlimited);
    _restarting = true;
    _readyTimer?.cancel();
    _game.setPaused(true);
    await _stopWebView();
    if (!mounted || _disposing) return;
    await _reportProgress();
    _reportedScore = 0;
    _liveScore = 0;
    _runCounted = false;
    _bestBeforeRun = _bestScore ?? 0;
    ref.read(gameControllerProvider.notifier).restartGame();
    _newRecord = false;
    // A fresh document isolates queued bridge events and resets all JS state.
    _configured = false;
    _restarting = false;
    _cleanup = null;
    setState(() => _failed = false);
    _lastInsets = null;
    _initialization = _initWebView();
    _game.setPaused(_inLobby || !_active);
  }

  // A new personal best: remember it, celebrate with the fanfare; the dialog
  // shows the badge and confetti while `_newRecord` is set.
  void _finishRun(int score) {
    // The record is judged against the best before this run (a live report
    // may already have stored this run's score).
    final best = _bestBeforeRun;
    final record = score > best && score > 0;
    setState(() {
      _newRecord = record;
      if (record) _bestScore = score;
    });
    // Every finished run counts towards the weekly rating; the best score
    // and the garage go to the cloud with the rest of the progress.
    _liveScore = score;
    unawaited(_reportProgress());
    if (record) {
      SoundEffectsService.instance.playStreak();
      HapticFeedbackHelper.success();
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setInt(_bestScoreKey, score))
          .then((_) => ProgressSyncService.instance.syncWithServer())
          .catchError((_) {});
    } else {
      unawaited(ProgressSyncService.instance.syncWithServer());
    }
  }

  // «To menu» at the end of a run: back to the garage start screen.
  void _handleExit() {
    HapticFeedbackHelper.tap();
    _openLobby();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final gameState = ref.watch(gameControllerProvider);
    final gameNotifier = ref.read(gameControllerProvider.notifier);
    if (_failed) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(appL10n.gameLoadError, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _handleRestart,
                    child: Text(appL10n.gameRestart),
                  ),
                  TextButton(
                    onPressed: _handleExit,
                    child: Text(appL10n.gameExit),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    ref.listen(gameControllerProvider, (previous, next) {
      _liveScore = next.score;
      if (previous?.phase != GamePhase.situation &&
          next.phase == GamePhase.situation) {
        HapticFeedbackHelper.tap();
      }
      if (previous?.controlsEnabled == true && !next.controlsEnabled) {
        _send('setGas', [false]);
        _send('setBrake', [false]);
        _send('setSteering', [0]);
      }
      if (previous != null &&
          next.fuel != previous.fuel &&
          !next.fuelUnlimited) {
        GameFuelService.instance.setFuel(next.fuel);
        _scheduleFuelTick();
      }
      if (previous?.phase == GamePhase.situation &&
          next.phase != GamePhase.situation &&
          next.isLastAnswerCorrect == false &&
          previous?.currentSituation != null) {
        unawaited(
          _recordMistake(previous!.currentSituation!, next.selectedAnswerIndex),
        );
      }
      if (previous?.phase == GamePhase.situation &&
          next.phase == GamePhase.resolving &&
          next.isLastAnswerCorrect == true) {
        // A correct answer: confetti rises from the top edge of the question
        // card as the card slides away.
        final cardTop = _bottomKey.currentContext?.size?.height;
        final screen = MediaQuery.sizeOf(context).height;
        _burstOrigin = Offset(
          0.5,
          cardTop == null || screen <= 0
              ? 0.72
              : (1 - cardTop / screen).clamp(0.3, 0.95),
        );
        setState(() => _correctBurst++);
        unawaited(_countCorrect());
        _burstTimer?.cancel();
        _burstTimer = Timer(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _correctBurst = 0);
        });
      }
      if (next.violationCount != previous?.violationCount) {
        if (next.lastViolation == 'collision') {
          HapticFeedbackHelper.collision();
        } else {
          HapticFeedbackHelper.warning();
        }
      }
      if (previous?.phase != GamePhase.gameOver &&
          next.phase == GamePhase.gameOver) {
        _send('setPaused', [true]);
        _finishRun(next.score);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final padding = MediaQuery.paddingOf(context);
      final insets = {
        'top': _hudKey.currentContext?.size?.height ?? padding.top,
        'bottom': math
            .max(
              _bottomKey.currentContext?.size?.height ?? padding.bottom,
              _cardKey.currentContext?.size?.height ?? 0,
            )
            .clamp(padding.bottom, double.infinity),
      };
      final encoded = jsonEncode(insets);
      if (encoded != _lastInsets) {
        _lastInsets = encoded;
        _send('setViewportInsets', [insets]);
      }
    });

    if (kIsWeb || !CountryConfig.current.hasVerifiedGame) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _handleExit,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        backgroundColor: colors.homeScreenBackground,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sports_esports_rounded,
                  size: 64,
                  color: colors.accent,
                ),
                const SizedBox(height: 16),
                Text(
                  appL10n.gameSimulator,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  CountryConfig.current.hasVerifiedGame
                      ? appL10n.gameMobileOnly
                      : appL10n.gameUnavailable,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 14,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Not signed in: the scene is visible (paused) but the car cannot be
    // driven; a card at the bottom asks to sign in. Everything else stays.
    final locked = !ref.watch(isAuthenticatedProvider);
    final premium = ref.watch(isPremiumProvider);
    final unlimitedFuel = premium || _debugUnlimitedFuel;
    if (_fuelLoaded && unlimitedFuel != gameState.fuelUnlimited) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _game.configureFuel(
            fuel: GameFuelService.instance.refresh(),
            unlimited: unlimitedFuel,
          );
        }
      });
    }
    final outOfFuel =
        !locked &&
        !unlimitedFuel &&
        _fuelLoaded &&
        gameState.fuel <= 0 &&
        gameState.phase != GamePhase.gameOver;
    if (outOfFuel != _outOfFuel) {
      _outOfFuel = outOfFuel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _game.setPaused(_inLobby || outOfFuel || locked || !_active);
        _send('setAttract', [outOfFuel || locked]);
        _send('setPaused', [!_active]);
      });
    }
    if (locked != _locked) {
      _locked = locked;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _game.setPaused(_inLobby || locked || !_active);
        _send('setAttract', [locked || _outOfFuel]);
        _send('setPaused', [!_active]);
      });
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: colors.cardBackground,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: colors.background,
        body: Stack(
          children: [
            // 3D Canvas
            if (_webViewController != null)
              Positioned.fill(
                child: WebViewWidget(
                  key: ValueKey(_game.sessionId),
                  controller: _webViewController!,
                ),
              ),
            // Opaque, theme-coloured loading cover with a spinning wheel: the
            // WebView paints nothing useful until the engine reports ready.
            if (gameState.phase == GamePhase.ready)
              Positioned.fill(
                child: Container(
                  color: colors.background,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LoadingWheel(
                          color: colors.accent,
                          rim: colors.cardBackground,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          appL10n.gameLoading,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Top HUD
            if (_reveal == null && !_inLobby)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  key: _hudKey,
                  child: GameHud(
                    state: gameState,
                    vehicleId: _vehicleId,
                    vehiclePaint: _vehiclePaint,
                    thumbnail: _thumbnail,
                    thumbnailCache: _thumbnails,
                    onGarage: gameState.controlsEnabled ? _openGarage : null,
                    showGarage:
                        GameGarageService.instance.cars.length > 1 || premium,
                    onGarageLongPress: AuthService.debugSignInAvailable
                        ? _openDebug
                        : null,
                    onLeaderboard: gameState.controlsEnabled
                        ? _openLeaderboard
                        : null,
                  ),
                ),
              ),

            if (locked && !_inLobby)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                child: _LockCard(
                  onSignIn: () => AuthModalSheet.show(context),
                  onDebugSignIn: AuthService.debugSignInAvailable
                      ? () => AuthService.instance.signInDebug()
                      : null,
                ),
              ),
            if (outOfFuel && !_inLobby)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                child: GameFuelEmptyPanel(
                  refillAt: GameFuelService.instance.firstUnitAt,
                  onBuyPremium: () => PremiumPaywallSheet.show(context),
                  // Back to driving right away, no reload needed.
                  onRefilled: () => _game.configureFuel(
                    fuel: GameFuelService.instance.refresh(),
                    unlimited:
                        _debugUnlimitedFuel || ref.read(isPremiumProvider),
                  ),
                ),
              ),
            if (_correctBurst > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: _CorrectCheck(
                    key: ValueKey(_correctBurst),
                    origin: _burstOrigin,
                  ),
                ),
              ),
            // The question card lives on its own layer: when it slides away
            // nothing else in the bottom column moves, so there is no jerk.
            if (!locked && !outOfFuel && _reveal == null && !_inLobby)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: KeyedSubtree(
                  key: _cardKey,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInOutCubic,
                    // No clipping: the card slides down past the bottom
                    // edge of the game area and disappears under the menu.
                    transitionBuilder: (child, animation) => SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 1.15),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.bottomCenter,
                      children: [...previous, ?current],
                    ),
                    child: gameState.phase == GamePhase.situation
                        ? GameQuestionCard(
                            key: const ValueKey('question'),
                            state: gameState,
                            onSelectAnswer: gameNotifier.submitAnswer,
                          )
                        : const SizedBox.shrink(key: ValueKey('none')),
                  ),
                ),
              ),
            // Bottom Overlays depending on game phase
            if (!locked &&
                !outOfFuel &&
                _reveal == null &&
                !_inLobby &&
                gameState.phase != GamePhase.gameOver)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  key: _bottomKey,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (gameState.phase == GamePhase.explanation &&
                        gameState.currentSituation != null)
                      GameExplanationSheet(
                        situation: gameState.currentSituation!,
                        onContinue: gameNotifier.continueAfterExplanation,
                      ),
                    if (gameState.phase == GamePhase.driving ||
                        gameState.phase == GamePhase.resolving)
                      GameControlsOverlay(
                        state: gameState,
                        onGasChanged: _handleGas,
                        onSwitchLane: _handleSwitchLane,
                        onSteering: (direction) =>
                            _send('setSteering', [direction]),
                        onBrake: (pressed) => _send('setBrake', [pressed]),
                      ),
                  ],
                ),
              ),

            if (_showGasHint &&
                !_inLobby &&
                !locked &&
                !outOfFuel &&
                _reveal == null &&
                gameState.phase == GamePhase.driving &&
                gameState.speedKmH == 0)
              // Beside the gas pedal (the brake sits above it), pointing at it.
              Positioned(
                right: 20 + 100 + 10,
                bottom: MediaQuery.paddingOf(context).bottom + 20 + 28,
                child: IgnorePointer(
                  child: _GasHint(text: appL10n.gameGasHint),
                ),
              ),

            if (_reveal != null)
              Positioned.fill(
                child: GameRevealOverlay(
                  car: _reveal!,
                  shown: _revealShown,
                  onChoose: () => _closeReveal(choose: true),
                  onClose: () => _closeReveal(choose: false),
                ),
              ),

            // Game Over Dialog Modal
            // The garage start screen over the engine's garage scene.
            if (_inLobby &&
                _reveal == null &&
                gameState.phase != GamePhase.ready)
              Positioned.fill(
                child: GameLobby(
                  vehicleId: _vehicleId,
                  vehiclePaint: _vehiclePaint,
                  bestScore: _bestScore ?? 0,
                  fuel: GameFuelGauge(
                    fuel: gameState.fuel,
                    maxFuel: GameState.maxFuel,
                    unlimited: gameState.fuelUnlimited,
                  ),
                  blocker: locked
                      ? _LockCard(
                          onSignIn: () => AuthModalSheet.show(context),
                          onDebugSignIn: AuthService.debugSignInAvailable
                              ? () => AuthService.instance.signInDebug()
                              : null,
                        )
                      : !unlimitedFuel && _fuelLoaded && gameState.fuel <= 0
                      ? GameFuelEmptyPanel(
                          refillAt: GameFuelService.instance.firstUnitAt,
                          onBuyPremium: () => PremiumPaywallSheet.show(context),
                          onRefilled: () => _game.configureFuel(
                            fuel: GameFuelService.instance.refresh(),
                            unlimited:
                                _debugUnlimitedFuel ||
                                ref.read(isPremiumProvider),
                          ),
                        )
                      : null,
                  onStart: _startFromLobby,
                  onGarage: locked ? null : _openGarage,
                  onLeaderboard: _openLeaderboard,
                ),
              ),

            if (gameState.phase == GamePhase.gameOver &&
                _reveal == null &&
                !_inLobby)
              Positioned.fill(
                child: Container(
                  color: const Color(0x80000000),
                  child: Center(
                    child: GameOverDialog(
                      state: gameState,
                      vehicleId: _vehicleId,
                      vehiclePaint: _vehiclePaint,
                      thumbnail: _thumbnail,
                      thumbnailCache: _thumbnails,
                      onLeaderboard: () {
                        HapticFeedbackHelper.tap();
                        GameLeaderboardSheet.show(context);
                      },
                      fuelRefillAt: GameFuelService.instance.firstUnitAt,
                      onBuyPremium: () => PremiumPaywallSheet.show(context),
                      bestScore: _newRecord ? null : _bestScore,
                      isNewRecord: _newRecord,
                      onRestart: _handleRestart,
                      onExit: _handleExit,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A gently bouncing callout above the gas pedal for the very first drive.
class _GasHint extends StatefulWidget {
  final String text;
  const _GasHint({required this.text});

  @override
  State<_GasHint> createState() => _GasHintState();
}

class _GasHintState extends State<_GasHint>
    with SingleTickerProviderStateMixin {
  // Finite (nine bounces, then rest): keeps widget tests settling.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(6 * math.sin(_controller.value * math.pi * 9).abs(), 0),
        child: child,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              ),
              child: Text(
                widget.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.white,
                  fontFamily: 'Onest',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ),
          Icon(Icons.arrow_forward_rounded, color: colors.accent, size: 26),
        ],
      ),
    );
  }
}

/// A rolling tyre with a rim and spokes — the game's loading indicator.
class _LoadingWheel extends StatefulWidget {
  final Color color;
  final Color rim;
  const _LoadingWheel({required this.color, required this.rim});

  @override
  State<_LoadingWheel> createState() => _LoadingWheelState();
}

class _LoadingWheelState extends State<_LoadingWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: CustomPaint(
        size: const Size(72, 72),
        painter: _WheelPainter(
          tyre: const Color(0xFF23272C),
          rim: widget.rim,
          hub: widget.color,
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final Color tyre;
  final Color rim;
  final Color hub;
  const _WheelPainter({
    required this.tyre,
    required this.rim,
    required this.hub,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = tyre);
    canvas.drawCircle(c, r * 0.62, Paint()..color = rim);
    final spoke = Paint()
      ..color = tyre
      ..strokeWidth = r * 0.14
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final a = i * 2 * math.pi / 5;
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * r * 0.5, spoke);
    }
    canvas.drawCircle(c, r * 0.2, Paint()..color = hub);
    // Tread notches make the rotation visible.
    final notch = Paint()
      ..color = rim.withValues(alpha: 0.35)
      ..strokeWidth = 3;
    for (var i = 0; i < 12; i++) {
      final a = i * 2 * math.pi / 12;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * r * 0.86,
        c + Offset(math.cos(a), math.sin(a)) * r * 0.98,
        notch,
      );
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hub != hub || old.rim != rim;
}

/// Bottom card shown to signed-out visitors: they can look, not drive.
class _LockCard extends StatelessWidget {
  final VoidCallback onSignIn;
  // Dev builds only: a local test account, no OAuth.
  final VoidCallback? onDebugSignIn;
  const _LockCard({required this.onSignIn, this.onDebugSignIn});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: colors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  appL10n.gameLockedTitle,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            appL10n.gameLockedHint,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 13,
              height: 1.35,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: onSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              ),
            ),
            child: Text(
              appL10n.gameSignIn,
              style: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onDebugSignIn != null)
            TextButton.icon(
              onPressed: onDebugSignIn,
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('Тестовый вход (dev-сборка)'),
            ),
        ],
      ),
    );
  }
}

/// A correct answer: a bright green check pops above the question card as
/// it slides away, holds for a moment and fades.
class _CorrectCheck extends StatefulWidget {
  final Offset origin;
  const _CorrectCheck({super.key, required this.origin});

  @override
  State<_CorrectCheck> createState() => _CorrectCheckState();
}

class _CorrectCheckState extends State<_CorrectCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final pop = Curves.elasticOut.transform((t / 0.45).clamp(0.0, 1.0));
        final fade = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
        final rise = Curves.easeOut.transform(t) * 40;
        return Align(
          alignment: Alignment(0, (widget.origin.dy * 2 - 1) - 0.12),
          child: Transform.translate(
            offset: Offset(0, -rise),
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.4 + 0.6 * pop,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
