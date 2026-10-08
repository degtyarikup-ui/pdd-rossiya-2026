import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Модель единичного дорожного знака из базы `signs.json`.
class SignItem {
  final String number;
  final String title;
  final String image;
  final String category;
  final String description;
  final String? folkName;

  const SignItem({
    required this.number,
    required this.title,
    required this.image,
    required this.category,
    required this.description,
    this.folkName,
  });

  /// Полный относительный путь к SVG/PNG ассету изображения знака.
  String get assetPath => '${CountryConfig.current.signImagesDir}/$image';

  factory SignItem.fromMap({
    required String number,
    required String category,
    required Map<String, dynamic> map,
  }) {
    final rawImage = (map['image'] as String? ?? '').trim();
    final fileName = rawImage.isNotEmpty ? rawImage.split('/').last : '';
    final rawTitle = (map['title'] as String? ?? map['name'] as String? ?? number).trim();
    final rawDesc = (map['description'] as String? ?? '').trim();
    final rawFolk = (map['folkName'] as String?)?.trim();

    return SignItem(
      number: number,
      title: rawTitle,
      image: fileName,
      category: category,
      description: rawDesc,
      folkName: (rawFolk != null && rawFolk.isNotEmpty) ? rawFolk : null,
    );
  }
}

/// Тип вопроса на карточке свайпера.
enum SignQuestionType {
  actionPermission,
  driverObligation,
  zoneAndException,
  speedAndLane,
  warningNotice,
}

/// Карточка с вопросом-утверждением для свайпера.
class SignCardQuestion {
  final String id;
  final SignItem sign;
  final String prompt;
  final bool isCorrect;
  final String explanation;
  final SignQuestionType type;

  const SignCardQuestion({
    required this.id,
    required this.sign,
    required this.prompt,
    required this.isCorrect,
    required this.explanation,
    required this.type,
  });

  /// Определяет, начинается ли вопрос с разрешения («Можно ли», «Разрешено ли»).
  bool get isPermissionQuestion {
    final lower = prompt.trim().toLowerCase();
    return lower.startsWith('можно') ||
        lower.startsWith('разрешено') ||
        lower.startsWith('разрешена') ||
        lower.startsWith('разрешен') ||
        lower.startsWith('разрешён') ||
        lower.startsWith('разрешается');
  }

  /// Текст для правого свайпа / кнопки согласия («МОЖНО» или «ДА»).
  String get rightActionLabel =>
      isPermissionQuestion ? appL10n.gameSignCan : appL10n.gameSignYes;

  /// Текст для левого свайпа / кнопки несогласия («НЕЛЬЗЯ» или «НЕТ»).
  String get leftActionLabel =>
      isPermissionQuestion ? appL10n.gameSignCannot : appL10n.gameSignNo;
}

/// Сохранённый прогресс игрока в игре «Знак-Свайпер».
class SignSwiperProgress {
  final int bestScore;
  final int maxCombo;
  final int totalSwiped;
  final int trainingCount;

  const SignSwiperProgress({
    this.bestScore = 0,
    this.maxCombo = 0,
    this.totalSwiped = 0,
    this.trainingCount = 0,
  });

  SignSwiperProgress copyWith({
    int? bestScore,
    int? maxCombo,
    int? totalSwiped,
    int? trainingCount,
  }) {
    return SignSwiperProgress(
      bestScore: bestScore ?? this.bestScore,
      maxCombo: maxCombo ?? this.maxCombo,
      totalSwiped: totalSwiped ?? this.totalSwiped,
      trainingCount: trainingCount ?? this.trainingCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'bestScore': bestScore,
    'maxCombo': maxCombo,
    'totalSwiped': totalSwiped,
    'trainingCount': trainingCount,
  };

  factory SignSwiperProgress.fromJson(Map<String, dynamic> json) {
    return SignSwiperProgress(
      bestScore: (json['bestScore'] as num?)?.toInt() ?? 0,
      maxCombo: (json['maxCombo'] as num?)?.toInt() ?? 0,
      totalSwiped: (json['totalSwiped'] as num?)?.toInt() ?? 0,
      trainingCount: (json['trainingCount'] as num?)?.toInt() ?? 0,
    );
  }
}
