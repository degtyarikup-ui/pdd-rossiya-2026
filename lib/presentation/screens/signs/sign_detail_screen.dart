import 'package:flutter/material.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

class SignDetailScreen extends StatelessWidget {
  final String signNumber;
  final String signName;
  final String? signImage;
  final String? signDescription;

  const SignDetailScreen({
    super.key,
    required this.signNumber,
    required this.signName,
    this.signImage,
    this.signDescription,
  });

  @override
  Widget build(BuildContext context) {
    final description = signDescription?.trim();

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                            color: AppColors.primaryText,
                          ),
                        ),
                      ],
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
                  Container(
                    width: double.infinity,
                    height: 260,
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(
                        AppDimensions.cardRadius,
                      ),
                    ),
                    child: Center(
                      child: signImage != null
                          ? (signImage!.endsWith('.svg')
                                ? SvgPicture.asset(
                                    '${CountryConfig.current.signImagesDir}/$signImage',
                                    fit: BoxFit.contain,
                                    height: 180,
                                  )
                                : Image.asset(
                                    '${CountryConfig.current.signImagesDir}/$signImage',
                                    fit: BoxFit.contain,
                                    height: 180,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.signpost,
                                      size: 88,
                                      color: AppColors.secondaryText,
                                    ),
                                  ))
                          : const Icon(
                              Icons.signpost,
                              size: 88,
                              color: AppColors.secondaryText,
                            ),
                    ),
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: AppDimensions.spacingL),
                    Container(
                      padding: const EdgeInsets.all(AppDimensions.spacingL),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(
                          AppDimensions.cardRadius,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Описание',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                              color: AppColors.primaryText,
                            ),
                          ),
                          const SizedBox(height: AppDimensions.spacingS),
                          Text(
                            description,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: AppColors.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
