import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/app_pill_search_field.dart';

/// Вкладка «ПДД»: разделы правил из контента страны
/// (assets/countries/{code}/questions/pdd_sections.json).
class PddScreen extends StatefulWidget {
  const PddScreen({super.key});

  @override
  State<PddScreen> createState() => _PddScreenState();
}

class _PddScreenState extends State<PddScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Future<List<Map<String, String>>> _sectionsFuture =
      QuestionsDataSource().loadPddSections();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: double.infinity,
                    child: Text(
                      'ПДД',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingS),
                  AppPillSearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    hintText: 'Поиск',
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, String>>>(
                future: _sectionsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final normalizedQuery = _query.trim().toLowerCase();
                  final filteredSections = snapshot.data!.where((section) {
                    if (normalizedQuery.isEmpty) return true;
                    return section['title']!
                            .toLowerCase()
                            .contains(normalizedQuery) ||
                        section['content']!
                            .toLowerCase()
                            .contains(normalizedQuery);
                  }).toList();

                  if (filteredSections.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppDimensions.screenPadding),
                        child: Text(
                          'Ничего не найдено. Попробуйте номер раздела или ключевое слово.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(AppDimensions.screenPadding),
                    children: [
                      ...filteredSections.map((section) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppDimensions.spacingM,
                          ),
                          child: _buildPddSection(
                            context,
                            section['title']!,
                            section['content']!,
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPddSection(BuildContext context, String title, String content) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: () {
          HapticFeedbackHelper.tap();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PddDetailScreen(title: title, content: content),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingL,
            vertical: 20,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.secondaryText,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PddDetailScreen extends StatelessWidget {
  final String title;
  final String content;

  const PddDetailScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = content
        .split('\n\n')
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppDimensions.screenPadding),
              child: Row(
                children: [
                  AppChromeIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () {
                      HapticFeedbackHelper.tap();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: AppDimensions.spacingM),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.screenPadding,
                  0,
                  AppDimensions.screenPadding,
                  24,
                ),
                children: [
                  ...blocks.map((block) {
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: AppDimensions.spacingM,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(AppDimensions.spacingL),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.cardRadius,
                          ),
                        ),
                        child: Text(
                          block,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.65,
                            color: AppColors.primaryText,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
