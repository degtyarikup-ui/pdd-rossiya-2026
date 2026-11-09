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
    final appRoot = File.fromUri(Platform.script).parent.parent;
    final bank = QuestionBank.fromJson(
      jsonDecode(File(paths.single).readAsStringSync()) as Map<String, dynamic>,
    );
    for (final question in bank.questions) {
      for (final asset in question.imageAssets) {
        if (!File('${appRoot.path}/$asset').existsSync()) {
          throw FormatException('Missing image: $asset');
        }
      }
    }
    if (flags.contains('--require-ready') &&
        File(
          '${appRoot.path}/assets/countries/by/preview_catalog.json',
        ).existsSync()) {
      throw StateError(
        'Local preview assets must be removed from a release workspace',
      );
    }
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
