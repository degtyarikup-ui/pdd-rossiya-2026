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

  static void error() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }

  static void warning() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }
}
