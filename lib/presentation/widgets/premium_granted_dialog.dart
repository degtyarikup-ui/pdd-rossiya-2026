import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';

class PremiumGrantedDialog extends StatefulWidget {
  final DateTime? expiresAt;
  final VoidCallback onDismiss;

  const PremiumGrantedDialog({
    super.key,
    required this.expiresAt,
    required this.onDismiss,
  });

  static Future<void> show(
    BuildContext context, {
    DateTime? expiresAt,
  }) {
    HapticFeedbackHelper.success();
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PremiumGrantedDialog(
        expiresAt: expiresAt,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  State<PremiumGrantedDialog> createState() => _PremiumGrantedDialogState();
}

class _PremiumGrantedDialogState extends State<PremiumGrantedDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _confettiAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
    );

    _confettiAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.1, 1.0, curve: Curves.easeOutQuad),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _formatDurationSubtitle() {
    if (widget.expiresAt == null) {
      return 'Вам открыт бессрочный доступ навсегда!';
    }
    final exp = widget.expiresAt!;
    final now = DateTime.now();
    final diffDays = exp.difference(now).inDays + 1;
    const months = [
      '',
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    final dateStr = '${exp.day} ${months[exp.month]} ${exp.year}';

    if (diffDays <= 1) {
      return 'Доступ активен до конца сегодняшнего дня';
    } else if (diffDays <= 7) {
      return 'Доступ открыт на $diffDays дней (до $dateStr)';
    } else if (diffDays <= 31) {
      return 'Доступ открыт на 1 месяц (до $dateStr)';
    } else if (diffDays <= 95) {
      return 'Доступ открыт на 3 месяца (до $dateStr)';
    } else if (diffDays <= 370) {
      return 'Доступ открыт на 1 год (до $dateStr)';
    }
    return 'Доступ активен до $dateStr';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Confetti canvas animation
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confettiAnim,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ConfettiPainter(
                        progress: _confettiAnim.value,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Main Dialog Card
            ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                width: 320,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Party Popper Icon
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2BC280).withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '🎉',
                        style: TextStyle(fontSize: 38),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // PRO Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2BC280),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'PRO ДОСТУП АКТИВИРОВАН',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Title
                    Text(
                      'Вам выдан Premium!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle (duration)
                    Text(
                      _formatDurationSubtitle(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.secondaryText,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Feature highlights
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.homeStatGraySurface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          _buildFeatureRow(
                            icon: Icons.bolt_rounded,
                            color: const Color(0xFF0574F8),
                            text: 'Умная лента и все 800 вопросов',
                            colors: colors,
                          ),
                          const SizedBox(height: 8),
                          _buildFeatureRow(
                            icon: Icons.psychology_rounded,
                            color: const Color(0xFF2BC280),
                            text: 'Подробные объяснения от ИИ',
                            colors: colors,
                          ),
                          const SizedBox(height: 8),
                          _buildFeatureRow(
                            icon: Icons.block_rounded,
                            color: const Color(0xFFED4621),
                            text: 'Полное отсутствие рекламы',
                            colors: colors,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedbackHelper.tap();
                          widget.onDismiss();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2BC280),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Отлично, спасибо!',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required Color color,
    required String text,
    required AppThemeColors colors,
  }) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfettiParticle {
  final double x;
  final double y;
  final double size;
  final Color color;
  final double speed;
  final double angle;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.color,
    required this.speed,
    required this.angle,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  static final List<_ConfettiParticle> _particles = _generateParticles();

  _ConfettiPainter({required this.progress});

  static List<_ConfettiParticle> _generateParticles() {
    final rng = math.Random(42);
    final colors = [
      const Color(0xFF2BC280),
      const Color(0xFF0574F8),
      const Color(0xFFFFA53C),
      const Color(0xFFED4621),
      const Color(0xFF8B5CF6),
      const Color(0xFF06B6D4),
    ];
    return List.generate(45, (i) {
      return _ConfettiParticle(
        x: rng.nextDouble() * 320 - 160,
        y: rng.nextDouble() * -100,
        size: rng.nextDouble() * 5 + 4,
        color: colors[rng.nextInt(colors.length)],
        speed: rng.nextDouble() * 200 + 150,
        angle: rng.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final p in _particles) {
      final currentY = center.dy + p.y + (p.speed * progress);
      final currentX = center.dx + p.x + math.sin(progress * 4 + p.angle) * 20;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(currentX, currentY);
      canvas.rotate(p.angle + progress * 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.7,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
