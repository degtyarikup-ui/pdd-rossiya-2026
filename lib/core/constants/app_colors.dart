import 'package:flutter/material.dart';

/// Design tokens for light and dark themes.
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color accent;
  final Color lightAccent;
  final Color primaryText;
  final Color secondaryText;
  final Color background;
  final Color cardBackground;
  final Color green;
  final Color greenLight;
  final Color red;
  final Color redLight;
  final Color gray;
  final Color lightBlueGray;
  final Color searchFieldFill;
  final Color gold;
  final Color goldLightSurface;
  final Color divider;
  final Color homeScreenBackground;
  final Color homeStatGraySurface;
  final Color accentSurface10;
  final Color homeRedSurface;
  final Color homeGreenSurface;
  final Color white;
  final Color black;
  final bool isDark;

  const AppThemeColors({
    required this.accent,
    required this.lightAccent,
    required this.primaryText,
    required this.secondaryText,
    required this.background,
    required this.cardBackground,
    required this.green,
    required this.greenLight,
    required this.red,
    required this.redLight,
    required this.gray,
    required this.lightBlueGray,
    required this.searchFieldFill,
    required this.gold,
    required this.goldLightSurface,
    required this.divider,
    required this.homeScreenBackground,
    required this.homeStatGraySurface,
    required this.accentSurface10,
    required this.homeRedSurface,
    required this.homeGreenSurface,
    this.white = const Color(0xFFFFFFFF),
    this.black = const Color(0xFF000000),
    required this.isDark,
  });

  static const light = AppThemeColors(
    accent: Color(0xFF0574F8),
    lightAccent: Color(0xFFE8F2FE),
    primaryText: Color(0xFF121212),
    secondaryText: Color(0xFFA1A6B7),
    background: Color(0xFFF8F8FA),
    cardBackground: Color(0xFFFFFFFF),
    green: Color(0xFF34A853),
    greenLight: Color(0xFFE6F7DE),
    red: Color(0xFFEA4335),
    redLight: Color(0xFFFFE6E6),
    gray: Color(0xFFEFF0F4),
    lightBlueGray: Color(0xFFEFF0F4),
    searchFieldFill: Color(0xFFF2F2F7),
    gold: Color(0xFFFFA53C),
    goldLightSurface: Color(0xFFFFF1E6),
    divider: Color(0xFFE8E8E8),
    homeScreenBackground: Color(0xFFF8F9FA),
    homeStatGraySurface: Color(0xFFF5F5F5),
    accentSurface10: Color(0x1A0574F8),
    homeRedSurface: Color(0xFFFFEBEE),
    homeGreenSurface: Color(0xFFE8F5E9),
    white: Color(0xFFFFFFFF),
    black: Color(0xFF000000),
    isDark: false,
  );

  static const dark = AppThemeColors(
    accent: Color(0xFF298BFE),
    lightAccent: Color(0xFF18283C),
    primaryText: Color(0xFFF2F3F7),
    secondaryText: Color(0xFF8A90A2),
    background: Color(0xFF121214),
    cardBackground: Color(0xFF1C1D22),
    green: Color(0xFF34C759),
    greenLight: Color(0xFF162B1D),
    red: Color(0xFFFF453A),
    redLight: Color(0xFF341717),
    gray: Color(0xFF25272E),
    lightBlueGray: Color(0xFF25272E),
    searchFieldFill: Color(0xFF202229),
    gold: Color(0xFFFFA53C),
    goldLightSurface: Color(0xFF2E2215),
    divider: Color(0xFF22242B),
    homeScreenBackground: Color(0xFF121214),
    homeStatGraySurface: Color(0xFF1C1D22),
    accentSurface10: Color(0x2E298BFE),
    homeRedSurface: Color(0xFF341717),
    homeGreenSurface: Color(0xFF162B1D),
    white: Color(0xFFFFFFFF),
    black: Color(0xFF000000),
    isDark: true,
  );

  @override
  AppThemeColors copyWith({
    Color? accent,
    Color? lightAccent,
    Color? primaryText,
    Color? secondaryText,
    Color? background,
    Color? cardBackground,
    Color? green,
    Color? greenLight,
    Color? red,
    Color? redLight,
    Color? gray,
    Color? lightBlueGray,
    Color? searchFieldFill,
    Color? gold,
    Color? goldLightSurface,
    Color? divider,
    Color? homeScreenBackground,
    Color? homeStatGraySurface,
    Color? accentSurface10,
    Color? homeRedSurface,
    Color? homeGreenSurface,
    Color? white,
    Color? black,
    bool? isDark,
  }) {
    return AppThemeColors(
      accent: accent ?? this.accent,
      lightAccent: lightAccent ?? this.lightAccent,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      background: background ?? this.background,
      cardBackground: cardBackground ?? this.cardBackground,
      green: green ?? this.green,
      greenLight: greenLight ?? this.greenLight,
      red: red ?? this.red,
      redLight: redLight ?? this.redLight,
      gray: gray ?? this.gray,
      lightBlueGray: lightBlueGray ?? this.lightBlueGray,
      searchFieldFill: searchFieldFill ?? this.searchFieldFill,
      gold: gold ?? this.gold,
      goldLightSurface: goldLightSurface ?? this.goldLightSurface,
      divider: divider ?? this.divider,
      homeScreenBackground:
          homeScreenBackground ?? this.homeScreenBackground,
      homeStatGraySurface: homeStatGraySurface ?? this.homeStatGraySurface,
      accentSurface10: accentSurface10 ?? this.accentSurface10,
      homeRedSurface: homeRedSurface ?? this.homeRedSurface,
      homeGreenSurface: homeGreenSurface ?? this.homeGreenSurface,
      white: white ?? this.white,
      black: black ?? this.black,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      accent: Color.lerp(accent, other.accent, t)!,
      lightAccent: Color.lerp(lightAccent, other.lightAccent, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      background: Color.lerp(background, other.background, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      green: Color.lerp(green, other.green, t)!,
      greenLight: Color.lerp(greenLight, other.greenLight, t)!,
      red: Color.lerp(red, other.red, t)!,
      redLight: Color.lerp(redLight, other.redLight, t)!,
      gray: Color.lerp(gray, other.gray, t)!,
      lightBlueGray: Color.lerp(lightBlueGray, other.lightBlueGray, t)!,
      searchFieldFill: Color.lerp(searchFieldFill, other.searchFieldFill, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      goldLightSurface: Color.lerp(goldLightSurface, other.goldLightSurface, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      homeScreenBackground:
          Color.lerp(homeScreenBackground, other.homeScreenBackground, t)!,
      homeStatGraySurface:
          Color.lerp(homeStatGraySurface, other.homeStatGraySurface, t)!,
      accentSurface10: Color.lerp(accentSurface10, other.accentSurface10, t)!,
      homeRedSurface: Color.lerp(homeRedSurface, other.homeRedSurface, t)!,
      homeGreenSurface: Color.lerp(homeGreenSurface, other.homeGreenSurface, t)!,
      white: Color.lerp(white, other.white, t)!,
      black: Color.lerp(black, other.black, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

class AppColors {
  AppColors._();

  /// Retrieve current theme colors from BuildContext.
  static AppThemeColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppThemeColors>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark
        ? AppThemeColors.dark
        : AppThemeColors.light;
  }

  // --- Static fallback & constant tokens (backward compatibility) ---
  static const Color accent = Color(0xFF0574F8);
  static const Color lightAccent = Color(0xFFE8F2FE);
  static const Color primaryText = Color(0xFF121212);
  static const Color secondaryText = Color(0xFFA1A6B7);
  static const Color background = Color(0xFFF8F8FA);
  static const Color white = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color green = Color(0xFF34A853);
  static const Color greenLight = Color(0xFFE6F7DE);
  static const Color red = Color(0xFFEA4335);
  static const Color redLight = Color(0xFFFFE6E6);
  static const Color gray = Color(0xFFEFF0F4);
  static const Color lightBlueGray = Color(0xFFEFF0F4);
  static const Color searchFieldFill = Color(0xFFF2F2F7);
  static const Color gold = Color(0xFFFFA53C);
  static const Color goldLightSurface = Color(0xFFFFF1E6);
  static const Color divider = Color(0xFFE8E8E8);
  static const Color black = Color(0xFF000000);

  static const Color homeScreenBackground = Color(0xFFF8F9FA);
  static const Color homeStatGraySurface = Color(0xFFF5F5F5);
  static const Color accentSurface10 = Color(0x1A0574F8);
  static const Color homeRedSurface = Color(0xFFFFEBEE);
  static const Color homeGreenSurface = Color(0xFFE8F5E9);
}

extension AppColorsBuildContextExtension on BuildContext {
  AppThemeColors get colors => AppColors.of(this);
}

