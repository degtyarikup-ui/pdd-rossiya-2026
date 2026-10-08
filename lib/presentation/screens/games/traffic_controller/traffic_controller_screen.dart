import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/traffic_controller_rules.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

enum GamePlayMode {
  training,
  arcade,
}

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
  bool _engineReady = false;

  // Режим обучения (выбранное состояние)
  ControllerGesture _curGesture = ControllerGesture.rightArmForward;
  ApproachDirection _curApproach = ApproachDirection.left;
  VehicleKind _curVehicle = VehicleKind.car;
  String _cameraMode = 'overview'; // 'overview' | 'driver'

  // Режим Блиц-аркада
  int _score = 0;
  int _combo = 0;
  int _maxComboInRound = 0;
  int _lives = 3;
  int _secondsLeft = 35;
  int _solvedCount = 0;
  Timer? _countdownTimer;
  bool _isGameOver = false;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    if (!kIsWeb) {
      _initWebView();
    }
    if (_mode == GamePlayMode.arcade) {
      _startArcadeRound();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _initWebView() {
    final params = const PlatformWebViewControllerCreationParams();
    final controller = WebViewController.fromPlatformCreationParams(params);

    if (controller.platform is AndroidWebViewController) {
      final androidController =
          controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF131722))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _updateEngineScenario();
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: _onJsMessageReceived,
      )
      ..loadFlutterAsset('assets/game/traffic-controller.html');

    _webViewController = controller;
  }

  void _onJsMessageReceived(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == 'ready') {
        if (mounted) {
          setState(() => _engineReady = true);
          _updateEngineScenario();
        }
      }
    } catch (_) {}
  }

  void _runJs(String code) {
    if (_webViewController != null && _engineReady) {
      _webViewController!.runJavaScript(code).ignore();
    }
  }

  void _updateEngineScenario() {
    final gestureStr = switch (_curGesture) {
      ControllerGesture.handsDownOrSides => 'handsDownOrSides',
      ControllerGesture.rightArmForward => 'rightArmForward',
      ControllerGesture.armUp => 'armUp',
    };
    final approachStr = switch (_curApproach) {
      ApproachDirection.front => 'front',
      ApproachDirection.back => 'back',
      ApproachDirection.left => 'left',
      ApproachDirection.right => 'right',
    };
    final vehicleStr = switch (_curVehicle) {
      VehicleKind.car => 'car',
      VehicleKind.tram => 'tram',
    };
    final modeStr = _mode == GamePlayMode.training ? 'training' : 'arcade';

    _runJs(
      'window.TrafficControllerGame && window.TrafficControllerGame.setMode("$modeStr");',
    );
    _runJs(
      'window.TrafficControllerGame && window.TrafficControllerGame.setScenario("$gestureStr", "$approachStr", "$vehicleStr");',
    );
    _runJs(
      'window.TrafficControllerGame && window.TrafficControllerGame.setCameraView("$_cameraMode");',
    );
  }

  void _switchMode(GamePlayMode mode) {
    if (_mode == mode) return;
    HapticFeedbackHelper.select();
    _countdownTimer?.cancel();

    setState(() {
      _mode = mode;
      if (_mode == GamePlayMode.arcade) {
        _startArcadeRound();
      } else {
        _isGameOver = false;
        _updateEngineScenario();
      }
    });
  }

  void _startArcadeRound() {
    _score = 0;
    _combo = 0;
    _maxComboInRound = 0;
    _lives = 3;
    _secondsLeft = 35;
    _solvedCount = 0;
    _isGameOver = false;

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsLeft > 1) {
          _secondsLeft--;
        } else {
          _secondsLeft = 0;
          _endArcadeGame();
        }
      });
    });

    _nextArcadeSituation();
  }

  void _nextArcadeSituation() {
    // Выбираем случайную комбинацию
    final gestures = ControllerGesture.values;
    final approaches = ApproachDirection.values;

    _curGesture = gestures[_random.nextInt(gestures.length)];
    _curApproach = approaches[_random.nextInt(approaches.length)];
    // В 70% случаев авто, в 30% трамвай
    _curVehicle = _random.nextDouble() < 0.7
        ? VehicleKind.car
        : VehicleKind.tram;

    _updateEngineScenario();
  }

  void _onArcadeMoveSelected(TrafficMove move) {
    if (_isGameOver) return;

    final isAllowed = TrafficControllerRules.isMoveAllowed(
      gesture: _curGesture,
      approach: _curApproach,
      vehicle: _curVehicle,
      move: move,
    );

    final moveStr = switch (move) {
      TrafficMove.straight => 'straight',
      TrafficMove.right => 'right',
      TrafficMove.left => 'left',
      TrafficMove.uTurn => 'uTurn',
      TrafficMove.none => 'none',
    };

    _runJs(
      'window.TrafficControllerGame && window.TrafficControllerGame.makeMove("$moveStr");',
    );

    if (isAllowed) {
      HapticFeedbackHelper.tap();
      SoundEffectsService.instance.playCorrect();
      setState(() {
        _combo++;
        if (_combo > _maxComboInRound) _maxComboInRound = _combo;
        _score += 100 * _combo;
        _solvedCount++;
        _secondsLeft = math.min(_secondsLeft + 3, 60);
      });
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted && !_isGameOver) {
          _nextArcadeSituation();
        }
      });
    } else {
      HapticFeedbackHelper.error();
      SoundEffectsService.instance.playIncorrect();
      setState(() {
        _combo = 0;
        _lives--;
        if (_lives <= 0) {
          _endArcadeGame();
        }
      });
      if (_lives > 0) {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted && !_isGameOver) {
            _nextArcadeSituation();
          }
        });
      }
    }
  }

  void _endArcadeGame() {
    _countdownTimer?.cancel();
    setState(() => _isGameOver = true);

    ref
        .read(trafficControllerProgressProvider.notifier)
        .recordGameResult(
          score: _score,
          combo: _maxComboInRound,
          solved: _solvedCount,
        );
  }

  void _onTrainingMoveTest(TrafficMove move) {
    HapticFeedbackHelper.select();
    final moveStr = switch (move) {
      TrafficMove.straight => 'straight',
      TrafficMove.right => 'right',
      TrafficMove.left => 'left',
      TrafficMove.uTurn => 'uTurn',
      TrafficMove.none => 'none',
    };
    _runJs(
      'window.TrafficControllerGame && window.TrafficControllerGame.makeMove("$moveStr");',
    );
  }

  void _toggleCamera() {
    HapticFeedbackHelper.select();
    setState(() {
      _cameraMode = (_cameraMode == 'overview') ? 'driver' : 'overview';
    });
    _runJs(
      'window.TrafficControllerGame && window.TrafficControllerGame.setCameraView("$_cameraMode");',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF11141A),
      body: SafeArea(
        child: Stack(
          children: [
            // 3D Canvas
            Positioned.fill(
              child: _webViewController != null
                  ? WebViewWidget(controller: _webViewController!)
                  : const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
            ),

            // Top HUD Overlay
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: _buildTopBar(colors),
            ),

            // Bottom Controls Overlay
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _mode == GamePlayMode.training
                  ? _buildTrainingControls(colors)
                  : _buildArcadeControls(colors),
            ),

            // Game Over Dialog
            if (_isGameOver) _buildGameOverOverlay(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(AppThemeColors colors) {
    return Row(
      children: [
        AppChromeIconButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.of(context).pop(),
          backgroundColor: Colors.black.withValues(alpha: 0.55),
        ),
        const SizedBox(width: 8),

        // Mode switch pill
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeTab(
                label: appL10n.gameModeTraining,
                mode: GamePlayMode.training,
              ),
              _buildModeTab(
                label: appL10n.gameModeArcade,
                mode: GamePlayMode.arcade,
              ),
            ],
          ),
        ),

        const Spacer(),

        // Camera toggle
        AppChromeIconButton(
          icon: _cameraMode == 'overview'
              ? Icons.videocam_rounded
              : Icons.drive_eta_rounded,
          onTap: _toggleCamera,
          backgroundColor: Colors.black.withValues(alpha: 0.55),
        ),
      ],
    );
  }

  Widget _buildModeTab({
    required String label,
    required GamePlayMode mode,
  }) {
    final active = _mode == mode;
    return GestureDetector(
      onTap: () => _switchMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  // --- Контролы режима «Обучение» ---
  Widget _buildTrainingControls(AppThemeColors colors) {
    final verse = TrafficControllerRules.mnemonicVerse(
      gesture: _curGesture,
      approach: _curApproach,
      vehicle: _curVehicle,
    );
    final officialRule = TrafficControllerRules.officialRuleDescription(
      gesture: _curGesture,
      approach: _curApproach,
      vehicle: _curVehicle,
    );
    final allowed = TrafficControllerRules.allowedMoves(
      gesture: _curGesture,
      approach: _curApproach,
      vehicle: _curVehicle,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xE61A202C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Стишок-мнемоника
          if (verse.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_stories_rounded,
                    color: AppColors.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      verse,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Переключатель жестов
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPillChoice(
                  title: 'Рука вперёд',
                  selected: _curGesture == ControllerGesture.rightArmForward,
                  onTap: () {
                    setState(
                      () => _curGesture = ControllerGesture.rightArmForward,
                    );
                    _updateEngineScenario();
                  },
                ),
                const SizedBox(width: 6),
                _buildPillChoice(
                  title: 'Руки в стороны',
                  selected: _curGesture == ControllerGesture.handsDownOrSides,
                  onTap: () {
                    setState(
                      () => _curGesture = ControllerGesture.handsDownOrSides,
                    );
                    _updateEngineScenario();
                  },
                ),
                const SizedBox(width: 6),
                _buildPillChoice(
                  title: 'Рука вверх',
                  selected: _curGesture == ControllerGesture.armUp,
                  onTap: () {
                    setState(() => _curGesture = ControllerGesture.armUp);
                    _updateEngineScenario();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Ракурс регулировщика
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPillChoice(
                  title: 'Слева',
                  selected: _curApproach == ApproachDirection.left,
                  onTap: () {
                    setState(() => _curApproach = ApproachDirection.left);
                    _updateEngineScenario();
                  },
                ),
                const SizedBox(width: 6),
                _buildPillChoice(
                  title: 'С груди',
                  selected: _curApproach == ApproachDirection.front,
                  onTap: () {
                    setState(() => _curApproach = ApproachDirection.front);
                    _updateEngineScenario();
                  },
                ),
                const SizedBox(width: 6),
                _buildPillChoice(
                  title: 'Справа',
                  selected: _curApproach == ApproachDirection.right,
                  onTap: () {
                    setState(() => _curApproach = ApproachDirection.right);
                    _updateEngineScenario();
                  },
                ),
                const SizedBox(width: 6),
                _buildPillChoice(
                  title: 'Со спины',
                  selected: _curApproach == ApproachDirection.back,
                  onTap: () {
                    setState(() => _curApproach = ApproachDirection.back);
                    _updateEngineScenario();
                  },
                ),
                const SizedBox(width: 12),
                // Выбор: авто или трамвай
                _buildPillChoice(
                  icon: Icons.directions_car_rounded,
                  title: appL10n.gameVehicleCar,
                  selected: _curVehicle == VehicleKind.car,
                  onTap: () {
                    setState(() => _curVehicle = VehicleKind.car);
                    _updateEngineScenario();
                  },
                ),
                const SizedBox(width: 6),
                _buildPillChoice(
                  icon: Icons.tram_rounded,
                  title: appL10n.gameVehicleTram,
                  selected: _curVehicle == VehicleKind.tram,
                  onTap: () {
                    setState(() => _curVehicle = VehicleKind.tram);
                    _updateEngineScenario();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Кнопки тестового проезда
          Row(
            children: [
              _buildMoveTestBtn(
                label: appL10n.gameActionStraight,
                isAllowed: allowed.contains(TrafficMove.straight),
                onTap: () => _onTrainingMoveTest(TrafficMove.straight),
              ),
              const SizedBox(width: 6),
              _buildMoveTestBtn(
                label: appL10n.gameActionRight,
                isAllowed: allowed.contains(TrafficMove.right),
                onTap: () => _onTrainingMoveTest(TrafficMove.right),
              ),
              const SizedBox(width: 6),
              _buildMoveTestBtn(
                label: appL10n.gameActionLeft,
                isAllowed: allowed.contains(TrafficMove.left),
                onTap: () => _onTrainingMoveTest(TrafficMove.left),
              ),
              const SizedBox(width: 6),
              _buildMoveTestBtn(
                label: appL10n.gameActionStand,
                isAllowed: allowed.contains(TrafficMove.none),
                onTap: () => _onTrainingMoveTest(TrafficMove.none),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Пояснение официального пункта
          Text(
            officialRule,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPillChoice({
    IconData? icon,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white10,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoveTestBtn({
    required String label,
    required bool isAllowed,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isAllowed
                ? const Color(0xFF00E676).withValues(alpha: 0.25)
                : Colors.white10,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isAllowed ? const Color(0xFF00E676) : Colors.white24,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isAllowed ? const Color(0xFF00E676) : Colors.white60,
                ),
              ),
              Icon(
                isAllowed ? Icons.check_circle_rounded : Icons.block_rounded,
                size: 14,
                color: isAllowed ? const Color(0xFF00E676) : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Контролы режима «Блиц-аркада» ---
  Widget _buildArcadeControls(AppThemeColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Статистика: счёт, таймер, комбо, жизни
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Счёт и комбо
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${appL10n.gameScore}: $_score',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  if (_combo > 1)
                    Text(
                      '${appL10n.gameCombo} x$_combo 🔥',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.orangeAccent,
                      ),
                    ),
                ],
              ),

              // Таймер
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _secondsLeft <= 10
                      ? Colors.redAccent.withValues(alpha: 0.3)
                      : Colors.white12,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _secondsLeft <= 10
                        ? Colors.redAccent
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: _secondsLeft <= 10
                          ? Colors.redAccent
                          : Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_secondsLeft с',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _secondsLeft <= 10
                            ? Colors.redAccent
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Жизни (3 сердца)
              Row(
                children: List.generate(3, (i) {
                  final alive = i < _lives;
                  return Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Icon(
                      alive
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 20,
                      color: alive ? Colors.redAccent : Colors.white24,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Вопрос
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xE61A202C),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _curVehicle == VehicleKind.car
                    ? Icons.directions_car_rounded
                    : Icons.tram_rounded,
                size: 18,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                _curVehicle == VehicleKind.car
                    ? 'Куда разрешено поехать автомобилю?'
                    : 'Куда разрешено поехать трамваю?',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Кнопки быстрого выбора
        Row(
          children: [
            _buildArcadeButton(
              label: appL10n.gameActionStraight,
              icon: Icons.straight_rounded,
              onTap: () => _onArcadeMoveSelected(TrafficMove.straight),
            ),
            const SizedBox(width: 8),
            _buildArcadeButton(
              label: appL10n.gameActionRight,
              icon: Icons.turn_right_rounded,
              onTap: () => _onArcadeMoveSelected(TrafficMove.right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildArcadeButton(
              label: appL10n.gameActionLeft,
              icon: Icons.turn_left_rounded,
              onTap: () => _onArcadeMoveSelected(TrafficMove.left),
            ),
            const SizedBox(width: 8),
            _buildArcadeButton(
              label: appL10n.gameActionStand,
              icon: Icons.front_hand_rounded,
              onTap: () => _onArcadeMoveSelected(TrafficMove.none),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildArcadeButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF222938),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.white24),
          ),
          elevation: 4,
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  // --- Оверлей окончания игры ---
  Widget _buildGameOverOverlay(AppThemeColors colors) {
    final progress = ref.watch(trafficControllerProgressProvider);
    final isNewRecord = _score > progress.bestScore;

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Colors.amber,
                size: 54,
              ),
              const SizedBox(height: 12),
              Text(
                appL10n.gameOverTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (isNewRecord)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    appL10n.gameOverNewRecord,
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                appL10n.gameOverScore(_score),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${appL10n.gameComboLabel}: $_maxComboInRound  •  ${appL10n.gameSolvedLabel}: $_solvedCount',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(appL10n.gameExit),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _startArcadeRound,
                      child: Text(appL10n.gamePlayAgain),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
