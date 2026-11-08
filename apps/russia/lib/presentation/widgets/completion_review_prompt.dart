import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/data/services/review_prompt_service.dart';

/// Records one completed set/exam when its result is created. Waits until the
/// route transition ends before requesting a native review; never blocks the UI.
class CompletionReviewPrompt extends ConsumerStatefulWidget {
  const CompletionReviewPrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CompletionReviewPrompt> createState() =>
      _CompletionReviewPromptState();
}

class _CompletionReviewPromptState
    extends ConsumerState<CompletionReviewPrompt> {
  final _ready = Completer<void>();
  Animation<double>? _animation;
  bool _recorded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_recorded) return;
    _recorded = true;
    _animation = ModalRoute.of(context)?.animation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_animation == null ||
          _animation!.status == AnimationStatus.completed) {
        _markReady();
      } else {
        _animation!.addStatusListener(_onAnimationStatus);
      }
    });
    unawaited(
      ref
          .read(reviewPromptServiceProvider)
          .onCompleted(
            readyToRequest: () async {
              await _ready.future;
              return mounted &&
                  (ModalRoute.of(context)?.isCurrent ?? false) &&
                  (WidgetsBinding.instance.lifecycleState == null ||
                      WidgetsBinding.instance.lifecycleState ==
                          AppLifecycleState.resumed);
            },
          ),
    );
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _markReady();
  }

  void _markReady() {
    _animation?.removeStatusListener(_onAnimationStatus);
    if (!_ready.isCompleted) _ready.complete();
  }

  @override
  void dispose() {
    _markReady();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
