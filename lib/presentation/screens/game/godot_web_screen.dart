import 'package:flutter/material.dart';

import 'package:pdd_app/presentation/screens/game/platform/godot_web_frame.dart';

/// «Живой город» on the web: the Godot game fills the screen. Its exit pops
/// the route with the run's summary (JSON), as GodotGame's channel does on
/// Android; the game's own screens (pause, questions, result) run inside it.
class GodotWebScreen extends StatefulWidget {
  const GodotWebScreen({super.key, required this.args});

  final List<String> args;

  @override
  State<GodotWebScreen> createState() => _GodotWebScreenState();
}

class _GodotWebScreenState extends State<GodotWebScreen> {
  late final GodotWebFrame _frame = GodotWebFrame(
    args: widget.args,
    onExit: _exit,
    onSummary: (json) => _summary = json,
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
        widget.args.contains('--crossroads');
    return PopScope<String>(
      canPop: _closing || !isMiniGame,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          final gameId =
              widget.args.contains('--crossroads') ? 'crossroads' : 'regulator';
          _exit(_summary ?? '{"game":"$gameId","runs":[]}');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(child: _frame.widget),
      ),
    );
  }
}
