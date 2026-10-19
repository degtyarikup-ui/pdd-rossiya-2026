import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pdd_app/data/services/game_question_history_service.dart';
import 'package:pdd_app/presentation/screens/game/platform/godot_web_frame.dart';

/// «Живой город» on the web: the Godot game fills the screen. Its exit pops
/// the route with the run's summary (JSON), as GodotGame's channel does on
/// Android; the game's own screens (pause, questions, result) run inside it.
class GodotWebScreen extends StatefulWidget {
  const GodotWebScreen({super.key, required this.args});

  final List<String> args;

  /// Keep the fullscreen road and the menu stationary throughout the handover.
  static PageRouteBuilder<String> route({required List<String> args}) =>
      PageRouteBuilder<String>(
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (_, _, _) => GodotWebScreen(args: args),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeOutCubic,
          ),
          child: child,
        ),
      );

  @override
  State<GodotWebScreen> createState() => _GodotWebScreenState();
}

class _GodotWebScreenState extends State<GodotWebScreen> {
  late final GodotWebFrame _frame = GodotWebFrame(
    args: widget.args,
    onExit: _exit,
    onSummary: (json) => _summary = json,
    onEvent: (event) =>
        unawaited(GameQuestionHistoryService.instance.recordEvent(event)),
  );
  bool _closing = false;
  String? _summary;

  void _exit(String summaryJson) {
    if (_closing || !mounted) return;
    setState(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(summaryJson);
    });
  }

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMiniGame =
        widget.args.contains('--regulator') ||
        widget.args.contains('--crossroads') ||
        widget.args.contains('--parking');
    return PopScope<String>(
      canPop: _closing || !isMiniGame,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          final gameId = widget.args.contains('--crossroads')
              ? 'crossroads'
              : widget.args.contains('--parking')
              ? 'parking'
              : 'regulator';
          _exit(_summary ?? '{"game":"$gameId","runs":[]}');
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SizedBox.expand(child: _frame.widget),
      ),
    );
  }
}
