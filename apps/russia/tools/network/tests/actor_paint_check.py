#!/usr/bin/env python3
"""Saved editor paints survive export; clearing restores the archived model colour."""
import copy
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check
import engine_sync

source = json.loads((check.NET / 'ticket_32_15.json').read_text())
archived = engine_sync.engine_base('ticket_32_15')
with tempfile.TemporaryDirectory(prefix='actor-paint-', dir=check.ROOT / 'scratch') as tmp:
    root = Path(tmp)
    template = root / 'template'
    target = root / 'fixture'
    (template / 'parts').mkdir(parents=True)
    target.mkdir()
    (template / 'engine.json').write_text(json.dumps(archived))
    (target / 'engine.json').write_text(json.dumps(archived))
    for i in range(len(archived['actors'])):
        (template / 'parts' / f'actor_{i}.glb').write_bytes(b'fixture')
    engine_sync.engine_base.cache_clear()
    try:
        with patch.object(engine_sync, 'SIT', root), patch.object(check, 'load', return_value=source):
            source['lights'] = []
            for i, actor in enumerate(source['actors']):
                actor['asset'] = f'template/actor_{i}.glb'
            for paint in ('#C0392B', '#317ED4', '#F2F3F5', None):
                for actor in source['actors']:
                    if paint:
                        actor['paint'] = paint
                    else:
                        actor.pop('paint', None)
                before = copy.deepcopy(source)
                engine_sync.sync('fixture')
                exported = json.loads((target / 'scene.json').read_text())['actors']
                for i, actor in enumerate(exported):
                    assert actor['paint'] == paint
                    assert actor['config']['color'] == archived['actors'][i]['config']['color']
                assert source == before, 'export must preserve author data'
                print(f'PASS editor paint {paint}: export and original model colours')
    finally:
        engine_sync.engine_base.cache_clear()
