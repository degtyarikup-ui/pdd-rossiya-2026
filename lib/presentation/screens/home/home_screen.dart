import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/navigation/route_observer.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/app_update_service.dart';
import 'package:pdd_app/presentation/widgets/app_update_dialog.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/data/services/review_prompt_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/exam/exam_screen.dart';
import 'package:pdd_app/presentation/screens/favorites/favorites_screen.dart';
import 'package:pdd_app/presentation/screens/mistakes/mistakes_screen.dart';
import 'package:pdd_app/presentation/screens/feed/feed_screen.dart';
import 'package:pdd_app/presentation/screens/game/game_screen.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_screen.dart';
import 'package:pdd_app/presentation/screens/profile/profile_screen.dart';
import 'package:pdd_app/presentation/screens/tickets/tickets_screen.dart';
import 'package:pdd_app/presentation/screens/topics/topics_screen.dart';
import 'package:pdd_app/presentation/widgets/app_notice_widgets.dart';
import 'package:pdd_app/presentation/widgets/premium_granted_dialog.dart';
import 'package:pdd_app/presentation/widgets/web_payment_return.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdd_app/presentation/widgets/sign_in_required_view.dart';
import 'package:pdd_app/presentation/widgets/streak_celebration_dialog.dart';
import 'package:pdd_app/presentation/widgets/continue_session_card.dart';
import 'package:pdd_app/presentation/widgets/exam_hero_card.dart';
import 'package:pdd_app/presentation/widgets/progress_panel_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  late int _currentIndex;
  StreamSubscription<DateTime?>? _premiumGrantSub;
  Timer? _grantPoll;
  bool _noticeOpen = false;
  bool _updateChecking = false;
  bool _updateCheckQueued = false;
  bool _routeSubscribed = false;
  StreamSubscription<void>? _updateSub;
  StreamSubscription<NoticeTap>? _tapSub;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _updateSub = ref.read(appUpdateServiceProvider).changes.listen((_) {
      if (_updateChecking || _noticeOpen) {
        _updateCheckQueued = true;
      } else {
        unawaited(_checkNotices());
      }
    });
    _subscribePremiumGrant();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkNotices());
      // Веб: возврат с формы оплаты (?pay=done&order=…).
      if (mounted) unawaited(handleWebPaymentReturn(context));
    });
    WidgetsBinding.instance.addObserver(this);
    _tapSub = RemoteNotificationsService.instance.taps.listen(
      (tap) => unawaited(_runNoticeTap(tap)),
    );
    // A Premium granted from the admin panel shows up while the app is open
    // (a read-only check, no write on the server).
    _grantPoll = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(PremiumService.instance.checkForGrant());
      unawaited(_checkNotices());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(PremiumService.instance.checkForGrant());
      unawaited(_checkNotices());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_routeSubscribed && route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkNotices());
    });
  }

  bool get _canShowNotice {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        !_noticeOpen &&
        _currentIndex == 0 &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        ModalRoute.of(context)?.isCurrent == true &&
        !PremiumService.instance.hasPendingGrant;
  }

  Future<bool> _checkUpdate() async {
    if (_updateChecking) return false;
    _updateChecking = true;
    var ownsModal = false;
    try {
      final service = ref.read(appUpdateServiceProvider);
      final offer = await service.check();
      if (offer == null ||
          !_canShowNotice ||
          !await service.shouldShow(offer) ||
          !_canShowNotice ||
          !mounted) {
        return false;
      }
      _noticeOpen = true;
      ownsModal = true;
      // Show synchronously after checking route/lifecycle. Record presentation,
      // including swipe/back dismissal, without delaying the dialog on disk I/O.
      final result = AppUpdateDialog.show(context, offer);
      unawaited(service.markShown(offer));
      final accepted = await result;
      if (accepted && mounted) {
        final opened = await service.update(offer);
        if (!opened && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(appL10n.appUpdateOpenFailed)));
        }
      }
      return true;
    } catch (_) {
      return false; // Update checks must not prevent offline training.
    } finally {
      if (ownsModal) _noticeOpen = false;
      _updateChecking = false;
      _retryQueuedUpdate();
    }
  }

  void _retryQueuedUpdate() {
    if (!mounted || _noticeOpen || _updateChecking || !_updateCheckQueued) {
      return;
    }
    _updateCheckQueued = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkNotices());
    });
  }

  Future<void> _checkNotices() async {
    if (!mounted || _updateChecking || _noticeOpen) return;
    final service = RemoteNotificationsService.instance;
    final launchTap = service.takePendingTap();
    if (launchTap != null) {
      await _runNoticeTap(launchTap);
      return;
    }
    if (await _checkUpdate()) return;
    await service.refresh();
    final pending = service.takePendingTap();
    if (pending != null && mounted) {
      await _runNoticeTap(pending);
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        _noticeOpen ||
        _currentIndex != 0 ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        ModalRoute.of(context)?.isCurrent != true ||
        PremiumService.instance.hasPendingGrant) {
      return;
    }
    final notice = service.nextNotice;
    if (notice == null) return;
    _noticeOpen = true;
    try {
      await service.markSeen(notice.id);
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          _currentIndex != 0) {
        return;
      }
      final accepted = await AppNoticeDialog.show(context, notice);
      final tap = notice.tap;
      if (accepted && tap != null && mounted) await _runNoticeTap(tap);
    } finally {
      _noticeOpen = false;
      _retryQueuedUpdate();
    }
  }

  /// Executes the action attached to a popup / banner / push.
  Future<void> _runNoticeTap(NoticeTap tap) async {
    if (!mounted) return;
    void tab(int index) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() => _currentIndex = index);
    }

    switch (tap.action) {
      case NoticeAction.none:
        return;
      case NoticeAction.url:
        try {
          await launchUrl(
            Uri.parse(tap.url),
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {
          /* ignore unlaunchable external links */
        }
      case NoticeAction.game:
        tab(1);
      case NoticeAction.feed:
        tab(3);
      case NoticeAction.settings:
        tab(4);
      case NoticeAction.tickets || NoticeAction.topics:
        tab(0);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => tap.action == NoticeAction.tickets
                ? const TicketsScreen()
                : const TopicsScreen(),
          ),
        );
    }
  }

  void _subscribePremiumGrant() {
    _premiumGrantSub = PremiumService.instance.onPremiumGrantedStream.listen((
      expiresAt,
    ) {
      if (!mounted) return;
      _showPremiumGrantedDialog(expiresAt);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (PremiumService.instance.hasPendingGrant) {
        final pendingExp =
            PremiumService.instance.pendingGrantNotificationExpiresAt;
        PremiumService.instance.consumePendingGrantNotification();
        _showPremiumGrantedDialog(pendingExp);
      }
    });
  }

  void _showPremiumGrantedDialog(DateTime? expiresAt) {
    PremiumService.instance.consumePendingGrantNotification();
    PremiumGrantedDialog.show(
      context,
      expiresAt: expiresAt,
      message: PremiumService.instance.grantMessage,
    );
  }

  @override
  void dispose() {
    _premiumGrantSub?.cancel();
    _grantPoll?.cancel();
    _tapSub?.cancel();
    _updateSub?.cancel();
    if (_routeSubscribed) appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Only the game is kept alive off-screen (paused) so a run survives a tab
  // switch; every other tab is built only while shown, so e.g. the feed's
  // autoplay, voice-over and sounds stop the moment you leave it.
  static const _gameTab = 1;
  bool _gameVisited = false;

  List<Widget> get _screens => [
    _HomeTab(onNoticeTap: _runNoticeTap),
    GameScreen(
      onExit: () {
        setState(() => _currentIndex = 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_checkNotices());
        });
      },
      visible: _currentIndex == 1,
    ),
    const GamesHubScreen(),
    if (ref.watch(isAuthenticatedProvider))
      const FeedScreen()
    else
      SignInRequiredView(
        icon: Icons.style_rounded,
        title: appL10n.feedLockedTitle,
        body: appL10n.feedLockedBody,
      ),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: colors.cardBackground,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: colors.homeScreenBackground,
        body: Builder(
          builder: (context) {
            if (_currentIndex == _gameTab) _gameVisited = true;
            final screens = _screens;
            return IndexedStack(
              index: _currentIndex,
              children: [
                for (var i = 0; i < screens.length; i++)
                  i == _currentIndex || (i == _gameTab && _gameVisited)
                      ? screens[i]
                      : const SizedBox.shrink(),
              ],
            );
          },
        ),
        bottomNavigationBar: ref.watch(fullscreenProvider)
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(height: 1, color: colors.divider),
                  NavigationBar(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (index) {
                      if (index == _currentIndex) return;
                      TtsService.instance.stop();
                      HapticFeedbackHelper.select();
                      setState(() => _currentIndex = index);
                      if (index == 0) unawaited(_checkNotices());
                    },
                    destinations: [
                      NavigationDestination(
                        icon: const Icon(Icons.menu_book_outlined),
                        selectedIcon: const Icon(Icons.menu_book),
                        label: appL10n.training,
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.sports_esports_outlined),
                        selectedIcon: const Icon(Icons.sports_esports_rounded),
                        label: appL10n.game,
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.extension_outlined),
                        selectedIcon: const Icon(Icons.extension_rounded),
                        label: appL10n.navGames,
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.style_outlined),
                        selectedIcon: const Icon(Icons.style_rounded),
                        label: appL10n.video,
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.person_outline_rounded),
                        selectedIcon: const Icon(Icons.person_rounded),
                        label: appL10n.profile,
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

