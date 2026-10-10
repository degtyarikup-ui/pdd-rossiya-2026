import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pdd_app/data/models/ticket_category.dart';

class AppSettings {
  final bool hapticsEnabled;
  final bool soundEffectsEnabled;
  final bool confirmAnswerEnabled;
  final bool voiceEnabled;
  final bool notificationsEnabled;
  final bool pushMessagesEnabled;
  final TicketCategory ticketCategory;
  final ThemeMode themeMode;

  /// Код языка интерфейса: 'system' (по умолчанию), 'ru', 'en', 'kk'.
  final String languageCode;

  /// `false` — показать онбординг выбора A/B vs C/D. До загрузки из хранилища держим `true`.
  final bool vehicleOnboardingCompleted;

  const AppSettings({
    this.hapticsEnabled = true,
    this.soundEffectsEnabled = true,
    this.confirmAnswerEnabled = false,
    this.voiceEnabled = false,
    this.notificationsEnabled = true,
    this.pushMessagesEnabled = false,
    this.ticketCategory = TicketCategory.ab,
    this.themeMode = ThemeMode.system,
    this.languageCode = 'system',
    this.vehicleOnboardingCompleted = true,
  });

  /// Определение языка интерфейса по языку системы устройства.
  /// Если язык системы английский -> 'en', казахский -> 'kk', во всех остальных случаях -> 'ru'.
  static String detectSystemLanguage([Locale? systemLocale]) {
    try {
      final locale = systemLocale ?? PlatformDispatcher.instance.locale;
      final code = locale.languageCode.toLowerCase();
      if (code == 'en') return 'en';
      if (code == 'kk' || code == 'kz') return 'kk';
      return 'ru';
    } catch (_) {
      return 'ru';
    }
  }

  /// Эффективный язык интерфейса ('ru', 'en', 'kk') с учетом системного языка.
  String get effectiveLanguageCode {
    if (languageCode == 'system') {
      return detectSystemLanguage();
    }
    if (languageCode == 'en' || languageCode == 'kk' || languageCode == 'ru') {
      return languageCode;
    }
    return detectSystemLanguage();
  }

  AppSettings copyWith({
    bool? hapticsEnabled,
    bool? soundEffectsEnabled,
    bool? confirmAnswerEnabled,
    bool? voiceEnabled,
    bool? notificationsEnabled,
    bool? pushMessagesEnabled,
    TicketCategory? ticketCategory,
    ThemeMode? themeMode,
    String? languageCode,
    bool? vehicleOnboardingCompleted,
  }) {
    return AppSettings(
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
      confirmAnswerEnabled: confirmAnswerEnabled ?? this.confirmAnswerEnabled,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      pushMessagesEnabled: pushMessagesEnabled ?? this.pushMessagesEnabled,
      ticketCategory: ticketCategory ?? this.ticketCategory,
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
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
    final migratedOnboarding =
        map['vehicleOnboardingCompleted'] as bool? ??
        (map.isEmpty ? false : true);

    return AppSettings(
      hapticsEnabled: map['hapticsEnabled'] as bool? ?? true,
      soundEffectsEnabled: map['soundEffectsEnabled'] as bool? ?? true,
      confirmAnswerEnabled: map['confirmAnswerEnabled'] as bool? ?? false,
      voiceEnabled: map['voiceEnabled'] as bool? ?? false,
      notificationsEnabled: map['notificationsEnabled'] as bool? ?? true,
      pushMessagesEnabled: map['pushMessagesEnabled'] as bool? ?? false,
      ticketCategory: TicketCategory.parse(map['ticketCategory'] as String?),
      themeMode: parseThemeMode(map['themeMode'] as String?),
      languageCode: map['languageCode'] as String? ?? 'system',
      vehicleOnboardingCompleted: migratedOnboarding,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hapticsEnabled': hapticsEnabled,
      'soundEffectsEnabled': soundEffectsEnabled,
      'confirmAnswerEnabled': confirmAnswerEnabled,
      'voiceEnabled': voiceEnabled,
      'notificationsEnabled': notificationsEnabled,
      'pushMessagesEnabled': pushMessagesEnabled,
      'ticketCategory': ticketCategory.name,
      'themeMode': themeMode.name,
      'languageCode': languageCode,
      'vehicleOnboardingCompleted': vehicleOnboardingCompleted,
    };
  }
}
