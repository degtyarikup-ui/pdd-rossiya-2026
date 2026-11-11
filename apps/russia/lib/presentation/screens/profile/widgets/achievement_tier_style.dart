import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdd_app/data/models/achievement.dart';

/// Оформление уровня ачивки (вариант «Лучи», docs/application/achievements-3d.md):
/// фон карточки с лучами металла, сегментная полоска, сияние крупных значков
/// и фон экрана награды. Металл уровня: 1 бронза, 2 серебро, 3 золото, 4 платина.
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

/// Мягкое сияние цвета металла за крупным значком.
class TierHaloPainter extends CustomPainter {
  TierHaloPainter({
    required this.level,
    required this.isDark,
    required this.focus,
  });

  final int level;
  final bool isDark;
  final Offset focus;

  @override
  void paint(Canvas canvas, Size size) {
    final m = TierMetal.of(level);
    final s = size.width;
    final c = Offset(focus.dx * s, focus.dy * s + s * .04);
    final strength =
        (isDark ? .62 : .5) * (.55 + .15 * level) * (level == 2 ? 1.35 : 1);
    final r = s * (.42 + .03 * level);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            m.glow.withValues(alpha: strength),
            m.glow.withValues(alpha: strength * .45),
            m.glow.withValues(alpha: 0),
          ],
          stops: const [0, .5, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(TierHaloPainter old) =>
      old.level != level || old.isDark != isDark || old.focus != focus;
}

/// Четырёхлучевые блики поверх крупного значка; их число равно уровню.
class TierSparklePainter extends CustomPainter {
  TierSparklePainter({required this.level});

  final int level;

  static const _spots = [
    (Offset(.79, .11), .115),
    (Offset(.18, .19), .08),
    (Offset(.86, .47), .07),
    (Offset(.15, .54), .06),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final tint = TierMetal.of(level).glow;
    final s = size.width;
    for (var i = 0; i < level.clamp(1, 4); i++) {
      final (pos, k) = _spots[i];
      final c = Offset(pos.dx * s, pos.dy * s);
      final r = k * s;
      canvas.drawCircle(
        c,
        r * .55,
        Paint()
          ..color = tint.withValues(alpha: .55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .35),
      );
      canvas.drawPath(
        _star(c, r),
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white, Color.lerp(Colors.white, tint, .45)!],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  static Path _star(Offset c, double r) {
    final w = r * .16;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(TierSparklePainter old) => old.level != level;
}

/// Фон карточки полученной ачивки в сетке: оттенок металла сверху вниз и
/// неподвижные лучи от центра предмета, гаснущие к краям.
class AchievementRaysBackground extends StatelessWidget {
  const AchievementRaysBackground({
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
    final tint = isDark ? m.deep : m.light;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, tint, isDark ? .42 : .7)!,
            Color.lerp(base, tint, isDark ? .12 : .18)!,
          ],
          stops: const [0, .78],
        ),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RaysPainter(
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

class _RaysPainter extends CustomPainter {
  _RaysPainter({
    required this.metal,
    required this.isDark,
    required this.focus,
    required this.badgeSize,
    required this.badgeTop,
  });

  final TierMetal metal;
  final bool isDark;
  final Offset focus;
  final double badgeSize, badgeTop;

  @override
  void paint(Canvas canvas, Size size) {
    // Значок стоит по центру карточки, сверху отступ badgeTop.
    final c = Offset(
      (size.width - badgeSize) / 2 + focus.dx * badgeSize,
      badgeTop + focus.dy * badgeSize,
    );
    final reach = size.longestSide * 1.1;
    final silver = identical(metal, TierMetal.silver);
    canvas.saveLayer(Offset.zero & size, Paint());
    final rayPaint = Paint()
      ..color = (isDark ? metal.mid : Color.lerp(metal.mid, metal.deep, .35)!)
          .withValues(alpha: isDark ? .42 : (silver ? .4 : .3));
    const count = 12;
    const halfWidth = .075;
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
    // Лучи гаснут к краям карточки и не заходят под подпись.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x66FFFFFF), Color(0x00FFFFFF)],
          stops: [0, .22, .5],
        ).createShader(Rect.fromCircle(center: c, radius: reach)),
    );
    canvas.restore();
    // Мягкое свечение прямо за предметом.
    final r = size.width * .42;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            metal.glow.withValues(alpha: isDark ? .45 : .38),
            metal.glow.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_RaysPainter old) =>
      old.metal != metal ||
      old.isDark != isDark ||
      old.focus != focus ||
      old.badgeSize != badgeSize ||
      old.badgeTop != badgeTop;
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
