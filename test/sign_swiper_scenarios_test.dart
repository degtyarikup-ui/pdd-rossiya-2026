import 'package:pdd_app/domain/services/sign_swiper_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/sources/sign_scenarios_library.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';

void main() {
  group('SignScenariosLibrary Tests', () {
    test('Key signs have handcrafted scenarios in library', () {
      final keySigns = [
        '1.1',
        '1.2',
        '1.5',
        '1.6',
        '1.7',
        '1.11.1',
        '1.23',
        '1.25',
        '2.1',
        '2.2',
        '2.3.1',
        '2.4',
        '2.5',
        '2.6',
        '2.7',
        '3.1',
        '3.2',
        '3.4',
        '3.18.1',
        '3.18.2',
        '3.19',
        '3.20',
        '3.24',
        '3.27',
        '3.28',
        '3.29',
        '3.31',
        '4.1.1',
        '4.1.2',
        '4.1.3',
        '4.1.4',
        '4.1.5',
        '4.2.1',
        '4.3',
        '4.6',
        '5.1',
        '5.3',
        '5.5',
        '5.14.1',
        '5.15.1',
        '5.19.1',
        '5.20',
        '5.21',
        '5.23.1',
        '5.25',
        '6.2',
        '6.3.1',
        '6.4',
        '6.16',
        '7.1',
        '7.3',
        '8.1.1',
        '8.2.1',
        '8.2.3',
        '8.4.1',
        '8.4.3',
        '8.17',
      ];

      for (final signNum in keySigns) {
        final scenarios = SignScenariosLibrary.getScenariosForSign(signNum);
        expect(
          scenarios,
          isNotNull,
          reason: 'Sign $signNum should have scenarios',
        );
        expect(
          scenarios!.isNotEmpty,
          isTrue,
          reason: 'Sign $signNum scenarios should not be empty',
        );

        for (final sc in scenarios) {
          expect(sc.prompt.trim().isNotEmpty, isTrue);
          expect(sc.explanation.trim().isNotEmpty, isTrue);
          expect(sc.prompt.contains('называется'), isFalse);
          expect(
            sc.prompt.contains('Относится ли этот знак к категории'),
            isFalse,
          );
          expect(sc.prompt.contains('В народе'), isFalse);
        }
      }
    });

    test('unreviewed signs never receive category-wide guessed rules', () {
      expect(SignScenariosLibrary.getScenariosForSign('3.17.2'), isNull);
      final engine = SignSwiperEngine(
        allSigns: const [
          SignItem(
            number: '3.17.2',
            title: 'Danger',
            image: 'test.svg',
            category: 'Prohibitory',
            description: '',
          ),
        ],
      );
      expect(engine.generateDeck(count: 30), isEmpty);
    });

    test(
      '8 tonne truck sign uses the pictured limit, not a generic 3.5 tonnes',
      () {
        final scenarios = SignScenariosLibrary.getScenariosForSign('3.4')!;
        final fiveTonnes = scenarios.firstWhere(
          (s) => s.prompt.contains('5 т'),
        );
        expect(fiveTonnes.isCorrect, isTrue);
        expect(fiveTonnes.explanation, contains('8 т'));
      },
    );

    test('negative statements use YES/NO rather than permission labels', () {
      final scenarios = SignScenariosLibrary.getScenariosForSign('3.18.2')!;
      final prohibition = scenarios.firstWhere(
        (s) => s.prompt.contains('запрещает'),
      );
      expect(prohibition.isCorrect, isFalse);
      expect(prohibition.type, SignQuestionType.warningNotice);
    });

    test('Adaptive labels (МОЖНО/НЕЛЬЗЯ vs ДА/НЕТ) match question starter', () {
      final permQuestion = SignCardQuestion(
        id: '1',
        sign: const SignItem(
          number: '3.20',
          title: 'Обгон запрещен',
          image: 'test.svg',
          category: 'Запрещающие знаки',
          description: '',
        ),
        prompt: 'Можно ли обогнать тихоходное транспортное средство?',
        isCorrect: true,
        explanation: 'Да, можно.',
        type: SignQuestionType.actionPermission,
      );
      expect(permQuestion.isPermissionQuestion, isTrue);
      expect(permQuestion.rightActionLabel, equals('МОЖНО'));
      expect(permQuestion.leftActionLabel, equals('НЕЛЬЗЯ'));

      final allowedQuestion = SignCardQuestion(
        id: '2',
        sign: const SignItem(
          number: '3.1',
          title: 'Въезд запрещен',
          image: 'test.svg',
          category: 'Запрещающие знаки',
          description: '',
        ),
        prompt: 'Разрешён ли въезд под этот знак?',
        isCorrect: false,
        explanation: 'Нельзя.',
        type: SignQuestionType.actionPermission,
      );
      expect(allowedQuestion.isPermissionQuestion, isTrue);
      expect(allowedQuestion.rightActionLabel, equals('МОЖНО'));
      expect(allowedQuestion.leftActionLabel, equals('НЕЛЬЗЯ'));

      final obligQuestion = SignCardQuestion(
        id: '3',
        sign: const SignItem(
          number: '2.5',
          title: 'Движение без остановки запрещено',
          image: 'test.svg',
          category: 'Знаки приоритета',
          description: '',
        ),
        prompt: 'Обязаны ли вы остановиться перед знаком или стоп-линией?',
        isCorrect: true,
        explanation: 'Да, обязаны.',
        type: SignQuestionType.driverObligation,
      );
      expect(obligQuestion.isPermissionQuestion, isFalse);
      expect(obligQuestion.rightActionLabel, equals('ДА'));
      expect(obligQuestion.leftActionLabel, equals('НЕТ'));
    });
  });
}
