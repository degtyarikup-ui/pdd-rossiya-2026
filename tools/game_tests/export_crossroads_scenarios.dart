import 'dart:convert';
import 'dart:io';

import 'package:pdd_app/data/models/crossroads_priority_model.dart';

void main() {
  final scenarios = CrossroadsScenariosLibrary.allScenarios;
  final jsonList = scenarios.map((s) => s.toJson()).toList();
  final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonList);
  File('/tmp/crossroads_scenarios.json').writeAsStringSync(jsonStr);
  stdout.writeln('Successfully exported ${scenarios.length} scenarios to /tmp/crossroads_scenarios.json');
}
