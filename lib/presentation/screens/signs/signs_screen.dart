import 'package:flutter/material.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/constants/app_strings.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/safe_user_message.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/screens/signs/markup_category_screen.dart';
import 'package:pdd_app/presentation/screens/signs/sign_detail_screen.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/app_pill_search_field.dart';

/// Иконка для категории знаков по её названию. Названия отличаются по странам
/// (РФ: «Знаки особых предписаний»/«Информационные знаки»; РБ:
/// «Информационно-указательные знаки»/«Дополнительные таблички»), поэтому
/// маппинг покрывает оба набора; для неизвестной категории — запасная иконка.
const Map<String, String> _kSignCategoryIcons = {
  'Предупреждающие знаки': 'warning.svg',
  'Знаки приоритета': 'priority.svg',
  'Запрещающие знаки': 'prohibitory.svg',
  'Предписывающие знаки': 'mandatory.svg',
  'Знаки особых предписаний': 'special_prescriptions.svg',
  'Информационные знаки': 'information.svg',
  'Информационно-указательные знаки': 'information.svg',
  'Знаки сервиса': 'service.svg',
  'Знаки дополнительной информации (таблички)': 'additional_info.svg',
  'Дополнительные таблички': 'additional_info.svg',
  // Сербия (латиница): категории MUP.
  'Znakovi opasnosti': 'warning.svg',
  'Znakovi izričitih naredbi': 'prohibitory.svg',
  'Znakovi obaveštenja': 'information.svg',
  'Dopunske table': 'additional_info.svg',
};

const String _kSignCategoryFallbackIcon = 'information.svg';

class SignsScreen extends ConsumerStatefulWidget {
  final bool showHeader;
  const SignsScreen({super.key, this.showHeader = true});

  @override
  ConsumerState<SignsScreen> createState() => _SignsScreenState();
}

