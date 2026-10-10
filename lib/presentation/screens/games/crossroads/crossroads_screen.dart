import 'package:pdd_app/core/config/game_economy.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
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
  List<CrossroadsScenario> get _scenarios {
    final lang = ref.watch(
      appSettingsProvider.select((s) => s.effectiveLanguageCode),
    );
    return CrossroadsScenariosLibrary.getScenarios(lang);
  }

  int _scenarioIndex = 0;

  /// Перекрёстки раунда в случайном порядке: раньше каждый раунд шёл
  /// одной и той же цепочкой, и порядок проезда запоминался, а не решался.
  List<int> _order = const [];
  CrossroadsScenario get _curScenario {
    final list = _scenarios;
    if (_order.length != list.length) {
      _order = List.generate(list.length, (i) => i)..shuffle();
    }
    return list[_order[_scenarioIndex % _order.length]];
  }

  // Игровое состояние
  int _currentStep = 1;
  int _score = 0;
  String _ratingRunId = GameLeaderboardService.newRunId();
  int _combo = 0;
  int _maxComboInRound = 0;
  int _lives = GameEconomy.miniGameLives;
  int _secondsLeft = 45;
  int _solvedCount = 0;
  Timer? _countdownTimer;
  bool _isGameOver = false;
  bool _isNewRecord = false;
  int _previousBest = 0;
  int _wrongCount = 0;

  // Ошибка / разбор ДТП
  bool _showCollisionModal = false;
  String _collisionReason = '';
  String _collisionPddArticle = '';
  String _collisionShouldGo = '';

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
      _ratingRunId = GameLeaderboardService.newRunId();
      _combo = 0;
      _maxComboInRound = 0;
      _lives = GameEconomy.miniGameLives;
      _secondsLeft = 45;
      _solvedCount = 0;
      _wrongCount = 0;
      _isGameOver = false;
      _isNewRecord = false;
      _scenarioIndex = 0;
      _order = List.generate(_scenarios.length, (i) => i)..shuffle();
      _previousBest = ref.read(crossroadsPriorityProgressProvider).bestScore;
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
    if (_isGameOver) return;
    HapticFeedbackHelper.softSuccess();
    SoundEffectsService.instance.playCorrect();
    setState(() {
      _currentStep++;
    });
  }

  void _handleCollision(Map<String, dynamic> data) {
    if (_isGameOver) return;
    HapticFeedbackHelper.collision();
    SoundEffectsService.instance.playIncorrect();

    final reason = data['reason'] as String? ?? '';
    final pddArticle = data['pddArticle'] as String? ?? '';
    final priorityId = data['priorityId'] as String?;
    final shouldGo = _curScenario.actors
        .where((a) => a.id == priorityId)
        .map((a) => a.name)
        .firstOrNull;

    setState(() {
      _combo = 0;
      _wrongCount++;
      _collisionShouldGo = shouldGo ?? '';
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
    if (_isGameOver) return;
    HapticFeedbackHelper.success();
    SoundEffectsService.instance.playCorrect();

    final gainedScore = GameEconomy.crossroads(_combo + 1);

    setState(() {
      _solvedCount++;
      _combo++;
      if (_combo > _maxComboInRound) _maxComboInRound = _combo;
      _score = (_score + gainedScore).clamp(0, GameEconomy.maxRunScore);
      if (_mode == CrossroadsGameMode.arcade) {
        _secondsLeft = math.min(60, _secondsLeft + 6); // +6 сек бонус
      }
    });

    if (_mode == CrossroadsGameMode.arcade && _solvedCount >= 20) {
      _endGame();
      return;
    }

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
    if (_isGameOver) return;
    if (_mode == CrossroadsGameMode.arcade) {
      unawaited(
        GameLeaderboardService.instance.submitRun(
          GameEconomy.rankedScore(
            _score,
            correct: _solvedCount,
            wrong: GameEconomy.miniGameLives - _lives,
          ),
          runId: _ratingRunId,
        ),
      );
    }
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
              child: kIsWeb
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
                      icon: Icons.close_rounded,
                      onTap: () {
                        HapticFeedbackHelper.tap();
                        if (_mode == CrossroadsGameMode.arcade &&
                            _solvedCount > 0) {
                          _endGame();
                        }
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: AppDimensions.spacingM),
                    if (_mode == CrossroadsGameMode.arcade)
                      Expanded(child: _buildHud(colors))
                    else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.cardBackground,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.buttonRadius,
                          ),
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

  /// Счёт (звёзды), время и жизни (сердца) — единой плоской плашкой с фоном (как в Регулировщике).
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
          GameScoreLabel(score: _score, streak: _combo),
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
          GameLives(lives: _lives, total: GameEconomy.miniGameLives),
        ],
      ),
    );
  }

  /// Нижняя панель в стиле «Регулировщика»: без тени и обводок, крупные
  /// плитки участников с цветом их машины. Проехавшие — зелёные, с номером.
  Widget _buildBottomPanel(AppThemeColors colors) {
    final scenario = _curScenario;
    return Container(
      key: _panelKey,
      padding: EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        AppDimensions.spacingL,
        AppDimensions.screenPadding,
        MediaQuery.paddingOf(context).bottom + AppDimensions.spacingM,
      ),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusExtraLarge),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  scenario.title,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingS),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colors.lightAccent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  appL10n.gameCrossroadsStepOf(
                    math.min(_currentStep, scenario.actors.length),
                    scenario.actors.length,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingXS),
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
          const SizedBox(height: AppDimensions.spacingM),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppDimensions.spacingS;
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final actor in scenario.actors)
                    SizedBox(
                      width: width,
                      child: _ActorTile(
                        actor: actor,
                        done: actor.priorityOrder < _currentStep,
                        onTap: () {
                          HapticFeedbackHelper.tap();
                          _call('selectVehicle("${actor.id}")');
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Разбор ошибки: кто должен был ехать и почему, по пункту ПДД.
  Widget _buildCollisionModal(AppThemeColors colors) {
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          AppDimensions.screenPadding,
          AppDimensions.spacingXL,
          AppDimensions.screenPadding,
          MediaQuery.paddingOf(context).bottom + AppDimensions.spacingM,
        ),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppDimensions.radiusExtraLarge),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.redLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.car_crash_rounded,
                    color: colors.red,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingM),
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
            if (_collisionShouldGo.isNotEmpty) ...[
              const SizedBox(height: AppDimensions.spacingM),
              Text(
                appL10n.gameCrossroadsShouldGo(_collisionShouldGo),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
            ],
            const SizedBox(height: AppDimensions.spacingS),
            Text(
              _collisionReason,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: colors.primaryText,
              ),
            ),
            if (_collisionPddArticle.isNotEmpty) ...[
              const SizedBox(height: AppDimensions.spacingS),
              Text(
                _collisionPddArticle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
            ],
            const SizedBox(height: AppDimensions.spacingL),
            Row(
              children: [
                Expanded(
                  child: GameActionButton(
                    label: appL10n.gameCrossroadsRepeatCrossroad,
                    onTap: _retryCurrentScenario,
                    background: colors.gray,
                    foreground: colors.primaryText,
                    height: 52,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingS),
                Expanded(
                  child: GameActionButton(
                    label: appL10n.gameCrossroadsNextCrossroad,
                    onTap: _skipToNextScenario,
                    background: colors.accent,
                    foreground: colors.white,
                    height: 52,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Итог раунда — тот же экран, что у «Регулировщика» и основной игры.
  Widget _buildGameOverDialog(AppThemeColors colors) {
    final answered = _solvedCount + _wrongCount;
    final accuracy = answered > 0 ? (_solvedCount * 100 / answered).round() : 0;
    return Positioned.fill(
      child: GameResultOverlay(
        art: const CrossroadsArt(),
        title: _secondsLeft <= 1 ? appL10n.gameTimeUp : appL10n.gameOverTitle,
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
      ),
    );
  }
}

/// Плитка участника: цвет машины, иконка типа и название. Без обводки —
/// состояние передаёт заливка (серая — ждёт, зелёная — проехал).
class _ActorTile extends StatelessWidget {
  const _ActorTile({
    required this.actor,
    required this.done,
    required this.onTap,
  });

  final CrossroadsActor actor;
  final bool done;
  final VoidCallback onTap;

  Color get _carColor {
    final hex = actor.colorHex.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final icon = switch (actor.type) {
      CrossroadsVehicleType.tram => Icons.tram_rounded,
      CrossroadsVehicleType.emergency => Icons.emergency_rounded,
      CrossroadsVehicleType.police => Icons.local_police_rounded,
      CrossroadsVehicleType.truck => Icons.local_shipping_rounded,
      CrossroadsVehicleType.bus => Icons.directions_bus_rounded,
      CrossroadsVehicleType.motorcycle => Icons.two_wheeler_rounded,
      CrossroadsVehicleType.suv ||
      CrossroadsVehicleType.car => Icons.directions_car_rounded,
    };
    return Material(
      color: done ? colors.greenLight : colors.gray,
      borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        onTap: done ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? colors.green : _carColor,
                  shape: BoxShape.circle,
                ),
                child: done
                    ? Text(
                        '${actor.priorityOrder}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        icon,
                        size: 18,
                        color: _carColor.computeLuminance() > 0.6
                            ? const Color(0xFF2B2F36)
                            : Colors.white,
                      ),
              ),
              const SizedBox(width: AppDimensions.spacingS),
              Expanded(
                child: Text(
                  actor.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: done ? colors.green : colors.primaryText,
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
