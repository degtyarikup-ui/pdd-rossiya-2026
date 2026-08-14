import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/pdd_point_refs.dart';
import 'package:pdd_app/data/services/pdd_point_index.dart';
import 'package:pdd_app/presentation/screens/pdd/pdd_screen.dart';

/// Текст разбора вопроса, в котором номера пунктов Правил кликабельны.
///
/// Один виджет на все экраны с разбором (обучение, разбор экзамена): раньше
/// комментарий рисовался одинаковым `Text` в двух местах, и любая правка
/// требовала помнить про оба.
class PddCommentText extends StatefulWidget {
  const PddCommentText(this.comment, {super.key});

  final String comment;

  @override
  State<PddCommentText> createState() => _PddCommentTextState();
}

class _PddCommentTextState extends State<PddCommentText> {
  static const TextStyle _base = TextStyle(
    fontSize: 14,
    color: AppColors.primaryText,
    height: 1.45,
  );

  static const TextStyle _link = TextStyle(
    color: AppColors.accent,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.underline,
    decorationColor: AppColors.accent,
  );

  /// Распознаватели живут ровно столько же, сколько построенные с ними спаны.
  /// Пересоздавать их в build() нельзя: перерисовка (хоть от setState
  /// родителя, хоть от hot reload) уничтожала бы распознаватель, который
  /// прямо сейчас участвует в разборе жеста, и тап переставал доходить.
  final List<TapGestureRecognizer> _recognizers = [];

  PddPointIndex? _index;
  InlineSpan? _span;

  @override
  void initState() {
    super.initState();
    _index = PddPointIndex.cached;
    if (_index == null) {
      // Указатель строится один раз за запуск. Пока он не готов, показываем
      // обычный текст — это доли секунды и только при первом открытии разбора.
      PddPointIndex.load().then((value) {
        if (!mounted) return;
        setState(() {
          _index = value;
          _rebuildSpan();
        });
      });
    }
    _rebuildSpan();
  }

  @override
  void didUpdateWidget(PddCommentText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment != widget.comment) _rebuildSpan();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _rebuildSpan() {
    _clearRecognizers();

    final index = _index;
    final text = widget.comment;

    // Ссылка живая, только если пункт действительно есть в тексте Правил.
    // Часть разборов ссылается на «Перечень неисправностей» — это отдельный
    // документ, вести туда некуда, и подчёркивать такое нельзя.
    final refs = index == null
        ? const <PddPointRef>[]
        : findPddPointRefs(text).where((r) => index.contains(r.point)).toList();

    if (refs.isEmpty) {
      _span = null;
      return;
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final ref in refs) {
      if (ref.start < cursor) continue; // перекрытие — пропускаем
      if (ref.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, ref.start)));
      }
      final point = ref.point;
      final recognizer = TapGestureRecognizer()..onTap = () => _open(point);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: text.substring(ref.start, ref.end),
          style: _link,
          recognizer: recognizer,
        ),
      );
      cursor = ref.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    _span = TextSpan(style: _base, children: spans);
  }

  void _open(String point) {
    final section = _index?.sectionOf(point);
    if (section == null || !mounted) return;
    HapticFeedbackHelper.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PddDetailScreen(
          title: section['title'] ?? '',
          content: section['content'] ?? '',
          highlightPoint: point,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final span = _span;
    if (span == null) return Text(widget.comment, style: _base);
    return Text.rich(span);
  }
}
