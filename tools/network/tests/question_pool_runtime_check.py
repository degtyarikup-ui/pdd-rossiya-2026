#!/usr/bin/env python3
"""Load new blank questions in the actual Godot loader, in an isolated scratch project."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build
import check
import engine_sync
import question_pool

root = check.ROOT
game = root / 'game_godot'
with tempfile.TemporaryDirectory(prefix='question-pool-godot-', dir=root / 'scratch') as temporary:
    project = Path(temporary)
    for entry in game.iterdir():
        if entry.name not in ('network', 'situations', '.godot'):
            (project / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
    cache = project / '.godot'
    cache.mkdir()
    for name in ('global_script_class_cache.cfg', 'uid_cache.bin'):
        if (game / '.godot' / name).exists(): shutil.copy2(game / '.godot' / name, cache / name)
    (cache / 'imported').symlink_to(game / '.godot' / 'imported', target_is_directory=True)
    net, sit = project / 'network', project / 'situations'
    (net / 'build').mkdir(parents=True)
    sit.mkdir()
    pool = question_pool.QuestionPool()
    records = pool.list()['questions']
    chosen = [next(q for q in records if q['category'] == 'ab' and not q['image']),
              next(q for q in records if q['category'] == 'ab' and q['image'])]
    engine_sync.engine_base.cache_clear()
    try:
        with patch.object(check, 'NET', net), patch.object(engine_sync, 'SIT', sit):
            for record in chosen:
                scene = pool.template(record['id'])
                assert not check.check_scene(scene)
                sid = record['id']
                target = sit / sid
                target.mkdir()
                (net / f'{sid}.json').write_text(json.dumps(scene))
                (net / 'build' / f'{sid}.json').write_text(json.dumps(build.build(scene)))
                (target / 'engine.json').write_text(json.dumps(question_pool.engine_template(scene)))
                engine_sync.sync(sid)
                assert not (target / 'scene.glb').exists()
    finally:
        engine_sync.engine_base.cache_clear()
    (project / 'pool-fixtures.json').write_text(json.dumps(chosen))
    result = subprocess.run(['godot','--headless','--path',str(project),'--script','res://tests/question_pool_runtime_check.gd','--',
        '--question-images-dir='+str(root / 'assets/countries/ru/images/questions_ab'),
        '--question-images-dir='+str(root / 'assets/countries/ru/images/questions_cd')], cwd=root, timeout=90)
    if result.returncode: raise SystemExit(result.returncode)
print('Procedural question templates: actual isolated Godot load/prepare/render geometry PASS')
