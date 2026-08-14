import 'package:flutter/widgets.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/l10n/gen/app_localizations.dart';

export 'package:pdd_app/l10n/gen/app_localizations.dart';

/// Локализация текущей сборки. Язык фиксирован конфигом страны
/// ([CountryConfig.language]) — рантайм-переключателя нет, поэтому доступ
/// context-free: строки берём из этого объекта где угодно (в т.ч. вне виджетов).
final AppLocalizations appL10n = lookupAppLocalizations(
  Locale(CountryConfig.current.language),
);

/// Доступ через context, если удобнее в виджете.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
