// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Belarus driving theory · Test';

  @override
  String get welcome => 'Get ready for Belarus roads';

  @override
  String get intro =>
      'Road rules and practice exam for the Republic of Belarus.';

  @override
  String get exam => 'Exam';

  @override
  String get examRules => '10 questions · 15 minutes · at most one mistake';

  @override
  String get contentPending =>
      'We are checking current questions and answers. The exam will be available after the question bank is reviewed.';

  @override
  String get startExam => 'Start exam';

  @override
  String get preparing => 'Preparing question bank';

  @override
  String get practiceNotice =>
      'Independent practice tool. This is not an official traffic police exam.';

  @override
  String get loadError => 'Could not load questions.';

  @override
  String get retry => 'Retry';

  @override
  String get leaveTitle => 'End this attempt?';

  @override
  String get leaveBody =>
      'Your answers in this attempt will not be saved. The timer keeps running.';

  @override
  String get stay => 'Continue';

  @override
  String get leave => 'Leave';

  @override
  String get result => 'Result';

  @override
  String get passed => 'Passed';

  @override
  String get failed => 'Not passed';

  @override
  String get expired => 'Time is up';

  @override
  String score(int count) {
    return 'Correct answers: $count of 10';
  }

  @override
  String correctAnswer(String answer) {
    return 'Correct answer: $answer';
  }

  @override
  String get home => 'Home';

  @override
  String questionNumber(int number) {
    return 'Question $number of 10';
  }

  @override
  String get previewOpen => 'Browse questions';

  @override
  String get previewNotice =>
      'PDD.by test sample. Completeness and currency are still under review.';

  @override
  String previewCount(int count) {
    return 'Questions in snapshot: $count';
  }

  @override
  String previewPosition(int number, int total) {
    return '$number of $total';
  }

  @override
  String get previewReveal => 'Show answer';

  @override
  String get previewPrevious => 'Previous';

  @override
  String get previewNext => 'Next';

  @override
  String get previewImageError =>
      'Image could not be loaded. This question cannot be assessed without its illustration.';
}
