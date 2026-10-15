import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/game_question_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = GameQuestionHistoryService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.resetForTest();
  });

  Map<String, Object> snapshot(
    int sequence,
    Map<String, int> shown,
    Map<String, int> counts,
  ) => {
    'version': 1,
    'sequence': sequence,
    'last_shown': shown,
    'show_counts': counts,
  };

  test('age-only v1 history migrates without inventing unseen cards', () {
    final history = GameQuestionHistory.fromJson({
      'version': 1,
      'sequence': 3,
      'last_shown': {'ticket_19_13': 3, 'ticket_29_14': 1},
    });
    expect(history.sequence, 3);
    expect(history.showCounts, {'ticket_19_13': 1, 'ticket_29_14': 1});
    expect(history.lastShown, {'ticket_19_13': 3, 'ticket_29_14': 1});
  });

  test('unsupported or malformed values cannot poison valid history', () {
    final history = GameQuestionHistory.fromJson({
      'version': 1,
      'sequence': -10,
      'last_shown': {'ticket_19_13': 5, '../bad': 9, 'fraction': 2.5},
      'show_counts': {'ticket_19_13': 3, 'broken': -2, 'nan': double.nan},
    });
    expect(history.sequence, 5);
    expect(history.showCounts, {'ticket_19_13': 3});
    expect(history.lastShown, {'ticket_19_13': 5});
    for (final value in [
      null,
      [],
      'broken',
      {'version': 2, 'sequence': 99},
    ]) {
      expect(
        history.merge(GameQuestionHistory.fromJson(value)).toJson(),
        history.toJson(),
      );
    }
  });

  test(
    'queued show events and stale exit summaries merge exactly once',
    () async {
      final first = service.recordEvent({
        'event': 'question_shown',
        'question_history': snapshot(
          2,
          {'ticket_19_13': 2},
          {'ticket_19_13': 2},
        ),
      });
      final second = service.recordSnapshot(
        snapshot(
          1,
          {'ticket_19_13': 1, 'ticket_29_14': 1},
          {'ticket_19_13': 1, 'ticket_29_14': 1},
        ),
      );
      final loaded = await service.load(); // Must wait for both queued writes.
      await Future.wait([first, second]);
      expect(
        loaded,
        snapshot(
          2,
          {'ticket_19_13': 2, 'ticket_29_14': 1},
          {'ticket_19_13': 2, 'ticket_29_14': 1},
        ),
      );
      await service.recordSnapshot(loaded);
      expect(await service.load(), loaded);
    },
  );

  test('a shown unanswered card survives a fresh service session', () async {
    await service.recordEvent({
      'event': 'question_shown',
      'situation': 'ticket_19_13',
      'question_history': snapshot(1, {'ticket_19_13': 1}, {'ticket_19_13': 1}),
    });
    service.resetForTest();
    expect(
      await service.load(),
      snapshot(1, {'ticket_19_13': 1}, {'ticket_19_13': 1}),
    );
  });

  test(
    'loading and approach events never count prefetched questions',
    () async {
      for (final event in ['approach_situation', 'answer', 'run_finished']) {
        await service.recordEvent({
          'event': event,
          'situation': 'ticket_19_13',
          'question_history': snapshot(
            1,
            {'ticket_19_13': 1},
            {'ticket_19_13': 1},
          ),
        });
      }
      expect(await service.load(), snapshot(0, {}, {}));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(GameQuestionHistoryService.storageKey), isNull);
    },
  );

  test('valid exit checkpoint repairs damaged local storage', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(GameQuestionHistoryService.storageKey, '{broken');
    expect(await service.load(), snapshot(0, {}, {}));
    final checkpoint = snapshot(2, {'ticket_29_14': 2}, {'ticket_29_14': 1});
    await service.recordSnapshot(checkpoint);
    expect(
      jsonDecode(prefs.getString(GameQuestionHistoryService.storageKey)!),
      checkpoint,
    );
    expect(await service.load(), checkpoint);
  });
}
