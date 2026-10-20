from pathlib import Path
import sys,json,concurrent.futures,warnings,subprocess,os,difflib
warnings.filterwarnings('ignore')
from common import ROOT, output_dir
sys.path.insert(0,str(ROOT))
from tools.signs_reel import audio,verify
D=output_dir()
EPISODE=json.loads((D/'episode.json').read_text())
STYLE=EPISODE['voice']['style']
LINES=[(x['key'],x['text']) for x in EPISODE['lines']]
# This machine uses an active gcloud account rather than an ADC file.
from google import genai
from google.oauth2.credentials import Credentials
if not (Path.home()/'.config/gcloud/application_default_credentials.json').exists():
 project=subprocess.check_output(['gcloud','config','get-value','project'],stderr=subprocess.DEVNULL,text=True).strip()
 if not project or project=='(unset)': raise RuntimeError('No active Google Cloud project')
 os.environ['GOOGLE_CLOUD_PROJECT']=project
 token=subprocess.check_output(['gcloud','auth','print-access-token'],stderr=subprocess.DEVNULL,text=True).strip()
 original_client=genai.Client
 def client_with_active_account(*args,**kwargs):
  kwargs['credentials']=Credentials(token)
  return original_client(*args,**kwargs)
 genai.Client=client_with_active_account
vc=audio.VoiceConfig(voice=EPISODE['voice']['name'],model=EPISODE['voice']['model'],style=STYLE)
def one(pair):
 k,txt=pair
 p=D/'audio'/f'{k}_{audio.tts_cache_key(txt,vc)}.wav'
 audio.synthesize(txt,p,vc)
 x=audio.trim_silence(audio.read_wav(p),pad=.07)
 target=D/'audio'/f'{k}.wav'
 audio.write_wav(target,x)
 heard=verify.transcribe(target,vc,attempts=3)
 ratio=difflib.SequenceMatcher(None,' '.join(verify.normalize(txt)),' '.join(verify.normalize(heard))).ratio()
 if ratio<.85:
  raise RuntimeError(f'{k}: speech differs from script ({ratio:.2f}): {heard}. Remove this cached clip and regenerate.')
 print(k,round(len(x)/24000,3),heard,flush=True)
 return dict(key=k,text=txt,path=f'audio/{k}.wav',duration=len(x)/24000,transcription=heard)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 data=list(pool.map(one,LINES))
(D/'voice.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
