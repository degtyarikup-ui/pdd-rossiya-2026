"""Mix a quiet street sound bed, normal subtitles and an exact-duration master."""
from pathlib import Path
import json, subprocess, sys, math, hashlib
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from tools.signs_reel import audio
OUT=ROOT/'output/blender_youtube/pilot_001'
T=json.loads((OUT/'timeline.json').read_text());SR=24000;duration=T['duration']
n=round(SR*duration);t=np.arange(n,dtype=np.float32)/SR
rng=np.random.default_rng(3914)
noise=rng.normal(0,1,n).astype(np.float32)
# Subtle outdoor air, never a music bed.
air=np.convolve(noise,np.ones(75,dtype=np.float32)/75,mode='same')*.016
mix=audio.read_wav(OUT/'narration.wav')
mix+=air
def engine(start,end,gain):
    u=np.clip((t-start)/(end-start),0,1)
    env=np.where((t>=start)&(t<end),np.maximum(0,np.sin(np.pi*u))**.6,0)
    frequency=43+15*np.sin(np.pi*u)
    phase=np.cumsum(frequency)*2*np.pi/SR
    return (np.sin(phase)+.28*np.sin(2*phase)+.12*np.sin(4*phase))*env*gain+noise*env*gain*.1
mix+=engine(0,18,.013)+engine(53,62,.014)+engine(62,82,.013)
# Indicator is attached to the red car's actual manoeuvre; no quiz countdown.
for at in np.arange(12,70.8,.8):
    k=round(at*SR);q=np.arange(round(.045*SR))/SR
    click=np.sin(2*np.pi*1800*q)*np.exp(-q*110)*.018
    mix[k:k+len(click)]+=click
audio.write_wav(OUT/'mix.wav',mix)
subprocess.run(['ffmpeg','-y','-v','warning','-i',str(OUT/'mix.wav'),'-af','highpass=f=65,loudnorm=I=-16:TP=-1.5:LRA=9','-ar','48000',str(OUT/'master_audio.wav')],check=True)
def stamp(s):
    ms=round(s*1000);h,ms=divmod(ms,3600000);m,ms=divmod(ms,60000);sec,ms=divmod(ms,1000)
    return f'{h:02}:{m:02}:{sec:02},{ms:03}'
subtitles=[]
for clip in T['clips']:
    # Sentence-level subtitles retain a calm film presentation.
    import re
    phrases=re.findall(r'[^.!?]+[.!?]?',clip['text'])
    total=sum(len(x) for x in phrases);cursor=clip['start']
    for phrase in phrases:
        end=cursor+clip['duration']*len(phrase)/total
        subtitles.append(f'{len(subtitles)+1}\n{stamp(cursor)} --> {stamp(end)}\n{phrase.strip()}\n')
        cursor=end
(OUT/'pdd_youtube_001.srt').write_text('\n'.join(subtitles))
if '--audio-only' in sys.argv:sys.exit(0)
frames=sorted((OUT/'frames').glob('frame_*.png'))
assert len(frames)==T['frames'],(len(frames),T['frames'])
target=OUT/'pdd_youtube_001.mp4'
subprocess.run(['ffmpeg','-y','-v','warning','-framerate',str(T['fps']),'-start_number','1','-i',str(OUT/'frames/frame_%04d.png'),'-i',str(OUT/'master_audio.wav'),'-i',str(OUT/'pdd_youtube_001.srt'),'-map','0:v:0','-map','1:a:0','-map','2:0','-c:v','libx264','-preset','slow','-crf','17','-pix_fmt','yuv420p','-c:a','aac','-b:a','256k','-c:s','mov_text','-metadata:s:s:0','language=rus','-t',str(duration),'-movflags','+faststart',str(target)],check=True)
subprocess.run(['ffmpeg','-v','error','-i',str(target),'-f','null','-'],check=True)
probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(target)]))
v=next(s for s in probe['streams'] if s['codec_type']=='video')
assert (v['width'],v['height'],int(v['nb_frames']))==(1920,1080,T['frames'])
assert abs(float(probe['format']['duration'])-duration)<1/T['fps']
(OUT/'delivery.json').write_text(json.dumps(dict(sha256=hashlib.sha256(target.read_bytes()).hexdigest(),probe=probe),ensure_ascii=False,indent=2))
print(target)
