import 'package:flutter/material.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/core/config/country_config.dart';
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
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      appL10n.pdd,
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
                    hintText: appL10n.search,
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
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppDimensions.screenPadding),
                        child: Text(
                          appL10n.pddSearchEmpty,
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
                      // Дисклеймер источника: где текст правил — авторский
                      // пересказ, человек должен видеть это на самом экране,
                      // а не только в настройках (требование Google Play к
                      // приложениям с гос-информацией). Страны без заметки
                      // (RU/BY — там дословный официальный текст) её не
                      // показывают.
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
                  // Тот же кегль и начертание, что у строк на экране настроек:
                  // это одинаковые по смыслу элементы — строка списка со
                  // стрелкой, — и выглядеть они должны одинаково.
                  // Межстрочный интервал не задаём: у настроек его нет, а
                  // здесь заголовки переносятся на 2–3 строки, и height: 1.0
                  // слепляла их.
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
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

/// Заметка об источнике текста правил (показывается только там, где она
/// задана в конфиге страны — сейчас это Сербия).
class _SourceNote extends StatelessWidget {
  const _SourceNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppDimensions.spacingM),
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: AppColors.gray,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.secondaryText,
          ),
          const SizedBox(width: AppDimensions.spacingM),
          Expanded(
            child: Text(
              CountryConfig.current.notAffiliatedNote,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.secondaryText,
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
          // Ровно 0: ставим начало пункта к верхней кромке. Любой отступ
          // сверху ломается на пунктах выше экрана — например, 1.2 занимает
          // несколько экранов (там весь список терминов), и прокрутка
          // проскакивала мимо его начала, в середину текста.
          alignment: 0,
        );
      });
    }
  }

  /// Номер пункта в начале блока: «13.11.» → 13.11, «13.11.1.» → 13.11.1.
  static final RegExp _leadingPoint = RegExp(
    r'^(\d{1,2}(?:\.\d{1,2}){1,3})[.\s]',
  );

  /// Тот ли это пункт, ради которого открыли экран.
  ///
  /// Сравниваем номер целиком, а не по началу строки: пункт 13.11.1 тоже
  /// начинается с «13.11.», и проверка на префикс пометила бы сразу два блока
  /// (а GlobalKey на двух виджетах — это падение, а не просто лишняя рамка).
  bool _isTarget(String block) {
    final point = widget.highlightPoint;
    if (point == null) return false;
    return _leadingPoint.firstMatch(block)?.group(1) == point;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final blocks = widget.content
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
                // Все карточки должны быть разложены, иначе прокрутка к
                // пункту за пределами экрана не найдёт его render-объект.
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
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.cardRadius,
                          ),
                          // Пункт, ради которого пришли, помечен рамкой:
                          // человек попал сюда по ссылке и должен сразу
                          // видеть, какой именно абзац искал.
                          border: target
                              ? Border.all(color: AppColors.accent, width: 2)
                              : null,
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
