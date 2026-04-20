import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

class MarkupEntry {
  const MarkupEntry({required this.title, required this.description});

  final String title;
  final String description;
}

const List<MarkupEntry> horizontalMarkupEntries = [
  MarkupEntry(
    title: 'Сплошные линии',
    description:
        'Разделяют потоки противоположных направлений, обозначают край проезжей части и ограничивают пересечение.',
  ),
  MarkupEntry(
    title: 'Прерывистые линии',
    description:
        'Разрешают перестроение и помогают ориентироваться по полосам движения.',
  ),
  MarkupEntry(
    title: 'Желтая разметка',
    description: 'Используется для зон, где запрещены остановка или стоянка.',
  ),
  MarkupEntry(
    title: 'Комбинированные линии',
    description:
        'Правила пересечения зависят от стороны, с которой водитель подъезжает к линии.',
  ),
  MarkupEntry(
    title: 'Пешеходные переходы',
    description:
        'Выделяют место перехода и усиливают внимание водителя при приближении к пешеходам.',
  ),
  MarkupEntry(
    title: 'Стоп-линии',
    description:
        'Показывают точку обязательной остановки перед перекрестком, светофором или знаком STOP.',
  ),
  MarkupEntry(
    title: 'Направления по полосам',
    description:
        'Стрелы и надписи подсказывают, в каком направлении разрешено движение с каждой полосы.',
  ),
  MarkupEntry(
    title: 'Специальные полосы и остановки',
    description:
        'Обозначают полосы для маршрутного транспорта, велосипедистов и места остановки общественного транспорта.',
  ),
];

const List<MarkupEntry> verticalMarkupEntries = [
  MarkupEntry(
    title: 'Опоры и выступающие элементы',
    description:
        'Помогают заранее заметить опоры мостов, путепроводов и другие массивные препятствия у дороги.',
  ),
  MarkupEntry(
    title: 'Нижний габарит сооружений',
    description:
        'Подчеркивают нижний край тоннелей, мостов и путепроводов, где важно контролировать высоту транспорта.',
  ),
  MarkupEntry(
    title: 'Ограждения на опасных участках',
    description:
        'Используются на закруглениях, крутых спусках и в местах, где особенно важна визуальная ориентация.',
  ),
  MarkupEntry(
    title: 'Ограждения на обычных участках',
    description:
        'Выделяют боковые поверхности дорожных ограждений там, где требуется дополнительная заметность.',
  ),
  MarkupEntry(
    title: 'Бордюры и направляющие элементы',
    description:
        'Подсказывают контур островков безопасности, бордюров и направляющих сооружений в темное время суток.',
  ),
];

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

  @override
  Widget build(BuildContext context) {
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
                  Container(
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.lightAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SvgPicture.asset(iconAssetPath),
                  ),
                  const SizedBox(width: AppDimensions.spacingM),
                  Expanded(
                    child: Text(
                      title,
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
                      padding: const EdgeInsets.all(
                        AppDimensions.spacingL,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(
                          AppDimensions.cardRadius,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                              color: AppColors.primaryText,
                            ),
                          ),
                          const SizedBox(height: AppDimensions.spacingS),
                          Text(
                            entry.description,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: AppColors.secondaryText,
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
