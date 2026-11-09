"""Create a separate EEVEE scene with baked street illumination."""
import bpy,time,json
from mathutils import Vector
from pathlib import Path
S=bpy.context.scene
OUT=Path(__file__).resolve().parents[2]/'output/blender_youtube/pilot_001'
S.render.engine='BLENDER_EEVEE'
e=S.eevee;e.taa_render_samples=8;e.use_raytracing=False;e.use_fast_gi=False
e.shadow_ray_count=1;e.shadow_step_count=6;e.gi_cubemap_resolution='256'
S.render.threads_mode='FIXED';S.render.threads=4
S.render.resolution_percentage=100
for m in bpy.data.materials:
 if m.use_nodes:
  for n in m.node_tree.nodes:
   if n.type=='BSDF_PRINCIPLED':
    for link in list(n.inputs['Normal'].links):m.node_tree.links.remove(link)
for o in bpy.data.objects:
 if o.type=='CAMERA':o.data.dof.use_dof=False
 if o.type=='LIGHT' and o.data.type=='SUN':o.data.angle=0
 if o.type=='LIGHT' and o.data.type=='AREA':o.data.use_shadow=False
# Raster transparency avoids noisy dithered windscreens and solid headlamp lenses.
for name in ['Smoked automotive glass','Headlamp lenses']:
 m=bpy.data.materials.get(name)
 if not m:continue
 m.surface_render_method='BLENDED'
 if name=='Headlamp lenses':
  n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF');p.inputs['Transmission Weight'].default_value=0
  tr=n.new('ShaderNodeBsdfTransparent');mix=n.new('ShaderNodeMixShader');mix.inputs[0].default_value=.08
  l.new(tr.outputs[0],mix.inputs[1]);l.new(p.outputs[0],mix.inputs[2]);l.new(mix.outputs[0],n.get('Material Output').inputs['Surface'])
# Bake only the static environment; moving cars must not leave baked shadows.
cars=[o for o in bpy.data.objects if o.name.startswith(('RED •','BLUE •','Integrated left'))]
old={o:o.hide_render for o in cars}
for o in cars:o.hide_render=True
bpy.ops.object.select_all(action='DESELECT')
p=bpy.data.lightprobes.new('Street indirect illumination','VOLUME')
p.resolution_x=24;p.resolution_y=20;p.resolution_z=4
p.bake_samples=256;p.surfel_density=8;p.capture_world=False;p.capture_distance=65
obj=bpy.data.objects.new('Baked street lighting',p);S.collection.objects.link(obj)
obj.location=(0,-18,3);obj.scale=(48,40,6);obj.select_set(True);bpy.context.view_layer.objects.active=obj
start=time.monotonic();print('BAKING',flush=True)
bpy.ops.object.lightprobe_cache_bake()
print('BAKED_SECONDS',time.monotonic()-start,flush=True)
for o,value in old.items():o.hide_render=value
# One static HDR capture replaces per-frame cubemap rendering.
world=S.world;nodes=world.node_tree.nodes;links=world.node_tree.links
image=bpy.data.images.load(str(OUT/'street_reflections.exr'));image.pack()
env=nodes.new('ShaderNodeTexEnvironment');env.image=image
links.new(env.outputs['Color'],nodes.get('Background').inputs['Color'])
nodes.get('Background').inputs['Strength'].default_value=3.5
bpy.ops.object.light_add(type='AREA',location=(-12,-24,12))
fill=bpy.context.object;fill.name='EEVEE broad camera fill';fill.data.energy=5000;fill.data.use_shadow=False;fill.data.shape='DISK';fill.data.size=18
fill.data.color=(.82,.9,1)
fill.rotation_euler=(Vector((0,-10,0))-fill.location).to_track_quat('-Z','Y').to_euler()
for name in ['RED • driver','BLUE • right priority']:
 car=bpy.data.objects[name];car.delta_location.z=-.025
 # Soft contact shadow under the chassis supplements EEVEE shadow-map bias.
 bpy.ops.mesh.primitive_plane_add(size=2)
 plane=bpy.context.object;plane.name=name+' contact shadow';plane.parent=car
 plane.location=(0,0,-.001);plane.scale=(1.02,2.08,1)
 m=bpy.data.materials.new(name+' soft contact');m.use_nodes=True;m.surface_render_method='BLENDED'
 n=m.node_tree.nodes;l=m.node_tree.links;n.clear()
 uv=n.new('ShaderNodeTexCoord');dist=n.new('ShaderNodeVectorMath');dist.operation='DISTANCE';dist.inputs[1].default_value=(.5,.5,0)
 l.new(uv.outputs['UV'],dist.inputs[0])
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.1;ramp.color_ramp.elements[0].color=(.5,.5,.5,1)
 ramp.color_ramp.elements[1].position=.5;ramp.color_ramp.elements[1].color=(0,0,0,1);l.new(dist.outputs['Value'],ramp.inputs[0])
 tr=n.new('ShaderNodeBsdfTransparent');black=n.new('ShaderNodeEmission');black.inputs[0].default_value=(0,0,0,1)
 mix=n.new('ShaderNodeMixShader');l.new(ramp.outputs['Color'],mix.inputs[0]);l.new(tr.outputs[0],mix.inputs[1]);l.new(black.outputs[0],mix.inputs[2])
 output=n.new('ShaderNodeOutputMaterial');l.new(mix.outputs[0],output.inputs[0]);plane.data.materials.append(m)
S.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'pdd_youtube_001_eevee.blend'))
timings=[]
for sec in [3,47,65,3.04,3.08]:
 S.frame_set(round(sec*24)+1);S.render.filepath=str(OUT/('eevee_baked_'+str(sec).replace('.','_')+'.png'))
 start=time.monotonic();bpy.ops.render.render(write_still=True);elapsed=time.monotonic()-start
 timings.append({'second':sec,'renderSeconds':elapsed});print('TIMING',timings[-1],flush=True)
(OUT/'eevee_timings.json').write_text(json.dumps(timings,indent=2))
