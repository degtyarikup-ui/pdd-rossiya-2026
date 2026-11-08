"""Export the actual editor's short guide, preserving the entire gameplay route."""
import copy
import json
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import check
import engine_sync

folder = check.ROOT / 'scratch' / 'short-guide-check'
folder.mkdir(parents=True, exist_ok=True)
fixture = folder / 'fixture.json'
subprocess.run(['node', str(HERE / 'player_route_inspector_check.js'), str(fixture)], check=True)
scene = json.loads(fixture.read_text())
assert not [f for f in check.check_scene(scene) if f['level'] == 'error']
target = folder / 'situations' / scene['id']
target.mkdir(parents=True, exist_ok=True)
archived = engine_sync.engine_base('ticket_1_3')
exports = {}
for custom in (False, True):
    source = copy.deepcopy(scene)
    if not custom:
        source['routes'] = [r for r in source['routes'] if r['kind'] != 'guide']
    before = copy.deepcopy(source)
    with patch.object(check, 'load', return_value=source), \
            patch.object(engine_sync, 'SIT', target.parent), \
            patch.object(engine_sync, 'engine_base', return_value=archived):
        engine_sync.sync(source['id'])
    exports[str(custom)] = json.loads((target / 'scene.json').read_text())
    assert source == before, 'export preserves author data'
custom = exports['True']
assert custom['playerGuidePoints'] == next(r['points'] for r in scene['routes'] if r['kind'] == 'guide')
without_guide = copy.deepcopy(custom)
without_guide.pop('playerGuidePoints')
assert without_guide == exports['False'], 'only the visual hint changes, including full exits, actors and answers'
fixture.write_text(json.dumps({'source':scene, 'exported':custom}), encoding='utf-8')
print('Short player guide: real inspector, validation, independent export and unchanged gameplay PASS')
