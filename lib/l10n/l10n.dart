import 'package:flutter/widgets.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/l10n/gen/app_localizations.dart';

export 'package:pdd_app/l10n/gen/app_localizations.dart';

Locale _appLocale = Locale(CountryConfig.current.language);
AppLocalizations _cachedAppL10n = lookupAppLocalizations(_appLocale);

/// Локализация текущей сборки / выбранного языка.
/// Предоставляет context-free доступ: строки берём из этого объекта где угодно
/// (в т.ч. вне виджетов, сервисах и репозиториях).
AppLocalizations get appL10n => _cachedAppL10n;

/// Обновляет текущую локаль приложения для context-free вызовов [appL10n].
void updateAppLocale(Locale locale) {
  _appLocale = locale;
  _cachedAppL10n = lookupAppLocalizations(locale);
}

/// Доступ через context, если удобнее в виджете.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
