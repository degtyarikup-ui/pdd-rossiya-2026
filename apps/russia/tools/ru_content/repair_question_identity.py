#!/usr/bin/env python3
"""Separate repeated source IDs without changing studio/Godot source IDs.

Ticket position identifies a distinct illustration. The first occurrence keeps
the legacy ID; later occurrences have variantId. Legacy progress is expanded
once into independent records, preserving the state previously shared by them.
"""
from collections import defaultdict
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / 'assets/countries/ru/questions'


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def repair(root=ROOT):
    folder = root / 'assets/countries/ru/questions'
    repairs_path = root / 'tools/ru_content/question_image_repairs.json'
    repairs = json.loads(repairs_path.read_text())['images'] if repairs_path.exists() else []
    aliases = {}
    for category in ['ab', 'cd']:
        sources = json.loads((folder / f'questions_{category}.json').read_text())
        groups = defaultdict(list)
        coordinates = {}
        for ticket in sources['tickets']:
            for number, question in enumerate(ticket['questions'], 1):
                key = (ticket['number'], number)
                groups[question['id']].append((key, question))
                coordinates[key] = question
        aliases[category] = {}
        identity = {}
        for raw_id, variants in groups.items():
            for index, (key, question) in enumerate(variants):
                if index:
                    variant = f'{raw_id}:v:ticket_{key[0]}_{key[1]}'
                    identity[key] = variant
                    aliases[category][variant] = raw_id
        # Resolve topic entries from their full source explanation. An image is
        # deliberately not used: the old replacement matched by duplicated ID.
        topic_source = json.loads((folder / f'topics_{category}.json').read_text())
        topic_coordinates = {}
        for topic_index, topic in enumerate(topic_source['topics']):
            for question_index, question in enumerate(topic['questions']):
                candidates = groups[question['id']]
                if len(candidates) > 1:
                    exact = [(k, q) for k, q in candidates if q.get('comment') == question.get('comment')]
                    if len(exact) != 1:
                        raise ValueError(f'Ambiguous explanation: {category}/{topic_index}/{question_index}')
                    selected = exact[0][0]
                else:
                    selected = candidates[0][0]
                topic_coordinates[(topic_index, question_index)] = selected
        for language in ['', '_en', '_kk']:
            tickets_path = folder / f'questions_{category}{language}.json'
            topics_path = folder / f'topics_{category}{language}.json'
            tickets = json.loads(tickets_path.read_text())
            by_coordinate = {}
            for ticket in tickets['tickets']:
                for number, question in enumerate(ticket['questions'], 1):
                    key = (ticket['number'], number)
                    image_repair = next((r for r in repairs if r['category'] == category and (r['ticket'], r['number']) == key), None)
                    if image_repair:
                        if question['id'] != image_repair['sourceId']:
                            raise ValueError(f'Question changed; reverify illustration: {category}/{key}')
                        question['image'] = image_repair['newImage']
                    question['ticketNumber'] = ticket['number']
                    question['questionNumber'] = number
                    if key in identity:
                        question['variantId'] = identity[key]
                    else:
                        question.pop('variantId', None)
                    by_coordinate[key] = question
            topics = json.loads(topics_path.read_text())
            for topic_index, topic in enumerate(topics['topics']):
                for question_index, question in enumerate(topic['questions']):
                    key = topic_coordinates[(topic_index, question_index)]
                    canonical = by_coordinate[key]
                    if question['id'] != canonical['id']:
                        raise ValueError(f'Language order differs: {topics_path}:{key}')
                    # Source text and translated explanations must stay paired.
                    for field in ['question', 'answers', 'comment', 'pddPoints', 'image', 'ticketNumber', 'questionNumber']:
                        question[field] = deepcopy(canonical[field])
                    if key in identity:
                        question['variantId'] = identity[key]
                    else:
                        question.pop('variantId', None)
            write(tickets_path, tickets)
            write(topics_path, topics)
    write(folder / 'question_identity_migration.json', {'version': 1, 'aliases': aliases})
    dart = ["// Generated by tools/ru_content/repair_question_identity.py.", "import 'package:pdd_app/data/models/ticket_category.dart';", '', 'class QuestionIdentity {', '  QuestionIdentity._();', '', '  static const aliases = <TicketCategory, Map<String, String>>{']
    for category, entries in aliases.items():
        dart.append(f'    TicketCategory.{category}: {{')
        dart += [f"      '{variant}':\n          '{legacy}'," for variant, legacy in entries.items()]
        dart.append('    },')
    dart += ['  };', '', "  static String sourceId(String id) => id.split(':v:ticket_').first;", '}', '']
    (root / 'lib/data/models/question_identity.dart').write_text('\n'.join(dart))
    return {category: len(entries) for category, entries in aliases.items()}


if __name__ == '__main__':
    print(repair())
