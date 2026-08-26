import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/screens/home/home_screen.dart';
import 'package:pdd_app/presentation/screens/feed/feed_screen.dart';
import 'package:pdd_app/presentation/screens/exam/exam_screen.dart';
import 'package:pdd_app/presentation/screens/signs/signs_screen.dart';
import 'package:pdd_app/presentation/screens/tickets/tickets_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockTts implements TtsService {
  @override Future<void> speakQuestion({String? rawQuestionId, required String question, required List<String> answers}) async {}
  @override Future<Duration?> speakOrPlayFeedItem({required String? rawQuestionId, required String question, required List<String> answers}) async => null;
  @override Future<void> stop() async {}
  @override Future<void> dispose() async {}
}

List<Map<String, dynamic>> buildSampleQuestions(int n) {
  return List.generate(n, (i) {
    return <String, dynamic>{
      'id': 'q$i',
      'question': 'Разрешен ли вам разворот на данном участке дороги?',
      'answers': [
        {'text': 'Разрешен только по траектории А', 'correct': true},
        {'text': 'Разрешен по любой траектории', 'correct': false},
        {'text': 'Запрещен', 'correct': false},
      ],
      'comment': 'Согласно пункту 8.11 ПДД РФ разворот запрещен в местах с видимостью дороги менее 100 м.',
      'pddPoints': <String>['8.11'],
      'image': null,
      'topic': <String>['Маневрирование'],
      'ticketNumber': 1,
      'points': 1,
    };
  });
}

void main() {
  testWidgets('Export iOS native screens', skip: true, (tester) async {
    SharedPreferences.setMockInitialValues({});
    final progressSource = ProgressDataSource();
    await progressSource.init();

    tester.view.physicalSize = const Size(1242, 2688);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final outDir = Directory('/Users/sergei/Documents/pdd/store_assets/ios_raw_screenshots');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    final key = GlobalKey();

    Future<void> saveScreen(String name, Widget widget) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressDataSourceProvider.overrideWithValue(progressSource),
            ttsServiceProvider.overrideWithValue(_MockTts()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              platform: TargetPlatform.iOS,
              fontFamily: 'Onest',
              scaffoldBackgroundColor: const Color(0xFFF8F8FA),
              extensions: const [AppThemeColors.light],
            ),
            home: RepaintBoundary(
              key: key,
              child: widget,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      File('${outDir.path}/$name.png').writeAsBytesSync(pngBytes);
      print('Rendered $name.png (${pngBytes.length} bytes)');
    }

    await saveScreen('01_home', const HomeScreen());
    await saveScreen('02_feed', const FeedScreen());
    await saveScreen('03_exam', ExamScreen(allQuestions: buildSampleQuestions(20)));
    await saveScreen('04_tickets', const TicketsScreen());
    await saveScreen('05_signs', const SignsScreen());
  });
}
