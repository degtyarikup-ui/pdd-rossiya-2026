import 'package:flutter/material.dart';
import 'package:pdd_app/data/models/ticket_category.dart';

class AppSettings {
  final bool hapticsEnabled;
  final bool soundEffectsEnabled;
  final bool confirmAnswerEnabled;
  final bool voiceEnabled;
  final TicketCategory ticketCategory;
  final ThemeMode themeMode;
  /// `false` — показать онбординг выбора A/B vs C/D. До загрузки из хранилища держим `true`.
  final bool vehicleOnboardingCompleted;

  const AppSettings({
    this.hapticsEnabled = true,
    this.soundEffectsEnabled = true,
    this.confirmAnswerEnabled = false,
    this.voiceEnabled = false,
    this.ticketCategory = TicketCategory.ab,
    this.themeMode = ThemeMode.system,
    this.vehicleOnboardingCompleted = true,
  });

  AppSettings copyWith({
    bool? hapticsEnabled,
    bool? soundEffectsEnabled,
    bool? confirmAnswerEnabled,
    bool? voiceEnabled,
    TicketCategory? ticketCategory,
    ThemeMode? themeMode,
    bool? vehicleOnboardingCompleted,
  }) {
    return AppSettings(
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
      confirmAnswerEnabled: confirmAnswerEnabled ?? this.confirmAnswerEnabled,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      ticketCategory: ticketCategory ?? this.ticketCategory,
      themeMode: themeMode ?? this.themeMode,
      vehicleOnboardingCompleted:
          vehicleOnboardingCompleted ?? this.vehicleOnboardingCompleted,
    );
  }

  static ThemeMode parseThemeMode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  factory AppSettings.fromJson(Map<String, dynamic>? json) {
    final map = json ?? <String, dynamic>{};
    final migratedOnboarding = map['vehicleOnboardingCompleted'] as bool? ??
        (map.isEmpty ? false : true);

    return AppSettings(
      hapticsEnabled: map['hapticsEnabled'] as bool? ?? true,
      soundEffectsEnabled: map['soundEffectsEnabled'] as bool? ?? true,
      confirmAnswerEnabled: map['confirmAnswerEnabled'] as bool? ?? false,
      voiceEnabled: map['voiceEnabled'] as bool? ?? false,
      ticketCategory: TicketCategory.parse(map['ticketCategory'] as String?),
      themeMode: parseThemeMode(map['themeMode'] as String?),
      vehicleOnboardingCompleted: migratedOnboarding,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hapticsEnabled': hapticsEnabled,
      'soundEffectsEnabled': soundEffectsEnabled,
      'confirmAnswerEnabled': confirmAnswerEnabled,
      'voiceEnabled': voiceEnabled,
      'ticketCategory': ticketCategory.name,
      'themeMode': themeMode.name,
      'vehicleOnboardingCompleted': vehicleOnboardingCompleted,
    };
  }
}

