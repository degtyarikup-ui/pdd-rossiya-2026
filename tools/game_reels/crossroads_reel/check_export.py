from pathlib import Path
import hashlib,json,subprocess
from common import output_dir
D=output_dir()
C=json.loads((D/'timeline.json').read_text())
p=D/'reel.mp4'
x=json.loads(subprocess.check_output(['ffprobe','-v','error','-count_frames','-show_streams','-show_format','-of','json',str(p)],text=True))
v=next(s for s in x['streams'] if s['codec_type']=='video')
a=next(s for s in x['streams'] if s['codec_type']=='audio')
assert (v['width'],v['height'],v['r_frame_rate'],int(v['nb_read_frames']))==(1080,1920,'30/1',int(C['frames']))
assert (v['codec_name'],v['pix_fmt'])==('h264','yuv420p')
assert all(v.get(k)=='bt709' for k in ['color_space','color_transfer','color_primaries']),v
assert abs(float(v['duration'])-C['duration'])<1/30 and abs(float(a['duration'])-C['duration'])<1/30
assert (a['codec_name'],a['channels'],int(a['sample_rate']))==('aac',2,48000)
subprocess.run(['ffmpeg','-v','error','-i',str(p),'-f','null','-'],check=True)
frames=[round((C['frames']-1)*x/7) for x in range(8)]
select='+'.join(f'eq(n,{n})' for n in frames)
(D/'previews').mkdir(exist_ok=True)
subprocess.run(['ffmpeg','-v','error','-y','-i',str(p),'-vf',f"select='{select}',scale=270:480,tile=4x2",'-frames:v','1',str(D/'previews/encoded-qa.jpg')],check=True)
checks={'video':{k:v.get(k) for k in ['codec_name','width','height','r_frame_rate','pix_fmt','duration','nb_read_frames','color_space','color_transfer','color_primaries']},'audio':{k:a[k] for k in ['codec_name','channels','sample_rate','duration']},'decode':'passed','sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size,'sceneValidation':(D/'validation.log').read_text()}
(D/'export-checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2))
print(json.dumps(checks,ensure_ascii=False,indent=2))
