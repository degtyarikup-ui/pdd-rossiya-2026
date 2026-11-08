import 'package:flutter/widgets.dart';
import 'package:pdd_app/l10n/l10n.dart';

class DriverTip {
  final String id;
  final String title;
  final String description;
  final String category;
  final String iconKey;
  final String imagePath;

  const DriverTip({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.iconKey,
    this.imagePath = '',
  });
}

class DriverTipsData {
  static final Map<String, List<DriverTip>> _localized = {};

  static List<DriverTip> get tips => getTips('ru');

  static AppLocalizations _strings(String? lang) => lookupAppLocalizations(
    Locale(lang == 'en' || lang == 'kk' ? lang! : 'ru'),
  );

  static List<DriverTip> getTips([String? lang]) {
    final code = lang == 'en' || lang == 'kk' ? lang! : 'ru';
    return _localized.putIfAbsent(code, () => _build(_strings(code)));
  }

  static DriverTip _tip(
    String id,
    String title,
    String body,
    String category,
    String icon,
  ) => DriverTip(
    id: id,
    title: title,
    description: body,
    category: category,
    iconKey: icon,
    imagePath: 'assets/images/tips/$id.webp',
  );

  static List<DriverTip> _build(AppLocalizations l) => List.unmodifiable([
    _tip('tip_1', l.driverTip1Title, l.driverTip1Body, 'safety', 'timer'),
    _tip('tip_2', l.driverTip2Title, l.driverTip2Body, 'weather', 'water'),
    _tip('tip_3', l.driverTip3Title, l.driverTip3Body, 'mirrors', 'visibility'),
    _tip('tip_4', l.driverTip4Title, l.driverTip4Body, 'rules', 'roundabout'),
    _tip('tip_5', l.driverTip5Title, l.driverTip5Body, 'winter', 'car_drive'),
    _tip('tip_6', l.driverTip6Title, l.driverTip6Body, 'safety', 'car_drive'),
    _tip('tip_7', l.driverTip7Title, l.driverTip7Body, 'rules', 'stop_sign'),
    _tip('tip_8', l.driverTip8Title, l.driverTip8Body, 'highway', 'truck'),
    _tip('tip_9', l.driverTip9Title, l.driverTip9Body, 'rules', 'slope'),
    _tip(
      'tip_10',
      l.driverTip10Title,
      l.driverTip10Body,
      'safety',
      'traffic_light',
    ),
    _tip('tip_11', l.driverTip11Title, l.driverTip11Body, 'winter', 'ice'),
    _tip(
      'tip_12',
      l.driverTip12Title,
      l.driverTip12Body,
      'safety',
      'turn_left',
    ),
    _tip(
      'tip_13',
      l.driverTip13Title,
      l.driverTip13Body,
      'highway',
      'blind_spot',
    ),
    _tip(
      'tip_14',
      l.driverTip14Title,
      l.driverTip14Body,
      'safety',
      'pedestrian',
    ),
    _tip(
      'tip_15',
      l.driverTip15Title,
      l.driverTip15Body,
      'maneuver',
      'turn_right',
    ),
    _tip('tip_16', l.driverTip16Title, l.driverTip16Body, 'comfort', 'wind'),
    _tip(
      'tip_17',
      l.driverTip17Title,
      l.driverTip17Body,
      'parking',
      'parking_icon',
    ),
    _tip('tip_18', l.driverTip18Title, l.driverTip18Body, 'weather', 'fog'),
    _tip(
      'tip_19',
      l.driverTip19Title,
      l.driverTip19Body,
      'rules',
      'hazard_triangle',
    ),
    _tip('tip_20', l.driverTip20Title, l.driverTip20Body, 'safety', 'rest'),
  ]);

  static String resolveCategoryTitle(String category, [String? lang]) {
    final l = _strings(lang);
    return switch (category.toLowerCase()) {
      'safety' => l.driverTipCategorySafety,
      'weather' => l.driverTipCategoryWeather,
      'winter' => l.driverTipCategoryWinter,
      'rules' => l.driverTipCategoryRules,
      'highway' => l.driverTipCategoryHighway,
      'maneuver' => l.driverTipCategoryManeuver,
      'parking' => l.driverTipCategoryParking,
      'comfort' => l.driverTipCategoryComfort,
      'fuel' => l.driverTipCategoryFuel,
      'mirrors' => l.driverTipCategoryMirrors,
      _ => l.driverTipCategoryOther,
    };
  }
}
