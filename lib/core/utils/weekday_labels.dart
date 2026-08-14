import 'package:pdd_app/l10n/l10n.dart';

/// Короткие названия дней недели, начиная с понедельника.
///
/// Индекс совпадает с `DateTime.weekday - 1`, поэтому подпись к дате берётся
/// как `weekdayShortLabels()[date.weekday - 1]`.
List<String> weekdayShortLabels() => [
      appL10n.weekdayMon,
      appL10n.weekdayTue,
      appL10n.weekdayWed,
      appL10n.weekdayThu,
      appL10n.weekdayFri,
      appL10n.weekdaySat,
      appL10n.weekdaySun,
    ];
