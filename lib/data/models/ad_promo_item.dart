class AdPromoItem {
  final String id;
  final bool isEnabled;
  final String badge;
  final String title;
  final String description;
  final String buttonText;
  final String buttonUrl;
  final String themeColor; // 'blue', 'green', 'gold', 'purple', 'dark'
  final String icon; // 'shield', 'car', 'star', 'gift', 'tag'
  final List<String> targetStores;

  const AdPromoItem({
    required this.id,
    this.isEnabled = true,
    required this.badge,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.buttonUrl,
    this.themeColor = 'blue',
    this.icon = 'shield',
    this.targetStores = const ['all'],
  });

  factory AdPromoItem.fromJson(Map<String, dynamic> json) {
    return AdPromoItem(
      id: json['id'] as String? ?? 'promo_${DateTime.now().millisecondsSinceEpoch}',
      isEnabled: json['enabled'] as bool? ?? true,
      badge: json['badge'] as String? ?? 'ПРОМО',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      buttonText: json['buttonText'] as String? ?? 'Подробнее →',
      buttonUrl: json['buttonUrl'] as String? ?? '',
      themeColor: json['themeColor'] as String? ?? 'blue',
      icon: json['icon'] as String? ?? 'shield',
      targetStores: (json['targetStores'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['all'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': isEnabled,
        'badge': badge,
        'title': title,
        'description': description,
        'buttonText': buttonText,
        'buttonUrl': buttonUrl,
        'themeColor': themeColor,
        'icon': icon,
        'targetStores': targetStores,
      };
}

class AdPromoConfig {
  final bool isEnabled;
  final int frequency;
  final String mode;
  final String yandexAdUnitId;
  final List<AdPromoItem> cards;

  const AdPromoConfig({
    this.isEnabled = true,
    this.frequency = 15,
    this.mode = 'custom_cards',
    this.yandexAdUnitId = '',
    this.cards = const [],
  });

  factory AdPromoConfig.fromJson(Map<String, dynamic> json) {
    return AdPromoConfig(
      isEnabled: json['enabled'] as bool? ?? true,
      frequency: json['frequency'] as int? ?? 15,
      mode: json['mode'] as String? ?? 'custom_cards',
      yandexAdUnitId: json['yandexAdUnitId'] as String? ?? '',
      cards: (json['cards'] as List<dynamic>?)
              ?.map((c) => AdPromoItem.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  static const defaultFallback = AdPromoConfig(
    isEnabled: true,
    frequency: 15,
    mode: 'yandex',
    yandexAdUnitId: 'R-M-19816566-1',
    cards: [],
  );
}
