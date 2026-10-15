import 'package:flutter/widgets.dart';

/// The Godot game in a frame on the site. Only the web build has one; native
/// builds never open it (GodotGame.available() is false there).
class GodotWebFrame {
  GodotWebFrame({
    required List<String> args,
    required void Function(String summaryJson) onExit,
    void Function(String summaryJson)? onSummary,
    void Function(Map<String, dynamic> event)? onEvent,
  });

  static Future<bool> available() async => false;

  Widget get widget => const SizedBox.shrink();

  void dispose() {}
}
