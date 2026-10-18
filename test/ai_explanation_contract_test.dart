import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/services/gemini_ai_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    updateAppLocale(const Locale('ru'));
  });
  tearDown(() => updateAppLocale(const Locale('ru')));
  test(
    'local official explanation never invents a signal or priority mnemonic and is localized',
    () {
      for (final language in ['ru', 'en', 'kk']) {
        updateAppLocale(Locale(language));
        final text = GeminiAiService.instance.buildInstantPrewrittenExplanation(
          questionText: 'regulator whistle',
          correctAnswerText: 'attention',
          officialExplanation: 'Only the verified source comment.',
        );
        expect(text, contains('Only the verified source comment.'));
        expect(text, contains(appL10n.aiOfficialComment));
        expect(text, isNot(contains('Зеленый')));
        expect(
          GeminiAiService.instance.getQuickSuggestionsForQuestion(
            questionText: '',
            officialExplanation: '',
            correctAnswerText: '',
          ),
          [
            appL10n.aiSuggestRule,
            appL10n.aiSuggestWhy,
            appL10n.aiSuggestExceptions,
          ],
        );
      }
    },
  );
  test(
    'AI cache separates source variants, edited content and locale, and skips unavailable fallbacks',
    () async {
      var calls = 0;
      var generated = true;
      await http.runWithClient(
        () async {
          Future<String> explain(String id, String text) =>
              GeminiAiService.instance.explainQuestion(
                questionId: id,
                questionText: text,
                answers: ['first', 'second'],
                correctAnswerIndex: 0,
                officialExplanation: 'source',
              );
          expect(
            await explain('collision:v:ticket_9_15', 'version one'),
            'reply-1',
          );
          expect(
            await explain('collision:v:ticket_9_15', 'version one'),
            'reply-1',
          );
          expect(calls, 1);
          expect(
            await explain('collision:v:ticket_9_15', 'version two'),
            'reply-2',
          );
          updateAppLocale(const Locale('en'));
          expect(
            await explain('collision:v:ticket_9_15', 'version two'),
            'reply-3',
          );
          expect(await explain('collision', 'version two'), 'reply-4');
          generated = false;
          expect(
            await explain('offline-fixture', 'whistle'),
            contains('source'),
          );
          generated = true;
          expect(await explain('offline-fixture', 'whistle'), 'reply-6');
        },
        () => MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body);
          expect(body['installationId'], isNotEmpty);
          expect(body['locale'], isIn(['ru', 'en']));
          return http.Response(
            jsonEncode({'reply': 'reply-$calls', 'generated': generated}),
            200,
          );
        }),
      );
    },
  );
  test(
    'server quota denial is surfaced without a fabricated AI answer',
    () async {
      await http.runWithClient(
        () async {
          await expectLater(
            GeminiAiService.instance.askAiQuestion(
              questionId: 'q',
              questionText: 'question',
              answers: ['yes'],
              correctAnswerIndex: 0,
              officialExplanation: 'source',
              conversationHistory: [],
              userMessage: 'why',
            ),
            throwsA(
              isA<AiServiceException>().having(
                (e) => e.quotaExceeded,
                'quotaExceeded',
                isTrue,
              ),
            ),
          );
          expect(PremiumService.instance.remainingAiMessages, 0);
          expect(PremiumService.instance.aiDailyLimit, 10);
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': 'ai_quota_exceeded',
              'remaining': 0,
              'limit': 10,
              'resetsAt': DateTime.now()
                  .add(const Duration(days: 1))
                  .toUtc()
                  .toIso8601String(),
            }),
            429,
          ),
        ),
      );
    },
  );
  test(
    'minute throttling preserves the real daily balance and exposes a short cooldown',
    () async {
      await http.runWithClient(
        () async {
          await expectLater(
            GeminiAiService.instance.askAiQuestion(
              questionId: 'rate-limit',
              questionText: 'Source question?',
              answers: ['yes'],
              correctAnswerIndex: 0,
              officialExplanation: 'Source',
              conversationHistory: [],
              userMessage: 'Why?',
            ),
            throwsA(
              isA<AiServiceException>()
                  .having(
                    (e) => e.quotaExceeded,
                    'daily quota exhausted',
                    isFalse,
                  )
                  .having((e) => e.retryAfterSeconds, 'cooldown', 42),
            ),
          );
          expect(PremiumService.instance.remainingAiMessages, 190);
          expect(PremiumService.instance.aiDailyLimit, 200);
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': 'ai_quota_exceeded',
              'reason': 'rate_limit',
              'remaining': 190,
              'limit': 200,
              'retryAfterSeconds': 42,
              'resetsAt': DateTime.now()
                  .add(const Duration(days: 1))
                  .toUtc()
                  .toIso8601String(),
            }),
            429,
          ),
        ),
      );
    },
  );
}
