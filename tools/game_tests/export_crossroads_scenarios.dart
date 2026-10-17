import 'dart:convert';
import 'dart:io';

import 'package:pdd_app/data/models/crossroads_priority_model.dart';

void main() {
  final targetFile = File('game_godot/data/crossroads_scenarios.json');
  if (!targetFile.existsSync()) {
    stderr.writeln('Error: target file ${targetFile.path} does not exist.');
    exit(1);
  }

  // Load existing source-of-truth scenarios
  final existingRaw = targetFile.readAsStringSync();
  final List<dynamic> existingJson =
      jsonDecode(existingRaw) as List<dynamic>;
  final existingById = <String, Map<String, dynamic>>{
    for (final item in existingJson)
      (item as Map<String, dynamic>)['id'] as String:
          Map<String, dynamic>.from(item),
  };

  final scenariosRu = CrossroadsScenariosLibrary.allScenarios;
  final scenariosEn = CrossroadsScenariosLibrary.getScenarios('en');
  final scenariosKk = CrossroadsScenariosLibrary.getScenarios('kk');

  final enById = {for (final s in scenariosEn) s.id: s};
  final kkById = {for (final s in scenariosKk) s.id: s};

  final List<Map<String, dynamic>> exported = [];
  final exportedIds = <String>{};

  for (final s in scenariosRu) {
    final sEn = enById[s.id] ?? s;
    final sKk = kkById[s.id] ?? s;
    final existingSc = existingById[s.id];

    final actorsList = s.actors.map((a) {
      final existingActor = (existingSc?['actors'] as List?)
          ?.cast<Map<String, dynamic>>()
          .firstWhere((ea) => ea['id'] == a.id, orElse: () => {});
      final actorMap = <String, dynamic>{
        'id': a.id,
        'type': a.type.name,
        'name': a.name,
        'model': a.vehicleModel,
        'color': a.colorHex,
        'side': a.side.name,
        'maneuver': a.maneuver.name,
        'order': a.priorityOrder,
        'explanation': a.ruleExplanation,
        'hasSiren': a.hasSiren,
      };
      // Preserve any additional Godot-specific actor attributes
      if (existingActor != null) {
        for (final entry in existingActor.entries) {
          actorMap.putIfAbsent(entry.key, () => entry.value);
        }
      }
      return actorMap;
    }).toList();

    final translations = {
      'ru': {
        'title': s.title,
        'subtitle': s.subtitle,
        'pddArticle': s.pddArticle,
        'actors': {
          for (final a in s.actors)
            a.id: {'name': a.name, 'explanation': a.ruleExplanation},
        },
      },
      'en': {
        'title': sEn.title,
        'subtitle': sEn.subtitle,
        'pddArticle': sEn.pddArticle,
        'actors': {
          for (final a in sEn.actors)
            a.id: {'name': a.name, 'explanation': a.ruleExplanation},
        },
      },
      'kk': {
        'title': sKk.title,
        'subtitle': sKk.subtitle,
        'pddArticle': sKk.pddArticle,
        'actors': {
          for (final a in sKk.actors)
            a.id: {'name': a.name, 'explanation': a.ruleExplanation},
        },
      },
    };

    final scMap = existingSc != null
        ? Map<String, dynamic>.from(existingSc)
        : <String, dynamic>{};

    scMap['id'] = s.id;
    scMap['category'] = s.category.name;
    scMap['title'] = s.title;
    scMap['subtitle'] = s.subtitle;
    scMap['pddArticle'] = s.pddArticle;
    scMap['isEqual'] = s.isEqualCrossroad;
    scMap['isHard'] = s.isHardSituation;
    if (s.closedSide != null) {
      scMap['closedSide'] = s.closedSide!.name;
    }
    scMap['signs'] = s.signs.map((sign) => sign.toJson()).toList();
    scMap['trafficLights'] =
        s.trafficLights?.map((tl) => tl.toJson()).toList() ?? [];
    scMap['actors'] = actorsList;
    scMap['translations'] = translations;

    exported.add(scMap);
    exportedIds.add(s.id);
  }

  // Preserve Godot-native scenarios (scenarios 28..33) not defined in Dart library
  for (final item in existingJson) {
    final sc = item as Map<String, dynamic>;
    final id = sc['id'] as String;
    if (!exportedIds.contains(id)) {
      exported.add(sc);
      exportedIds.add(id);
    }
  }

  // MANDATORY INTEGRITY & DOWNGRADE GUARDS:
  // 1. Must never decrease scenario count below 33 or existing total
  if (exported.length < 33 || exported.length < existingJson.length) {
    stderr.writeln(
      'REFUSING TO DOWNGRADE: exported count (${exported.length}) is below '
      'expected minimum (33) or existing count (${existingJson.length}). Aborting.',
    );
    exit(1);
  }

  // 2. Validate all scenarios have valid 1..N order and trilingual translations
  for (final s in exported) {
    final id = s['id'] as String;
    final actors = (s['actors'] as List).cast<Map<String, dynamic>>();
    if (actors.length < 2) {
      stderr.writeln('Validation error: Scenario $id has < 2 actors');
      exit(1);
    }
    final orders = actors.map((a) => a['order'] as int).toList()..sort();
    for (int i = 0; i < orders.length; i++) {
      if (orders[i] != i + 1) {
        stderr.writeln(
          'Validation error: Scenario $id has invalid priority order: $orders',
        );
        exit(1);
      }
    }
    final tr = s['translations'] as Map<String, dynamic>?;
    if (tr == null) {
      stderr.writeln('Validation error: Scenario $id is missing translations map');
      exit(1);
    }
    for (final lang in ['ru', 'en', 'kk']) {
      final tLang = tr[lang] as Map<String, dynamic>?;
      if (tLang == null ||
          (tLang['title'] as String?)?.isEmpty == true ||
          (tLang['subtitle'] as String?)?.isEmpty == true ||
          (tLang['pddArticle'] as String?)?.isEmpty == true) {
        stderr.writeln(
          'Validation error: Scenario $id missing or empty header translations for $lang',
        );
        exit(1);
      }
      final tActors = tLang['actors'] as Map<String, dynamic>?;
      if (tActors == null) {
        stderr.writeln(
          'Validation error: Scenario $id missing actor translations for $lang',
        );
        exit(1);
      }
      for (final a in actors) {
        final aid = a['id'] as String;
        final aTr = tActors[aid] as Map<String, dynamic>?;
        if (aTr == null ||
            (aTr['name'] as String?)?.isEmpty == true ||
            (aTr['explanation'] as String?)?.isEmpty == true) {
          stderr.writeln(
            'Validation error: Scenario $id actor $aid missing name/explanation in $lang',
          );
          exit(1);
        }
      }
    }
  }

  // Create backup before writing
  final backupFile = File('${targetFile.path}.bak');
  backupFile.writeAsStringSync(existingRaw);

  final jsonStr = const JsonEncoder.withIndent('  ').convert(exported);
  targetFile.writeAsStringSync('$jsonStr\n');
  stdout.writeln(
    'Successfully validated and protected ${exported.length} scenarios '
    '(all 33 intact with ru/en/kk) in ${targetFile.path} (backup at ${backupFile.path})',
  );
}
