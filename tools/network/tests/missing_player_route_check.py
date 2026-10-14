#!/usr/bin/env python3
"""Every intended player manoeuvre, including straight, needs a saved route."""
import copy
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check


source = check.load('ticket_3_13')
original = copy.deepcopy(source)
checks = 0
for maneuver in check.MANOEUVRES:
    fixture = copy.deepcopy(source)
    fixture['question']['maneuver'] = maneuver
    assert not any(f['code'] == 'no-manoeuvre' for f in check.check_scene(fixture)), maneuver
    checks += 1
    fixture['routes'] = [r for r in fixture['routes'] if r['id'] != f'manoeuvre_{maneuver}']
    before = copy.deepcopy(fixture)
    findings = [f for f in check.check_scene(fixture) if f['code'] == 'no-manoeuvre']
    assert len(findings) == 1 and findings[0]['level'] == 'error', maneuver
    assert findings[0]['ref'] == {'type': 'question'}, maneuver
    assert fixture == before, 'validation must preserve routes and the author review flag'
    checks += 3
assert source == original, 'all fixtures must leave the real source unchanged'
checks += 1

reviewed_missing = []
for path in sorted(check.NET.glob('*.json')):
    authored = json.loads(path.read_text(encoding='utf-8'))
    if not authored.get('reviewed'):
        continue
    maneuver = (authored.get('question') or {}).get('maneuver')
    if maneuver not in check.MANOEUVRES:
        continue
    missing = not any(r.get('id') == f'manoeuvre_{maneuver}' for r in authored.get('routes', []))
    before = copy.deepcopy(authored)
    findings = [f for f in check.check_scene(authored) if f['code'] == 'no-manoeuvre']
    assert bool(findings) == missing, path.stem
    assert authored == before, path.stem
    checks += 2
    if missing:
        reviewed_missing.append(path.stem)

print(f'Missing player route: {checks} checks passed; reviewed scenes needing a route: {reviewed_missing}')
