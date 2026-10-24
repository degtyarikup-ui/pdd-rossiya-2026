import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/domain/services/road_signs_engine.dart';

const _questions = 'assets/countries/ru/questions';
const _images = 'assets/countries/ru/images/signs';

Map<String, dynamic> _readMap(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final reference = _readMap('tools/ru_content/official_signs.json');
  final groups = reference['groups'] as List<dynamic>;
  final official = <String, String>{
    for (final group in groups)
      for (final sign in group['signs'] as List<dynamic>)
        sign['number'] as String: sign['title'] as String,
  };

  for (final suffix in ['', '_en', '_kk']) {
    test('Official numbered catalog and feed stay complete in $suffix', () {
      final data = _readMap('$_questions/signs$suffix.json');
      final signs = RoadSignsEngine.parseSignsJson(data);
      expect(signs.map((s) => s.number).toSet(), official.keys.toSet());
      expect(signs.length, official.length);
      expect(data.values.map((g) => (g as Map).length), [
        47,
        13,
        38,
        24,
        59,
        36,
        22,
        73,
      ]);
      for (final group in data.values) {
        for (final entry in (group as Map).entries) {
          expect(entry.value['number'], entry.key);
        }
      }
      for (final sign in signs) {
        if (suffix.isEmpty) {
          expect(sign.title, official[sign.number], reason: sign.number);
        }
        expect(sign.description.trim(), isNotEmpty, reason: sign.number);
        expect(
          File('$_images/${sign.image}').existsSync(),
          isTrue,
          reason: '${sign.number}: ${sign.image}',
        );
      }
      final feed =
          jsonDecode(
                File(
                  '$_questions/signs_feed_manifest$suffix.json',
                ).readAsStringSync(),
              )
              as List<dynamic>;
      expect(feed.length, official.length);
      expect(feed.map((s) => s['number']).toSet(), official.keys.toSet());
      expect(feed.map((s) => s['id']).toSet().length, official.length);
      final byNumber = {for (final sign in signs) sign.number: sign};
      for (final row in feed) {
        final sign = byNumber[row['number']]!;
        expect(row['title'], sign.title);
        expect(row['category'], sign.category);
        expect((row['description'] as String).trim(), sign.description);
        expect(row['image'], sign.image);
        final answers = (row['answers'] as List).cast<String>();
        expect(answers.length, 4);
        expect(answers.toSet().length, 4, reason: '${sign.number}: $answers');
        expect(answers[row['correctAnswerIndex'] as int], sign.title);
      }
    });
  }

  test('Translations share feed identities for synchronized progress', () {
    Map<String, String> ids(String suffix) {
      final rows =
          jsonDecode(
                File(
                  '$_questions/signs_feed_manifest$suffix.json',
                ).readAsStringSync(),
              )
              as List;
      return {
        for (final row in rows) row['number'] as String: row['id'] as String,
      };
    }

    expect(ids('_en'), ids(''));
    expect(ids('_kk'), ids(''));
  });

  test('Separated numeric variants use distinct images', () {
    final signs = RoadSignsEngine.parseSignsJson(
      _readMap('$_questions/signs.json'),
    );
    final byNumber = {for (final sign in signs) sign.number: sign};
    for (final numbers in [
      [for (var i = 1; i <= 6; i++) '1.4.$i'],
      [for (var i = 1; i <= 3; i++) '4.8.$i'],
      ['5.7.1', '5.7.2'],
      ['5.13.1', '5.13.2'],
      [for (var i = 1; i <= 4; i++) '5.14.$i'],
      ['5.19.1', '5.19.2'],
      ['5.23.1', '5.23.2'],
      ['5.24.1', '5.24.2'],
      ['6.19.1', '6.19.2'],
      ['6.20.1', '6.20.2'],
      ['6.21.1', '6.21.2'],
      ['7.14.1', '7.14.2'],
      [for (var i = 1; i <= 6; i++) '8.2.$i'],
      [for (var i = 1; i <= 3; i++) '8.3.$i'],
      ['8.4.7.2', '8.4.8'],
      [for (var i = 1; i <= 3; i++) '8.9.$i'],
      [for (var i = 1; i <= 3; i++) '8.22.$i'],
    ]) {
      expect(
        numbers.map((n) => byNumber[n]!.image).toSet().length,
        numbers.length,
        reason: '$numbers',
      );
    }
  });

  test(
    'New SVG assets decode and render through the application renderer',
    () async {
      final sources = (reference['images'] as Map).keys.cast<String>().toList();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final rows = (sources.length / 6).ceil();
      canvas.drawColor(const ui.Color(0xffeeeeee), ui.BlendMode.src);
      for (var i = 0; i < sources.length; i++) {
        final source = File('$_images/${sources[i]}').readAsStringSync();
        final picture = await vg.loadPicture(SvgStringLoader(source), null);
        expect(picture.size.isEmpty, isFalse, reason: sources[i]);
        canvas.save();
        canvas.translate((i % 6) * 160.0 + 15, (i ~/ 6) * 140.0 + 10);
        final scale = (130 / picture.size.width).clamp(
          0.0,
          100 / picture.size.height,
        );
        canvas.scale(scale);
        canvas.drawPicture(picture.picture);
        canvas.restore();
        picture.picture.dispose();
        final label = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 12))
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xff000000)))
          ..addText(
            sources[i].replaceAll('official_', '').replaceAll('.svg', ''),
          );
        final paragraph = label.build()
          ..layout(const ui.ParagraphConstraints(width: 155));
        canvas.drawParagraph(
          paragraph,
          ui.Offset((i % 6) * 160.0 + 10, (i ~/ 6) * 140.0 + 115),
        );
        paragraph.dispose();
      }
      final contact = recorder.endRecording();
      if (Platform.environment['SIGN_CATALOG_PREVIEW'] == '1') {
        final image = await contact.toImage(960, rows * 140);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('scratch/official-signs')
          ..createSync(recursive: true);
        File('${dir.path}/flutter-preview.png').writeAsBytesSync(
          bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        image.dispose();
      }
      contact.dispose();
    },
  );
}
