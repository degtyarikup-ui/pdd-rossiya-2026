import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdd_app/data/models/achievement.dart';

/// Оформление уровня ачивки (вариант «Лучи», docs/application/achievements-3d.md):
/// фон карточки в цвет металла, сегментная полоска и фон экрана награды. Металл уровня: 1 бронза, 2 серебро, 3 золото, 4 платина.
@immutable
class TierMetal {
  const TierMetal({
    required this.light,
    required this.mid,
    required this.deep,
    required this.glow,
    required this.award,
  });

  final Color light, mid, deep, glow;

  /// Фон экрана «Новое достижение» для этого уровня.
  final Color award;

  /// Насыщенный цвет металла для полоски уровня и подписи.
  Color ink(bool isDark) =>
      isDark ? Color.lerp(mid, light, .25)! : Color.lerp(mid, deep, .45)!;

  static TierMetal of(int level) => switch (level.clamp(1, 4)) {
    1 => bronze,
    2 => silver,
    3 => gold,
    _ => platinum,
  };

  static const bronze = TierMetal(
    light: Color(0xFFF6D3B5),
    mid: Color(0xFFC9834F),
    deep: Color(0xFF7C4524),
    glow: Color(0xFFF0965A),
    award: Color(0xFFB36A3A),
  );

  static const silver = TierMetal(
    light: Color(0xFFF5F7FA),
    mid: Color(0xFFB4BECB),
    deep: Color(0xFF5F6B7C),
    glow: Color(0xFF7FA6DD),
    award: Color(0xFF6F7E95),
  );

  static const gold = TierMetal(
    light: Color(0xFFFFE9A8),
    mid: Color(0xFFF0B22E),
    deep: Color(0xFF9A640C),
    glow: Color(0xFFFFBE2E),
    award: Color(0xFFFFA53C),
  );

  /// Платина — синий в тон акценту; экран награды — акцентный синий.
  static const platinum = TierMetal(
    light: Color(0xFFE3EEFF),
    mid: Color(0xFF3D8EFA),
    deep: Color(0xFF0458C4),
    glow: Color(0xFF3B8BFF),
    award: Color(0xFF0574F8),
  );
}

/// Центр главного элемента на картинке значка (доли стороны), измерен по
/// рендерам. От него расходятся лучи и сияние. Знаки на стойке — верхняя
/// треть, парящие предметы — середина.
Offset achievementFocus(AchievementId id) => switch (id) {
  AchievementId.streak => const Offset(.483, .327),
  AchievementId.flawless => const Offset(.495, .314),
  AchievementId.mistakes => const Offset(.489, .344),
  AchievementId.trafficController => const Offset(.464, .314),
  AchievementId.signSwiper => const Offset(.504, .278),
  AchievementId.game => const Offset(.483, .475),
  AchievementId.exams => const Offset(.514, .461),
  AchievementId.coverage => const Offset(.508, .377),
  AchievementId.attempts => const Offset(.504, .314),
  AchievementId.tickets => const Offset(.494, .468),
  AchievementId.rank => const Offset(.479, .463),
};

/// Фон полученной ачивки (карточка в сетке и шапка листа деталей): ровный
/// оттенок металла с тонкой рамкой, пятно света за предметом и едва заметные
/// лучи. Границы карточки остаются чёткими в обеих темах.
class AchievementTierBackground extends StatelessWidget {
  const AchievementTierBackground({
    super.key,
    required this.level,
    required this.focus,
    required this.badgeSize,
    required this.badgeTop,
    required this.radius,
    required this.child,
  });

