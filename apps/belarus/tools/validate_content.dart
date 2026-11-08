import 'dart:convert';
import 'dart:io';
import 'package:pdd_belarus/domain/question_bank.dart';

void main(List<String> args) {
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final paths = args.where((a) => !a.startsWith('--')).toList();
  if (paths.length != 1 || flags.difference({'--require-ready'}).isNotEmpty) {
    stderr.writeln(
      'Usage: dart tools/validate_content.dart catalog.json [--require-ready]',
    );
    exitCode = 2;
    return;
  }
  try {
    final bank = QuestionBank.fromJson(
      jsonDecode(File(paths.single).readAsStringSync()) as Map<String, dynamic>,
    );
    if (flags.contains('--require-ready') && !bank.canStartExam) {
      throw StateError('Content/regulations not approved; release blocked');
    }
    stdout.writeln(
      'BY catalog: ${bank.questions.length} questions; exam ready: ${bank.canStartExam}',
    );
  } catch (error) {
    stderr.writeln('Invalid BY content: $error');
    exitCode = 1;
  }
}
