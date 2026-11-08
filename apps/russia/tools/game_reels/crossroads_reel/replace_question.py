"""Replace only the spoken opening; retain the reviewed countdown and answer.

--out contains episode.json (new hook, no setup), question-voice/ (new TTS),
source.mp4 and source-scene/{episode,voice,timeline,subtitles,production}.json.
The source MP4 must match its production hash. Source media stays in output/.
"""
import hashlib,json,math,re,shutil,subprocess,sys,wave
from pathlib import Path
import numpy as np
from PIL import Image
from common import ROOT,output_dir
D=output_dir();TOOLS=Path(__file__).resolve().parent

def read(path):return json.loads(path.read_text())
def write(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def run(args):subprocess.run([str(x) for x in args],check=True)
def wav(path,samples):
 with wave.open(str(path),'wb') as f:
  f.setnchannels(2);f.setsampwidth(2);f.setframerate(48000);f.writeframes(samples.astype('<i2').tobytes())

def encode_retained(E,old,cfg,intro_frames):
 source=D/'source.mp4';intro=D/'intro.mp4';audio=D/'audio'
 original=read(D/'source-scene/production.json')
 assert hashlib.sha256(source.read_bytes()).hexdigest()==original['sha256']
 old_cut=math.floor(old['challenge']*30);delta=(intro_frames-old_cut)/30;offset=-delta
 graph=f'[0:v]setpts=PTS-STARTPTS[i];[1:v]trim=start_frame={old_cut},setpts=PTS-STARTPTS[t];[i][t]concat=n=2:v=1:a=0[v]'
 run(['ffmpeg','-v','error','-y','-i',intro,'-i',source,'-i',audio/'master.wav','-filter_complex',graph,'-map','[v]','-map','2:a','-c:v','libx264','-preset','slow','-crf','10','-maxrate','18M','-bufsize','36M','-x264-params','colorprim=bt709:transfer=bt709:colormatrix=bt709','-profile:v','high','-level','4.2','-pix_fmt','yuv420p','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-c:a','aac','-b:a','256k','-ar','48000','-ac','2','-movflags','+faststart',D/'reel.mp4'])
 graph=f'[0:v]trim=start_frame={intro_frames},setpts=PTS-STARTPTS[n];[1:v]trim=start_frame={old_cut},setpts=PTS-STARTPTS[o];[n][o]ssim'
 comparison=subprocess.run(['ffmpeg','-hide_banner','-i',str(D/'reel.mp4'),'-i',str(source),'-filter_complex',graph,'-an','-f','null','-'],text=True,capture_output=True,check=True)
 score=float(re.search(r'All:([0-9.]+)',comparison.stderr).group(1));assert score>=.995,score
 edit={'sourceSha256':original['sha256'],'sourceCutFrame':old_cut,'introFrames':intro_frames,'deltaSeconds':delta,'sourceFrameOffset':offset,'retainedTailSsim':score,'pcmTailExact':True,'newQuestion':E['lines'][0]['text']}
 write(D/'question-edit.json',edit)
 print('QUESTION_EDIT_OK',E['id'],cfg['duration'],'seconds; SSIM',score,flush=True)


def main():
 E=read(D/'episode.json');old=read(D/'source-scene/timeline.json');original=read(D/'source-scene/production.json')
 if '--encode-only' in sys.argv:
  cfg=read(D/'timeline.json');intro_frames=int(cfg['frames'])-int(old['frames'])+math.floor(old['challenge']*30)
  encode_retained(E,old,cfg,intro_frames);return
 source=D/'source.mp4'
 assert hashlib.sha256(source.read_bytes()).hexdigest()==original['sha256']
 assert E['directQuestion'] and not any(x['key']=='setup' for x in E['lines'])
 audio=D/'audio';audio.mkdir(exist_ok=True)
 hook=read(D/'question-voice/voice.json')[0];hook.update(start=.12,path='audio/hook.wav')
 shutil.copyfile(D/'question-voice/audio/hook.wav',audio/'hook.wav')
 intro_frames=math.ceil((hook['start']+hook['duration']+.17)*30)
 old_cut=math.floor(old['challenge']*30);delta=(intro_frames-old_cut)/30
 assert old_cut>intro_frames and old_cut-intro_frames>=0
 frames=int(old['frames'])+intro_frames-old_cut
 cfg={k:v+delta for k,v in old.items() if k not in ['hook','setup','frames','duration']}
 cfg.update(hook=.12,frames=frames,duration=frames/30)
 write(D/'timeline.json',cfg);write(D/'voice.json',[hook])
 model=ROOT/'scratch/whisper/ggml-large-v3-turbo.bin'
 # A caller may provide the local alignment model without changing the recipe.
 if '--model' in sys.argv:model=Path(sys.argv[sys.argv.index('--model')+1])
 run(['whisper-cli','-m',model,'-f',audio/'hook.wav','-l','ru','-ojf','-of',audio/'hook-align','-ml','1','-sow','-t','4'])
 import finish
 captions=finish.subtitles()
 old_captions=read(D/'source-scene/subtitles.json')
 captions += [dict(x,start=x['start']+delta,end=x['end']+delta) for x in old_captions if x['key'] not in ['hook','setup']]
 write(D/'subtitles.json',captions)
 def stamp(t):
  ms=round(t*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
 (D/'reel.srt').write_text('\n\n'.join(f'{i+1}\n{stamp(x["start"])} --> {stamp(x["end"])}\n{x["text"]}' for i,x in enumerate(captions))+'\n')
 voices=[hook]
 for old_line in read(D/'source-scene/voice.json'):
  if old_line['key'] in ['hook','setup']:continue
  key=old_line['key'];line=dict(old_line,start=old_line['start']+delta,retainedFromMixedMaster=True)
  run(['ffmpeg','-v','error','-y','-ss',old_line['start'],'-t',old_line['duration'],'-i',source,'-ar','24000','-ac','1',audio/f'{key}.wav'])
  voices.append(line)
 write(D/'voice.json',voices)
 # Preserve the existing mix after the edit point, sample for sample in PCM.
 raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(source),'-f','s16le','-ar','48000','-ac','2','pipe:1'])
 original_pcm=np.frombuffer(raw,dtype='<i2').reshape(-1,2)
 total_samples=frames*1600;intro_samples=intro_frames*1600
 tail=original_pcm[old_cut*1600:old['frames']*1600]
 assert len(tail)==total_samples-intro_samples
 # Match the opening's active speech level to the preceding master.
 old_hook=read(D/'source-scene/voice.json')[0]
 ref=subprocess.run(['ffmpeg','-hide_banner','-ss',str(old_hook['start']),'-t',str(old_hook['duration']),'-i',str(source),'-af','loudnorm=I=-14:TP=-2:LRA=7:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
 level=float(json.loads(re.search(r'\{\s*"input_i".*?\}',ref.stderr,re.S).group())['input_i'])
 level=max(-16,min(-11,level))
 run(['ffmpeg','-v','error','-y','-i',audio/'hook.wav','-af',f'highpass=f=85,acompressor=threshold=0.13:ratio=1.8:attack=12:release=100,loudnorm=I={level}:TP=-2.5:LRA=7','-ar','48000','-ac','2',audio/'hook-master.wav'])
 with wave.open(str(audio/'hook-master.wav'),'rb') as f:new_hook=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').reshape(-1,2)
 rng=np.random.default_rng(812);noise=rng.standard_normal(intro_samples)
 freq=np.fft.rfftfreq(intro_samples,1/48000);spectrum=np.fft.rfft(noise)
 bed=np.fft.irfft(spectrum*np.exp(-(freq/1200)**2)*(1-np.exp(-(freq/110)**2)),intro_samples)
 bed=bed/max(float(np.std(bed)),1e-9)*.0015*32767
 opening=np.repeat(bed[:,None],2,axis=1)
 start=round(.12*48000);assert start+len(new_hook)<=intro_samples
 opening[start:start+len(new_hook)]+=new_hook
 opening[:3840]*=np.linspace(0,1,3840)[:,None]
 pcm=np.concatenate([np.clip(opening,-32767,32767).astype('<i2'),tail])
 assert np.array_equal(pcm[intro_samples:],tail)
 wav(audio/'master.wav',pcm);shutil.copyfile(audio/'master.wav',audio/'speech.wav')
 # Validate the original scene again, then map its exact camera/geometry
 # samples to the shortened edit. Both sections use integer source frames.
 run([sys.executable,TOOLS/'build.py','validate','--out',D/'source-scene'])
 original_framing=read(D/'source-scene/framing.json')
 source_frames=list(range(old_cut-intro_frames,old_cut))+list(range(old_cut,int(old['frames'])))
 assert len(source_frames)==frames
 write(D/'framing.json',[dict(original_framing[source_frame],frame=i) for i,source_frame in enumerate(source_frames)])
 (D/'validation.log').write_text((D/'source-scene/validation.log').read_text()+f'RETAINED_EDIT_OK {frames} frames; source frames {source_frames[0]}..{source_frames[-1]}; exact PCM tail\n')
 offset=(old_cut-intro_frames)/30
 run(['godot','--rendering-method','forward_plus','--path',ROOT/'game_godot','--script','res://videos/crossroads_reel/render.gd','--',f'--data={D / "source-scene"}',f'--scene={E["scene"]}',f'--end={intro_frames}',f'--time-offset={offset}',f'--out={D / "intro-frames"}'])
 # Encode the fresh captioned question losslessly before joining the old tail.
 intro=D/'intro.mp4'
 cmd=['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','1080x1920','-r','30','-i','pipe:0','-vf','scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p','-c:v','libx264','-preset','fast','-crf','0','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709',str(intro)]
 proc=subprocess.Popen(cmd,stdin=subprocess.PIPE)
 grad=np.zeros((1920,1080,4),np.uint8);grad[:,:,3]=(np.clip((np.arange(1920)-1250)/550,0,1)*32)[:,None].astype(np.uint8);gradient=Image.fromarray(grad)
 for frame in range(intro_frames):
  image=Image.open(D/'intro-frames'/f'{frame:05}.png').convert('RGBA')
  image=Image.alpha_composite(image,gradient);image=Image.alpha_composite(image,finish.overlay(frame/30,captions))
  proc.stdin.write(image.convert('RGB').tobytes())
 proc.stdin.close();assert proc.wait()==0
 encode_retained(E,old,cfg,intro_frames)

if __name__=='__main__':main()
