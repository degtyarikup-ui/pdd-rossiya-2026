import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/utils/pdd_point_refs.dart';
import 'package:pdd_app/data/services/pdd_point_index.dart';
import 'package:pdd_app/presentation/screens/pdd/pdd_screen.dart';
import 'package:pdd_app/presentation/widgets/pdd_comment_text.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Строим указатель ДО тестов: иначе закэшированный Future, созданный
    // внутри одного testWidgets, доигрывается уже в зоне следующего — и
    // flutter_test валится на guardSync.
    await PddPointIndex.load();
  });

  group('поиск ссылок на пункты', () {
    test('«Пункт 13.11 ПДД» — одна ссылка на нужный номер', () {
      final refs = findPddPointRefs('Уступите справа. (Пункт 13.11 ПДД)');
      expect(refs.map((r) => r.point), ['13.11']);
    });

    test('перечисление разбирается по отдельным номерам', () {
      final refs = findPddPointRefs('См. пункты 8.1, 8.2 и 8.5 Правил.');
      expect(refs.map((r) => r.point), ['8.1', '8.2', '8.5']);
    });

    test('трёхуровневый пункт не обрезается до двухуровневого', () {
      // 9.1.1 — запрет выезда на встречную. Обрезав его до 9.1, ушли бы
      // в пункт про число полос, то есть совсем в другое правило.
      final refs = findPddPointRefs('Запрещено (пункт 9.1.1 ПДД).');
      expect(refs.map((r) => r.point), ['9.1.1']);
    });

    test('номера знаков и разметки ссылками НЕ становятся', () {
      // Главная причина, по которой ловим только номера после слова «пункт»:
      // «знак 3.1» выглядит ровно как номер пункта.
      final refs = findPddPointRefs(
        'Установлен знак 3.1, нанесена разметка 1.1.',
      );
      expect(refs, isEmpty);
    });

    test('границы номера указывают ровно на него', () {
      const text = 'Смотри пункт 13.9 Правил.';
      final ref = findPddPointRefs(text).single;
      expect(text.substring(ref.start, ref.end), '13.9');
    });
  });

  group('указатель пунктов', () {
    test('находит раздел по номеру пункта', () async {
      final index = await PddPointIndex.load();

      final s13 = index.sectionOf('13.11');
      expect(s13, isNotNull);
      expect(s13!['title'], contains('Проезд перекрестков'));

      // Раздел 22 — перевозка людей. До замены текста ПДД раздел с таким
      // номером назывался иначе, и ссылки вели не туда.
      expect(index.sectionOf('22.9')?['title'], contains('Перевозка людей'));
    });

    test('надстрочные пункты доступны по «плоскому» номеру', () async {
      final index = await PddPointIndex.load();
      // В законе это 9.1¹ и 13.11¹, но цитируют их всегда так.
      expect(index.contains('9.1.1'), isTrue);
      expect(index.contains('13.11.1'), isTrue);
    });

    test('пункт из другого документа не найден и ссылкой не станет', () async {
      final index = await PddPointIndex.load();
      // 5.6 — из «Перечня неисправностей», отдельного приложения к ПДД.
      expect(index.contains('5.6'), isFalse);
    });
  });

  group('виджет комментария', () {
    testWidgets('номер пункта становится кликабельным', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PddCommentText('Уступите дорогу. (Пункт 13.11 ПДД)'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rich = tester.widget<Text>(find.byType(Text));
      final span = rich.textSpan! as TextSpan;
      final linked = <String>[];
      span.visitChildren((s) {
        if (s is TextSpan && s.recognizer != null) linked.add(s.text ?? '');
        return true;
      });
      expect(linked, ['13.11']);
    });

    testWidgets('тап открывает раздел правил на нужном пункте', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PddCommentText('Уступите дорогу. (Пункт 13.11 ПДД)'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapOnText(find.textRange.ofSubstring('13.11'));
      await tester.pumpAndSettle();

      final detail = tester.widget<PddDetailScreen>(
        find.byType(PddDetailScreen),
      );
      expect(detail.highlightPoint, '13.11');
      expect(detail.title, contains('Проезд перекрестков'));
    });

    testWidgets('нужный пункт обведён рамкой, соседние — нет', (tester) async {
      // Ради этого вся затея: человек пришёл по ссылке и должен сразу видеть,
      // какой абзац искал. Проверка перехода такое не ловит — экран
      // открывается правильный, а выделения нет.
      await tester.pumpWidget(
        const MaterialApp(
          home: PddDetailScreen(
            title: '13. Проезд перекрестков',
            content: '13.10. Первый пункт.\n\n'
                '13.11. Нужный пункт.\n\n'
                '13.12. Третий пункт.',
            highlightPoint: '13.11',
          ),
        ),
      );
      await tester.pumpAndSettle();

      Border? borderOf(String text) {
        final container = tester.widget<Container>(
          find.ancestor(of: find.text(text), matching: find.byType(Container)),
        );
        return (container.decoration as BoxDecoration?)?.border as Border?;
      }

      expect(borderOf('13.11. Нужный пункт.'), isNotNull);
      expect(borderOf('13.10. Первый пункт.'), isNull);
      expect(borderOf('13.12. Третий пункт.'), isNull);
    });

    testWidgets('13.11 не задевает соседний 13.11.1', (tester) async {
      // Пункт 13.11.1 тоже начинается с «13.11.». Проверка на префикс
      // пометила бы оба блока сразу — и приложение падало бы на GlobalKey.
      await tester.pumpWidget(
        const MaterialApp(
          home: PddDetailScreen(
            title: '13. Проезд перекрестков',
            content: '13.11. Правило правой руки.\n\n'
                '13.11.1. Круговое движение.',
            highlightPoint: '13.11',
          ),
        ),
      );
      await tester.pumpAndSettle();

      Border? borderOf(String text) {
        final container = tester.widget<Container>(
          find.ancestor(of: find.text(text), matching: find.byType(Container)),
        );
        return (container.decoration as BoxDecoration?)?.border as Border?;
      }

      expect(borderOf('13.11. Правило правой руки.'), isNotNull);
      expect(borderOf('13.11.1. Круговое движение.'), isNull);
    });

    testWidgets('без highlightPoint не выделен ни один пункт', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PddDetailScreen(
            title: '13. Проезд перекрестков',
            content: '13.10. Первый пункт.\n\n13.11. Нужный пункт.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final c in tester.widgetList<Container>(find.byType(Container))) {
        expect((c.decoration as BoxDecoration?)?.border, isNull);
      }
    });

    testWidgets('текст без ссылок остаётся обычным текстом', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PddCommentText('Просто пояснение без ссылок.')),
        ),
      );
      await tester.pumpAndSettle();

      final rich = tester.widget<Text>(find.byType(Text));
      expect(rich.data, 'Просто пояснение без ссылок.');
    });
  });
}
