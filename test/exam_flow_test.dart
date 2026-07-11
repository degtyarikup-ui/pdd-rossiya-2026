import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/presentation/screens/exam/exam_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Немой TTS, чтобы тесты не трогали платформенный канал flutter_tts.
class _SilentTts implements TtsService {
  @override
  Future<void> speakQuestion({
    required String question,
    required List<String> answers,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Вопросы с фиксированными текстами ответов: «Верный ответ» всегда первый.
List<Map<String, dynamic>> buildQuestions(int n) {
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
    };
  });
}

Future<void> pumpExam(WidgetTester tester, {ExamRules? rules}) async {
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
        home: ExamScreen(allQuestions: buildQuestions(60), rules: rules),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

  testWidgets('2 ошибки: +10 доп. вопросов и сдача при верных доп.',
      (tester) async {
    await pumpExam(tester);

    await answerCurrent(tester, correct: false);
    await answerCurrent(tester, correct: false);
    for (var i = 2; i < 20; i++) {
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

    // Отвечаем на 6..20 (две ошибки — на 6-м и 7-м).
    await answerCurrent(tester, correct: false);
    await answerCurrent(tester, correct: false);
    for (var i = 7; i < 20; i++) {
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

  testWidgets('3 ошибки в основном блоке: экзамен сразу завершается провалом',
      (tester) async {
    await pumpExam(tester);

    await answerCurrent(tester, correct: false);
    await answerCurrent(tester, correct: false);
    await answerCurrent(tester, correct: false);

    expect(find.text('Экзамен не сдан'), findsOneWidget);
    // 17 вопросов остались без ответа и показаны отдельной строкой.
    expect(find.text('Без ответа'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
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

  testWidgets('крестик: диалог позволяет завершить экзамен и увидеть разбор',
      (tester) async {
    await pumpExam(tester);

    await answerCurrent(tester, correct: true);

    await tester.tap(find.byIcon(Icons.close_rounded).hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('Прервать экзамен?'), findsOneWidget);

    await tester.tap(find.text('Завершить'));
    await tester.pumpAndSettle();

    // Результаты показаны, разбор доступен, досрочное завершение = не сдан.
    expect(find.text('Экзамен не сдан'), findsOneWidget);
    expect(find.text('Мои ошибки'), findsOneWidget);
  });

  testWidgets('крестик без единого ответа: молча выходим без результатов',
      (tester) async {
    await pumpExam(tester);

    await tester.tap(find.byIcon(Icons.close_rounded).hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('Прервать экзамен?'), findsNothing);
    expect(find.byType(ExamScreen), findsNothing);
  });

  testWidgets('системный «назад» показывает тот же диалог, а не гасит экзамен',
      (tester) async {
    await pumpExam(tester);

    await answerCurrent(tester, correct: true);

    // Эмуляция системной кнопки/жеста «назад».
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    // Экзамен на месте, диалог показан.
    expect(find.byType(ExamScreen), findsOneWidget);
    expect(find.text('Прервать экзамен?'), findsOneWidget);

    // «Продолжить» возвращает к экзамену.
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('Прервать экзамен?'), findsNothing);
    expect(find.byType(ExamScreen), findsOneWidget);
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
      // 8 вопросов остались без ответа.
      expect(find.text('Без ответа'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
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
}
