"""App catalogue, exported vectors and actual editor server must expose the same sign numbers."""
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import server

root = HERE.parents[2]
source = json.loads((root / 'assets/countries/ru/questions/signs.json').read_text())
signs = {code: sign for group in source.values() for code, sign in group.items()}
subprocess.run([sys.executable, str(root / 'tools/godot_export/export_sign_catalog.py'), '--check'], check=True)
catalog = server.Handler.catalog(server.Handler.__new__(server.Handler))
assert set(catalog['signs']) == set(signs)
assert set(catalog['signInfo']) == set(signs)
for code, sign in signs.items():
    assert catalog['signInfo'][code]['title'] == sign['title']
    rules = [(pattern.match(f'sign/{code}.svg'), resolve) for pattern, resolve in server.ASSET_RULES]
    matches = [(match, resolve) for match, resolve in rules if match]
    assert len(matches) == 1 and matches[0][1](matches[0][0]).is_file(), code
assert {'3.28','8.2.2','8.2.3','8.2.4'} <= set(catalog['signs'])
print(f'Sign catalogue API: {len(signs)} canonical names, safe asset URLs and vectors PASS')
