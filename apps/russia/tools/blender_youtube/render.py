"""Resume deterministic PNG rendering from the saved .blend, on Metal or CPU."""
import bpy, sys, argparse, time, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/blender_youtube/pilot_001'
p=argparse.ArgumentParser();p.add_argument('--start',type=int,default=1);p.add_argument('--end',type=int,default=1968)
p.add_argument('--cpu',action='store_true');p.add_argument('--samples',type=int,default=32)
p.add_argument('--scale',type=int,default=100);p.add_argument('--folder',default='frames')
p.add_argument('--cooldown',type=float,default=1.0)
args=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
S=bpy.context.scene;S.render.engine='CYCLES';S.cycles.samples=args.samples
S.cycles.use_denoising=True;S.render.use_persistent_data=True;S.render.resolution_percentage=args.scale
S.render.threads_mode='FIXED';S.render.threads=4
S.cycles.adaptive_threshold=.05
if args.cpu:S.cycles.device='CPU'
else:
    pref=bpy.context.preferences.addons['cycles'].preferences;pref.compute_device_type='METAL'
    pref.kernel_optimization_level='OFF';pref.metalrt='ON';pref.get_devices()
    for d in pref.devices:d.use=d.type=='METAL'
    S.cycles.device='GPU'
    if hasattr(S.cycles,'denoising_use_gpu'):S.cycles.denoising_use_gpu=True
folder=OUT/args.folder;folder.mkdir(exist_ok=True)
start=time.monotonic();count=0
for frame in range(args.start,args.end+1):
    path=folder/f'frame_{frame:04d}.png'
    if path.exists() and path.stat().st_size>10000:continue
    S.frame_set(frame);S.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)
    count+=1;elapsed=time.monotonic()-start
    print(json.dumps(dict(frame=frame,end=args.end,rendered=count,seconds=round(elapsed,2),secondsPerFrame=round(elapsed/count,2))),flush=True)
    time.sleep(args.cooldown)
print('RENDER COMPLETE',flush=True)
