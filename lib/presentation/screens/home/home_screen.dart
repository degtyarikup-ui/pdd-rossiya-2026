import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/screens/exam/exam_screen.dart';
import 'package:pdd_app/presentation/screens/favorites/favorites_screen.dart';
import 'package:pdd_app/presentation/screens/mistakes/mistakes_screen.dart';
import 'package:pdd_app/presentation/screens/pdd/pdd_screen.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:pdd_app/presentation/screens/signs/signs_screen.dart';
import 'package:pdd_app/presentation/screens/tickets/tickets_screen.dart';
import 'package:pdd_app/presentation/screens/topics/topics_screen.dart';
import 'package:pdd_app/presentation/widgets/vehicle_onboarding_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    _HomeTab(),
    PddScreen(),
    SignsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showVehicleOnboardingIfNeeded(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: AppColors.divider),
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              HapticFeedbackHelper.select();
              setState(() => _currentIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book),
                label: 'Обучение',
              ),
              NavigationDestination(
                icon: Icon(Icons.gavel_outlined),
                selectedIcon: Icon(Icons.gavel),
                label: 'ПДД',
              ),
              NavigationDestination(
                icon: Icon(Icons.signpost_outlined),
                selectedIcon: Icon(Icons.signpost),
                label: 'Знаки',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Настройки',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statsProvider);

    return Scaffold(
      backgroundColor: AppColors.homeScreenBackground,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(statsProvider);
            await ref.read(statsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.screenPadding,
              16,
              AppDimensions.screenPadding,
              24,
            ),
            children: [
              statsAsync.when(
                data: (stats) => _buildStatisticsCard(
                  context,
                  ref,
                  stats,
                ),
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => _buildStatisticsCard(context, ref, const {
                  'correctAnswers': 0,
                  'answeredQuestions': 0,
                  'passedTickets': 0,
                  'wrongQuestions': 0,
                  'totalQuestions': 800,
                  'totalTickets': 40,
                }),
              ),
              const SizedBox(height: AppDimensions.spacingL),
              _buildExamHero(context, ref),
              const SizedBox(height: AppDimensions.spacingL),
              Row(
                children: [
                  Expanded(
                    child: _buildModeCard(
                      context: context,
                      iconAsset: 'assets/images/home_icon_topics.png',
                      label: 'Темы',
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
                      label: 'Билеты',
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
                      label: 'Ошибки',
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
                      label: 'Избранное',
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
        ),
      ),
    );
  }

  static const double _examTitleFontSize = 26;
  static const double _homeNavLabelFontSize = 26;

  Widget _buildExamHero(BuildContext context, WidgetRef ref) {
    const double bannerHeight = 160;

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
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: AppColors.accent),
                ),
                Positioned(
                  right: -28,
                  bottom: -6,
                  child: Image.asset(
                    'assets/images/home_exam_car.png',
                    height: 148,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Резервируем справа место под фото; машина сдвинута правее, чтобы «Экзамен» не заходил на капот.
                      final reserveRight = (constraints.maxWidth * 0.54)
                          .clamp(142.0, 204.0);
                      return Padding(
                        padding: EdgeInsets.fromLTRB(18, 14, reserveRight, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                _buildHeroBadge('20 вопросов'),
                                const SizedBox(width: AppDimensions.spacingS),
                                _buildHeroBadge('20 минут'),
                              ],
                            ),
                            const Text(
                              'Экзамен',
                              style: TextStyle(
                                fontSize: _examTitleFontSize,
                                fontWeight: FontWeight.w600,
                                height: 1.1,
                                letterSpacing: -0.3,
                                color: AppColors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: onTap,
        child: Container(
          height: 128,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.accentSurface10,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                iconAsset,
                width: 32,
                height: 32,
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
                  style: const TextStyle(
                    fontSize: _homeNavLabelFontSize,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                    letterSpacing: -0.3,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticsCard(
    BuildContext context,
    WidgetRef ref,
    Map<String, int> stats,
  ) {
    final correctAnswers = stats['correctAnswers'] ?? 0;
    final answeredQuestions = stats['answeredQuestions'] ?? 0;
    final wrongQuestions = stats['wrongQuestions'] ?? 0;
    final passedTickets = stats['passedTickets'] ?? 0;
    final totalQuestions = stats['totalQuestions'] ?? 800;
    final totalTickets = stats['totalTickets'] ?? 40;
    final readiness = totalQuestions > 0
        ? (correctAnswers / totalQuestions * 100).round()
        : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildStatMetricCell(
                  backgroundColor: AppColors.homeStatGraySurface,
                  valueColor: AppColors.primaryText,
                  labelColor: AppColors.secondaryText,
                  value: '$answeredQuestions/$totalQuestions',
                  label: 'Пройдено вопросов',
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: _buildStatMetricCell(
                  backgroundColor: AppColors.accentSurface10,
                  valueColor: AppColors.accent,
                  labelColor: AppColors.accent,
                  value: '$correctAnswers/$totalQuestions',
                  label: 'Верно решено',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingM),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildStatMetricCell(
                  backgroundColor: AppColors.homeRedSurface,
                  valueColor: AppColors.red,
                  labelColor: AppColors.red,
                  value: '$wrongQuestions/$totalQuestions',
                  label: 'Ошибки',
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: _buildStatMetricCell(
                  backgroundColor: AppColors.homeGreenSurface,
                  valueColor: AppColors.green,
                  labelColor: AppColors.green,
                  value: '$passedTickets/$totalTickets',
                  label: 'Сдано билетов',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '$readiness% Готовность к экзамену',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: readiness / 100,
              minHeight: 10,
              backgroundColor: AppColors.gray,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Ячейка сетки статистики: крупная дробь сверху, подпись снизу, тонированный фон.
  Widget _buildStatMetricCell({
    required Color backgroundColor,
    required Color valueColor,
    required Color labelColor,
    required String value,
    required String label,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.3,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}
