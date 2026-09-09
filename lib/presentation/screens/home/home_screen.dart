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
import 'package:pdd_app/data/services/review_prompt_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/exam/exam_screen.dart';
import 'package:pdd_app/presentation/screens/favorites/favorites_screen.dart';
import 'package:pdd_app/presentation/screens/mistakes/mistakes_screen.dart';
import 'package:pdd_app/presentation/screens/pdd/pdd_screen.dart';
import 'package:pdd_app/presentation/screens/feed/feed_screen.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:pdd_app/presentation/screens/tickets/tickets_screen.dart';
import 'package:pdd_app/presentation/screens/topics/topics_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_granted_dialog.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int _currentIndex;
  StreamSubscription<DateTime?>? _premiumGrantSub;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _subscribePremiumGrant();
  }

  void _subscribePremiumGrant() {
    _premiumGrantSub = PremiumService.instance.onPremiumGrantedStream.listen((expiresAt) {
      if (!mounted) return;
      _showPremiumGrantedDialog(expiresAt);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pendingExp = PremiumService.instance.pendingGrantNotificationExpiresAt;
      if (pendingExp != null) {
        PremiumService.instance.consumePendingGrantNotification();
        _showPremiumGrantedDialog(pendingExp);
      }
    });
  }

  void _showPremiumGrantedDialog(DateTime? expiresAt) {
    PremiumGrantedDialog.show(context, expiresAt: expiresAt);
  }

  @override
  void dispose() {
    _premiumGrantSub?.cancel();
    super.dispose();
  }

  final List<Widget> _screens = const [
    _HomeTab(),
    FeedScreen(),
    PddScreen(),
    SettingsScreen(),
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
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: colors.homeScreenBackground,
        body: _screens[_currentIndex],
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 1,
              color: colors.divider,
            ),
            NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                if (index != _currentIndex) {
                  TtsService.instance.stop();
                  HapticFeedbackHelper.select();
                  setState(() => _currentIndex = index);
                }
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.menu_book_outlined),
                  selectedIcon: const Icon(Icons.menu_book),
                  label: appL10n.training,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.style_outlined),
                  selectedIcon: const Icon(Icons.style_rounded),
                  label: appL10n.video,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.gavel_outlined),
                  selectedIcon: const Icon(Icons.gavel),
                  label: appL10n.pdd,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: appL10n.settings,
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
  const _HomeTab();

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

        final double availableH = totalH - topInset - topPadding - bottomPadding - topPanelHeight - continueCardH - totalGaps;

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
              statsAsync.when(
                data: (stats) => ProgressPanelCard(
                  stats: stats,
                  streak: streakAsync.valueOrNull,
                ),
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => ProgressPanelCard(
                  stats: const {
                    'correctAnswers': 0,
                    'answeredQuestions': 0,
                    'passedTickets': 0,
                    'wrongQuestions': 0,
                    'totalQuestions': 0,
                    'totalTickets': 0,
                  },
                  streak: streakAsync.valueOrNull,
                ),
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

  Widget _buildExamHero(BuildContext context, WidgetRef ref, {required double height}) {
    final settings = ref.watch(appSettingsProvider);
    final categoryLabel =
        settings.ticketCategory == TicketCategory.cd ? 'C/D' : 'A/B';

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
              'points': q.points,
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
