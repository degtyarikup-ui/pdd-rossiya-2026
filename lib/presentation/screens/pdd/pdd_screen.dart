import 'package:flutter/material.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:pdd_app/presentation/screens/signs/signs_screen.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/app_pill_search_field.dart';

/// Вкладка «ПДД»: разделы правил из контента страны
/// (assets/countries/{code}/questions/pdd_sections.json) и знаки/разметка.
class PddScreen extends StatefulWidget {
  const PddScreen({super.key});

  @override
  State<PddScreen> createState() => _PddScreenState();
}

class _PddScreenState extends State<PddScreen> {
  int _subTab = 0; // 0: Правила, 1: Знаки и разметка
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
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                16,
                AppDimensions.screenPadding,
                8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      appL10n.pdd,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colors.gray,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildSubTabButton(
                            index: 0,
                            title: appL10n.rules,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _buildSubTabButton(
                            index: 1,
                            title: appL10n.signsAndMarkup,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_subTab == 0) ...[
                    const SizedBox(height: AppDimensions.spacingS),
                    AppPillSearchField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      hintText: appL10n.search,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _subTab == 0
                  ? _buildRulesContent()
                  : const SignsScreen(showHeader: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTabButton({required int index, required String title}) {
    final colors = AppColors.of(context);
    final isSelected = _subTab == index;
    return GestureDetector(
      onTap: () {
        HapticFeedbackHelper.tap();
        setState(() => _subTab = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.cardBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? colors.primaryText : colors.secondaryText,
          ),
        ),
      ),
    );
  }

  Widget _buildRulesContent() {
    final colors = AppColors.of(context);
    return FutureBuilder<List<Map<String, String>>>(
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppDimensions.screenPadding),
                        child: Text(
                          appL10n.pddSearchEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: colors.secondaryText,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(AppDimensions.screenPadding),
                    children: [
                      if (CountryConfig.current.notAffiliatedNote.isNotEmpty)
                        const _SourceNote(),
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
              );
  }

  Widget _buildPddSection(BuildContext context, String title, String content) {
    final colors = AppColors.of(context);
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
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.secondaryText,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Заметка об источнике текста правил (показывается только там, где она
/// задана в конфиге страны — сейчас это Сербия).
class _SourceNote extends StatelessWidget {
  const _SourceNote();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppDimensions.spacingM),
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: colors.gray,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: colors.secondaryText,
          ),
          const SizedBox(width: AppDimensions.spacingM),
          Expanded(
            child: Text(
              CountryConfig.current.notAffiliatedNote,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: colors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PddDetailScreen extends StatefulWidget {
  final String title;
  final String content;

  /// Номер пункта, к которому нужно прокрутить и который надо выделить —
  /// когда экран открыт по ссылке из разбора вопроса. null — обычный вход
  /// из списка разделов, тогда открываем с начала.
  final String? highlightPoint;

  const PddDetailScreen({
    super.key,
    required this.title,
    required this.content,
    this.highlightPoint,
  });

  @override
  State<PddDetailScreen> createState() => _PddDetailScreenState();
}

class _PddDetailScreenState extends State<PddDetailScreen> {
  final GlobalKey _highlightKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.highlightPoint != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _highlightKey.currentContext;
        if (ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0,
        );
      });
    }
  }

  /// Номер пункта в начале блока: «13.11.» → 13.11, «13.11.1.» → 13.11.1.
  static final RegExp _leadingPoint = RegExp(
    r'^(\d{1,2}(?:\.\d{1,2}){1,3})[.\s]',
  );

  bool _isTarget(String block) {
    final point = widget.highlightPoint;
    if (point == null) return false;
    return _leadingPoint.firstMatch(block)?.group(1) == point;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final title = widget.title;
    final blocks = widget.content
        .split('\n\n')
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: colors.background,
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
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: colors.primaryText,
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
                cacheExtent: 100000,
                children: [
                  ...blocks.map((block) {
                    final target = _isTarget(block);
                    return Padding(
                      key: target ? _highlightKey : null,
                      padding: const EdgeInsets.only(
                        bottom: AppDimensions.spacingM,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(AppDimensions.spacingL),
                        decoration: BoxDecoration(
                          color: colors.cardBackground,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.cardRadius,
                          ),
                          border: target
                              ? Border.all(color: colors.accent, width: 2)
                              : null,
                        ),
                        child: Text(
                          block,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.65,
                            color: colors.primaryText,
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