/// Карточка «Продолжить» — возврат к незаконченной тренировке одним нажатием.
///
/// Раньше вернуться к недорешанному билету стоило четырёх шагов: главная →
/// Билеты → прокрутка списка → свайпы до нужного вопроса. Основной сценарий
/// приложения — короткие сессии в транспорте, и каждый лишний шаг на возврате
/// стоит самого возврата.
class _HomeTab extends ConsumerStatefulWidget {
  final Future<void> Function(NoticeTap tap) onNoticeTap;
  const _HomeTab({required this.onNoticeTap});

  @override
  ConsumerState<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<_HomeTab> with RouteAware {
  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    // Случай «пользователь закрыл приложение сразу после ответа, не дождавшись
    // поздравления» — проверим флаг при первом фрейме после монтирования.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowStreakCelebration();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    super.dispose();
  }

  /// Когда пользователь возвращается с тренировки (любой экран pop'ается
  /// поверх HomeScreen) — это надёжный момент для показа поздравления.
  /// Не зависит от того, какой именно экран был сверху.
  @override
  void didPopNext() {
    ref.read(appDataRefreshProvider.notifier).state++;
    _maybeShowStreakCelebration();
  }

  /// Проверяет флаг pending celebration и показывает диалог, если он стоит.
  /// Идемпотентно: сбрасывает флаг сразу после прочтения.
  Future<void> _maybeShowStreakCelebration() async {
    if (!mounted) return;
    final dataSource = ref.read(progressDataSourceProvider);
    final hasPending = await dataSource.consumePendingStreakCelebration();
    if (!hasPending || !mounted) return;
    // Принудительно обновим streakProvider, чтобы получить актуальные данные.
    ref.invalidate(streakProvider);
    final streak = await ref.read(streakProvider.future);
    if (!mounted || streak.current == 0) return;
    await showStreakCelebrationDialog(context: context, streak: streak);
    // Сразу после поздравления — момент, когда пользователь доволен. Сервис
    // сам решит, показывать ли (серия ≥ 3 дней и просим только один раз).
    await ReviewPromptService.maybeRequest(currentStreak: streak.current);
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(statsProvider);
    final streakAsync = ref.watch(streakProvider);
    final unfinishedSession = ref.watch(unfinishedSessionProvider);
    final sessionData = unfinishedSession.valueOrNull;
    final hasContinueCard = sessionData != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalH = constraints.maxHeight;
        final double topInset = MediaQuery.paddingOf(context).top;
        const double topPadding = 12.0;
        const double bottomPadding = AppDimensions.screenPadding; // 16.0
        const double gap = 12.0;

        // Top progress panel height is ~206.0
        const double topPanelHeight = 206.0;
        final double continueCardH = hasContinueCard ? 56.0 : 0.0;
        final double totalGaps = gap * (hasContinueCard ? 4 : 3);

        final double availableH =
            totalH -
            topInset -
            topPadding -
            bottomPadding -
            topPanelHeight -
            continueCardH -
            totalGaps;

        final double examHeight;
        final double buttonHeight;

        if (availableH > 260) {
          examHeight = (availableH * 0.40).clamp(130.0, 220.0);
          final double remainingForButtons = availableH - examHeight - gap;
          buttonHeight = math.max(100.0, remainingForButtons / 2);
        } else {
          examHeight = 140.0;
          buttonHeight = AppDimensions.topicButtonHeight;
        }

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            topInset + topPadding,
            AppDimensions.screenPadding,
            bottomPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<List<AppNotice>>(
                valueListenable: RemoteNotificationsService.instance.banners,
                builder: (context, banners, _) {
                  const emptyStats = {
                    'correctAnswers': 0,
                    'answeredQuestions': 0,
                    'passedTickets': 0,
                    'wrongQuestions': 0,
                    'totalQuestions': 0,
                    'totalTickets': 0,
                  };
                  final progressCard = statsAsync.when(
                    data: (stats) => ProgressPanelCard(
                      stats: stats,
                      streak: streakAsync.valueOrNull,
                    ),
                    loading: () => banners.isNotEmpty
                        ? ProgressPanelCard(
                            stats: emptyStats,
                            streak: streakAsync.valueOrNull,
                          )
                        : const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                    error: (error, _) => ProgressPanelCard(
                      stats: emptyStats,
                      streak: streakAsync.valueOrNull,
                    ),
                  );
                  if (banners.isEmpty) return progressCard;
                  final banner = banners.first;
                  return Stack(
                    children: [
                      Visibility(
                        visible: false,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: progressCard,
                      ),
                      Positioned.fill(
                        child: AppNoticeBanner(
                          key: ValueKey(banner.id),
                          notice: banner,
                          onDismiss: () => RemoteNotificationsService.instance
                              .dismissBanner(banner.id),
                          onTap: () {
                            final tap = banner.tap;
                            if (tap != null) widget.onNoticeTap(tap);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: gap),
              unfinishedSession.maybeWhen(
                data: (session) => session == null
                    ? const SizedBox.shrink()
                    : ContinueSessionCard(
                        key: ValueKey(session['questions'].hashCode),
                        session: session,
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              _buildExamHero(context, ref, height: examHeight),
              const SizedBox(height: gap),
              Row(
                children: [
                  Expanded(
                    child: _buildModeCard(
                      context: context,
                      iconAsset: 'assets/images/home_icon_topics.png',
                      label: appL10n.topics,
                      height: buttonHeight,
                      onTap: () {
                        HapticFeedbackHelper.tap();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TopicsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: _buildModeCard(
                      context: context,
                      iconAsset: 'assets/images/home_icon_tickets.png',
                      label: appL10n.tickets,
                      height: buttonHeight,
                      onTap: () {
                        HapticFeedbackHelper.tap();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TicketsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: gap),
              Row(
                children: [
                  Expanded(
                    child: _buildModeCard(
                      context: context,
                      iconAsset: 'assets/images/home_icon_errors.png',
                      label: appL10n.mistakes,
                      height: buttonHeight,
                      onTap: () {
                        HapticFeedbackHelper.tap();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MistakesScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: _buildModeCard(
                      context: context,
                      iconAsset: 'assets/images/home_icon_favorites.png',
                      label: appL10n.favorites,
                      height: buttonHeight,
                      onTap: () {
                        HapticFeedbackHelper.tap();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FavoritesScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static const double _homeNavLabelFontSize = 18;

  Widget _buildExamHero(
    BuildContext context,
    WidgetRef ref, {
    required double height,
  }) {
    final settings = ref.watch(appSettingsProvider);
    final categoryLabel = settings.ticketCategory == TicketCategory.cd
        ? 'C/D'
        : 'A/B';

    return ExamHeroCard(
      height: height,
      questionsBadge: appL10n.examQuestionsBadge(
        CountryConfig.current.examRules.mainCount,
      ),
      timeBadge: appL10n.examMinutesBadge(
        CountryConfig.current.examRules.totalMinutes,
      ),
      categoryBadge: categoryLabel,
      onTap: () async {
        HapticFeedbackHelper.tap();
        final tickets = await ref.read(ticketsProvider.future);
        final allQuestions = <Map<String, dynamic>>[];

        for (final ticket in tickets) {
          final questions = ticket['questions'] as List;
          for (final q in questions) {
            allQuestions.add({
              'id': q.id,
              'question': q.question,
              'answers': q.answers
                  .map((a) => {'text': a.text, 'correct': a.isCorrect})
                  .toList(),
              'comment': q.comment ?? '',
              'pddPoints': q.pddPoints ?? [],
              'image': q.image,
              'topic': q.topic ?? [],
              'ticketNumber': q.ticketNumber,
            });
          }
        }

        if (!context.mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExamScreen(allQuestions: allQuestions),
          ),
        );
      },
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required String iconAsset,
    required String label,
    required double height,
    required VoidCallback onTap,
  }) {
    final colors = AppColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.all(AppDimensions.spacingL),
          decoration: BoxDecoration(
            color: colors.accentSurface10,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                iconAsset,
                width: AppDimensions.iconSize,
                height: AppDimensions.iconSize,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: _homeNavLabelFontSize,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    color: colors.accent,
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
