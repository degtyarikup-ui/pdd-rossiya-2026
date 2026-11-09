import bpy,math
from pathlib import Path
s=bpy.context.scene;s.frame_set(1)
for o in bpy.data.objects:
 if o.name.startswith(('RED •','BLUE •','Integrated left')):o.hide_render=True
c=bpy.data.cameras.new('Reflection capture');c.type='PANO';c.panorama_type='EQUIRECTANGULAR'
o=bpy.data.objects.new('Reflection capture',c);s.collection.objects.link(o);o.location=(0,-8,1.7);o.rotation_euler=(math.pi/2,0,0);s.camera=o
s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=16;s.render.threads_mode='FIXED';s.render.threads=4
s.render.resolution_x=1024;s.render.resolution_y=512;s.render.resolution_percentage=100
s.render.image_settings.file_format='OPEN_EXR';s.render.image_settings.color_depth='16'
s.render.filepath=str(Path(bpy.data.filepath).parent/'street_reflections.exr')
bpy.ops.render.render(write_still=True)
