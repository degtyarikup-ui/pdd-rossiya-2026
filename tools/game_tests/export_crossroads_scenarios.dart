import 'dart:convert';
import 'dart:io';

import 'package:pdd_app/data/models/crossroads_priority_model.dart';

void main() {
  final scenariosRu = CrossroadsScenariosLibrary.allScenarios;
  final scenariosEn = CrossroadsScenariosLibrary.getScenarios('en');
  final scenariosKk = CrossroadsScenariosLibrary.getScenarios('kk');

  final enById = {for (final s in scenariosEn) s.id: s};
  final kkById = {for (final s in scenariosKk) s.id: s};

  final List<Map<String, dynamic>> exported = [];

  for (final s in scenariosRu) {
    final sEn = enById[s.id] ?? s;
    final sKk = kkById[s.id] ?? s;

    final actorsList = s.actors.map((a) {
      return {
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

    exported.add({
      'id': s.id,
      'category': s.category.name,
      'title': s.title,
      'subtitle': s.subtitle,
      'pddArticle': s.pddArticle,
      'isEqual': s.isEqualCrossroad,
      'isHard': s.isHardSituation,
      if (s.closedSide != null) 'closedSide': s.closedSide!.name,
      'signs': s.signs.map((sign) => sign.toJson()).toList(),
      'trafficLights': s.trafficLights?.map((tl) => tl.toJson()).toList() ?? [],
      'actors': actorsList,
      'translations': translations,
    });
  }

  final jsonStr = const JsonEncoder.withIndent('  ').convert(exported);
  final targetFile = File('game_godot/data/crossroads_scenarios.json');
  targetFile.writeAsStringSync(jsonStr);
  stdout.writeln('Successfully exported ${exported.length} scenarios with ru/en/kk to ${targetFile.path}');
}
