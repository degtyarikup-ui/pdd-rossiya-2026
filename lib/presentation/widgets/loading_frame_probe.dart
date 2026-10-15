import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Only dev builds opt in. The call site is also a constant branch, so the
/// probe and its timing subscription are removed from ordinary production.
const loadingFrameProbeEnabled = bool.fromEnvironment('GAME_DEBUG');

/// Measures engine frames during an animated loader's visible lifetime.
/// It does not schedule frames, rebuild per frame, or measure WebP frame rate.
class LoadingFrameProbe extends StatefulWidget {
  const LoadingFrameProbe({
    required this.label,
    required this.child,
    super.key,
  });

  final String label;
  final Widget child;

  @override
  State<LoadingFrameProbe> createState() => _LoadingFrameProbeState();
}

class _LoadingFrameProbeState extends State<LoadingFrameProbe>
    with WidgetsBindingObserver {
  _LoadingFrameSession? _session;

  @override
  void initState() {
    super.initState();
    if (loadingFrameProbeEnabled) {
      WidgetsBinding.instance.addObserver(this);
      _startIfResumed();
    }
  }

  void _startIfResumed() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
      _session ??= _LoadingFrameSession(widget.label);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startIfResumed();
    } else {
      // A paused engine might never rebuild the conditional parent before
      // resuming. Stop here so native game time cannot enter loader wall time.
      _session?.close();
      _session = null;
    }
  }

  @override
  void didUpdateWidget(LoadingFrameProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (loadingFrameProbeEnabled && oldWidget.label != widget.label) {
      _session?.close();
      _session = null;
      _startIfResumed();
    }
  }

  @override
  void dispose() {
    if (loadingFrameProbeEnabled) WidgetsBinding.instance.removeObserver(this);
    _session?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _LoadingFrameSession {
  _LoadingFrameSession(this.label)
    : id = ++_nextId,
      _startBuildMicroseconds = _frameBoundary() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static int _nextId = 0;
  // Release batches can arrive about one second late. This grace period keeps
  // their original timestamps, not the frames rendered after the loader hid.
  static const _timingBatchGrace = Duration(milliseconds: 1200);

  final int id;
  final String label;
  final int _startBuildMicroseconds;
  final _clock = Stopwatch()..start();
  final _statistics = LoaderFrameStatistics();
  int? _endBuildMicroseconds;

  static int _frameBoundary() {
    final scheduler = SchedulerBinding.instance;
    final current = scheduler.currentSystemFrameTimeStamp.inMicroseconds;
    // Outside a build, the last frame has already rendered. Exclude it when
    // starting a resumed session and include it when closing a paused one.
    return current +
        (scheduler.schedulerPhase == SchedulerPhase.idle ||
                scheduler.schedulerPhase == SchedulerPhase.postFrameCallbacks
            ? 1
            : 0);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final start = timing.timestampInMicroseconds(FramePhase.buildStart);
      if (start >= _startBuildMicroseconds &&
          (_endBuildMicroseconds == null || start < _endBuildMicroseconds!)) {
        _statistics.add(timing);
      }
    }
  }

  void close() {
    if (_endBuildMicroseconds != null) return;
    _clock.stop();
    // The frame removing the loader is excluded. Raw scheduler timestamps and
    // FrameTiming.buildStart share the engine clock, unlike DateTime.now().
    _endBuildMicroseconds = _frameBoundary();
    Timer(_timingBatchGrace, () {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      final report = {
        'sessionId': id,
        'label': label,
        'buildMode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        'source': 'Flutter engine frames while animated loader is visible',
        'wallDurationMs': _clock.elapsedMicroseconds / 1000,
        'timingBatchGraceMs': _timingBatchGrace.inMilliseconds,
        ..._statistics.toJson(),
      };
      debugPrint('LoaderPerfJSON ${jsonEncode(report)}');
    });
  }
}

/// All-frame sums and maxima, with bounded storage for the latest p95 window.
/// Public for deterministic aggregation tests; it does not collect timings.
@visibleForTesting
class LoaderFrameStatistics {
  static const budgetMicroseconds = 16670;
  static const maximumSamples = 256;

  final _build = _DurationStatistics();
  final _raster = _DurationStatistics();
  int _overBudgetFrames = 0;

  void add(FrameTiming timing) {
    final build = timing.buildDuration.inMicroseconds;
    final raster = timing.rasterDuration.inMicroseconds;
    _build.add(build);
    _raster.add(raster);
    if (build > budgetMicroseconds || raster > budgetMicroseconds) {
      _overBudgetFrames++;
    }
  }

  Map<String, Object> toJson() => {
    'frames': _build.count,
    'budgetMs': budgetMicroseconds / 1000,
    'overBudgetFrames': _overBudgetFrames,
    'buildOverBudgetFrames': _build.overBudgetCount,
    'rasterOverBudgetFrames': _raster.overBudgetCount,
    'buildMeanMs': _build.meanMs,
    'buildP95Ms': _build.p95Ms,
    'buildMaxMs': _build.maximum / 1000,
    'rasterMeanMs': _raster.meanMs,
    'rasterP95Ms': _raster.p95Ms,
    'rasterMaxMs': _raster.maximum / 1000,
    'p95SampleFrames': _build.sampleCount,
    'p95SampleCapacity': maximumSamples,
    'p95Window':
        'latest frames; means, maxima and budget counts cover all frames',
  };
}

class _DurationStatistics {
  final _samples = List<int>.filled(LoaderFrameStatistics.maximumSamples, 0);
  int count = 0;
  int maximum = 0;
  int overBudgetCount = 0;
  int _sum = 0;

  int get sampleCount => count < _samples.length ? count : _samples.length;
  double get meanMs => count == 0 ? 0 : _sum / count / 1000;
  double get p95Ms {
    if (count == 0) return 0;
    final sorted = _samples.take(sampleCount).toList()..sort();
    return sorted[(sorted.length * .95).ceil() - 1] / 1000;
  }

  void add(int microseconds) {
    _samples[count % _samples.length] = microseconds;
    count++;
    _sum += microseconds;
    if (microseconds > maximum) maximum = microseconds;
    if (microseconds > LoaderFrameStatistics.budgetMicroseconds) {
      overBudgetCount++;
    }
  }
}
