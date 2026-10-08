import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/traffic_controller_rules.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/platform/browser_game.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_art.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

enum GamePlayMode { training, arcade }

class TrafficControllerScreen extends ConsumerStatefulWidget {
  final GamePlayMode initialMode;

  const TrafficControllerScreen({
    super.key,
    this.initialMode = GamePlayMode.training,
  });

  @override
  ConsumerState<TrafficControllerScreen> createState() =>
      _TrafficControllerScreenState();
}

class _TrafficControllerScreenState
    extends ConsumerState<TrafficControllerScreen> {
  late GamePlayMode _mode;
  WebViewController? _webViewController;
  BrowserGame? _browserGame;
  bool _engineReady = false;

  // Текущая ситуация: жест, откуда едет ТС и кто едет.
  ControllerGesture _curGesture = ControllerGesture.rightArmForward;
  ApproachDirection _curApproach = ApproachDirection.left;
  VehicleKind _curVehicle = VehicleKind.car;

  // Блиц
  int _score = 0;
  int _combo = 0;
  int _maxComboInRound = 0;
  int _lives = 3;
  int _secondsLeft = 35;
  int _solvedCount = 0;
  Timer? _countdownTimer;
  // Пауза между ситуациями: ввод закрыт, чтобы не засчитать ответ дважды.
  Timer? _nextSituationTimer;
  bool _awaitingNext = false;
  TrafficMove? _lastMove;
  bool _lastWasCorrect = false;
  int _wrongCount = 0;
  bool _isGameOver = false;
  bool _timeUp = false;
  bool _isNewRecord = false;
  int _previousBest = 0;
  final _random = math.Random();

  // Высота нижней панели: сцена ставит центр кадра над ней.
  final GlobalKey _panelKey = GlobalKey();
  double _sentInset = -1;

  // Приближение камеры щипком по сцене.
  static const double _minZoom = 0.65;
  static const double _maxZoom = 2.2;
  double _zoom = 1;
  double _zoomAtGestureStart = 1;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    if (kIsWeb) {
      _initWebGame();
    } else {
      _initWebView();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _nextSituationTimer?.cancel();
    if (kIsWeb) {
      _browserGame?.dispose();
    }
    super.dispose();
  }

  // --- Мост со сценой (Three.js) ---

  void _initWebGame() {
    final browser = BrowserGame(
      onMessage: _handleBridgeMessage,
      onBlur: () {},
      onKey: (_, _, _) {},
      htmlPath: 'assets/assets/game/traffic-controller.html?flutterWeb=1',
      allowPointerEvents: false,
    );
    setState(() => _browserGame = browser);
  }

  void _initWebView() {
    final controller = WebViewController.fromPlatformCreationParams(
      const PlatformWebViewControllerCreationParams(),
    );

    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _updateEngineScenario()),
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      )
      ..loadFlutterAsset('assets/game/traffic-controller.html');

    _webViewController = controller;
  }

  void _handleBridgeMessage(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['type'] == 'ready' && mounted) {
        setState(() => _engineReady = true);
        _sentInset = -1;
        _syncViewInset();
        unawaited(_sendPlayerCar());
        _call('setZoom($_zoom)');
        // Блиц стартует, когда сцена готова, — иначе время тратится на загрузку.
        if (_mode == GamePlayMode.arcade) {
          _startArcadeRound();
        } else {
          _updateEngineScenario();
        }
      }
    } catch (_) {}
  }

  void _runJs(String code) {
    if (!_engineReady) return;
    if (kIsWeb) {
      _browserGame?.runJavaScript(code).ignore();
    } else {
      _webViewController?.runJavaScript(code).ignore();
    }
  }

  void _call(String method) => _runJs(
    'window.TrafficControllerGame && window.TrafficControllerGame.$method;',
  );

  static String _moveName(TrafficMove move) => switch (move) {
    TrafficMove.straight => 'straight',
    TrafficMove.right => 'right',
    TrafficMove.left => 'left',
    TrafficMove.uTurn => 'uTurn',
    TrafficMove.none => 'none',
  };

  /// Та же машина, что выбрана в гараже основной игры.
  Future<void> _sendPlayerCar() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('game_vehicle');
    if (!mounted || id == null || !gameVehicleIds.contains(id)) return;
    final paint = prefs.getString('game_vehicle_paint') ?? 'red';
    _call('setPlayerCar(${jsonEncode(id)}, ${jsonEncode(paint)})');
  }

  void _syncViewInset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_engineReady) return;
      final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
      final screen = MediaQuery.sizeOf(context).height;
      if (box == null || !box.hasSize || screen <= 0) return;
      final inset = box.size.height / screen;
      if ((inset - _sentInset).abs() < 0.005) return;
      _sentInset = inset;
      _call('setViewInsetBottom(${inset.toStringAsFixed(3)})');
    });
  }

  void _setZoom(double value) {
    final zoom = value.clamp(_minZoom, _maxZoom).toDouble();
    if ((zoom - _zoom).abs() < 0.001) return;
    setState(() => _zoom = zoom);
    _call('setZoom(${zoom.toStringAsFixed(3)})');
  }

  void _updateEngineScenario() {
    final gesture = switch (_curGesture) {
      ControllerGesture.handsDownOrSides => 'handsDownOrSides',
      ControllerGesture.rightArmForward => 'rightArmForward',
      ControllerGesture.armUp => 'armUp',
    };
    final approach = switch (_curApproach) {
      ApproachDirection.front => 'front',
      ApproachDirection.back => 'back',
      ApproachDirection.left => 'left',
      ApproachDirection.right => 'right',
    };
    final vehicle = _curVehicle == VehicleKind.tram ? 'tram' : 'car';
    final mode = _mode == GamePlayMode.training ? 'training' : 'arcade';

    _call('setMode("$mode")');
    _call('setScenario("$gesture", "$approach", "$vehicle")');
    _call('setCameraView("driver")');
  }

  // --- Режимы ---

  void _switchMode(GamePlayMode mode) {
    if (_mode == mode) return;
    _countdownTimer?.cancel();
    _nextSituationTimer?.cancel();

    setState(() {
      _mode = mode;
      _isGameOver = false;
    });
    if (_mode == GamePlayMode.arcade) {
      _startArcadeRound();
    } else {
      _updateEngineScenario();
    }
  }

  void _setScenario({
    ControllerGesture? gesture,
    ApproachDirection? approach,
    VehicleKind? vehicle,
  }) {
    setState(() {
      _curGesture = gesture ?? _curGesture;
      _curApproach = approach ?? _curApproach;
      _curVehicle = vehicle ?? _curVehicle;
    });
    _updateEngineScenario();
  }

  // --- Блиц ---

  void _startArcadeRound() {
    if (!_engineReady) return;
    HapticFeedbackHelper.select();
    _countdownTimer?.cancel();
    _nextSituationTimer?.cancel();
    setState(() {
      _score = 0;
      _combo = 0;
      _maxComboInRound = 0;
      _lives = 3;
      _secondsLeft = 35;
      _solvedCount = 0;
      _wrongCount = 0;
      _isGameOver = false;
      _timeUp = false;
      _isNewRecord = false;
      _awaitingNext = false;
      _lastMove = null;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        setState(() {
          _secondsLeft = 0;
          _timeUp = true;
        });
        _endArcadeGame();
      }
    });

    _nextArcadeSituation();
  }

  void _nextArcadeSituation() {
    final gestures = ControllerGesture.values;
    final approaches = ApproachDirection.values;
    // В основном авто (~88%), трамвай появляется редко (~12%) и не два раза подряд.
    final wasTram = _curVehicle == VehicleKind.tram;

    setState(() {
      _curGesture = gestures[_random.nextInt(gestures.length)];
      _curApproach = approaches[_random.nextInt(approaches.length)];
      _curVehicle = (!wasTram && _random.nextDouble() < 0.12)
          ? VehicleKind.tram
          : VehicleKind.car;
      _awaitingNext = false;
      _lastMove = null;
    });

    _updateEngineScenario();
  }

  void _scheduleNextSituation(Duration delay) {
    _nextSituationTimer?.cancel();
    _nextSituationTimer = Timer(delay, () {
      if (mounted && !_isGameOver) _nextArcadeSituation();
    });
  }

  void _onArcadeMoveSelected(TrafficMove move) {
    if (_isGameOver || _awaitingNext) return;

    final isAllowed = TrafficControllerRules.isMoveAllowed(
      gesture: _curGesture,
      approach: _curApproach,
      vehicle: _curVehicle,
      move: move,
    );
    _call('makeMove("${_moveName(move)}")');

    if (isAllowed) {
      HapticFeedbackHelper.tap();
      SoundEffectsService.instance.playCorrect();
      setState(() {
        _awaitingNext = true;
        _lastMove = move;
        _lastWasCorrect = true;
        _combo++;
        if (_combo > _maxComboInRound) _maxComboInRound = _combo;
        _score += 100 * _combo;
        _solvedCount++;
        _secondsLeft = math.min(_secondsLeft + 3, 60);
      });
      _scheduleNextSituation(
        Duration(milliseconds: move == TrafficMove.none ? 700 : 1250),
      );
    } else {
      HapticFeedbackHelper.error();
      SoundEffectsService.instance.playIncorrect();
      setState(() {
        _awaitingNext = true;
        _lastMove = move;
        _lastWasCorrect = false;
        _combo = 0;
        _lives--;
        _wrongCount++;
      });
      if (_lives <= 0) {
        _endArcadeGame();
      } else {
        _scheduleNextSituation(const Duration(milliseconds: 1100));
      }
    }
  }

  /// Конец заезда. Рекорд сравниваем ДО записи, иначе он всегда «побит».
  void _endArcadeGame() {
    _countdownTimer?.cancel();
    _nextSituationTimer?.cancel();
    final previousBest = ref.read(trafficControllerProgressProvider).bestScore;

    ref
        .read(trafficControllerProgressProvider.notifier)
        .recordGameResult(
          score: _score,
          combo: _maxComboInRound,
          solved: _solvedCount,
        );
    setState(() {
      _previousBest = previousBest;
      _isNewRecord = _score > 0 && _score > previousBest;
      _isGameOver = true;
      _awaitingNext = false;
    });
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final padding = MediaQuery.paddingOf(context);
    final arcade = _mode == GamePlayMode.arcade;

    // Сцена всегда дневная — значки статус-бара тёмные в любой теме.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: colors.background,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: (_) => _zoomAtGestureStart = _zoom,
                onScaleUpdate: (details) {
                  if (details.pointerCount < 2) return;
                  _setZoom(_zoomAtGestureStart / details.scale);
                },
                child: _buildScene(colors),
              ),
            ),

            // Пока сцена грузится — тема приложения и спиннер.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _engineReady,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _engineReady ? 0 : 1,
                  child: ColoredBox(
                    color: colors.background,
                    child: Center(
                      child: CircularProgressIndicator(color: colors.accent),
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              top: padding.top + AppDimensions.spacingS,
              left: AppDimensions.screenPadding,
              right: AppDimensions.screenPadding,
              child: _buildTopBar(colors, arcade),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildPanel(colors, padding.bottom, arcade),
            ),

            if (_isGameOver) Positioned.fill(child: _buildResult(colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(AppThemeColors colors) {
    final answered = _solvedCount + _wrongCount;
    final accuracy = answered > 0 ? (_solvedCount * 100 / answered).round() : 0;
    return GameResultOverlay(
      art: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        child: const TrafficControllerArt(),
      ),
      title: _timeUp ? appL10n.gameTimeUp : appL10n.gameOverTitle,
      score: _score,
      bestScore: _previousBest,
      isNewRecord: _isNewRecord,
      stats: [
        GameResultStat(appL10n.gameSolvedLabel, '$_solvedCount'),
        GameResultStat(appL10n.gameAccuracyLabel, '$accuracy%'),
        GameResultStat(appL10n.gameComboLabel, 'x$_maxComboInRound'),
      ],
      onRestart: _startArcadeRound,
      onExit: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildScene(AppThemeColors colors) {
    if (kIsWeb) {
      return _browserGame?.widget ?? const SizedBox.shrink();
    }
    final controller = _webViewController;
    return controller == null
        ? const SizedBox.shrink()
        : WebViewWidget(controller: controller);
  }

  Widget _buildTopBar(AppThemeColors colors, bool arcade) {
    return Row(
      children: [
        AppChromeIconButton(
          icon: Icons.close_rounded,
          onTap: () {
            HapticFeedbackHelper.tap();
            Navigator.of(context).pop();
          },
        ),
        const SizedBox(width: AppDimensions.spacingM),
        if (arcade)
          Expanded(child: _buildHud(colors))
        else ...[
          const Spacer(),
          _buildVehicleToggle(colors),
        ],
      ],
    );
  }

  /// Счёт, комбо, время и жизни — одной плоской плашкой.
  Widget _buildHud(AppThemeColors colors) {
    final urgent = _secondsLeft <= 10;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingM),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
      ),
      child: Row(
        children: [
          GameScoreLabel(score: _score, multiplier: _combo),
          const Spacer(),
          Icon(
            Icons.timer_outlined,
            size: 18,
            color: urgent ? colors.red : colors.secondaryText,
          ),
          const SizedBox(width: 4),
          Text(
            appL10n.gameSecondsLeft(_secondsLeft),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: urgent ? colors.red : colors.primaryText,
            ),
          ),
          const SizedBox(width: AppDimensions.spacingM),
          GameLives(lives: _lives),
        ],
      ),
    );
  }

  Widget _buildVehicleToggle(AppThemeColors colors) {
    Widget item(VehicleKind kind, IconData icon, String label) {
      final selected = _curVehicle == kind;
      return Semantics(
        label: label,
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (selected) return;
            HapticFeedbackHelper.select();
            _setScenario(vehicle: kind);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 40,
            height: 32,
            decoration: BoxDecoration(
              color: selected ? colors.accentSurface10 : Colors.transparent,
              borderRadius: BorderRadius.circular(
                AppDimensions.smallRadius + 1,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: selected ? colors.accent : colors.secondaryText,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
      ),
      child: Row(
        children: [
          item(
            VehicleKind.car,
            Icons.directions_car_rounded,
            appL10n.gameVehicleCar,
          ),
          item(VehicleKind.tram, Icons.tram_rounded, appL10n.gameVehicleTram),
        ],
      ),
    );
  }

  Widget _buildPanel(AppThemeColors colors, double bottomInset, bool arcade) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _syncViewInset();
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(
          key: _panelKey,
          child: _panelBody(colors, bottomInset, arcade),
        ),
      ),
    );
  }

  Widget _panelBody(AppThemeColors colors, double bottomInset, bool arcade) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        AppDimensions.spacingL,
        AppDimensions.screenPadding,
        AppDimensions.spacingL + bottomInset,
      ),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusExtraLarge),
        ),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GameModeSwitch(
              labels: [appL10n.gameModeTraining, appL10n.gameModeArcade],
              selected: arcade ? 1 : 0,
              onChanged: (i) => _switchMode(
                i == 1 ? GamePlayMode.arcade : GamePlayMode.training,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            if (arcade)
              _buildArcadeControls(colors)
            else
              _buildTraining(colors),
          ],
        ),
      ),
    );
  }

  // --- Обучение ---

  Widget _buildTraining(AppThemeColors colors) {
    final verse = TrafficControllerRules.mnemonicVerse(
      gesture: _curGesture,
      approach: _curApproach,
      vehicle: _curVehicle,
    );
    final allowed = TrafficControllerRules.allowedMoves(
      gesture: _curGesture,
      approach: _curApproach,
      vehicle: _curVehicle,
    );

    Widget caption(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingS),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: colors.secondaryText),
      ),
    );

    Widget chips<T>(
      List<(T, String)> items,
      T selected,
      ValueChanged<T> onSelect,
    ) {
      return Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: AppDimensions.spacingS),
            Expanded(
              child: GameChip(
                label: items[i].$2,
                selected: items[i].$1 == selected,
                onTap: () => onSelect(items[i].$1),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 38),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              verse,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: colors.primaryText,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppDimensions.spacingL),
        caption(appL10n.gameCaptionGesture),
        chips<ControllerGesture>(
          [
            (ControllerGesture.rightArmForward, appL10n.gameGestureRightArm),
            (ControllerGesture.handsDownOrSides, appL10n.gameGestureHandsSides),
            (ControllerGesture.armUp, appL10n.gameGestureArmUp),
          ],
          _curGesture,
          (g) => _setScenario(gesture: g),
        ),
        const SizedBox(height: AppDimensions.spacingM),
        caption(appL10n.gameCaptionApproach),
        chips<ApproachDirection>(
          [
            (ApproachDirection.left, appL10n.gameApproachLeft),
            (ApproachDirection.front, appL10n.gameApproachFront),
            (ApproachDirection.right, appL10n.gameApproachRight),
            (ApproachDirection.back, appL10n.gameApproachBack),
          ],
          _curApproach,
          (a) => _setScenario(approach: a),
        ),
        const SizedBox(height: AppDimensions.spacingL),
        Row(
          children: [
            for (var i = 0; i < _moves.length; i++) ...[
              if (i > 0) const SizedBox(width: AppDimensions.spacingS),
              Expanded(
                child: _MoveTile(
                  move: _moves[i],
                  allowed: allowed.contains(_moves[i].move),
                  onTap: () {
                    HapticFeedbackHelper.select();
                    _call('makeMove("${_moveName(_moves[i].move)}")');
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // --- Блиц ---

  Widget _buildArcadeControls(AppThemeColors colors) {
    final allowed = TrafficControllerRules.allowedMoves(
      gesture: _curGesture,
      approach: _curApproach,
      vehicle: _curVehicle,
    );

    Widget button(_MoveSpec spec) {
      final isLast = _lastMove == spec.move;
      Color background = colors.gray;
      Color foreground = colors.primaryText;
      if (_awaitingNext) {
        if (isLast) {
          background = _lastWasCorrect ? colors.green : colors.red;
          foreground = colors.white;
        } else if (!_lastWasCorrect && allowed.contains(spec.move)) {
          // Неверный ответ — подсвечиваем, как было правильно.
          background = colors.greenLight;
          foreground = colors.green;
        } else {
          foreground = colors.secondaryText;
        }
      }
      return GameActionButton(
        label: spec.label,
        icon: spec.icon,
        iconColor: _awaitingNext ? null : colors.accent,
        height: 52,
        background: background,
        foreground: foreground,
        onTap: () => _onArcadeMoveSelected(spec.move),
      );
    }

    Widget row(List<_MoveSpec> specs) => Row(
      children: [
        for (var i = 0; i < specs.length; i++) ...[
          if (i > 0) const SizedBox(width: AppDimensions.spacingS),
          Expanded(child: button(specs[i])),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _curVehicle == VehicleKind.car
                  ? Icons.directions_car_rounded
                  : Icons.tram_rounded,
              size: 20,
              color: colors.accent,
            ),
            const SizedBox(width: AppDimensions.spacingS),
            Text(
              appL10n.gamePromptWhereCanGo,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.spacingM),
        row(_moves.sublist(0, 3)),
        const SizedBox(height: AppDimensions.spacingS),
        row(_moves.sublist(3)),
      ],
    );
  }

  static final List<_MoveSpec> _moves = [
    _MoveSpec(
      TrafficMove.straight,
      Icons.straight_rounded,
      () => appL10n.gameActionStraight,
    ),
    _MoveSpec(
      TrafficMove.right,
      Icons.turn_right_rounded,
      () => appL10n.gameActionRight,
    ),
    _MoveSpec(
      TrafficMove.left,
      Icons.turn_left_rounded,
      () => appL10n.gameActionLeft,
    ),
    _MoveSpec(
      TrafficMove.uTurn,
      Icons.u_turn_left_rounded,
      () => appL10n.gameActionUTurn,
    ),
    _MoveSpec(
      TrafficMove.none,
      Icons.front_hand_rounded,
      () => appL10n.gameActionStand,
    ),
  ];
}

class _MoveSpec {
  const _MoveSpec(this.move, this.icon, this._label);

  final TrafficMove move;
  final IconData icon;
  final String Function() _label;

  String get label => _label();
}

/// Маневр в обучении: зелёный — разрешён, серый — нет. Нажатие — проезд.
class _MoveTile extends StatelessWidget {
  const _MoveTile({
    required this.move,
    required this.allowed,
    required this.onTap,
  });

  final _MoveSpec move;
  final bool allowed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final foreground = allowed ? colors.green : colors.secondaryText;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: allowed ? colors.greenLight : colors.gray,
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(move.icon, size: 22, color: foreground),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  move.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
