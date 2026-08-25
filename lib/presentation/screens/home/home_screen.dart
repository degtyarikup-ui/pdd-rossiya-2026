import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/navigation/route_observer.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
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
import 'package:pdd_app/presentation/widgets/streak_celebration_dialog.dart';
import 'package:pdd_app/presentation/widgets/continue_session_card.dart';
import 'package:pdd_app/presentation/widgets/progress_panel_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
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
    return Scaffold(
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
    final hasContinueCard = unfinishedSession.valueOrNull != null;
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.homeScreenBackground,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(statsProvider);
            ref.invalidate(streakProvider);
            await ref.read(statsProvider.future);
          },
          // Воздух между блоками зависит от высоты экрана: на высоком даём
          // разделам разойтись, на низком схлопываем в ноль — там каждый
          // пиксель нужен под содержимое.
          //
          // Считаем явно, а не через Spacer: Spacer требует ограниченной
          // высоты, а IntrinsicHeight, который её даёт, учитывает натуральный
          // размер распорок — и на невысоком экране они не схлопывались,
          // добавляя мёртвое место, которое приходилось пролистывать.
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Высота содержимого без распорок: панель + карточка экзамена +
              // два ряда плиток + постоянные отступы и поля. Оценка, а не
              // точный расчёт — ошибка в пару десятков пикселей даёт лишь
              // чуть больший отступ снизу.
              const contentHeight = 648.0;
              // Карточка «Продолжить» появляется и исчезает, и её высоту надо
              // вычесть — иначе распорки остаются прежними, содержимое
              // перестаёт помещаться и появляется паразитный скролл.
              const continueCardHeight = 92.0;
              final slack = constraints.maxHeight -
                  contentHeight -
                  (hasContinueCard ? continueCardHeight : 0);

              final sectionGap = (slack * 0.6).clamp(0.0, 56.0);
              // Внутри группы действий отступ меньше: экзамен и плитки должны
              // читаться вместе, а не как два разных раздела.
              final groupGap = (slack * 0.27).clamp(0.0, 25.0);

              return SingleChildScrollView(
                // Иначе «потянуть для обновления» перестаёт работать, когда
                // содержимое умещается на экран целиком.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.screenPadding,
                  16,
                  AppDimensions.screenPadding,
                  24,
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    // Готовность, четыре числа и серия — одной карточкой.
                    // Серия ждёт статистику, а не показывается отдельно: две
                    // карточки одинакового веса не давали экрану иерархии.
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
                    // Граница между сводкой и действиями.
                    //
                    // Анимированная: когда карточку «Продолжить» убирают, она
                    // схлопывается плавно, а отступы пересчитываются мгновенно
                    // — и карточка экзамена, доехав вверх, дёргалась вниз.
                    // Обе анимации теперь одной длительности.
                    _AnimatedGap(height: sectionGap),
                    const SizedBox(height: AppDimensions.spacingL),
                    // Возврат к незаконченной тренировке или прерванному экзамену.
                    unfinishedSession.maybeWhen(
                          data: (session) => session == null
                              ? const SizedBox.shrink()
                              // Ключ по набору вопросов: при смене сессии нужен
                              // новый State, иначе карточка осталась бы свёрнутой
                              // после предыдущего скрытия.
                              : ContinueSessionCard(
                                  key: ValueKey(session['questions'].hashCode),
                                  session: session,
                                ),
                          orElse: () => const SizedBox.shrink(),
                        ),
                    _buildExamHero(context, ref),
                    _AnimatedGap(height: groupGap),
                    const SizedBox(height: AppDimensions.spacingL),
                    Row(
                      children: [
                        Expanded(
                          child: _buildModeCard(
                            context: context,
                            iconAsset: 'assets/images/home_icon_topics.png',
                            label: appL10n.topics,
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
                        const SizedBox(width: AppDimensions.spacingM),
                        Expanded(
                          child: _buildModeCard(
                            context: context,
                            iconAsset: 'assets/images/home_icon_tickets.png',
                            label: appL10n.tickets,
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
              const SizedBox(height: AppDimensions.spacingM),
              Row(
                children: [
                  Expanded(
                    child: _buildModeCard(
                      context: context,
                      iconAsset: 'assets/images/home_icon_errors.png',
                      label: appL10n.mistakes,
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
                  const SizedBox(width: AppDimensions.spacingM),
                  Expanded(
                    child: _buildModeCard(
                      context: context,
                      iconAsset: 'assets/images/home_icon_favorites.png',
                      label: appL10n.favorites,
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
          ),
        ),
      ),
    );
  }

  static const double _examTitleFontSize = 26;
  /// Подпись плитки режима. 26 pt выбивались из шкалы: это крупнее
  /// заголовков карточек (16) и почти как заголовок экрана (28) — именно
  /// из-за них плитки приходилось делать высотой 128.
  static const double _homeNavLabelFontSize = 18;

  Widget _buildExamHero(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    const double bannerHeight = 160;

    // Картинка на кнопке экзамена зависит от выбранной категории и реактивно
    // обновляется при её смене (в т.ч. из настроек).
    final vehicleAsset =
        ref.watch(appSettingsProvider).ticketCategory == TicketCategory.cd
            ? 'assets/images/onboarding_truck.png'
            : 'assets/images/onboarding_car.png';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: bannerHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bw = constraints.maxWidth;
                final imageW = (bw * 0.50).clamp(170.0, 225.0);
                final reserveRight = imageW + 6;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: colors.accent),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Image.asset(
                        vehicleAsset,
                        width: imageW,
                        fit: BoxFit.fitWidth,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(18, 14, reserveRight, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Wrap(
                            spacing: AppDimensions.spacingS,
                            runSpacing: 6,
                            children: [
                              _buildHeroBadge(
                                appL10n.examQuestionsBadge(
                                  CountryConfig.current.examRules.mainCount,
                                ),
                              ),
                              _buildHeroBadge(
                                appL10n.examMinutesBadge(
                                  CountryConfig.current.examRules.totalMinutes,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            appL10n.exam,
                            style: const TextStyle(
                              fontSize: _examTitleFontSize,
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                              letterSpacing: -0.3,
                              color: AppColors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: AppColors.white,
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required String iconAsset,
    required String label,
    required VoidCallback onTap,
  }) {
    final colors = AppColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: onTap,
        child: Container(
          height: AppDimensions.topicButtonHeight,
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

/// Отступ, который меняет высоту плавно.
///
/// Длительность совпадает с анимацией скрытия карточки «Продолжить»
/// ([ContinueSessionCard]): иначе один элемент едет, а второй прыгает.
class _AnimatedGap extends StatelessWidget {
  const _AnimatedGap({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      height: height,
    );
  }
}
