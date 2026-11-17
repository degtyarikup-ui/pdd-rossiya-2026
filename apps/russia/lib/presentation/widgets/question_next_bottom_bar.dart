import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Квадратная кнопка переключения избранного, выровненная по высоте
/// основной кнопки перехода к следующему вопросу.
class QuestionFavoriteButton extends StatelessWidget {
  const QuestionFavoriteButton({
    super.key,
    required this.isFavorite,
    required this.onPressed,
    this.size = 56,
  });

  final bool isFavorite;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tooltip = isFavorite
        ? appL10n.removeFromFavorites
        : appL10n.addToFavorites;

    return Semantics(
      toggled: isFavorite,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isFavorite ? colors.goldLightSurface : colors.gray,
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    key: ValueKey(isFavorite),
                    size: 24,
                    color: isFavorite ? colors.gold : colors.primaryText,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Нижняя панель после ответа на вопрос (и в разборе экзамена):
/// основная кнопка «Следующий вопрос» / «Завершить» и кнопка избранного.
class QuestionNextBottomBar extends StatelessWidget {
  const QuestionNextBottomBar({
    super.key,
    required this.actionLabel,
    required this.onAction,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.showFavorite = true,
  });

  final String actionLabel;
  final VoidCallback? onAction;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final bool showFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      color: colors.cardBackground,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                ),
                onPressed: onAction,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    actionLabel,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            if (showFavorite) ...[
              const SizedBox(width: AppDimensions.spacingM),
              QuestionFavoriteButton(
                isFavorite: isFavorite,
                onPressed: onToggleFavorite,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
