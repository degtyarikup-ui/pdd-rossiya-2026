import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/datasources/sign_scenarios_library.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';

void main() {
  group('SignScenariosLibrary Tests', () {
    test('Key signs have handcrafted scenarios in library', () {
      final keySigns = [
        '1.1', '1.2', '1.5', '1.6', '1.7', '1.11.1', '1.23', '1.25',
        '2.1', '2.2', '2.3.1', '2.4', '2.5', '2.6', '2.7',
        '3.1', '3.2', '3.4', '3.18.1', '3.18.2', '3.19', '3.20', '3.24', '3.27', '3.28', '3.29', '3.31',
        '4.1.1', '4.1.2', '4.1.3', '4.1.4', '4.1.5', '4.2.1', '4.3', '4.6',
        '5.1', '5.3', '5.5', '5.14.1', '5.15.1', '5.19.1', '5.20', '5.21', '5.23.1', '5.25',
        '6.2', '6.3.1', '6.4', '6.16',
        '7.1', '7.3',
        '8.1.1', '8.2.1', '8.2.3', '8.4.1', '8.4.3', '8.17',
      ];

      for (final signNum in keySigns) {
        final scenarios = SignScenariosLibrary.getScenariosForSign(signNum);
        expect(scenarios, isNotNull, reason: 'Sign $signNum should have scenarios');
        expect(scenarios!.isNotEmpty, isTrue, reason: 'Sign $signNum scenarios should not be empty');

        for (final sc in scenarios) {
          expect(sc.prompt.trim().isNotEmpty, isTrue);
          expect(sc.explanation.trim().isNotEmpty, isTrue);
          expect(sc.prompt.contains('называется'), isFalse);
          expect(sc.prompt.contains('Относится ли этот знак к категории'), isFalse);
          expect(sc.prompt.contains('В народе'), isFalse);
        }
      }
    });

    test('Fallback generator creates valid scenarios for all 8 categories', () {
      final categories = [
        'Предупреждающие знаки',
        'Знаки приоритета',
        'Запрещающие знаки',
        'Предписывающие знаки',
        'Знаки особых предписаний',
        'Информационные знаки',
        'Знаки сервиса',
        'Знаки дополнительной информации (таблички)',
      ];

      final rnd = Random(42);

      for (final cat in categories) {
        final sign = SignItem(
          number: '99.9',
          title: 'Тестовый знак категории',
          image: 'test.svg',
          category: cat,
          description: 'Официальное описание тестового знака.',
        );

        final trueScenario = SignScenariosLibrary.generateCategoryScenario(sign, true, rnd);
        expect(trueScenario.isCorrect, isTrue);
        expect(trueScenario.prompt.isNotEmpty, isTrue);
        expect(trueScenario.explanation.isNotEmpty, isTrue);
        expect(trueScenario.prompt.contains('называется'), isFalse);

        final falseScenario = SignScenariosLibrary.generateCategoryScenario(sign, false, rnd);
        expect(falseScenario.isCorrect, isFalse);
        expect(falseScenario.prompt.isNotEmpty, isTrue);
        expect(falseScenario.explanation.isNotEmpty, isTrue);
        expect(falseScenario.prompt.contains('называется'), isFalse);
      }
    });

    test('Adaptive labels (МОЖНО/НЕЛЬЗЯ vs ДА/НЕТ) match question starter', () {
      final permQuestion = SignCardQuestion(
        id: '1',
        sign: const SignItem(number: '3.20', title: 'Обгон запрещен', image: 'test.svg', category: 'Запрещающие знаки', description: ''),
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
        sign: const SignItem(number: '3.1', title: 'Въезд запрещен', image: 'test.svg', category: 'Запрещающие знаки', description: ''),
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
        sign: const SignItem(number: '2.5', title: 'Движение без остановки запрещено', image: 'test.svg', category: 'Знаки приоритета', description: ''),
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
