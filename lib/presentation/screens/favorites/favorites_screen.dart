import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/safe_user_message.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final favoriteIdsAsync = ref.watch(favoriteQuestionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                16,
                AppDimensions.screenPadding,
                0,
              ),
              child: _buildHeader(),
            ),
            Expanded(
              child: favoriteIdsAsync.when(
                data: (favoriteIds) {
                  if (favoriteIds.isEmpty) {
                    return _buildEmptyState();
                  }

                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: _loadFavoriteQuestions(ref, favoriteIds),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final allQuestions = snapshot.data!;
                      final filteredQuestions = _filterQuestions(
                        allQuestions,
                      );

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimensions.screenPadding,
                          AppDimensions.spacingL,
                          AppDimensions.screenPadding,
                          24,
                        ),
                        children: [
                          _buildIntroCard(context, allQuestions),
                          const SizedBox(height: AppDimensions.spacingL),
                          TextField(
                            controller: _searchController,
                            onChanged: (value) {
                              setState(
                                () => _query = value.trim().toLowerCase(),
                              );
                            },
                            decoration: const InputDecoration(
                              hintText: 'Поиск по вопросу или теме',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                          const SizedBox(height: AppDimensions.spacingL),
                          if (filteredQuestions.isEmpty)
                            _buildNoSearchResults()
                          else
                            ...filteredQuestions.map((question) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppDimensions.spacingM,
                                ),
                                child: _buildFavoriteCard(
                                  context,
                                  question,
                                ),
                              );
                            }),
                        ],
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Center(child: Text(dataLoadErrorMessage(error))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        AppChromeIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () {
            HapticFeedbackHelper.tap();
            Navigator.pop(context);
          },
        ),
        const SizedBox(width: AppDimensions.spacingM),
        const Expanded(
          child: Text(
            'Избранное',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.screenPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.lightAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.star_border_rounded,
                size: 36,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            const Text(
              'Пока здесь пусто',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingS),
            const Text(
              'Отмечай сложные вопросы звёздочкой, и они будут собираться в одном месте для быстрого повторения.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResults() {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: const Text(
        'По этому запросу ничего не найдено. Попробуй часть формулировки вопроса или название темы.',
        style: TextStyle(
          fontSize: 14,
          height: 1.4,
          color: AppColors.secondaryText,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterQuestions(
    List<Map<String, dynamic>> questions,
  ) {
    if (_query.isEmpty) {
      return questions;
    }

    return questions.where((question) {
      final text = (question['question'] as String).toLowerCase();
      final topics = ((question['topic'] as List?) ?? const [])
          .cast<String>()
          .join(' ')
          .toLowerCase();
      return text.contains(_query) || topics.contains(_query);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadFavoriteQuestions(
    WidgetRef ref,
    List<String> favoriteIds,
  ) async {
    final dataSource = ref.read(questionsDataSourceProvider);
    final category = ref.read(appSettingsProvider).ticketCategory;
    final allQuestions = await dataSource.loadTickets(category);
    final favoriteSet = favoriteIds.toSet();

    return allQuestions
        .where((question) => favoriteSet.contains(question.id))
        .map(
          (question) => {
            'id': question.id,
            'question': question.question,
            'answers': question.answers
                .map(
                  (answer) => {
                    'text': answer.text,
                    'correct': answer.isCorrect,
                  },
                )
                .toList(),
            'comment': question.comment ?? '',
            'pddPoints': question.pddPoints,
            'image': question.image,
            'topic': question.topic,
            'ticketNumber': question.ticketNumber,
          },
        )
        .toList();
  }

  Widget _buildIntroCard(
    BuildContext context,
    List<Map<String, dynamic>> questions,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Личные сложные вопросы',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingS),
          Text(
            'Сейчас в избранном ${questions.length} ${_questionWord(questions.length)}. Используй этот режим как персональную подборку перед экзаменом.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedbackHelper.tap();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrainingScreen(
                      questions: questions,
                      title: 'Избранное',
                    ),
                  ),
                );
              },
              child: const Text('Пройти всё избранное'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteCard(
    BuildContext context,
    Map<String, dynamic> question,
  ) {
    final topics = ((question['topic'] as List?) ?? const []).cast<String>();
    final topicLabel = topics.isNotEmpty ? topics.first : 'Без темы';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: () {
          HapticFeedbackHelper.tap();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TrainingScreen(
                questions: [question],
                title: 'Избранный вопрос',
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(AppDimensions.spacingL),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Избранное',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Билет ${question['ticketNumber']}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingM),
              Text(
                question['question'] as String,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingM),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      topicLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: AppColors.secondaryText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _questionWord(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;

    if (mod10 == 1 && mod100 != 11) {
      return 'вопрос';
    }

    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'вопроса';
    }

    return 'вопросов';
  }
}
