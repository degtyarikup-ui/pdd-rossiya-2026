// Render the current FeedCard with an unmodified bundled exam question.
// flutter test tools/store_graphics/test/capture_flutter_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/feed/widgets/feed_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('capture actual feed component for the store gallery', (
    tester,
  ) async {
    // This capture runs under flutter_test outside the default test/ folder.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final font in [
      'Onest-Regular',
      'Onest-Medium',
      'Onest-SemiBold',
      'Onest-Bold',
    ]) {
      final loader = FontLoader('Onest')
        ..addFont(rootBundle.load('assets/fonts/$font.ttf'));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final data = jsonDecode(
      File(
        'assets/countries/ru/questions/questions_ab.json',
      ).readAsStringSync(),
    );
    final q = data['tickets'][26]['questions'][12] as Map<String, dynamic>;
    final answers = (q['answers'] as List).cast<Map<String, dynamic>>();
    final item = FeedItem(
      id: q['id'],
      rawQuestionId: q['id'],
      type: FeedItemType.ticketQuestion,
      questionText: q['question'],
      imagePath: 'assets/countries/ru/images/questions_ab/${q['image']}.webp',
      answers: answers.map((a) => a['text'] as String).toList(),
      correctAnswerIndex: answers.indexWhere((a) => a['correct'] == true),
      explanation: q['comment'],
      badgeText:
          '${appL10n.ticketNumber(27)} · ${appL10n.question[0].toUpperCase()}${appL10n.question.substring(1)} 13',
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: FeedCard(
                item: item,
                isCurrent: false,
                isSoundEnabled: true,
                onToggleSound: () {},
                onAutoNext: () {},
                onPrevious: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        AssetImage(item.imagePath!),
        tester.element(find.byType(FeedCard)),
      );
    });
    await tester.pump(const Duration(milliseconds: 500));
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('output/store-cards-2026-10-18/feed.png');
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
