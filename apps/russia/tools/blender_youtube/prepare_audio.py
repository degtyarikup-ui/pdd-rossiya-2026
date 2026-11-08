"""Record verified narration; derive the edit from actual speech durations."""
from pathlib import Path
import json, sys, os, subprocess, warnings, difflib, math
warnings.filterwarnings('ignore')
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.signs_reel import audio, verify
from google import genai
from google.oauth2.credentials import Credentials
OUT = ROOT/'output/blender_youtube/pilot_001'
OUT.mkdir(parents=True, exist_ok=True)
EP = json.loads((Path(__file__).parent/'episode.json').read_text())
if not (Path.home()/'.config/gcloud/application_default_credentials.json').exists():
    os.environ['GOOGLE_CLOUD_PROJECT'] = subprocess.check_output(['gcloud','config','get-value','project'],stderr=subprocess.DEVNULL,text=True).strip()
    token = subprocess.check_output(['gcloud','auth','print-access-token'],stderr=subprocess.DEVNULL,text=True).strip()
    original = genai.Client
    def client(*args, **kwargs):
        kwargs['credentials'] = Credentials(token)
        return original(*args, **kwargs)
    genai.Client = client
ref=json.loads((ROOT/'tools/game_reels/crossroads_reel/reference/episode.json').read_text())['voice']
vc=audio.VoiceConfig(voice=ref['name'],model=ref['model'],style=ref['style']+' Темп спокойный, с понятными смысловыми паузами, для подробного горизонтального видео.')
clips=[]
def normalized(text):
    return verify.normalize(text.replace('13.11', 'тринадцать точка одиннадцать'))
for line in EP['lines']:
    key,text=line['key'],line['text']
    cache=OUT/'audio'/f'{key}_{audio.tts_cache_key(text,vc)}.wav'
    target=OUT/'audio'/f'{key}.wav'
    verified=target.with_suffix('.json')
    for attempt in range(3):
        audio.synthesize(text,cache,vc)
        samples=audio.trim_silence(audio.read_wav(cache),pad=.07)
        audio.write_wav(target,samples)
        data=json.loads(verified.read_text()) if verified.exists() else {}
        heard=data.get('transcription') if data.get('cache')==cache.name else verify.transcribe(target,vc)
        ratio=difflib.SequenceMatcher(None,normalized(text),normalized(heard)).ratio()
        if ratio>=.95:
            verified.write_text(json.dumps(dict(cache=cache.name,transcription=heard,similarity=ratio),ensure_ascii=False,indent=2));break
        cache.unlink();verified.unlink(missing_ok=True)
    else: raise RuntimeError(f'Speech mismatch: {key}: {heard}')
    clips.append(dict(line,path=str(target.relative_to(OUT)),duration=len(samples)/24000,transcription=heard))
    print(key,round(len(samples)/24000,2),heard,flush=True)
fps=EP['fps']; cursor=0
for line in clips:
    if line['start'] < cursor: raise RuntimeError('Narration overlaps next directed shot; revise edit')
    line['end']=line['start']+line['duration']
    cursor=line['end']+.45
total=max(82,math.ceil((cursor+1.5)*fps)/fps)
timeline=dict(fps=fps,duration=total,frames=round(total*fps),clips=clips)
(OUT/'timeline.json').write_text(json.dumps(timeline,ensure_ascii=False,indent=2))
mix=audio.mix([(c['start'],audio.read_wav(OUT/c['path'])) for c in clips],total)
audio.write_wav(OUT/'narration.wav',mix)
print('TIMELINE',total,'seconds',timeline['frames'],'frames',flush=True)
