"""Answer line styles survive layout rebuild and export without rewriting author files."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import check
import engine_sync

source = check.load('ticket_3_2')
source['actors'] = []
source['lights'] = []
source['routes'] = [r for r in source['routes'] if r['kind'] != 'choice'] + [
    {'id':'choice_А','kind':'choice','label':'А','points':[[0,-20],[-7,-20]],'labelPosition':[-7,-20],'arrowhead':False},
    {'id':'choice_Б','kind':'choice','label':'Б','points':[[0,-17],[-7,-17]],'labelPosition':[-7,-17]},
    {'id':'choice_В','kind':'choice','label':'В','points':[[0,-14],[-7,-14]],'labelPosition':[-7,-14],'arrowhead':True},
]
layout = HERE.parent / 'editor/layout.js'
rebuilt = json.loads(subprocess.check_output(['node','-e',
    "const L=require(process.argv[1]);const fs=require('fs');const s=JSON.parse(fs.readFileSync(0,'utf8'));if(s.layout)L.apply(s);process.stdout.write(JSON.stringify(s));",str(layout)],input=json.dumps(source).encode()))
assert [r for r in rebuilt['routes'] if r['kind']=='choice'] == [r for r in source['routes'] if r['kind']=='choice']
base = engine_sync.engine_base('ticket_3_2')
with tempfile.TemporaryDirectory(prefix='choice-lines-',dir=check.ROOT/'scratch') as tmp:
    sit = Path(tmp)
    (sit/'fixture').mkdir()
    before = copy.deepcopy(rebuilt)
    with patch.object(check,'load',return_value=rebuilt), patch.object(engine_sync,'SIT',sit), patch.object(engine_sync,'engine_base',return_value=base):
        engine_sync.sync('fixture')
    exported = json.loads((sit/'fixture/scene.json').read_text())
    assert [t['arrowhead'] for t in exported['trajectories']] == [False,True,True]
    assert [t['points'] for t in exported['trajectories']] == [r['points'] for r in source['routes'] if r['kind']=='choice']
    assert [l['letter'] for l in exported['labels']] == ['А','Б','В']
    assert rebuilt == before
print('Choice lines: source/save/layout/export/labels/legacy styles PASS')
