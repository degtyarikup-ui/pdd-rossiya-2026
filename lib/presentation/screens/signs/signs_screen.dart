import 'package:flutter/material.dart';
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

class SignsScreen extends ConsumerStatefulWidget {
  const SignsScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final signsAsync = ref.watch(signsProvider);

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
                      AppStrings.signs,
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
                  ),
                ],
              ),
            ),
            Expanded(
              child: signsAsync.when(
                data: (signs) {
                  final categories = [
                    _SignCategoryMeta(
                      title: 'Предупреждающие знаки',
                      assetPath: 'assets/images/category_icons/warning.svg',
                      signs: signs['Предупреждающие знаки'],
                    ),
                    _SignCategoryMeta(
                      title: 'Знаки приоритета',
                      assetPath: 'assets/images/category_icons/priority.svg',
                      signs: signs['Знаки приоритета'],
                    ),
                    _SignCategoryMeta(
                      title: 'Запрещающие знаки',
                      assetPath: 'assets/images/category_icons/prohibitory.svg',
                      signs: signs['Запрещающие знаки'],
                    ),
                    _SignCategoryMeta(
                      title: 'Предписывающие знаки',
                      assetPath: 'assets/images/category_icons/mandatory.svg',
                      signs: signs['Предписывающие знаки'],
                    ),
                    _SignCategoryMeta(
                      title: 'Знаки особых предписаний',
                      assetPath:
                          'assets/images/category_icons/special_prescriptions.svg',
                      signs: signs['Знаки особых предписаний'],
                    ),
                    _SignCategoryMeta(
                      title: 'Информационные знаки',
                      assetPath: 'assets/images/category_icons/information.svg',
                      signs: signs['Информационные знаки'],
                    ),
                    _SignCategoryMeta(
                      title: 'Знаки сервиса',
                      assetPath: 'assets/images/category_icons/service.svg',
                      signs: signs['Знаки сервиса'],
                    ),
                    _SignCategoryMeta(
                      title: 'Знаки дополнительной информации',
                      assetPath:
                          'assets/images/category_icons/additional_info.svg',
                      signs:
                          signs['Знаки дополнительной информации (таблички)'],
                    ),
                    const _SignCategoryMeta(
                      title: 'Горизонтальная разметка',
                      assetPath:
                          'assets/images/category_icons/markup_horizontal.svg',
                      markupEntries: horizontalMarkupEntries,
                    ),
                    const _SignCategoryMeta(
                      title: 'Вертикальная разметка',
                      assetPath:
                          'assets/images/category_icons/markup_vertical.svg',
                      markupEntries: verticalMarkupEntries,
                    ),
                  ];

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
                          'Ничего не найдено. Попробуйте другое слово.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppColors.secondaryText,
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
        ),
      ),
    );
  }

  Widget _buildSignCategory(BuildContext context, _SignCategoryMeta category) {
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
            color: AppColors.cardBackground,
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    color: AppColors.primaryText,
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
                  color: AppColors.gray,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$itemCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingS),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.secondaryText,
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
    final entries = signs.entries.toList();

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
                      categoryName,
                      style: const TextStyle(
                        fontSize: 22,
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
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(
                                    AppDimensions.spacingM,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardBackground,
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
                                                              ) => const Icon(
                                                                Icons.signpost,
                                                                size: 48,
                                                                color: AppColors
                                                                    .secondaryText,
                                                              ),
                                                        ),
                                                )
                                              : const Icon(
                                                  Icons.signpost,
                                                  size: 48,
                                                  color:
                                                      AppColors.secondaryText,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(
                                        height: AppDimensions.spacingS,
                                      ),
                                      Text(
                                        signNumber,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        signName,
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          height: 1.3,
                                          color: AppColors.primaryText,
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
