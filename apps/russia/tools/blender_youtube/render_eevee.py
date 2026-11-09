"""Render an EEVEE motion test or a complete film without rebuilding each frame."""
import argparse,bpy,json,sys,time
from pathlib import Path
OUT=Path(__file__).resolve().parents[2]/'output/blender_youtube/pilot_001'
p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True)
g.add_argument('--preview',action='store_true');g.add_argument('--full',action='store_true')
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
s=bpy.context.scene
assert s.render.engine=='BLENDER_EEVEE','Open the prepared EEVEE blend'
folder=OUT/('fast_preview_frames' if a.preview else 'frames_eevee');folder.mkdir(exist_ok=True)
ranges=[(73,120),(1009,1056),(1537,1584)] if a.preview else [(1,1968)]
records=[];start=time.monotonic();last=start
@bpy.app.handlers.persistent
def completed(scene):
 global last
 now=time.monotonic();record={'frame':scene.frame_current,'seconds':round(now-last,3),'elapsed':round(now-start,3)}
 records.append(record);last=now;print(json.dumps(record),flush=True)
bpy.app.handlers.render_write.append(completed)
try:
 for first,end in ranges:
  # Resume only missing contiguous runs, while preserving engine state within each run.
  missing=[f for f in range(first,end+1) if not (folder/f'frame_{f:04}.png').exists()]
  runs=[]
  for f in missing:
   if runs and f==runs[-1][1]+1:runs[-1][1]=f
   else:runs.append([f,f])
  for begin,finish in runs:
   s.frame_start=begin;s.frame_end=finish;s.render.filepath=str(folder/'frame_');last=time.monotonic()
   result=bpy.ops.render.render(animation=True)
   if 'FINISHED' not in result:raise RuntimeError('Render cancelled')
finally:
 bpy.app.handlers.render_write.remove(completed)
 (OUT/('fast_preview_timing.json' if a.preview else 'eevee_render_timing.json')).write_text(json.dumps(records,indent=2))
print('EEVEE RENDER COMPLETE',flush=True)
