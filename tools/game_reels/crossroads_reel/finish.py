from pathlib import Path
import sys,json,re,difflib,subprocess,wave,math,argparse
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from common import ROOT, output_dir
D=output_dir()
sys.path.insert(0,str(ROOT))
from tools.signs_reel import audio
C=json.loads((D/'timeline.json').read_text())
V=json.loads((D/'voice.json').read_text())
W,H,FPS=1080,1920,30
FONT=ROOT/'game_godot/fonts/Onest-ExtraBold.ttf'
MEDIUM=ROOT/'game_godot/fonts/Onest-Medium.ttf'
COLORS={'красн':'#ff7969','син':'#65bcff','жёлт':'#ffdb58','желт':'#ffdb58'}
EPISODE=json.loads((D/'episode.json').read_text())
GROUPS=EPISODE['captionGroups']
def norm(s):
 s=re.sub(r'[^а-яА-ЯёЁ0-9]','',s).lower().replace('ё','е')
 return 'три' if s=='3' else s

def subtitles():
 out=[];report=[]
 for line in V:
  a=line['start'];b=a+line['duration']
  local=json.loads((D/'audio'/f"{line['key']}-align.json").read_text())['transcription']
  raw=[{**s,'offsets':{'from':s['offsets']['from']+a*1000,'to':s['offsets']['to']+a*1000}} for s in local]
  words=[{'text':s['text'].strip(),'start':max(a,s['offsets']['from']/1000),'end':min(b,s['offsets']['to']/1000)} for s in raw if norm(s['text']) and s['offsets']['to']/1000>a+.015 and s['offsets']['from']/1000<b-.015]
  got=[norm(x['text']) for x in words]
  want=[norm(w) for group in GROUPS[line['key']] for w in group.split() if norm(w)]
  matcher=difflib.SequenceMatcher(None,want,got)
  mapping={block.a+j:block.b+j for block in matcher.get_matching_blocks() for j in range(block.size)}
  ratio=difflib.SequenceMatcher(None,' '.join(want),' '.join(got)).ratio()
  if ratio<.85:raise RuntimeError((line['key'],want,got,ratio))
  # Whisper can change gender endings without changing word positions.
  # Only use positional alignment after the whole phrase passes similarity.
  if len(want)==len(got):mapping=dict(enumerate(range(len(want))))
  report.append(dict(key=line['key'],text=line['text'],heard=' '.join(x['text'] for x in words),ratio=ratio))
  offset=0
  for group in GROUPS[line['key']]:
   n=len([w for w in group.split() if norm(w)])
   indices=[mapping[i] for i in range(offset,offset+n) if i in mapping]
   if not indices:raise RuntimeError(('unmapped caption',group))
   start=words[min(indices)]['start'];end=words[max(indices)]['end']
   if end-start<.18:end=min(b,start+.35)
   out.append(dict(text=group,start=start,end=end,key=line['key']))
   offset+=n
 # Extend readable holds through small pauses, never into the answer countdown.
 for i,s in enumerate(out):
  cap=next(x['start']+x['duration']+.08 for x in V if x['key']==s['key'])
  nxt=out[i+1]['start']-.025 if i+1<len(out) else cap
  s['end']=min(max(s['end'],s['start']+.35)+.08,nxt,cap)
 (D/'subtitles.json').write_text(json.dumps(out,ensure_ascii=False,indent=2))
 (D/'voice-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
 def stamp(t):
  ms=round(t*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
 (D/'reel.srt').write_text('\n\n'.join(f'{i+1}\n{stamp(s["start"])} --> {stamp(s["end"])}\n{s["text"]}' for i,s in enumerate(out))+'\n')
 print('CAPTIONS_OK',len(out),min(x['ratio'] for x in report),flush=True)
 return out

def mix_audio():
 # Process speech independently so effects never drive speech compression.
 subprocess.run(['ffmpeg','-v','error','-y','-i',str(D/'audio/speech.wav'),'-af','highpass=f=85,acompressor=threshold=0.13:ratio=1.8:attack=12:release=100,loudnorm=I=-15:TP=-2:LRA=7','-ar','24000','-ac','1',str(D/'audio/voice-master.wav')],check=True)
 sr=24000;n=round(C['duration']*sr);t=np.arange(n)/sr;rng=np.random.default_rng(812)
 voice=audio.read_wav(D/'audio/voice-master.wav')
 mix=np.zeros((n,2),np.float32);mix[:min(n,len(voice))]=voice[:n,None]*.92
 def add(at,x,pan=0):
  start=round(at*sr);end=min(n,start+len(x))
  if end<=start:return
  mono=x[:end-start];mix[start:end,0]+=mono*math.sqrt((1-pan)/2);mix[start:end,1]+=mono*math.sqrt((1+pan)/2)
 # Very quiet outdoor air, band limited, without synthetic music.
 noise=rng.standard_normal(n)
 freq=np.fft.rfftfreq(n,1/sr);spec=np.fft.rfft(noise)
 bed=np.fft.irfft(spec*np.exp(-(freq/1200)**2)*(1-np.exp(-(freq/110)**2)),n)
 bed=bed/max(np.std(bed),1e-9)*.0015
 mix+=bed[:,None]
 for key,pan in EPISODE.get('audio',{}).get('enginePans',{'red':-.25,'blue':.2,'yellow':-.1}).items():
  go=C[key]+EPISODE.get('motionDelays',dict(red=.45,blue=.35,yellow=.5))[key]
  length=min(C['duration']-go,5.7);tt=np.arange(round(length*sr))/sr
  speed=np.minimum(8.5,tt*3.6);rpm=63+speed*14
  phase=2*np.pi*np.cumsum(rpm)/sr
  engine=(np.sin(phase)+.32*np.sin(phase*2.03)+.17*np.sin(phase*3.02))
  if EPISODE.get("audio",{}).get("engineKinds",{}).get(key)=="tram":
   speed=np.minimum(5.0,tt*1.5)
   phase=2*np.pi*np.cumsum(110+speed*9)/sr
   engine=.65*np.sin(phase)+.18*np.sin(phase*2)+.10*rng.standard_normal(len(tt))
  amp=(1-np.exp(-tt*4))*np.exp(-np.maximum(tt-2.5,0)*.65)*.018
  add(go,engine*amp,pan)
 # Three tactile wooden ticks. The final answer has a soft, short two-note cue.
 for i in range(3):
  tt=np.arange(round(.11*sr))/sr
  click=(np.sin(2*np.pi*(1050+i*90)*tt)*np.exp(-tt/0.012)+rng.standard_normal(len(tt))*.08*np.exp(-tt/.008))*.14
  add(C['count']+i,click)
 tt=np.arange(round(.3*sr))/sr
 chime=(np.sin(2*np.pi*523.25*tt)+.45*np.sin(2*np.pi*783.99*tt))*np.exp(-tt/.075)*.07
 add(C.get('answer',C.get('red',0)),chime)
 # Direction-indicator foley under the waiting shot, ending before the turn.
 for at in (np.arange(2.4,7.1,.68) if EPISODE.get('audio',{}).get('indicator',True) else []):
  tt=np.arange(round(.04*sr))/sr
  click=rng.standard_normal(len(tt))*np.exp(-tt/.006)*.022
  add(float(at),click,EPISODE.get('audio',{}).get('indicatorPan',.2))
 # Tiny cut accents, kept far below the voice.
 for at in [*EPISODE.get('audio',{}).get('setupCutAccents',[2,3.25,4.45,5.7,7.3]),*[C[k] for k in EPISODE.get('answerPhases',['red','blue','yellow'])]]:
  tt=np.arange(round(.16*sr))/sr
  w=rng.standard_normal(len(tt));w=np.convolve(w,np.ones(5)/5,'same')
  add(max(0,at-.07),w*np.sin(np.pi*tt/.16)**2*.017)
 fade=np.minimum(t/.08,1)*np.minimum((C['duration']-t)/.3,1)
 mix*=fade[:,None]
 with wave.open(str(D/'audio/mix.wav'),'wb') as f:
  f.setnchannels(2);f.setsampwidth(2);f.setframerate(sr)
  f.writeframes((np.clip(mix,-.96,.96)*32767).astype('<i2').tobytes())
 subprocess.run(['ffmpeg','-v','error','-y','-i',str(D/'audio/mix.wav'),'-af','loudnorm=I=-14:TP=-1.5:LRA=7','-ar','48000','-c:a','pcm_s24le',str(D/'audio/master.wav')],check=True)
 print('AUDIO_OK',C['duration'],flush=True)

def text_center(layer,text,y,size=76,accent=True,alpha=255):
 font=ImageFont.truetype(str(FONT),size)
 words=text.split(' ');draw=ImageDraw.Draw(layer)
 widths=[draw.textlength(w+' ',font=font) for w in words]
 total=sum(widths)-draw.textlength(' ',font=font)
 if total>900 and size<=54:
  raise ValueError(f"Split this caption into shorter phrases: {text}")
 if total>900:
  return text_center(layer,text,y,max(54,int(size*890/total)),accent,alpha)
 x=(W-total)/2-20
 for w,width in zip(words,widths):
  color='#ffffff'
  if accent:
   for prefix,c in COLORS.items():
    if norm(w).startswith(norm(prefix)):color=c
  rgb=tuple(int(color[i:i+2],16) for i in (1,3,5))
  draw.text((round(x),y),w,font=font,fill=(*rgb,alpha),stroke_width=5,stroke_fill=(14,23,33,round(alpha*.88)),anchor='ls')
  x+=width

def overlay(t,captions):
 layer=Image.new('RGBA',(W,H));d=ImageDraw.Draw(layer)
 # Fixed safe area: right-side Instagram controls and bottom caption stay free.
 for s in captions:
  if s['start']<=t<s['end']:
   dt=t-s['start'];fade=min(1,dt/.065,(s['end']-t)/.045)
   y=1450
   size=76
   text_center(layer,s['text'],y,size,True,round(255*max(0,fade)))
   break
 if C['count']<=t<C['count']+3:
  u=t-C['count'];remaining=3-int(u)
  x,y,r=520,290,64
  d.ellipse((x-r,y-r,x+r,y+r),fill=(15,27,41,160),outline=(255,255,255,70),width=4)
  d.arc((x-r,y-r,x+r,y+r),-90,-90+360*(1-u/3),fill='#ffda55',width=7)
  f=ImageFont.truetype(str(FONT),74)
  d.text((x,y+1),str(remaining),font=f,fill='white',anchor='mm')
 if t>=C['cta']:
  # Numbered colour chips recap only the permitted participants.
  chips=EPISODE.get('answerChips',[{'car':'red','number':1},{'car':'blue','number':2},{'car':'yellow','number':3}])
  palette={'red':'#ed4621','blue':'#136ce8','yellow':'#f3bd28'}
  for i,chip in enumerate(chips):
   col=palette[chip['car']];x=520+(i-(len(chips)-1)/2)*110
   d.rounded_rectangle((x-42,1240,x+42,1324),radius=22,fill=col)
   d.text((x,1284),str(chip['number']),font=ImageFont.truetype(str(FONT),48),fill=(255,255,255),stroke_width=2,stroke_fill=(0,0,0,80),anchor='mm')
 return layer

def compose(captions,encode=False,preview_dir="preview-frames"):
 frames=D/'frames';files=sorted(frames.glob('*.png'))
 expected=C['frames']
 if encode and len(files)!=expected:raise RuntimeError(('missing frames',len(files),expected))
 if not encode:
  out=D/'previews/finished';out.mkdir(parents=True,exist_ok=True)
  for p in sorted((D/preview_dir).glob('*.png')):
   im=Image.open(p).convert('RGBA');t=int(p.stem)/30
   im=Image.alpha_composite(im,overlay(t,captions)).convert('RGB');im.save(out/p.name)
  return
 target=D/'reel.mp4'
 cmd=['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','1080x1920','-r','30','-i','pipe:0','-i',str(D/'audio/master.wav'),'-map','0:v','-map','1:a','-c:v','libx264','-preset','slow','-crf','18','-maxrate','18M','-bufsize','36M','-vf','scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p','-x264-params','colorprim=bt709:transfer=bt709:colormatrix=bt709','-profile:v','high','-level','4.2','-pix_fmt','yuv420p','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-c:a','aac','-b:a','256k','-ar','48000','-ac','2','-movflags','+faststart',str(target)]
 proc=subprocess.Popen(cmd,stdin=subprocess.PIPE)
 # A subtle bottom gradient improves readability without a subtitle box.
 grad=np.zeros((H,W,4),np.uint8)
 yy=np.arange(H)
 opacity=np.clip((yy-1250)/550,0,1)*32
 grad[:,:,3]=opacity[:,None].astype(np.uint8)
 gradient=Image.fromarray(grad)
 for i,p in enumerate(files):
  if int(p.stem)!=i:raise RuntimeError(('frame sequence',i,p))
  im=Image.open(p).convert('RGBA')
  im=Image.alpha_composite(im,gradient)
  im=Image.alpha_composite(im,overlay(i/FPS,captions)).convert('RGB')
  proc.stdin.write(im.tobytes())
  if i%120==0:print('ENCODE',i,expected,flush=True)
 proc.stdin.close()
 if proc.wait()!=0:raise RuntimeError('ffmpeg failed')
 print('VIDEO_OK',target,flush=True)

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--encode',action='store_true');p.add_argument('--audio',action='store_true');p.add_argument('--out',required=True);p.add_argument('--reference-captions',action='store_true');p.add_argument('--preview-dir',default='preview-frames');a=p.parse_args()
 captions=json.loads((D/'subtitles.json').read_text()) if a.reference_captions else subtitles()
 if a.audio:mix_audio()
 compose(captions,a.encode,a.preview_dir)
