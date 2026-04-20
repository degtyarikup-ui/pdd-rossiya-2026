import 'package:pdd_app/data/models/ticket_category.dart';

class AppSettings {
  final bool hapticsEnabled;
  final bool confirmAnswerEnabled;
  final bool voiceEnabled;
  final TicketCategory ticketCategory;
  /// `false` — показать онбординг выбора A/B vs C/D. До загрузки из хранилища держим `true`.
  final bool vehicleOnboardingCompleted;

  const AppSettings({
    this.hapticsEnabled = true,
    this.confirmAnswerEnabled = false,
    this.voiceEnabled = false,
    this.ticketCategory = TicketCategory.ab,
    this.vehicleOnboardingCompleted = true,
  });

  AppSettings copyWith({
    bool? hapticsEnabled,
    bool? confirmAnswerEnabled,
    bool? voiceEnabled,
    TicketCategory? ticketCategory,
    bool? vehicleOnboardingCompleted,
  }) {
    return AppSettings(
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      confirmAnswerEnabled: confirmAnswerEnabled ?? this.confirmAnswerEnabled,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      ticketCategory: ticketCategory ?? this.ticketCategory,
      vehicleOnboardingCompleted:
          vehicleOnboardingCompleted ?? this.vehicleOnboardingCompleted,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic>? json) {
    final map = json ?? <String, dynamic>{};
    final migratedOnboarding = map['vehicleOnboardingCompleted'] as bool? ??
        (map.isEmpty ? false : true);

    return AppSettings(
      hapticsEnabled: map['hapticsEnabled'] as bool? ?? true,
      confirmAnswerEnabled: map['confirmAnswerEnabled'] as bool? ?? false,
      voiceEnabled: map['voiceEnabled'] as bool? ?? false,
      ticketCategory: TicketCategory.parse(map['ticketCategory'] as String?),
      vehicleOnboardingCompleted: migratedOnboarding,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hapticsEnabled': hapticsEnabled,
      'confirmAnswerEnabled': confirmAnswerEnabled,
      'voiceEnabled': voiceEnabled,
      'ticketCategory': ticketCategory.name,
      'vehicleOnboardingCompleted': vehicleOnboardingCompleted,
    };
  }
}
