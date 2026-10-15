import 'dart:convert';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/widgets/loading_frame_probe.dart';

FrameTiming _timing({
  required int buildUs,
  required int rasterUs,
  int startUs = 1000,
}) => FrameTiming(
  vsyncStart: startUs,
  buildStart: startUs,
  buildFinish: startUs + buildUs,
  rasterStart: startUs + buildUs,
  rasterFinish: startUs + buildUs + rasterUs,
  rasterFinishWallTime: startUs + buildUs + rasterUs,
);

void main() {
  // Synthetic durations verify arithmetic and bounded storage only. They are
  // not device performance samples or evidence of animation smoothness.
  test('empty frame statistics serialize as finite zero values', () {
    final report = LoaderFrameStatistics().toJson();
    expect(report['frames'], 0);
    expect(report['p95SampleFrames'], 0);
    expect(report['buildMeanMs'], 0);
    expect(report['rasterP95Ms'], 0);
    expect(() => jsonEncode(report), returnsNormally);
  });

  test('reports both thread budgets without counting one frame twice', () {
    final statistics = LoaderFrameStatistics()
      ..add(_timing(buildUs: 1000, rasterUs: 2000))
      ..add(_timing(buildUs: 20000, rasterUs: 30000))
      ..add(_timing(buildUs: 5000, rasterUs: 16670));
    final report = statistics.toJson();
    expect(report['frames'], 3);
    expect(report['overBudgetFrames'], 1);
    expect(report['buildOverBudgetFrames'], 1);
    expect(report['rasterOverBudgetFrames'], 1);
    expect(report['buildMeanMs'], closeTo(26 / 3, .000001));
    expect(report['buildMaxMs'], 20);
    expect(report['buildP95Ms'], 20);
    expect(report['rasterMaxMs'], 30);
    expect(report['rasterP95Ms'], 30);
    expect(report['p95SampleFrames'], 3);
  });

  test('p95 storage is bounded while totals and maxima retain every frame', () {
    final statistics = LoaderFrameStatistics();
    statistics.add(_timing(buildUs: 900000, rasterUs: 800000));
    for (var ms = 0; ms < 300; ms++) {
      statistics.add(_timing(buildUs: ms * 1000, rasterUs: ms * 2000));
    }
    final report = statistics.toJson();
    expect(report['frames'], 301);
    expect(report['p95SampleFrames'], 256);
    expect(report['p95SampleCapacity'], 256);
    // The latest 256 build samples are 44..299 ms. Nearest-rank index 243
    // represents 287 ms; the old 900 ms sample still contributes to the max.
    expect(report['buildP95Ms'], 287);
    expect(report['rasterP95Ms'], 574);
    expect(report['buildMaxMs'], 900);
    expect(report['rasterMaxMs'], 800);
    expect(report['buildMeanMs'], closeTo((900 + 44850) / 301, .000001));
    expect(report['buildOverBudgetFrames'], 284);
    expect(report['rasterOverBudgetFrames'], 292);
    expect(report['overBudgetFrames'], 292);
  });

  testWidgets(
    'dev probe closes on pause without needing a parent rebuild',
    skip: !loadingFrameProbeEnabled,
    (tester) async {
      final reports = <Map<String, dynamic>>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        const prefix = 'LoaderPerfJSON ';
        if (message != null && message.startsWith(prefix)) {
          reports.add(
            jsonDecode(message.substring(prefix.length))
                as Map<String, dynamic>,
          );
        } else {
          previousDebugPrint(message, wrapWidth: wrapWidth);
        }
      };
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          const LoadingFrameProbe(
            label: 'probe-test',
            child: SizedBox.shrink(),
          ),
        );
        // Injected engine durations test session filtering and cleanup only.
        // They never represent measured renderer or phone performance.
        void reportFrame() {
          tester.binding.platformDispatcher.onReportTimings?.call([
            _timing(
              buildUs: 1000,
              rasterUs: 2000,
              startUs:
                  tester.binding.currentSystemFrameTimeStamp.inMicroseconds,
            ),
          ]);
        }

        reportFrame();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump(const Duration(milliseconds: 1300));
        expect(reports, hasLength(1));
        expect(reports.single['frames'], 1);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.scheduleForcedFrame();
        await tester.pump(const Duration(milliseconds: 2));
        reportFrame();
        tester.binding.scheduleForcedFrame();
        await tester.pump(const Duration(milliseconds: 2));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1300));
        expect(reports, hasLength(2));
        expect(reports.last['frames'], 1);
        expect(reports.last['sessionId'], isNot(reports.first['sessionId']));
      } finally {
        debugPrint = previousDebugPrint;
      }
    },
  );
}
