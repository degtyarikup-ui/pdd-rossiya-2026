// Standalone codec verification. This does not register assets or change app UI.
// Run: flutter test tools/mascot/webp_codec_probe_test.dart --reporter expanded
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'delivery WebPs decode and loop through the installed Flutter codec',
    () async {
      final directory = Directory('assets/mascot/raster');
      final manifest =
          jsonDecode(
                await File('${directory.path}/manifest.json').readAsString(),
              )
              as Map<String, dynamic>;
      final results = <Map<String, Object>>[];
      for (final entry in manifest['variants'] as List<dynamic>) {
        final variant = entry as Map<String, dynamic>;
        final bytes = await File(
          '${directory.path}/${variant['file']}',
        ).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          expect(codec.frameCount, variant['frames']);
          expect(codec.repetitionCount, -1);
          var durationMs = 0;
          final latencies = <int>[];
          for (var frame = 0; frame < codec.frameCount; frame++) {
            final timer = Stopwatch()..start();
            final decoded = await codec.getNextFrame();
            timer.stop();
            latencies.add(timer.elapsedMicroseconds);
            final image = decoded.image;
            try {
              expect(image.width, variant['width']);
              expect(image.height, variant['height']);
              durationMs += decoded.duration.inMilliseconds;
              if (frame == 0) {
                final pixels = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                var hasTransparent = false;
                var hasOpaque = false;
                for (var index = 3; index < pixels.lengthInBytes; index += 4) {
                  final alpha = pixels.getUint8(index);
                  hasTransparent |= alpha == 0;
                  hasOpaque |= alpha == 255;
                }
                expect(hasTransparent, isTrue);
                expect(hasOpaque, isTrue);
              }
            } finally {
              image.dispose();
            }
          }
          expect(durationMs, 7200);
          // Read through the actual wrap; the next frame must be the first again.
          final wrapped = await codec.getNextFrame();
          expect(wrapped.image.width, variant['width']);
          wrapped.image.dispose();
          final sorted = [...latencies]..sort();
          results.add({
            'variant': variant['id'] as String,
            'bytes': bytes.length,
            'frames': codec.frameCount,
            'durationMs': durationMs,
            'infiniteLoop': true,
            'meanDecodeMs':
                latencies.reduce((a, b) => a + b) / latencies.length / 1000,
            'p95DecodeMs': sorted[((sorted.length - 1) * .95).round()] / 1000,
            'maxDecodeMs': sorted.last / 1000,
          });
        } finally {
          codec.dispose();
        }
      }
      final report = {
        'environment':
            'Desktop Flutter test engine; not a phone or release performance profile',
        'variants': results,
      };
      await Directory('output/mascot').create(recursive: true);
      await File(
        'output/mascot/flutter-webp-codec-report.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      // ignore: avoid_print
      print('WEBP_CODEC_REPORT ${jsonEncode(report)}');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
