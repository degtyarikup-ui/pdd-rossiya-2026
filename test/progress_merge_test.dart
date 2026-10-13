import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/progress_snapshot.dart';

void main() {
  final cases =
      jsonDecode(File('test/fixtures/progress_merge.json').readAsStringSync())
          as List;
  for (final row in cases) {
    test(row['name'] as String, () {
      final merged = mergeProgressSnapshots(
        Map<String, dynamic>.from(row['local'] as Map),
        Map<String, dynamic>.from(row['remote'] as Map),
      );
      for (final entry in (row['expected'] as Map).entries) {
        expect(merged[entry.key], entry.value, reason: entry.key as String);
      }
    });
  }
}
