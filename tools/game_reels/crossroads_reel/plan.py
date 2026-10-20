from pathlib import Path
import json,sys,math
import numpy as np
from common import ROOT, output_dir
sys.path.insert(0,str(ROOT))
from tools.signs_reel import audio
D=output_dir()
v=json.loads((D/'voice.json').read_text())
by={x['key']:x for x in v}
starts={'hook':.12}
starts['setup']=starts['hook']+by['hook']['duration']+.17
starts['challenge']=starts['setup']+by['setup']['duration']+.14
count=starts['challenge']+by['challenge']['duration']+.18
starts['red']=count+3.0+.06
starts['blue']=starts['red']+max(by['red']['duration']+.3,4.7)
starts['yellow']=starts['blue']+max(by['blue']['duration']+.25,5.65)
starts['cta']=starts['yellow']+max(by['yellow']['duration']+.25,4.15)
frames=math.ceil((starts['cta']+by['cta']['duration']+.8)*30)
cfg={**starts,'count':count,'duration':frames/30,'frames':frames}
for x in v:x['start']=starts[x['key']]
(D/'voice.json').write_text(json.dumps(v,ensure_ascii=False,indent=2))
(D/'timeline.json').write_text(json.dumps(cfg,ensure_ascii=False,indent=2))
tracks=[(x['start'],audio.read_wav(D/x['path'])) for x in v]
audio.write_wav(D/'audio/speech.wav',audio.mix(tracks,frames/30))
print(json.dumps(cfg,indent=2))
