import 'package:flutter/services.dart';

class HapticFeedbackHelper {
  HapticFeedbackHelper._();

  static bool _enabled = true;

  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  static void tap() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  static void select() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  static void success() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// A deliberate action such as restarting a run or choosing an unlocked car.
  static void confirm() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  static void error() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }

  /// A gentle double tick for a correct answer: pleasant, not a thump.
  static void softSuccess() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
    Future<void>.delayed(
      const Duration(milliseconds: 90),
      HapticFeedback.lightImpact,
    );
  }

  /// A crash: an uneven medium-then-light hit, unpleasant but not violent.
  static void collision() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
    Future<void>.delayed(
      const Duration(milliseconds: 70),
      HapticFeedback.lightImpact,
    );
    Future<void>.delayed(
      const Duration(milliseconds: 160),
      HapticFeedback.lightImpact,
    );
  }

  static void warning() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }
}