class _SignsScreenState extends ConsumerState<SignsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const Map<String, String> _markupIcons = {
    'Горизонтальная разметка': 'markup_horizontal.svg',
    'Вертикальная разметка': 'markup_vertical.svg',
    // Сербия (латиница).
    'Horizontalna signalizacija': 'markup_horizontal.svg',
    'Vertikalna signalizacija': 'markup_vertical.svg',
  };

  @override
  Widget build(BuildContext context) {
    final signsAsync = ref.watch(signsProvider);
    final markup = ref.watch(markupProvider).valueOrNull ??
        const <String, List<Map<String, String>>>{};
    final colors = AppColors.of(context);

    final content = Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            widget.showHeader ? 16 : 0,
            AppDimensions.screenPadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showHeader) ...[
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    AppStrings.signs,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingS),
              ],
              AppPillSearchField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
              ),
            ],
          ),
        ),
            Expanded(
              child: signsAsync.when(
                data: (signs) {
                  final signCategories = <_SignCategoryMeta>[];
                  signs.forEach((title, value) {
                    if (value is Map && value.isNotEmpty) {
                      final icon = _kSignCategoryIcons[title] ??
                          _kSignCategoryFallbackIcon;
                      signCategories.add(
                        _SignCategoryMeta(
                          title: title,
                          assetPath: 'assets/images/category_icons/$icon',
                          signs: Map<String, dynamic>.from(value),
                        ),
                      );
                    }
                  });

                  final markupCategories = <_SignCategoryMeta>[];
                  markup.forEach((group, entries) {
                    if (entries.isNotEmpty) {
                      final icon = _markupIcons[group] ?? 'markup_horizontal.svg';
                      markupCategories.add(
                        _SignCategoryMeta(
                          title: group,
                          assetPath: 'assets/images/category_icons/$icon',
                          markupEntries: entries
                              .map((e) => MarkupEntry(
                                    title: e['title'] ?? '',
                                    description: e['description'] ?? '',
                                  ))
                              .toList(),
                        ),
                      );
                    }
                  });

                  final categories = [...signCategories, ...markupCategories];

                  final normalizedQuery = _query.trim().toLowerCase();
                  final filteredCategories = normalizedQuery.isEmpty
                      ? categories
                      : categories
                          .where(
                            (c) => c.title.toLowerCase().contains(
                                  normalizedQuery,
                                ),
                          )
                          .toList();

                  if (filteredCategories.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(
                          AppDimensions.screenPadding,
                        ),
                        child: Text(
                          appL10n.nothingFoundTryAnother,
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

                  return ListView.builder(
                    padding: const EdgeInsets.all(AppDimensions.screenPadding),
                    itemCount: filteredCategories.length,
                    itemBuilder: (context, index) {
                      final category = filteredCategories[index];
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppDimensions.spacingM,
                        ),
                        child: _buildSignCategory(context, category),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(dataLoadErrorMessage(e))),
              ),
            ),
          ],
        );

    if (!widget.showHeader) {
      return content;
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: content,
      ),
    );
  }

  Widget _buildSignCategory(BuildContext context, _SignCategoryMeta category) {
    final colors = AppColors.of(context);
    final signsMap = category.signs is Map<String, dynamic>
        ? category.signs as Map<String, dynamic>
        : <String, dynamic>{};
    final itemCount = category.markupEntries?.length ?? signsMap.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        onTap: () {
          HapticFeedbackHelper.tap();
          if (category.markupEntries != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MarkupCategoryScreen(
                  title: category.title,
                  iconAssetPath: category.assetPath,
                  entries: category.markupEntries!,
                ),
              ),
            );
            return;
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SignCategoryScreen(
                categoryName: category.title,
                signs: signsMap,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(AppDimensions.spacingL),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: SvgPicture.asset(category.assetPath),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Text(
                  category.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.gray,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$itemCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingS),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SignCategoryScreen extends StatelessWidget {
  final String categoryName;
  final Map<String, dynamic> signs;

  const SignCategoryScreen({
    super.key,
    required this.categoryName,
    required this.signs,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final entries = signs.entries.toList();

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
                      categoryName,
                      style: TextStyle(
                        fontSize: 22,
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxisCount = width >= 900
                      ? 5
                      : width >= 680
                      ? 4
                      : width >= 430
                      ? 3
                      : 2;

                  return GridView.builder(
                    padding: const EdgeInsets.all(
                      AppDimensions.screenPadding,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: AppDimensions.spacingM,
                      crossAxisSpacing: AppDimensions.spacingM,
                      childAspectRatio: 0.88,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                            final entry = entries[index];
                            final signNumber = entry.key;
                            final signData =
                                entry.value as Map<String, dynamic>;
                            final signName =
                                signData['title'] as String? ??
                                signData['name'] as String? ??
                                signNumber;
                            final rawImage = signData['image'] as String?;
                            final signImage =
                                rawImage != null && rawImage.isNotEmpty
                                ? rawImage.split('/').last
                                : null;

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppDimensions.cardRadius,
                                ),
                                onTap: () {
                                  HapticFeedbackHelper.tap();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SignDetailScreen(
                                        signNumber: signNumber,
                                        signName: signName,
                                        signImage: signImage,
                                        signDescription:
                                            signData['description'] as String?,
                                        signFolkName:
                                            signData['folkName'] as String?,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(
                                    AppDimensions.spacingM,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.cardBackground,
                                    borderRadius: BorderRadius.circular(
                                      AppDimensions.cardRadius,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: Center(
                                          child: signImage != null
                                              ? SizedBox(
                                                  width: 88,
                                                  height: 88,
                                                  child:
                                                      signImage.endsWith('.svg')
                                                      ? SvgPicture.asset(
                                                          '${CountryConfig.current.signImagesDir}/$signImage',
                                                          fit: BoxFit.contain,
                                                        )
                                                      : Image.asset(
                                                          '${CountryConfig.current.signImagesDir}/$signImage',
                                                          fit: BoxFit.contain,
                                                          errorBuilder:
                                                              (
                                                                _,
                                                                __,
                                                                ___,
                                                              ) => Icon(
                                                                Icons.signpost,
                                                                size: 48,
                                                                color: colors
                                                                    .secondaryText,
                                                              ),
                                                        ),
                                                )
                                              : Icon(
                                                  Icons.signpost,
                                                  size: 48,
                                                  color:
                                                      colors.secondaryText,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(
                                        height: AppDimensions.spacingS,
                                      ),
                                      Text(
                                        signNumber,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: colors.accent,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        signName,
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.3,
                                          color: colors.primaryText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignCategoryMeta {
  final String title;
  final String assetPath;
  final dynamic signs;
  final List<MarkupEntry>? markupEntries;

  const _SignCategoryMeta({
    required this.title,
    required this.assetPath,
    this.signs,
    this.markupEntries,
  });
}
