"""Final technical QA and extracted MP4 frames for a 3D reel episode."""
import json, subprocess, sys
from pathlib import Path
import numpy as np
from tools.signs_reel import audio,verify,config as C
out=Path(sys.argv[1]).resolve();m=json.loads((out/'timeline.json').read_text())
v=out/'reel.mp4';verify.check_durations(v,out/'sound-driving.wav',m['frames']);verify.check_result(v,m['frames'])
streams=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','stream=codec_type,nb_frames,r_frame_rate','-of','json',str(v)]))['streams']
vs=next(x for x in streams if x['codec_type']=='video');assert int(vs['nb_frames'])==m['frames'];assert vs['r_frame_rate']=='30/1'
assert m['voiceVerified']
evidence=json.loads((out/'scene-evidence.json').read_text());assert evidence['spec']['reviewed']
correct=next(i for i,a in enumerate(m['question']['answers']) if a['correct']);assert correct==evidence['source']['correctAnswerIndex']
audit=json.loads((out/'motion-audit.json').read_text());assert all(not x['collision'] for x in audit)
assert audit[0]['arrow'] and audit[0]['progress']==0
assert all(x['clear'] for x in audit if x['progress']>0)
frameqa=json.loads((out/'frame-verification.json').read_text())
assert frameqa['framesChecked']==m['frames']
assert frameqa['collisionFrames']==frameqa['prematureReleaseFrames']==0
assert abs(frameqa['arrowFirstHidden']-frameqa['arrowExpectedEnd'])<=1/m['fps']
if evidence['source']['actorsConfig'][0]['targetAction'] in ('turn_left','turn_right'):
 assert frameqa['npcIndicatorSeen']
base=audio.read_wav(out/'sound.wav');mixed=audio.read_wav(out/'sound-driving.wav');assert mixed.shape==base.shape;assert np.max(np.abs(mixed))<.999
# The mix may apply uniform attenuation to preserve headroom; speech before motion
# must otherwise differ by no more than PCM rounding.
first=m['reveal']+min(m['episode']['motion']['playerDelay'],m['episode']['motion']['npcDelay']);n=round(first*C.SR)
# PCM writes truncate toward zero; a least-squares gain biases low for quiet
# samples. Fit the feasible gain interval within one PCM unit instead.
a=base[:n].astype(np.float64);b=mixed[:n].astype(np.float64);nz=np.abs(a)>0
assert np.all(b[~nz]==0)
lower=float(np.max(np.abs(b[nz])/np.abs(a[nz])))
upper=float(np.min((np.abs(b[nz])+1/32768)/np.abs(a[nz])))
assert lower<=upper+1e-7
gain=(lower+upper)/2;assert np.max(np.abs(gain*a-b))<=2/32768
frames=out/'final-frames';frames.mkdir(exist_ok=True)
for shot in audit:
 subprocess.run(['ffmpeg','-v','error','-y','-ss',str(shot['time']),'-i',str(v),'-frames:v','1',str(frames/f"{shot['frame']:04d}.png")],check=True)
report=dict(status='technical_pass',frames=m['frames'],duration=m['duration'],resolution=[1080,1920],fps=30,voiceVerified=True,sourceQuestionId=m['question']['id'],correctAnswerIndex=correct,sampleFrames=[x['frame'] for x in audit],allFramesCheckedForCollision=True,finalFrames=str(frames),visualReview='pending')
(out/'qa.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False))
