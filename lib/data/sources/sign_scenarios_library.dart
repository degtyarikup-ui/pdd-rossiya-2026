import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/l10n/l10n.dart';

class SignScenario {
  final String prompt;
  final bool isCorrect;
  final String explanation;
  final SignQuestionType type;

  const SignScenario({
    required this.prompt,
    required this.isCorrect,
    required this.explanation,
    this.type = SignQuestionType.warningNotice,
  });
}

/// Only reviewed, sign-specific scenarios. No category-wide rule guessing.
/// See docs/game/mini-games-pdd-audit.md for sources and scope.
class SignScenariosLibrary {
  static final Map<String, List<SignScenario>> _scenarios = {
    '1.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario1_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario1_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario1_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario1_1_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario1_1_2Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario1_1_2Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '1.2': [
      SignScenario(
        prompt: appL10n.gameSignScenario1_2_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario1_2_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario1_2_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario1_2_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '1.3.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario1_3_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario1_3_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario1_3_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario1_3_1_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '1.5': [
      SignScenario(
        prompt: appL10n.gameSignScenario1_5_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario1_5_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario1_5_1Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario1_5_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '1.6': [
      SignScenario(
        prompt: appL10n.gameSignScenario1_6_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario1_6_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario1_6_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario1_6_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '1.7': [
      SignScenario(
        prompt: appL10n.gameSignScenario1_7_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario1_7_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario1_7_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario1_7_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '1.11.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario1_11_1_0Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario1_11_1_0Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario1_11_1_1Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario1_11_1_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '1.23': [
      SignScenario(
        prompt: appL10n.gameSignScenario1_23_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario1_23_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario1_23_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario1_23_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '1.25': [
      SignScenario(
        prompt: appL10n.gameSignScenario1_25_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario1_25_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario1_25_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario1_25_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '2.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario2_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario2_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario2_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario2_1_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario2_1_2Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario2_1_2Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '2.2': [
      SignScenario(
        prompt: appL10n.gameSignScenario2_2_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario2_2_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario2_2_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario2_2_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '2.3.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario2_3_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario2_3_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario2_3_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario2_3_1_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '2.4': [
      SignScenario(
        prompt: appL10n.gameSignScenario2_4_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario2_4_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario2_4_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario2_4_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario2_4_2Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario2_4_2Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '2.5': [
      SignScenario(
        prompt: appL10n.gameSignScenario2_5_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario2_5_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario2_5_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario2_5_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '2.6': [
      SignScenario(
        prompt: appL10n.gameSignScenario2_6_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario2_6_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario2_6_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario2_6_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '2.7': [
      SignScenario(
        prompt: appL10n.gameSignScenario2_7_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario2_7_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario2_7_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario2_7_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '3.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario3_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_1_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_1_2Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario3_1_2Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '3.2': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_2_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario3_2_0Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_2_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_2_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_2_2Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_2_2Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '3.4': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_4_0Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_4_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_4_1Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario3_4_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '3.18.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_18_1_0Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_18_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_18_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_18_1_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '3.18.2': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_18_2_0Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_18_2_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_18_2_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_18_2_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '3.19': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_19_0Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_19_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_19_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_19_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '3.20': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_20_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario3_20_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_20_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_20_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_20_2Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario3_20_2Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '3.24': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_24_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario3_24_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_24_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_24_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '3.27': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_27_0Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_27_0Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_27_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_27_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_27_2Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_27_2Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '3.28': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_28_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario3_28_0Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_28_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_28_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_28_2Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_28_2Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '3.29': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_29_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario3_29_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_29_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_29_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '3.31': [
      SignScenario(
        prompt: appL10n.gameSignScenario3_31_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario3_31_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario3_31_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario3_31_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '4.1.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario4_1_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario4_1_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario4_1_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario4_1_1_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '4.1.2': [
      SignScenario(
        prompt: appL10n.gameSignScenario4_1_2_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario4_1_2_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario4_1_2_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario4_1_2_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '4.1.3': [
      SignScenario(
        prompt: appL10n.gameSignScenario4_1_3_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario4_1_3_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario4_1_3_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario4_1_3_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '4.1.4': [
      SignScenario(
        prompt: appL10n.gameSignScenario4_1_4_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario4_1_4_0Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario4_1_4_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario4_1_4_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '4.1.5': [
      SignScenario(
        prompt: appL10n.gameSignScenario4_1_5_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario4_1_5_0Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario4_1_5_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario4_1_5_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '4.2.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario4_2_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario4_2_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario4_2_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario4_2_1_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '4.3': [
      SignScenario(
        prompt: appL10n.gameSignScenario4_3_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario4_3_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario4_3_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario4_3_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '4.6': [
      SignScenario(
        prompt: appL10n.gameSignScenario4_6_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario4_6_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario4_6_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario4_6_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '5.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario5_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario5_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_1_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_1_2Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_1_2Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '5.3': [
      SignScenario(
        prompt: appL10n.gameSignScenario5_3_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario5_3_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_3_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_3_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '5.5': [
      SignScenario(
        prompt: appL10n.gameSignScenario5_5_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario5_5_0Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_5_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_5_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_5_2Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario5_5_2Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '5.14.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario5_14_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario5_14_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_14_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_14_1_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '5.15.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario5_15_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario5_15_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_15_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_15_1_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '5.19.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario5_19_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario5_19_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_19_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_19_1_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_19_1_2Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_19_1_2Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '5.20': [
      SignScenario(
        prompt: appL10n.gameSignScenario5_20_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario5_20_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_20_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_20_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '5.21': [
      SignScenario(
        prompt: appL10n.gameSignScenario5_21_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario5_21_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_21_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_21_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_21_2Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_21_2Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '5.23.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario5_23_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario5_23_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_23_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_23_1_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '5.25': [
      SignScenario(
        prompt: appL10n.gameSignScenario5_25_0Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_25_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario5_25_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario5_25_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '6.2': [
      SignScenario(
        prompt: appL10n.gameSignScenario6_2_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario6_2_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario6_2_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario6_2_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '6.3.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario6_3_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario6_3_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario6_3_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario6_3_1_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
    '6.4': [
      SignScenario(
        prompt: appL10n.gameSignScenario6_4_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario6_4_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario6_4_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario6_4_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '6.16': [
      SignScenario(
        prompt: appL10n.gameSignScenario6_16_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario6_16_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario6_16_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario6_16_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '7.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario7_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario7_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario7_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario7_1_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '7.3': [
      SignScenario(
        prompt: appL10n.gameSignScenario7_3_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario7_3_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario7_3_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario7_3_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '8.1.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario8_1_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario8_1_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario8_1_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario8_1_1_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '8.2.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario8_2_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario8_2_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario8_2_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario8_2_1_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '8.2.3': [
      SignScenario(
        prompt: appL10n.gameSignScenario8_2_3_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario8_2_3_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario8_2_3_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario8_2_3_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '8.4.1': [
      SignScenario(
        prompt: appL10n.gameSignScenario8_4_1_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario8_4_1_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario8_4_1_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario8_4_1_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '8.4.3': [
      SignScenario(
        prompt: appL10n.gameSignScenario8_4_3_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario8_4_3_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario8_4_3_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario8_4_3_1Explanation,
        type: SignQuestionType.warningNotice,
      ),
    ],
    '8.17': [
      SignScenario(
        prompt: appL10n.gameSignScenario8_17_0Prompt,
        isCorrect: true,
        explanation: appL10n.gameSignScenario8_17_0Explanation,
        type: SignQuestionType.warningNotice,
      ),
      SignScenario(
        prompt: appL10n.gameSignScenario8_17_1Prompt,
        isCorrect: false,
        explanation: appL10n.gameSignScenario8_17_1Explanation,
        type: SignQuestionType.actionPermission,
      ),
    ],
  };

  static List<SignScenario>? getScenariosForSign(String number) =>
      _scenarios[number];
  static bool hasScenarios(String number) => _scenarios.containsKey(number);
}
