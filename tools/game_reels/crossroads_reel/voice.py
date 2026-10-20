from pathlib import Path
import sys,json,concurrent.futures,warnings,subprocess,os,difflib,argparse
warnings.filterwarnings('ignore')
from common import ROOT, output_dir
sys.path.insert(0,str(ROOT))
from tools.signs_reel import audio,verify
D=output_dir()
parser=argparse.ArgumentParser(add_help=False)
parser.add_argument('--verify-model',type=Path,default=ROOT/'scratch/whisper/ggml-large-v3-turbo.bin')
options,_=parser.parse_known_args()
def normalized(text):
 return ' '.join('три' if x=='3' else x for x in verify.normalize(text))
def local_transcription(path,key):
 prefix=D/'audio'/f'{key}-verification'
 subprocess.run(['whisper-cli','-m',str(options.verify_model),'-f',str(path),'-l','ru','-oj','-of',str(prefix),'-nt','-t','4'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 data=json.loads(prefix.with_suffix('.json').read_text())
 return ' '.join(x['text'].strip() for x in data['transcription'])
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
 for attempt in range(3):
  audio.synthesize(txt,p,vc)
  x=audio.trim_silence(audio.read_wav(p),pad=.07)
  target=D/'audio'/f'{k}.wav'
  audio.write_wav(target,x)
  heard=verify.transcribe(target,vc,attempts=3)
  ratio=difflib.SequenceMatcher(None,normalized(txt),normalized(heard)).ratio()
  if ratio<.85 and options.verify_model.is_file():
   heard=local_transcription(target,k)
   ratio=difflib.SequenceMatcher(None,normalized(txt),normalized(heard)).ratio()
  if ratio>=.85:break
  print(f'REGENERATE {k}: mismatch {ratio:.2f}, heard {heard}',flush=True)
  p.unlink(missing_ok=True)
 else:
  raise RuntimeError(f'{k}: speech differs after three takes: {heard}')
 print(k,round(len(x)/24000,3),heard,flush=True)
 return dict(key=k,text=txt,path=f'audio/{k}.wav',duration=len(x)/24000,transcription=heard)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 data=list(pool.map(one,LINES))
(D/'voice.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
