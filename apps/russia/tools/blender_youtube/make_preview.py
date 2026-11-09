"""Assemble the three EEVEE motion tests into a silent six-second review clip."""
from pathlib import Path
import subprocess,json,shutil
OUT=Path(__file__).resolve().parents[2]/'output/blender_youtube/pilot_001'
frames=[OUT/'fast_preview_frames'/f'frame_{f:04}.png' for a,b in [(73,120),(1009,1056),(1537,1584)] for f in range(a,b+1)]
assert all(f.is_file() for f in frames),'Preview frames are incomplete'
target=OUT/'pdd_youtube_001_fast_test.mp4'
cmd=['ffmpeg','-y','-v','error','-f','image2pipe','-framerate','24','-vcodec','png','-i','-','-an','-c:v','libx264','-threads','4','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(target)]
process=subprocess.Popen(cmd,stdin=subprocess.PIPE)
for frame in frames:process.stdin.write(frame.read_bytes())
process.stdin.close()
assert process.wait()==0
subprocess.run(['ffmpeg','-v','error','-i',str(target),'-f','null','-'],check=True)
probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(target)]))['streams'][0]
assert (probe['width'],probe['height'],int(probe['nb_frames']))==(1920,1080,144)
shutil.copy2(target,Path.home()/'Desktop'/target.name)
print(target)
