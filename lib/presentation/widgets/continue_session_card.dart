import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/exam/exam_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';

/// Карточка «Продолжить»: возврат к незаконченной тренировке или прерванному
/// экзамену. Вынесена из home_screen, чтобы её поведение можно было
/// проверять тестами отдельно от всего главного экрана.
class ContinueSessionCard extends ConsumerStatefulWidget {
  const ContinueSessionCard({super.key, required this.session});

  final Map<String, dynamic> session;

  @override
  ConsumerState<ContinueSessionCard> createState() =>
      ContinueSessionCardState();
}

class ContinueSessionCardState extends ConsumerState<ContinueSessionCard>
    with SingleTickerProviderStateMixin {
  /// 1 — карточка на месте, 0 — свёрнута. Порядок важен: сначала карточка
  /// уезжает, и только потом чистится хранилище и перечитываются данные.
  /// Раньше было наоборот — перезагрузка всего экрана шла первой, и карточка
  /// пропадала рывком уже после неё.
  late final AnimationController _dismiss = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _dismiss,
    // Прозрачность уходит раньше высоты: к моменту схлопывания карточки
    // её уже не видно, и соседние блоки не «прыгают» под полупрозрачным.
    curve: const Interval(0.35, 1, curve: Curves.easeOut),
  );

  late final Animation<double> _collapse = CurvedAnimation(
    parent: _dismiss,
    curve: Curves.easeInOutCubic,
  );

  @override
  void dispose() {
    _dismiss.dispose();
    super.dispose();
  }

  Future<void> _onDismiss() async {
    // Отклик — сразу по нажатию, до анимации: он подтверждает нажатие,
    // а не сообщает о завершении.
    HapticFeedbackHelper.select();

    await _dismiss.reverse();
    if (!mounted) return;

    await ref.read(progressDataSourceProvider).clearUnfinishedSession();
    if (!mounted) return;
    // Точечно, а не общим appDataRefreshProvider: перечитывать заодно
    // статистику и серию незачем — они не менялись.
    ref.invalidate(unfinishedSessionProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final session = widget.session;
    final isExam = session['kind'] == 'exam';
    final index = session['index'] as int;
    final total = session['total'] as int;
    final questions =
        (session['questions'] as List).cast<Map<String, dynamic>>();
    // У экзамена своего названия нет — он один, в отличие от билетов и тем.
    final title = isExam ? appL10n.exam : session['title'] as String;

    return SizeTransition(
      sizeFactor: _collapse,
      child: FadeTransition(
        opacity: _fade,
        child: Padding(
          // Отступ снизу внутри анимируемой части: иначе при схлопывании
          // карточки он остался бы висеть пустой полосой.
          padding: const EdgeInsets.only(bottom: AppDimensions.spacingL),
          child: Container(
            decoration: BoxDecoration(
              // Тот же синий, что у карточки экзамена: белая карточка терялась
              // между белой статистикой и белым фоном, а это главное действие
              // на экране — вернуться туда, где человек остановился.
              color: colors.accent,
              borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
                onTap: () async {
                  HapticFeedbackHelper.tap();
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => isExam
                          // Экзамен возвращается со своим состоянием: ответами,
                          // остатком времени и доп. фазой. allQuestions ему
                          // нужен только для новой жеребьёвки — здесь набор
                          // уже готов.
                          ? ExamScreen(allQuestions: questions, resume: session)
                          : TrainingScreen(
                              questions: questions,
                              title: title,
                              startIndex: index,
                            ),
                    ),
                  );
                  if (!mounted) return;
                  ref.read(appDataRefreshProvider.notifier).state++;
                },
                child: Padding(
                  padding: const EdgeInsets.all(AppDimensions.spacingL),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(width: AppDimensions.spacingM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appL10n.continueSession,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              appL10n.continueSessionSubtitle(
                                title,
                                index + 1,
                                total,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.white.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Крестик: незаконченная сессия не должна висеть вечно,
                      // если человек решил к ней не возвращаться.
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: AppColors.white.withValues(alpha: 0.75),
                        ),
                        tooltip: appL10n.continueSessionDismiss,
                        onPressed: _onDismiss,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
