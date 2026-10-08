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

class TrafficControllerScreen extends ConsumerStatefulWidget {
  const TrafficControllerScreen({super.key});

  @override
  ConsumerState<TrafficControllerScreen> createState() =>
      _TrafficControllerScreenState();
}

class _TrafficControllerScreenState
    extends ConsumerState<TrafficControllerScreen> {
  WebViewController? _webViewController;
  BrowserGame? _browserGame;
  bool _engineReady = false;

  // Текущая ситуация: жест, откуда едет ТС и кто едет.
  ControllerGesture _curGesture = ControllerGesture.rightArmForward;
  ApproachDirection _curApproach = ApproachDirection.left;
  static const _vehicle = VehicleKind.car;
  bool _hintOpen = false;
  bool _hintUsed = false;

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
  int _moveSequence = 0;
  int _wrongCount = 0;
  bool _isGameOver = false;
  bool _timeUp = false;
  bool _isNewRecord = false;
  int _previousBest = 0;
  final _random = math.Random();

  // Высота нижней панели: сцена ставит центр кадра над ней.
  final GlobalKey _panelKey = GlobalKey();
  double _sentInset = -1;
  double _panelHeight = 0;

  // Приближение камеры щипком по сцене.
  static const double _minZoom = 0.4;
  static const double _maxZoom = 2.6;
  double _zoom = 1;
  double _zoomAtGestureStart = 1;

  @override
  void initState() {
    super.initState();
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
      if (!mounted) return;
      if (data['type'] == 'ready' && mounted && !_engineReady) {
        setState(() => _engineReady = true);
        _sentInset = -1;
        _syncViewInset();
        unawaited(_sendPlayerCar());
        _call('setZoom($_zoom)');
        // Блиц стартует, когда сцена готова, — иначе время тратится на загрузку.
        _startArcadeRound();
      } else if (data['type'] == 'move_complete' &&
          data['id'] == _moveSequence &&
          _awaitingNext &&
          _lastWasCorrect &&
          !_isGameOver) {
        _scheduleNextSituation(const Duration(milliseconds: 160));
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
      if ((box.size.height - _panelHeight).abs() > 0.5) {
        setState(() => _panelHeight = box.size.height);
      }
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
      ControllerGesture.handsSides => 'handsSides',
      ControllerGesture.handsDown => 'handsDown',
      ControllerGesture.rightArmForward => 'rightArmForward',
      ControllerGesture.armUp => 'armUp',
    };
    final approach = switch (_curApproach) {
      ApproachDirection.front => 'front',
      ApproachDirection.back => 'back',
      ApproachDirection.left => 'left',
      ApproachDirection.right => 'right',
    };
    _call('setMode("arcade")');
    _call('setScenario("$gesture", "$approach", "car")');
    _call('setCameraView("driver")');
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
      _hintOpen = false;
      _hintUsed = false;
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
    setState(() {
      _curGesture = gestures[_random.nextInt(gestures.length)];
      _curApproach = approaches[_random.nextInt(approaches.length)];
      _awaitingNext = false;
      _hintOpen = false;
      _hintUsed = false;
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
    if (!_engineReady || _isGameOver || _awaitingNext) return;

    final isAllowed = TrafficControllerRules.isMoveAllowed(
      gesture: _curGesture,
      approach: _curApproach,
      vehicle: _vehicle,
      move: move,
    );
    setState(() => _hintOpen = false);
    _moveSequence++;
    _call('makeMove("${_moveName(move)}", $_moveSequence)');

    if (isAllowed) {
      HapticFeedbackHelper.tap();
      SoundEffectsService.instance.playCorrect(volume: 0.38);
      setState(() {
        _awaitingNext = true;
        _lastMove = move;
        _lastWasCorrect = true;
        _combo++;
        if (_combo > _maxComboInRound) _maxComboInRound = _combo;
        _score += (_hintUsed ? 50 : 100) * _combo;
        _solvedCount++;
        _secondsLeft = math.min(_secondsLeft + 3, 60);
      });
      _scheduleNextSituation(
        // Moving answers advance on the scene's completion message. This
        // fallback keeps input usable if a WebView loses that message.
        Duration(milliseconds: move == TrafficMove.none ? 700 : 3300),
      );
    } else {
      HapticFeedbackHelper.warning();
      SoundEffectsService.instance.playIncorrect(volume: 0.30);
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
                  child: TickerMode(
                    enabled: !_engineReady,
                    child: ColoredBox(
                      color: colors.background,
                      child: Center(
                        child: CircularProgressIndicator(color: colors.accent),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              top: padding.top + AppDimensions.spacingS,
              left: AppDimensions.screenPadding,
              right: AppDimensions.screenPadding,
              child: _buildTopBar(colors),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildPanel(colors, padding.bottom),
            ),

            if (_engineReady && _panelHeight > 0 && !_isGameOver)
              Positioned(
                left: AppDimensions.screenPadding,
                bottom: _panelHeight + AppDimensions.spacingM,
                right: AppDimensions.screenPadding,
                child: Row(
                  children: [
                    IconButton.filled(
                      tooltip: appL10n.gameTrafficHintButton,
                      onPressed: _awaitingNext ? null : _toggleHint,
                      icon: Icon(
                        _hintOpen
                            ? Icons.lightbulb_rounded
                            : Icons.lightbulb_outline_rounded,
                        size: 22,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: colors.cardBackground,
                        foregroundColor: colors.accent,
                        disabledBackgroundColor: colors.cardBackground,
                        disabledForegroundColor: colors.secondaryText,
                        minimumSize: const Size.square(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (_hintOpen) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: IgnorePointer(
                          child: Text(
                            TrafficControllerRules.mnemonicVerse(
                              gesture: _curGesture,
                              approach: _curApproach,
                              vehicle: _vehicle,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 4),
                                Shadow(color: Colors.black54, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
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
      art: const TrafficControllerArt(),
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

  void _toggleHint() {
    if (!_engineReady || _awaitingNext || _isGameOver) return;
    HapticFeedbackHelper.select();
    setState(() {
      _hintOpen = !_hintOpen;
      if (_hintOpen) _hintUsed = true;
    });
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

  Widget _buildTopBar(AppThemeColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppChromeIconButton(
          icon: Icons.close_rounded,
          onTap: () {
            HapticFeedbackHelper.tap();
            Navigator.of(context).pop();
          },
        ),
        const SizedBox(width: AppDimensions.spacingM),
        Expanded(child: _buildHud(colors)),
      ],
    );
  }

  /// Счёт, комбо, время и жизни — одной плоской плашкой.
  Widget _buildHud(AppThemeColors colors) {
    final urgent = _secondsLeft <= 10;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingM,
        vertical: AppDimensions.spacingS,
      ),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppDimensions.spacingM,
        runSpacing: AppDimensions.spacingS,
        children: [
          GameScoreLabel(score: _score, multiplier: _combo),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 18,
                color: urgent ? colors.red : colors.secondaryText,
              ),
              const SizedBox(width: AppDimensions.spacingXS),
              Text(
                appL10n.gameSecondsLeft(_secondsLeft),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: urgent ? colors.red : colors.primaryText,
                ),
              ),
            ],
          ),
          GameLives(lives: _lives),
        ],
      ),
    );
  }

  Widget _buildPanel(AppThemeColors colors, double bottomInset) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _syncViewInset();
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(
          key: _panelKey,
          child: _panelBody(colors, bottomInset),
        ),
      ),
    );
  }

  Widget _panelBody(AppThemeColors colors, double bottomInset) {
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
      child: _buildArcadeControls(colors),
    );
  }

  // --- Блиц ---

  Widget _buildArcadeControls(AppThemeColors colors) {
    final allowed = TrafficControllerRules.allowedMoves(
      gesture: _curGesture,
      approach: _curApproach,
      vehicle: _vehicle,
    );

    Widget button(_MoveSpec spec, {required bool directional}) {
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
      return _TrafficMoveButton(
        spec: spec,
        directional: directional,
        iconColor: _awaitingNext ? null : colors.accent,
        background: background,
        foreground: foreground,
        onTap: _engineReady && !_awaitingNext && !_isGameOver
            ? () => _onArcadeMoveSelected(spec.move)
            : null,
      );
    }

    Widget row(List<_MoveSpec> specs, {required bool directional}) =>
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < specs.length; i++) ...[
                if (i > 0) const SizedBox(width: AppDimensions.spacingS),
                Expanded(child: button(specs[i], directional: directional)),
              ],
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          appL10n.gameTrafficSignalQuestion,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingM),
        row(_moves.sublist(0, 3), directional: true),
        const SizedBox(height: AppDimensions.spacingS),
        row(_moves.sublist(3), directional: false),
      ],
    );
  }

  static final List<_MoveSpec> _moves = [
    _MoveSpec(
      TrafficMove.left,
      Icons.turn_left_rounded,
      () => appL10n.gameActionLeft,
    ),
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

/// Направления идут слева направо, значок читается раньше подписи.
/// Высота растёт вместе со шрифтом, а вся плитка остаётся зоной нажатия.
class _TrafficMoveButton extends StatelessWidget {
  const _TrafficMoveButton({
    required this.spec,
    required this.directional,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.iconColor,
  });

  final _MoveSpec spec;
  final bool directional;
  final Color background;
  final Color foreground;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      spec.icon,
      size: directional ? AppDimensions.iconSize : AppDimensions.smallIconSize,
      color: iconColor ?? foreground,
    );
    final label = Text(
      spec.label,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: directional ? 14 : 16,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: spec.label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              constraints: BoxConstraints(
                minHeight: directional
                    ? AppDimensions.answerOptionHeight +
                          AppDimensions.spacingXXL
                    : AppDimensions.answerOptionHeight,
              ),
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingS,
                vertical: directional
                    ? AppDimensions.spacingM
                    : AppDimensions.spacingS,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
              ),
              child: directional
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        icon,
                        const SizedBox(height: AppDimensions.spacingS),
                        label,
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        icon,
                        const SizedBox(width: AppDimensions.spacingS),
                        Flexible(child: label),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
