import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/feed/widgets/feed_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in [
    (type: FeedItemType.roadSign, index: 1),
    (type: FeedItemType.ticketQuestion, index: 1),
    (type: FeedItemType.ticketQuestion, index: 0),
    (type: FeedItemType.roadSign, index: -1),
  ]) {
    testWidgets(
      'feed ${scenario.type.name} answer ${scenario.index} never changes shared mistakes',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'question_progress_ab': jsonEncode({
            'real-question': {'isCorrect': false},
          }),
        });
        final progress = ProgressDataSource();
        await progress.init();
        final before = await progress.getAllQuestionProgress(TicketCategory.ab);
        SoundEffectsService.instance.setEnabled(false);
        HapticFeedbackHelper.setEnabled(false);
        addTearDown(() {
          SoundEffectsService.instance.setEnabled(true);
          HapticFeedbackHelper.setEnabled(true);
        });
        int? recorded;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: FeedCard(
                  item: FeedItem(
                    id: 'feed-card',
                    type: scenario.type,
                    rawQuestionId: scenario.type == FeedItemType.roadSign
                        ? 'sign_8_4_6'
                        : 'real-question',
                    questionText: 'Feed question',
                    answers: const ['Correct answer', 'Wrong answer'],
                    correctAnswerIndex: 0,
                  ),
                  isCurrent: true,
                  isSoundEnabled: false,
                  onToggleSound: () {},
                  onAutoNext: () {},
                  onPrevious: () {},
                  onAnswerRecorded: (index) => recorded = index,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        if (scenario.index < 0) {
          await tester.pump(const Duration(seconds: 20));
        } else {
          await tester.tap(
            find.text(scenario.index == 0 ? 'Correct answer' : 'Wrong answer'),
          );
          await tester.pump();
        }
        expect(recorded, scenario.index);
        expect(
          await progress.getAllQuestionProgress(TicketCategory.ab),
          before,
        );
        expect(
          await progress.getAllQuestionProgress(TicketCategory.cd),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
