import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/share_card_renderer.dart';
import 'package:pdd_app/presentation/widgets/share_result_card.dart';

/// Карточка результата для шеринга: собирается офскрин в PNG 1080×1080.
///
/// Тесты стерегут две вещи: что рендер вообще отрабатывает (он строит
/// отдельное дерево через PipelineOwner — легко сломать при обновлении
/// Flutter) и что вёрстка не переполняется на длинных подписях.
void main() {
  ShareResultCard buildCard({
    bool passed = true,
    int correct = 19,
    int wrong = 1,
    int readiness = 94,
    String correctLabel = 'правильных',
    String wrongLabel = 'ошибка',
  }) {
    return ShareResultCard(
      passed: passed,
      correct: correct,
      wrong: wrong,
      readinessPercent: readiness,
      title: passed ? 'Экзамен сдан' : 'Экзамен не сдан',
      correctLabel: correctLabel,
      wrongLabel: wrongLabel,
      readinessLabel: 'Готовность к экзамену',
      siteUrl: 'pdd-drive.ru',
    );
  }

  testWidgets('карточка собирается в PNG нужного размера', (tester) async {
    late final dynamic png;
    // toImage требует настоящего асинхронного исполнения — под фейковым
    // временем тестов он не дождётся кадра.
    await tester.runAsync(() async {
      png = await ShareCardRenderer.renderToPng(
        widget: buildCard(),
        size: const Size(ShareResultCard.side, ShareResultCard.side),
      );
    });

    expect(png, isNotNull, reason: 'рендер карточки не должен падать');
    expect(png.length, greaterThan(1000), reason: 'PNG подозрительно пустой');
    // Сигнатура PNG: \x89 P N G
    expect(png[0], 0x89);
    expect(png[1], 0x50);
    expect(png[2], 0x4E);
    expect(png[3], 0x47);
  });

  testWidgets('вёрстка не переполняется: длинные подписи и большие числа',
      (tester) async {
    // Сербский вариант подписей заметно длиннее русского, а число ошибок
    // на экзамене MUP доходит до двузначного — проверяем худший случай.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Center(
            child: SizedBox(
              width: ShareResultCard.side,
              height: ShareResultCard.side,
              child: buildCard(
                passed: false,
                correct: 35,
                wrong: 6,
                readiness: 100,
                correctLabel: 'tačnih odgovora',
                wrongLabel: 'grešaka ukupno',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull,
        reason: 'переполнение разметки бросило бы исключение');
    expect(find.text('Экзамен не сдан'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
    expect(find.text('Готовность к экзамену — 100%'), findsOneWidget);
  });
}
