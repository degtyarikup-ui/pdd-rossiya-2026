#!/usr/bin/env python3
"""Editor directions survive export without rewriting archived signal timing."""
import copy
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check
import engine_sync

source = json.loads((check.NET / 'ticket_19_13.json').read_text())
archived = engine_sync.engine_base('ticket_19_13')
with tempfile.TemporaryDirectory(prefix='actor-intent-', dir=check.ROOT / 'scratch') as tmp:
    root = Path(tmp)
    template = root / 'template'
    target = root / 'fixture'
    (template / 'parts').mkdir(parents=True)
    target.mkdir()
    (template / 'engine.json').write_text(json.dumps(archived))
    (target / 'engine.json').write_text(json.dumps(archived))
    (template / 'parts' / 'actor_0.glb').write_bytes(b'fixture')
    engine_sync.engine_base.cache_clear()
    try:
        with patch.object(engine_sync, 'SIT', root), patch.object(check, 'load', return_value=source):
            source['lights'] = []
            source['actors'][0]['asset'] = 'template/actor_0.glb'
            for way in ('left', 'right', 'straight', 'uturn', None):
                if way:
                    source['actors'][0]['way'] = way
                else:
                    source['actors'][0].pop('way', None)
                before = copy.deepcopy(source)
                engine_sync.sync('fixture')
                actor = json.loads((target / 'scene.json').read_text())['actors'][0]
                assert actor['way'] == way
                assert actor['signalPlan'] == archived['actors'][0]['signalPlan']
                assert source == before, 'export must preserve the authored network'
                print(f'PASS editor direction {way}: export and signal timing')
    finally:
        engine_sync.engine_base.cache_clear()
