import 'package:flutter/material.dart';

/// Длительность и кривая для [PageView] между вопросами (тренировка, экзамен, разбор).
abstract final class QuestionSwipeMotion {
  static const Duration duration = Duration(milliseconds: 280);
  static const Curve curve = Curves.easeOutCubic;
}
