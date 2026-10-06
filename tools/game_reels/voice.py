"""Voice and timing for the RU 3D reel pilot; exact question/options from content."""
import json, math, subprocess, argparse, os
from pathlib import Path
from google import genai
from google.oauth2.credentials import Credentials
adc=Path(os.environ.get('GOOGLE_APPLICATION_CREDENTIALS',str(Path.home()/'.config/gcloud/application_default_credentials.json')))
project=json.loads(adc.read_text()).get('quota_project_id') if adc.exists() else None
project=project or subprocess.check_output(["gcloud","config","get-value","project"],stderr=subprocess.DEVNULL,text=True).strip()
original_client=genai.Client
def authenticated_client(**kwargs):
 token=subprocess.check_output(["gcloud","auth","print-access-token"],stderr=subprocess.DEVNULL,text=True).strip()
 return original_client(**kwargs,credentials=Credentials(token=token))
genai.Client=authenticated_client
from pathlib import Path
from types import SimpleNamespace
import numpy as np
from tools.signs_reel import audio, verify, config as C
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument('episode',type=Path);args=parser.parse_args()
episode=json.loads(args.episode.read_text())
OUT=ROOT/'output/game-reels'/episode['id'];OUT.mkdir(parents=True,exist_ok=True)
q=json.loads((ROOT/f"assets/countries/{episode['country']}/questions/questions_ab.json").read_text())['tickets'][episode['ticket']-1]['questions'][episode['questionNumber']-1]
vc=audio.VoiceConfig(project=project,voice='Algenib',style='Говори по-русски быстро, энергично и естественно, как молодой ведущий короткого видео. Короткие паузы. Без крика, без растягивания слов, без театральности. Произнеси только заданный текст.')
texts=[('question',q['question']),('choices',episode['choicesSpeech']),('answer',episode['answerSpeech']),('cta','Ссылка на игру — в описании профиля.')]
lines=[]
for key,text in texts:
 path=OUT/f'{key}-{audio.tts_cache_key(text,vc)}.wav'
 audio.synthesize(text,path,vc)
 data=audio.trim_silence(audio.read_wav(path));audio.write_wav(path,data)
 lines.append(SimpleNamespace(key=key,text=text,path=path,data=data,seconds=len(data)/C.SR))
 print(key,round(len(data)/C.SR,2),flush=True)
bad,skipped=verify.check_voice(lines,vc)
if bad or skipped: raise RuntimeError(str((bad,skipped)))
t=0;clips=[];tracks=[]
for i,v in enumerate(lines):
 if v.key=='answer':
  think=t;t+=2.2
 start=t; dur=len(v.data)/C.SR
 clips.append(dict(key=v.key,text=v.text,start=start,end=start+dur))
 tracks.append((start,v.data));t+=dur+.15
 if v.key=='answer':t=max(t+.55,start+episode['motion']['playerDelay']+episode['motion']['playerDuration']+.25)
n=math.ceil((t+.35)*30);total=n/30
tracks.extend([(think,audio.tick_track(2.2)),(next(c['start'] for c in clips if c['key']=='answer'),audio.reveal_chime())])
audio.write_wav(OUT/'sound.wav',audio.mix(tracks,total))
meta=dict(episode=episode,question=q,clips=clips,think=think,reveal=next(c['start'] for c in clips if c['key']=='answer'),cta=next(c['start'] for c in clips if c['key']=='cta'),frames=n,fps=30,duration=total,voiceVerified=True)
(OUT/'timeline.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2))
print('duration',total,flush=True)
