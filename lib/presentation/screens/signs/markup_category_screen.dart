import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

class MarkupEntry {
  const MarkupEntry({
    required this.number,
    required this.title,
    required this.image,
    required this.description,
  });

  final String number;
  final String title;
  final String image;
  final String description;

  String get assetPath =>
      '${CountryConfig.current.markupImagesDir}/${image.split('/').last}';
}

class MarkupCategoryScreen extends StatelessWidget {
  const MarkupCategoryScreen({
    super.key,
    required this.title,
    required this.iconAssetPath,
    required this.entries,
  });

  final String title;
  final String iconAssetPath;
  final List<MarkupEntry> entries;

  void _showImage(BuildContext context, MarkupEntry entry) {
    HapticFeedbackHelper.tap();
    showDialog<void>(
      context: context,
      builder: (context) {
        final colors = AppColors.of(context);
        return Dialog(
          backgroundColor: colors.cardBackground,
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.spacingL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.number,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Flexible(
                  child: SizedBox(
                    width: double.infinity,
                    height: MediaQuery.sizeOf(context).height * 0.5,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: SvgPicture.asset(
                        entry.assetPath,
                        fit: BoxFit.contain,
                        semanticsLabel: '${entry.number} ${entry.title}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: SvgPicture.asset(iconAssetPath),
                  ),
                  const SizedBox(width: AppDimensions.spacingM),
                  Expanded(
                    child: Text(
                      title,
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
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.screenPadding,
                  0,
                  AppDimensions.screenPadding,
                  24,
                ),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
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
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (entry.image.isNotEmpty) ...[
                            Semantics(
                              button: true,
                              label: '${entry.number} ${entry.title}',
                              child: InkWell(
                                key: ValueKey('markup-image-${entry.number}'),
                                onTap: () => _showImage(context, entry),
                                borderRadius: BorderRadius.circular(
                                  AppDimensions.cardRadius,
                                ),
                                child: SizedBox(
                                  height: 140,
                                  width: double.infinity,
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      AppDimensions.spacingS,
                                    ),
                                    child: SvgPicture.asset(
                                      entry.assetPath,
                                      fit: BoxFit.contain,
                                      excludeFromSemantics: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppDimensions.spacingM),
                          ],
                          Text(
                            entry.number,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.accent,
                            ),
                          ),
                          const SizedBox(height: AppDimensions.spacingS),
                          Text(
                            entry.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                              color: colors.primaryText,
                            ),
                          ),
                          const SizedBox(height: AppDimensions.spacingS),
                          Text(
                            entry.description,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
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
