"""Exercise editor read/preview/save/reload on disposable mini-game data."""
import copy
from http.client import HTTPConnection
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server
import build
import check
import engine_sync

class RegulatorEditorTest(unittest.TestCase):
    def test_save_rebuild_reload_and_exclusion(self):
        original = check.load('mini_regulator')
        self.assertFalse(any(f['level']=='error' for f in check.check_scene(original)))
        with tempfile.TemporaryDirectory(prefix='regulator-editor-',dir=check.ROOT/'scratch') as tmp:
            net=Path(tmp)
            (net/'mini_regulator.json').write_text(json.dumps(original))
            with patch.object(server,'NET',net), patch.object(server,'HISTORY',net/'history'), patch.object(check,'NET',net), patch.object(build,'NET',net), patch.object(build,'BUILD',net/'build'):
                http=server.Server(('127.0.0.1',0),server.Handler)
                thread=threading.Thread(target=http.serve_forever,daemon=True);thread.start()
                def request(method,path,body=None):
                    c=HTTPConnection('127.0.0.1',http.server_port,timeout=15)
                    c.request(method,path,json.dumps(body) if body is not None else None,{'Content-Type':'application/json'})
                    response=c.getresponse();data=json.loads(response.read());status=response.status;c.close();return status,data
                try:
                    status,response=request('GET','/api/scene/mini_regulator');self.assertEqual(status,200)
                    changed=copy.deepcopy(response['scene'])
                    changed['officers'][0]['pos']=[1.5,2]
                    changed['decor'][0]['pos'][0]+=3
                    changed['markings'][0]['length']=3.2
                    status,preview=request('POST','/api/preview/mini_regulator',changed);self.assertEqual(status,200)
                    self.assertFalse(any(f['level']=='error' for f in preview['findings']))
                    status,saved=request('POST','/api/scene/mini_regulator',changed);self.assertEqual(status,200)
                    self.assertEqual(saved['synced']['miniGame'],'regulator')
                    status,loaded=request('GET','/api/scene/mini_regulator');self.assertEqual(status,200)
                    self.assertEqual(loaded['scene']['officers'][0]['pos'],[1.5,2])
                    self.assertEqual(loaded['scene']['decor'][0]['pos'],changed['decor'][0]['pos'])
                    self.assertEqual(json.loads((net/'build/mini_regulator.json').read_text()),build.build(changed))
                    self.assertTrue(list((net/'history/mini_regulator').glob('*.json')))
                    self.assertFalse(engine_sync.playable('mini_regulator'))
                    self.assertEqual(request('POST','/api/game/include/mini_regulator',{'playable':True})[0],400)
                    invalid=copy.deepcopy(changed);invalid['officers']=[]
                    self.assertEqual(request('POST','/api/scene/mini_regulator',invalid)[0],400)
                    self.assertEqual(check.load('mini_regulator')['officers'],changed['officers'],'invalid save does not overwrite source')
                finally:
                    http.shutdown();http.server_close();thread.join()

if __name__=='__main__':unittest.main()
