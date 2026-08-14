import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';

/// Квадратная кнопка-иконка «хром» приложения (закрыть, назад, поделиться…).
///
/// По умолчанию — нейтральная (подложка [AppColors.cardBackground], тёмная
/// иконка). Цвета можно переопределить, не ломая существующие вызовы: напр.
/// синяя кнопка «поделиться» — `backgroundColor: AppColors.accent`,
/// `iconColor: AppColors.white`.
class AppChromeIconButton extends StatelessWidget {
  const AppChromeIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child:
              Icon(icon, size: 18, color: iconColor ?? AppColors.primaryText),
        ),
      ),
    );
  }
}
