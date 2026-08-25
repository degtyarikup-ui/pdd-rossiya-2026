import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/screens/exam/exam_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Немой TTS, чтобы тесты не трогали платформенный канал flutter_tts.
class _SilentTts implements TtsService {
  @override
  Future<void> speakQuestion({
    String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {}

  @override
  Future<Duration?> speakOrPlayFeedItem({
    required String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {
    return null;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Вопросы с фиксированными текстами ответов: «Верный ответ» всегда первый.
/// [points] — вес каждого вопроса в балльной модели (по умолчанию 1).
List<Map<String, dynamic>> buildQuestions(int n, {int points = 1}) {
  return List.generate(n, (i) {
    return <String, dynamic>{
      'id': 'q$i',
      'question': 'Тестовый вопрос №${i + 1}',
      'answers': [
        {'text': 'Верный ответ', 'correct': true},
        {'text': 'Неверный ответ', 'correct': false},
      ],
      'comment': '',
      'pddPoints': <String>[],
      'image': null,
      'topic': <String>[],
      'ticketNumber': 1,
      'points': points,
    };
  });
}

Future<ProgressDataSource> pumpExam(
  WidgetTester tester, {
  ExamRules? rules,
  List<Map<String, dynamic>>? questions,
  Map<String, dynamic>? resume,
}) async {
  SharedPreferences.setMockInitialValues({});
  final dataSource = ProgressDataSource();
  await dataSource.init();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        progressDataSourceProvider.overrideWithValue(dataSource),
        ttsServiceProvider.overrideWithValue(_SilentTts()),
      ],
      child: MaterialApp(
        home: ExamScreen(
          allQuestions: questions ?? buildQuestions(60),
          rules: rules,
          resume: resume,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return dataSource;
}

/// Отвечает на текущий вопрос (верно или неверно) и ждёт все анимации.
Future<void> answerCurrent(WidgetTester tester, {required bool correct}) async {
  final label = correct ? 'Верный ответ' : 'Неверный ответ';
  await tester.tap(find.text(label).hitTestable(), warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Тап по ячейке полосы номеров (номер вопроса, 1-based).
/// Не использовать для 1 и 2 — коллизия с кружками вариантов ответа.
Future<void> tapStripCell(WidgetTester tester, int number) async {
  await tester.tap(find.text('$number').hitTestable(), warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('без ошибок: экзамен завершается сдачей после 20 ответов',
      (tester) async {
    await pumpExam(tester);

    for (var i = 0; i < 20; i++) {
      await answerCurrent(tester, correct: true);
    }

    expect(find.text('Экзамен сдан!'), findsOneWidget);
  });

  testWidgets('1 ошибка: +5 доп. вопросов, время продлено, сдача при верных доп.',
      (tester) async {
    await pumpExam(tester);

    await answerCurrent(tester, correct: false);
    for (var i = 1; i < 20; i++) {
      await answerCurrent(tester, correct: true);
    }

    // Перешли в доп. фазу: заголовок и нумерация доп. вопросов.
    expect(find.text('Дополнительные вопросы'), findsOneWidget);
    expect(find.text('Доп. вопрос 1 из 5'), findsOneWidget);

    // Таймер продлён на 5 минут: осталось больше 20:00.
    final timerText = tester
        .widgetList<Text>(find.textContaining(':'))
        .map((t) => t.data ?? '')
        .firstWhere((s) => RegExp(r'^\d{2}:\d{2}$').hasMatch(s));
    final minutes = int.parse(timerText.split(':').first);
    expect(minutes, greaterThanOrEqualTo(20));

    for (var i = 0; i < 5; i++) {
      await answerCurrent(tester, correct: true);
    }

    expect(find.text('Экзамен сдан!'), findsOneWidget);
  });

  testWidgets(
      '2 ошибки в РАЗНЫХ блоках: +10 доп. вопросов и сдача при верных доп.',
      (tester) async {
    await pumpExam(tester);

    // Ошибки в вопросах 1 и 6 — это блоки 0 (вопросы 1-5) и 1 (6-10).
    // В одном блоке две ошибки валят экзамен сразу (см. отдельный тест).
    await answerCurrent(tester, correct: false);
    for (var i = 1; i < 5; i++) {
      await answerCurrent(tester, correct: true);
    }
    await answerCurrent(tester, correct: false);
    for (var i = 6; i < 20; i++) {
      await answerCurrent(tester, correct: true);
    }

    expect(find.text('Дополнительные вопросы'), findsOneWidget);
    expect(find.text('Доп. вопрос 1 из 10'), findsOneWidget);

    for (var i = 0; i < 10; i++) {
      await answerCurrent(tester, correct: true);
    }

    expect(find.text('Экзамен сдан!'), findsOneWidget);
  });

  testWidgets(
      'ответы не по порядку: пропуск вопроса не блокирует переход к доп. фазе',
      (tester) async {
    await pumpExam(tester);

    // Отвечаем на вопросы 1-4.
    for (var i = 0; i < 4; i++) {
      await answerCurrent(tester, correct: true);
    }

    // Пропускаем вопрос 5: уходим на вопрос 6 через полосу номеров.
    await tapStripCell(tester, 6);
    expect(find.text('Вопрос 6 из 20'), findsOneWidget);

    // Отвечаем на 6..20. Ошибки — на 6-м и 11-м вопросе: это РАЗНЫЕ блоки
    // (1 и 2), иначе сработало бы правило «две ошибки в одном блоке — провал».
    await answerCurrent(tester, correct: false);
    for (var i = 6; i < 10; i++) {
      await answerCurrent(tester, correct: true);
    }
    await answerCurrent(tester, correct: false);
    for (var i = 11; i < 20; i++) {
      await answerCurrent(tester, correct: true);
    }

    // Автопереход по кругу должен вернуть на пропущенный вопрос 5.
    expect(find.text('Вопрос 5 из 20'), findsOneWidget);

    // Последний ответ даём НЕ на последней странице — раньше здесь был тупик.
    await answerCurrent(tester, correct: true);

    expect(find.text('Дополнительные вопросы'), findsOneWidget);
    expect(find.text('Доп. вопрос 1 из 10'), findsOneWidget);
  });

  testWidgets(
      'доп. фаза: ответы не по порядку не блокируют завершение экзамена',
      (tester) async {
    await pumpExam(tester);

    // 1 ошибка → +5 доп. вопросов (индексы 21..25).
    await answerCurrent(tester, correct: false);
    for (var i = 1; i < 20; i++) {
      await answerCurrent(tester, correct: true);
    }
    expect(find.text('Доп. вопрос 1 из 5'), findsOneWidget);

    // Пропускаем первый доп. вопрос (21): уходим на 22-й.
    await tapStripCell(tester, 22);
    expect(find.text('Доп. вопрос 2 из 5'), findsOneWidget);

    // Отвечаем 22..25, автопереход по кругу вернёт на 21-й.
    for (var i = 0; i < 4; i++) {
      await answerCurrent(tester, correct: true);
    }
    expect(find.text('Доп. вопрос 1 из 5'), findsOneWidget);

    // Последний ответ не на последней странице — раньше тупик, теперь финиш.
    await answerCurrent(tester, correct: true);

    expect(find.text('Экзамен сдан!'), findsOneWidget);
  });

  testWidgets(
      '3 ошибки в РАЗНЫХ блоках: экзамен сразу завершается провалом',
      (tester) async {
    await pumpExam(tester);

    // Ошибки в вопросах 1, 6 и 11 — по одной в блоках 0, 1 и 2. Блочное
    // правило не срабатывает, валит общий лимит «не больше двух ошибок».
    await answerCurrent(tester, correct: false);
    for (var i = 1; i < 5; i++) {
      await answerCurrent(tester, correct: true);
    }
    await answerCurrent(tester, correct: false);
    for (var i = 6; i < 10; i++) {
      await answerCurrent(tester, correct: true);
    }
    await answerCurrent(tester, correct: false);

    expect(find.text('Экзамен не сдан'), findsOneWidget);
    // Неотвеченные отдельной строкой не показываем: они уже учтены в
    // «неправильных», а лишняя карточка удлиняла экран результата.
    expect(find.text('Без ответа'), findsNothing);
  });

  // --- Блочное правило ГИБДД -------------------------------------------
  // Билет из 20 вопросов делится на 4 тематических блока по 5 вопросов
  // (по позиции: 1-5, 6-10, 11-15, 16-20). Две ошибки допускаются ТОЛЬКО
  // в разных блоках; две ошибки внутри одного блока — провал немедленно,
  // хотя суммарно ошибок всего две и общий лимит ещё не превышен.

  testWidgets(
      'две ошибки в ОДНОМ блоке: провал сразу, хотя ошибок всего две',
      (tester) async {
    await pumpExam(tester);

    // Вопросы 1 и 2 — оба в первом блоке.
    await answerCurrent(tester, correct: false);
    await answerCurrent(tester, correct: false);

    expect(find.text('Экзамен не сдан'), findsOneWidget);
    expect(find.text('Без ответа'), findsNothing);
  });

  testWidgets(
      'провал по блоку объясняется по кнопке-иконке, а не полотном текста',
      (tester) async {
    await pumpExam(tester);

    await answerCurrent(tester, correct: false);
    await answerCurrent(tester, correct: false);

    // Экран результата остаётся коротким: длинного объяснения на нём нет.
    expect(find.textContaining('4 тематических блоков'), findsNothing);

    // Но объяснение доступно — иначе «две ошибки, и не сдал» читается как баг.
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('4 тематических блоков'),
      findsOneWidget,
      reason: 'кнопка есть, а объяснения по ней нет — хуже, чем ничего',
    );
  });

  testWidgets(
      'две ошибки на границе блоков (5-й и 6-й вопрос) — это РАЗНЫЕ блоки',
      (tester) async {
    await pumpExam(tester);

    // Граничный случай: вопрос 5 — конец первого блока, вопрос 6 — начало
    // второго. Экзамен продолжается и уходит в доп. фазу.
    for (var i = 0; i < 4; i++) {
      await answerCurrent(tester, correct: true);
    }
    await answerCurrent(tester, correct: false);
    await answerCurrent(tester, correct: false);
    for (var i = 6; i < 20; i++) {
      await answerCurrent(tester, correct: true);
    }

    expect(find.text('Дополнительные вопросы'), findsOneWidget);
    expect(find.text('Доп. вопрос 1 из 10'), findsOneWidget);
  });

  testWidgets('ошибка в доп. вопросе: экзамен сразу завершается провалом',
      (tester) async {
    await pumpExam(tester);

    await answerCurrent(tester, correct: false);
    for (var i = 1; i < 20; i++) {
      await answerCurrent(tester, correct: true);
    }
    expect(find.text('Дополнительные вопросы'), findsOneWidget);

    await answerCurrent(tester, correct: false);

    expect(find.text('Экзамен не сдан'), findsOneWidget);
  });

  testWidgets('крестик: выходим без результата, не объявляя провал',
      (tester) async {
    await pumpExam(tester);

    await answerCurrent(tester, correct: true);

    await tester.tap(find.byIcon(Icons.close_rounded).hitTestable());
    await tester.pumpAndSettle();

    // Ни диалога, ни итогов: человек отвлёкся, а не провалил экзамен.
    // Недорешённый билет ждёт его на главной кнопкой «Продолжить».
    expect(find.text('Прервать экзамен?'), findsNothing);
    expect(find.text('Экзамен не сдан'), findsNothing);
    expect(find.byType(ExamScreen), findsNothing);
  });

  testWidgets('крестик без единого ответа: так же молча выходим',
      (tester) async {
    await pumpExam(tester);

    await tester.tap(find.byIcon(Icons.close_rounded).hitTestable());
    await tester.pumpAndSettle();

    expect(find.byType(ExamScreen), findsNothing);
  });

  testWidgets('системный «назад» выходит так же, как крестик', (tester) async {
    await pumpExam(tester);

    await answerCurrent(tester, correct: true);

    // Эмуляция системной кнопки/жеста «назад».
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(ExamScreen), findsNothing);
    expect(find.text('Экзамен не сдан'), findsNothing);
  });

  // ---------------------------------------------------------------------
  // Правила Беларуси (ГАИ РБ): 10 вопросов, 15 минут, максимум 1 ошибка,
  // механики дополнительных вопросов нет.
  // ---------------------------------------------------------------------
  group('Беларусь (10 вопросов / 1 ошибка / без доп. фазы)', () {
    final byRules = CountryConfig.belarus.examRules;

    testWidgets('без ошибок: сдан после 10 ответов', (tester) async {
      await pumpExam(tester, rules: byRules);

      for (var i = 0; i < 10; i++) {
        await answerCurrent(tester, correct: true);
      }

      expect(find.text('Экзамен сдан!'), findsOneWidget);
    });

    testWidgets('1 ошибка: доп. фаза НЕ начинается, экзамен сдан',
        (tester) async {
      await pumpExam(tester, rules: byRules);

      await answerCurrent(tester, correct: false);
      for (var i = 1; i < 10; i++) {
        await answerCurrent(tester, correct: true);
      }

      expect(find.text('Дополнительные вопросы'), findsNothing);
      expect(find.text('Экзамен сдан!'), findsOneWidget);
    });

    testWidgets('2 ошибки: провал сразу после второй ошибки', (tester) async {
      await pumpExam(tester, rules: byRules);

      await answerCurrent(tester, correct: false);
      await answerCurrent(tester, correct: false);

      expect(find.text('Экзамен не сдан'), findsOneWidget);
      expect(find.text('Без ответа'), findsNothing);
    });

    testWidgets('таймер стартует с 15 минут', (tester) async {
      await pumpExam(tester, rules: byRules);

      final timerText = tester
          .widgetList<Text>(find.textContaining(':'))
          .map((t) => t.data ?? '')
          .firstWhere((s) => RegExp(r'^\d{2}:\d{2}$').hasMatch(s));
      final minutes = int.parse(timerText.split(':').first);
      expect(minutes, lessThanOrEqualTo(15));
      expect(minutes, greaterThanOrEqualTo(14));
    });

    testWidgets('заголовок использует размер билета страны: «Вопрос 1 из 10»',
        (tester) async {
      await pumpExam(tester, rules: byRules);

      expect(find.text('Вопрос 1 из 10'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  // Балльная модель (Сербия, MUP): вопрос весит 1/2/3 балла, сдал при
  // наборе ≥ passPercent% от максимума. Доп. фазы и досрочного провала нет —
  // отвечаешь на все вопросы, затем итог по сумме баллов.
  // На тестах берём билет из 10 вопросов и порог 85%.
  // ---------------------------------------------------------------------
  group('Балльная модель (баллы / порог 85% / без доп. фазы)', () {
    const pointsRules = ExamRules(
      mainCount: 10,
      totalSeconds: 45 * 60,
      maxMistakes: 0,
      additionalPerMistake: 0,
      additionalSecondsPerBlock: 0,
      scoring: ExamScoring.points,
      passPercent: 85,
    );

    testWidgets('9/10 верных (90% ≥ 85%) — сдан, без доп. фазы',
        (tester) async {
      await pumpExam(tester, rules: pointsRules);

      await answerCurrent(tester, correct: false);
      for (var i = 1; i < 10; i++) {
        await answerCurrent(tester, correct: true);
      }

      expect(find.text('Дополнительные вопросы'), findsNothing);
      expect(find.text('Экзамен сдан!'), findsOneWidget);
      expect(find.text('Набрано баллов'), findsOneWidget);
      expect(find.text('90%'), findsOneWidget);
    });

    testWidgets('8/10 верных (80% < 85%) — не сдан', (tester) async {
      await pumpExam(tester, rules: pointsRules);

      await answerCurrent(tester, correct: false);
      await answerCurrent(tester, correct: false);
      for (var i = 2; i < 10; i++) {
        await answerCurrent(tester, correct: true);
      }

      expect(find.text('Дополнительные вопросы'), findsNothing);
      expect(find.text('Экзамен не сдан'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
    });

    testWidgets('веса вопросов суммируются: 9×2 из 20 = 90% — сдан',
        (tester) async {
      await pumpExam(
        tester,
        rules: pointsRules,
        questions: buildQuestions(60, points: 2),
      );

      await answerCurrent(tester, correct: false);
      for (var i = 1; i < 10; i++) {
        await answerCurrent(tester, correct: true);
      }

      // 9 верных × 2 балла = 18 из 20 = 90% → сдан.
      expect(find.text('Экзамен сдан!'), findsOneWidget);
      expect(find.text('18 из 20'), findsOneWidget);
      expect(find.text('90%'), findsOneWidget);
    });

    testWidgets(
        'таймаут при наборе ≥85%: сдан (баллы), а не автоматический провал',
        (tester) async {
      await pumpExam(
        tester,
        rules: pointsRules,
        questions: buildQuestions(60, points: 2), // макс билета = 10×2 = 20
      );

      // Отвечаем верно на 9 из 10 (18 баллов), 10-й НЕ трогаем — экзамен сам
      // не завершится, пока не выйдет время.
      for (var i = 0; i < 9; i++) {
        await answerCurrent(tester, correct: true);
      }

      // Прокручиваем таймер до истечения лимита (45 мин).
      await tester.pump(const Duration(seconds: 45 * 60 + 2));
      await tester.pumpAndSettle();

      // 18 из 20 = 90% ≥ 85%: на реальном тесте MUP это сдача, несмотря на
      // истёкшее время (неотвеченный вопрос просто = 0 баллов).
      expect(find.text('Экзамен сдан!'), findsOneWidget);
      expect(find.text('Экзамен не сдан'), findsNothing);
      expect(find.text('18 из 20'), findsOneWidget);
    });
  });

  // --- Прерванный экзамен ------------------------------------------------
  // Выход с экзамена больше не подводит итог: билет сохраняется целиком и
  // ждёт на главном экране. Иначе отвлёкшийся человек получал «не сдан».

  testWidgets('выход сохраняет экзамен: ответы, позиция и остаток времени',
      (tester) async {
    final data = await pumpExam(tester);

    await answerCurrent(tester, correct: true);
    await answerCurrent(tester, correct: false);

    await tester.tap(find.byIcon(Icons.close_rounded).hitTestable());
    await tester.pumpAndSettle();

    final saved = data.loadUnfinishedSession(TicketCategory.ab);
    expect(saved, isNotNull, reason: 'иначе продолжать будет нечего');
    expect(saved!['kind'], 'exam');
    expect((saved['questionIds'] as List).length, 20);
    expect((saved['answers'] as List).take(2).toList(), [0, 1]);
    expect(saved['index'], 2);
    // Остаток времени сохраняется: иначе выход обнулял бы таймер, и экзамен
    // можно было бы растянуть на сколько угодно.
    expect(saved['remainingSeconds'], lessThan(20 * 60));
    expect(saved['remainingSeconds'], greaterThan(0));
  });

  testWidgets('возврат восстанавливает ответы и позицию, а не начинает заново',
      (tester) async {
    final questions = buildQuestions(20);
    await pumpExam(
      tester,
      questions: questions,
      resume: {
        'questions': questions,
        'answers': <int?>[0, 1, ...List<int?>.filled(18, null)],
        'index': 2,
        'remainingSeconds': 600,
        'totalSeconds': 20 * 60,
        'additionalPhase': false,
        'additionalQuestionsCount': 0,
        'initialWrongCount': 0,
      },
    );

    // Продолжаем с третьего вопроса, а не с первого.
    expect(find.text('Вопрос 3 из 20'), findsOneWidget);
    // Таймер продолжает прежний отсчёт, а не стартует с 20:00.
    expect(find.text('10:00'), findsOneWidget);

    // Прежние ответы учтены: одна ошибка уже есть, добьём до провала по блоку.
    await answerCurrent(tester, correct: false);
    expect(find.text('Экзамен не сдан'), findsOneWidget);
  });

  testWidgets('битая запись игнорируется: экзамен начинается заново',
      (tester) async {
    final questions = buildQuestions(20);
    await pumpExam(
      tester,
      questions: questions,
      resume: {
        'questions': questions,
        // Ответов меньше, чем вопросов: позиции разъехались, и «ответ на
        // вопрос 5» на деле относился бы к другому вопросу. Лучше начать
        // заново, чем показать человеку чужие ответы как его собственные.
        'answers': <int?>[0, 1],
        'index': 2,
        'remainingSeconds': 600,
        'totalSeconds': 20 * 60,
        'additionalPhase': false,
        'additionalQuestionsCount': 0,
        'initialWrongCount': 0,
      },
    );

    expect(find.text('Вопрос 1 из 20'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
  });

  testWidgets('доведённый до результата экзамен из «продолжить» исчезает',
      (tester) async {
    final data = await pumpExam(tester);

    for (var i = 0; i < 20; i++) {
      await answerCurrent(tester, correct: true);
    }
    expect(find.text('Экзамен сдан!'), findsOneWidget);

    expect(
      data.loadUnfinishedSession(TicketCategory.ab),
      isNull,
      reason: 'предлагать продолжить сданный экзамен бессмысленно',
    );
  });
}
