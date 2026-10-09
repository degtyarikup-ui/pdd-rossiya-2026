import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/crossroads_priority_model.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/platform/browser_game.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_art.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

enum CrossroadsGameMode { arcade, training }

class CrossroadsScreen extends ConsumerStatefulWidget {
  const CrossroadsScreen({super.key});

  @override
  ConsumerState<CrossroadsScreen> createState() => _CrossroadsScreenState();
}

class _CrossroadsScreenState extends ConsumerState<CrossroadsScreen> {
  WebViewController? _webViewController;
  BrowserGame? _browserGame;
  bool _engineReady = false;

  // Режим игры
  CrossroadsGameMode _mode = CrossroadsGameMode.arcade;

  // Сценарии
  final List<CrossroadsScenario> _scenarios =
      CrossroadsScenariosLibrary.allScenarios;
  int _scenarioIndex = 0;
  CrossroadsScenario get _curScenario => _scenarios[_scenarioIndex];

  // Игровое состояние
  int _currentStep = 1;
  int _score = 0;
  int _combo = 0;
  int _maxComboInRound = 0;
  int _lives = 3;
  int _secondsLeft = 45;
  int _solvedCount = 0;
  Timer? _countdownTimer;
  bool _isGameOver = false;
  bool _isNewRecord = false;

  // Ошибка / разбор ДТП
  bool _showCollisionModal = false;
  String _collisionReason = '';
  String _collisionPddArticle = '';

  // Камера и зум
  static const double _minZoom = 0.5;
  static const double _maxZoom = 2.5;
  double _zoom = 1.0;
  double _zoomAtStart = 1.0;

