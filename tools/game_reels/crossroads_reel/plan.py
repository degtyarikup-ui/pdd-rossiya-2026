from pathlib import Path
import json,sys,math
import numpy as np
from common import ROOT, output_dir
sys.path.insert(0,str(ROOT))
from tools.signs_reel import audio
D=output_dir()
v=json.loads((D/'voice.json').read_text())
by={x['key']:x for x in v}
episode=json.loads((D/'episode.json').read_text())
minimums=episode.get('motionMinimums',{'red':4.7,'blue':5.65,'yellow':4.15})
starts={'hook':.12}
if episode.get('directQuestion',False):
 starts['challenge']=math.ceil((starts['hook']+by['hook']['duration']+.17)*30)/30+episode.get('challengeFrameOffset',0)
else:
 starts['setup']=starts['hook']+by['hook']['duration']+.17
 starts['challenge']=starts['setup']+by['setup']['duration']+.14
count=starts['challenge']+by['challenge']['duration']+.18
phases=episode.get('answerPhases',['red','blue','yellow'])
cursor=count+3.0+.06
answer=cursor
for i,key in enumerate(phases):
 starts[key]=cursor
 cursor+=max(by[key]['duration']+(.3 if i==0 else .25),minimums.get(key,0))
starts['cta']=cursor
frames=math.ceil((starts['cta']+by['cta']['duration']+.8)*30)
cfg={**starts,'count':count,'duration':frames/30,'frames':frames}
if 'answerPhases' in episode:cfg['answer']=answer
for x in v:x['start']=starts[x['key']]
(D/'voice.json').write_text(json.dumps(v,ensure_ascii=False,indent=2))
(D/'timeline.json').write_text(json.dumps(cfg,ensure_ascii=False,indent=2))
tracks=[(x['start'],audio.read_wav(D/x['path'])) for x in v]
audio.write_wav(D/'audio/speech.wav',audio.mix(tracks,frames/30))
print(json.dumps(cfg,indent=2))
