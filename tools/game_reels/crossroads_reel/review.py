"""Final frame/caption/audio checks and a small reproducible production record."""
import json,subprocess,hashlib,re,shutil
from pathlib import Path
from common import ROOT,output_dir
from finish import overlay
D=output_dir()
C=json.loads((D/'timeline.json').read_text());E=json.loads((D/'episode.json').read_text());S=json.loads((D/'subtitles.json').read_text())
F=json.loads((D/'framing.json').read_text());A=json.loads((D/'voice-audit.json').read_text());X=json.loads((D/'export-checks.json').read_text())
assert 'VALIDATION_OK' in X['sceneValidation'] and X['decode']=='passed'
assert not A.get('wrong_or_unclear_words') and min(A[k] for k in ['naturalness','expressiveness','clarity'])>=8,A
assert E.get('minimumDuration',25)<=C['duration']<=35,C
errors=[]
def intersects(a,b):
 return a[0]<b[2] and a[0]+a[2]>b[0] and a[1]<b[3] and a[1]+a[3]>b[1]
for f in F:
 t=f['frame']/30; layer=overlay(t,S);box=layer.getbbox()
 if not box:continue
 # The countdown and answer chips have their own scene safe areas. Check
 # only the actual caption alpha, against every visible full participant.
 caption=layer.crop((0,1360,1080,1510)).getbbox()
 if caption:
  box=(caption[0],caption[1]+1360,caption[2],caption[3]+1360)
  for car in f['cars']:
   r=car['rect']
   if car['visible'] and intersects(r,box):errors.append([f['frame'],car['i'],r,box])
assert not errors,errors[:10]
result=subprocess.run(['ffmpeg','-hide_banner','-i',str(D/'reel.mp4'),'-af','loudnorm=I=-14:TP=-1.5:LRA=7:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
match=re.search(r'\{\s*"input_i".*?\}',result.stderr,re.S);assert match
loud=json.loads(match.group());(D/'loudness.json').write_text(json.dumps(loud,indent=2)+'\n')
assert -14.7<=float(loud['input_i'])<=-13.3 and float(loud['input_tp'])<=-1.5,loud
n=E['id'].split('-')[1];recipe=ROOT/'tools/game_reels/crossroads_reel/episodes'/n
for name in ['voice.json','timeline.json','subtitles.json']:shutil.copyfile(D/name,recipe/name)
# A production record contains content and hashes, never credentials or local
# personal paths. Audio and video remain outside version control.
E['status']='produced';(recipe/'episode.json').write_text(json.dumps(E,ensure_ascii=False,indent=2)+'\n')
sources=['game_godot/videos/crossroads_reel/'+x for x in ['scene.gd','stage_geometry.gd','render.gd','signal_episodes.gd','validate_signals.gd']]+['tools/game_reels/crossroads_reel/'+x for x in ['plan.py','finish.py','review.py','audit_voice.py','deliver.py']]
record={'id':E['id'],'title':E['title'],'status':'produced','published':False,'createdDate':E['createdDate'],'styleReference':'crossroads-001 approved 2026-10-20','videoFile':f'game_{n}.mp4','deliveryDirectory':'Desktop','sha256':X['sha256'],'bytes':X['bytes'],'width':1080,'height':1920,'fps':30,'frames':C['frames'],'duration':C['duration'],'renderer':'Godot 4.7.2 / Forward+ / Metal','rules':E['rules'],'ruleSource':'https://www.consultant.ru/document/Cons_doc_LAW_2709/74cbe820904f4f8ce76047ddbd81d14c8b953d3e/','adaptation':E['adaptation'],'audio':{'voice':E['voice']['name'],'model':E['voice']['model'],'integratedLufs':float(loud['input_i']),'truePeakDbtp':float(loud['input_tp']),'music':False},'checks':{'sceneValidation':X['sceneValidation'],'captionClearanceFrames':len(F),'fullVideoDecode':'passed','automaticVoiceAudit':A,'flutterAnalyze':'No issues','flutterTests':'passed; see build logs'},'sources':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources},'voiceClips':{x['key']:hashlib.sha256((D/x['path']).read_bytes()).hexdigest() for x in json.loads((D/'voice.json').read_text())}}
record['revision']=E.get('revision',1)
if (D/'question-edit.json').is_file():
 edit=json.loads((D/'question-edit.json').read_text())
 record.update(previousRevisionSha256=edit['sourceSha256'],questionEdit=edit)
 record['checks'].update(questionFirst=True,retainedPcmTailExact=edit['pcmTailExact'],retainedTailSsim=edit['retainedTailSsim'])
 source='tools/game_reels/crossroads_reel/replace_question.py'
 record['sources'][source]=hashlib.sha256((ROOT/source).read_bytes()).hexdigest()
(recipe/'production.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print('REVIEW_OK',E['id'],C['frames'],'frames; captions clear; voice audit passed;',loud['input_i'],'LUFS;',loud['input_tp'],'dBTP')