  // Высота нижней панели
  final GlobalKey _panelKey = GlobalKey();
  double _sentInset = -1;
  double _panelHeight = 0;

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
    if (kIsWeb) {
      _browserGame?.dispose();
    }
    super.dispose();
  }

  // --- Мост с Three.js ---

  void _initWebGame() {
    final browser = BrowserGame(
      onMessage: _handleBridgeMessage,
      onBlur: () {},
      onKey: (_, _, _) {},
      htmlPath: 'assets/assets/game/crossroads.html?flutterWeb=1',
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
        NavigationDelegate(onPageFinished: (_) => _sendScenarioToEngine()),
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      )
      ..loadFlutterAsset('assets/game/crossroads.html');

    _webViewController = controller;
  }

  void _handleBridgeMessage(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;

      final type = data['type'] as String?;
      if (type == 'ready' && mounted && !_engineReady) {
        setState(() => _engineReady = true);
        _syncViewInset();
        _call('setZoom($_zoom)');
        _sendScenarioToEngine();
        if (_mode == CrossroadsGameMode.arcade) {
          _startArcadeRound();
        }
      } else if (type == 'step_correct') {
        _handleCorrectStep(data);
      } else if (type == 'collision') {
        _handleCollision(data);
      } else if (type == 'crossroad_complete') {
        _handleCrossroadComplete();
      }
    } catch (_) {
      // Игнорируем поврежденные сообщения
    }
  }

  void _call(String js) {
    if (kIsWeb) {
      _browserGame?.runJavaScript(js).ignore();
    } else {
      _webViewController?.runJavaScript(js);
    }
  }

  void _sendScenarioToEngine() {
    if (!_engineReady) return;
    setState(() => _currentStep = 1);
    final jsonStr = jsonEncode(_curScenario.toJson());
    _call('loadScenarioData($jsonStr)');
  }

  void _syncViewInset() {
    if (!mounted || !_engineReady) return;
    final renderBox =
        _panelKey.currentContext?.findRenderObject() as RenderBox?;
    final newHeight = renderBox?.size.height ?? 0;
    if (newHeight != _panelHeight) {
      _panelHeight = newHeight;
    }
    final targetInset = _panelHeight * MediaQuery.devicePixelRatioOf(context);
    if ((targetInset - _sentInset).abs() > 2) {
      _sentInset = targetInset;
      _call('setViewInset($targetInset)');
    }
  }

  // --- Игровой процесс ---

  void _startArcadeRound() {
    _countdownTimer?.cancel();
    setState(() {
      _mode = CrossroadsGameMode.arcade;
      _score = 0;
      _combo = 0;
      _maxComboInRound = 0;
      _lives = 3;
      _secondsLeft = 45;
      _solvedCount = 0;
      _isGameOver = false;
      _isNewRecord = false;
      _scenarioIndex = 0;
      _currentStep = 1;
    });
    _sendScenarioToEngine();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        _endGame();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _handleCorrectStep(Map<String, dynamic> data) {
    HapticFeedbackHelper.softSuccess();
    SoundEffectsService.instance.playCorrect();
    setState(() {
      _currentStep++;
    });
  }

  void _handleCollision(Map<String, dynamic> data) {
    HapticFeedbackHelper.collision();
    SoundEffectsService.instance.playIncorrect();

    final reason = data['reason'] as String? ?? '';
    final pddArticle = data['pddArticle'] as String? ?? '';

    setState(() {
      _combo = 0;
      _collisionReason = reason;
      _collisionPddArticle = pddArticle;
      _showCollisionModal = true;
      if (_mode == CrossroadsGameMode.arcade) {
        _lives--;
        if (_lives <= 0) {
          _endGame();
        }
      }
    });
  }

  void _handleCrossroadComplete() {
    HapticFeedbackHelper.success();
    SoundEffectsService.instance.playCorrect();

    final comboBonus = (_combo * 25);
    final gainedScore = 100 + comboBonus;

    setState(() {
      _solvedCount++;
      _combo++;
      if (_combo > _maxComboInRound) _maxComboInRound = _combo;
      _score += gainedScore;
      if (_mode == CrossroadsGameMode.arcade) {
        _secondsLeft = math.min(60, _secondsLeft + 6); // +6 сек бонус
      }
    });

    // Следующий перекресток
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _isGameOver) return;
      setState(() {
        _scenarioIndex = (_scenarioIndex + 1) % _scenarios.length;
      });
      _sendScenarioToEngine();
    });
  }

  void _endGame() {
    _countdownTimer?.cancel();
    final progress = ref.read(crossroadsPriorityProgressProvider);
    final isNewRecord = _score > progress.bestScore;

    setState(() {
      _isGameOver = true;
      _isNewRecord = isNewRecord;
    });

    ref
        .read(crossroadsPriorityProgressProvider.notifier)
        .recordGameResult(
          score: _score,
          combo: _maxComboInRound,
          solved: _solvedCount,
        );
  }

  void _retryCurrentScenario() {
    setState(() {
      _showCollisionModal = false;
      _currentStep = 1;
    });
    _call('resetCurrentScenario()');
  }

  void _skipToNextScenario() {
    setState(() {
      _showCollisionModal = false;
      _scenarioIndex = (_scenarioIndex + 1) % _scenarios.length;
      _currentStep = 1;
    });
    _sendScenarioToEngine();
  }

  // --- Виджеты UI ---

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncViewInset());

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Центральная 3D-сцена
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: (details) {
                _zoomAtStart = _zoom;
              },
              onScaleUpdate: (details) {
                if (details.pointerCount >= 2) {
                  final newZoom = (_zoomAtStart * details.scale).clamp(
                    _minZoom,
                    _maxZoom,
                  );
                  if ((newZoom - _zoom).abs() > 0.02) {
                    setState(() => _zoom = newZoom);
                    _call('setZoom($_zoom)');
                  }
                }
              },
              child:
                  kIsWeb
                      ? (_browserGame?.widget ?? const SizedBox())
                      : (_webViewController != null
                          ? WebViewWidget(controller: _webViewController!)
                          : const SizedBox()),
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

          // 2. Верхняя панель (Header)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.screenPadding,
                  vertical: 8,
                ),
                child: Row(
                children: [
                  AppChromeIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppDimensions.spacingM),
                  if (_mode == CrossroadsGameMode.arcade) ...[
                    GameLives(lives: _lives),
                    const Spacer(),
                    GameScoreLabel(
                      score: _score,
                      multiplier: _combo > 1 ? _combo : 1,
                    ),
                    const SizedBox(width: AppDimensions.spacingM),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.cardBackground.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(
                          AppDimensions.radiusSmall,
                        ),
                        boxShadow: gameSoftShadow(colors),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 16,
                            color:
                                _secondsLeft <= 10
                                    ? colors.red
                                    : colors.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            appL10n.gameSecondsLeft(_secondsLeft),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color:
                                  _secondsLeft <= 10
                                      ? colors.red
                                      : colors.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.cardBackground.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(
                          AppDimensions.radiusSmall,
                        ),
                        boxShadow: gameSoftShadow(colors),
                      ),
                      child: Text(
                        appL10n.gameCrossroadsModeTraining,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      onPressed: () {
                        setState(() {
                          _scenarioIndex =
                              (_scenarioIndex - 1 + _scenarios.length) %
                              _scenarios.length;
                        });
                        _sendScenarioToEngine();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios_rounded),
                      onPressed: () {
                        setState(() {
                          _scenarioIndex =
                              (_scenarioIndex + 1) % _scenarios.length;
                        });
                        _sendScenarioToEngine();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

          // 3. Нижняя панель управления и подсказок
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(colors),
          ),

          // 4. Модальная шторка ДТП (при ошибке очередности)
          if (_showCollisionModal) _buildCollisionModal(colors),

          // 5. Финальный экран GameOver / NewRecord
          if (_isGameOver) _buildGameOverDialog(colors),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(AppThemeColors colors) {
    return Container(
      key: _panelKey,
      padding: EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        14,
        AppDimensions.screenPadding,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      decoration: BoxDecoration(
        color: colors.cardBackground.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimensions.cardRadius),
        ),
        boxShadow: gameSoftShadow(colors),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _curScenario.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  appL10n.gameCrossroadsStepOf(
                    _currentStep,
                    _curScenario.actors.length,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _currentStep == 1
                ? appL10n.gameCrossroadsPromptWhoGoesFirst
                : appL10n.gameCrossroadsPromptWhoGoesNext(_currentStep),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          // Миниатюры участников
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _curScenario.actors.map((actor) {
                  final isDone = actor.priorityOrder < _currentStep;
                  return InkWell(
                    onTap: isDone
                        ? null
                        : () {
                            HapticFeedbackHelper.tap();
                            _call('selectVehicle("${actor.id}")');
                          },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isDone
                                ? colors.green.withValues(alpha: 0.12)
                                : colors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              isDone
                                  ? colors.green
                                  : colors.divider.withValues(alpha: 0.5),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDone
                                ? Icons.check_circle_rounded
                                : (actor.type == CrossroadsVehicleType.tram
                                    ? Icons.tram_rounded
                                    : (actor.type ==
                                            CrossroadsVehicleType.emergency
                                        ? Icons.emergency_rounded
                                        : Icons.directions_car_rounded)),
                            size: 16,
                            color: isDone ? colors.green : colors.primaryText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            actor.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDone
                                      ? colors.green
                                      : colors.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCollisionModal(AppThemeColors colors) {
    return Container(
      color: Colors.black.withValues(alpha: 0.54),
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(AppDimensions.screenPadding),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            boxShadow: gameSoftShadow(colors),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.red.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: colors.red,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      appL10n.gameCrossroadsCollision,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: colors.red,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_collisionPddArticle.isNotEmpty) ...[
                Text(
                  _collisionPddArticle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                _collisionReason,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _retryCurrentScenario,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusSmall,
                          ),
                        ),
                      ),
                      child: Text(appL10n.gameCrossroadsRepeatCrossroad),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _skipToNextScenario,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusSmall,
                          ),
                        ),
                      ),
                      child: Text(appL10n.gameCrossroadsNextCrossroad),
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

  Widget _buildGameOverDialog(AppThemeColors colors) {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      child: Material(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 120,
                width: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.all(
                    Radius.circular(AppDimensions.cardRadius),
                  ),
                  child: CrossroadsArt(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isNewRecord
                    ? appL10n.gameOverNewRecord
                    : appL10n.gameOverTitle,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _isNewRecord ? colors.gold : colors.primaryText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appL10n.gameCrossroadsSolvedCount(_solvedCount),
                style: TextStyle(fontSize: 14, color: colors.secondaryText),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statItem(
                    colors,
                    appL10n.gameBestScoreLabel,
                    '$_score',
                    colors.accent,
                  ),
                  _statItem(
                    colors,
                    appL10n.gameComboLabel,
                    'x$_maxComboInRound',
                    colors.gold,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _startArcadeRound,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(appL10n.gamePlayAgain),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDimensions.buttonRadius,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(
    AppThemeColors colors,
    String label,
    String value,
    Color valColor,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: valColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: colors.secondaryText),
        ),
      ],
    );
  }
}