  final int level;
  final Offset focus;
  final double badgeSize, badgeTop, radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = TierMetal.of(level);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1C1D22) : Colors.white;
    final tint = isDark ? m.deep : Color.lerp(m.mid, m.deep, .2)!;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, tint, isDark ? .55 : .30)!,
            Color.lerp(base, tint, isDark ? .30 : .16)!,
          ],
        ),
        border: Border.all(
          color: (isDark ? m.mid : tint).withValues(alpha: isDark ? .30 : .34),
        ),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TierStagePainter(
                  metal: m,
                  isDark: isDark,
                  focus: focus,
                  badgeSize: badgeSize,
                  badgeTop: badgeTop,
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Декор за крупным значком без рамки (лист деталей): пятно света и лучи
/// цвета металла, плавно уходящие в прозрачность.
class AchievementTierAura extends StatelessWidget {
  const AchievementTierAura({
    super.key,
    required this.level,
    required this.focus,
    required this.badgeSize,
    required this.height,
    required this.child,
  });

  final int level;
  final Offset focus;
  final double badgeSize, height;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TierStagePainter(
      metal: TierMetal.of(level),
      isDark: Theme.of(context).brightness == Brightness.dark,
      focus: focus,
      badgeSize: badgeSize,
      badgeTop: (height - badgeSize) / 2,
      aura: true,
    ),
    child: SizedBox(
      height: height,
      child: Center(child: child),
    ),
  );
}

class _TierStagePainter extends CustomPainter {
  _TierStagePainter({
    required this.metal,
    required this.isDark,
    required this.focus,
    required this.badgeSize,
    required this.badgeTop,
    this.aura = false,
  });

  final TierMetal metal;
  final bool isDark;

  /// Без тонированной подложки: свет — цвет металла в обеих темах.
  final bool aura;
  final Offset focus;
  final double badgeSize, badgeTop;

  @override
  void paint(Canvas canvas, Size size) {
    // Значок стоит по центру по ширине, сверху отступ badgeTop.
    final c = Offset(
      (size.width - badgeSize) / 2 + focus.dx * badgeSize,
      badgeTop + focus.dy * badgeSize,
    );
    // Свет: в светлой теме белый, в тёмной — цвет металла.
    final tinted = isDark || aura;
    final light = tinted ? metal.glow : Colors.white;
    final reach = badgeSize * (aura ? 1.35 : 1.25);
    // Слой по кругу лучей, а не по границам виджета: без рамки лучи гаснут
    // плавно во все стороны и не обрезаются.
    final bounds = Rect.fromCircle(center: c, radius: reach);
    canvas.saveLayer(bounds, Paint());
    final rayPaint = Paint()
      ..color = light.withValues(alpha: isDark ? .13 : (aura ? .2 : .34));
    const count = 12;
    const halfWidth = .085;
    for (var i = 0; i < count; i++) {
      final a = i * 2 * math.pi / count - math.pi / 2;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(
            c.dx + reach * math.cos(a - halfWidth),
            c.dy + reach * math.sin(a - halfWidth),
          )
          ..lineTo(
            c.dx + reach * math.cos(a + halfWidth),
            c.dy + reach * math.sin(a + halfWidth),
          )
          ..close(),
        rayPaint,
      );
    }
    // Лучи гаснут уже у края предмета и не доходят до подписи.
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x80FFFFFF), Color(0x00FFFFFF)],
          stops: [0, .5, 1],
        ).createShader(bounds),
    );
    canvas.restore();
    final r = badgeSize * .72;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            light.withValues(alpha: isDark ? .34 : (aura ? .36 : .8)),
            light.withValues(alpha: isDark ? .12 : (aura ? .13 : .3)),
            light.withValues(alpha: 0),
          ],
          stops: const [0, .55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_TierStagePainter old) =>
      old.metal != metal ||
      old.isDark != isDark ||
      old.focus != focus ||
      old.badgeSize != badgeSize ||
      old.badgeTop != badgeTop ||
      old.aura != aura;
}

/// Полоска уровня из сегментов: полученные уровни залиты цветом металла,
/// следующий заполняется по прогрессу.
class TierLevelBar extends StatelessWidget {
  const TierLevelBar({
    super.key,
    required this.level,
    required this.total,
    required this.progress,
    required this.fill,
    required this.track,
  });

  final int level, total;
  final double progress;
  final Color fill, track;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < total; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: i < level ? 1 : (i == level ? progress : 0),
              minHeight: 4,
              color: i < level ? fill : fill.withValues(alpha: .45),
              backgroundColor: track,
            ),
          ),
        ),
      ],
    ],
  );
}
