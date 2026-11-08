"""Repair thin windows and the imported quaternion wheel rigs in a saved pilot."""
import bpy, math
S=bpy.context.scene
material=bpy.data.materials['Smoked automotive glass']
mix=next(n for n in material.node_tree.nodes if n.type=='MIX_SHADER')
for link in list(mix.inputs[0].links):material.node_tree.links.remove(link)
mix.inputs[0].default_value=.06
# The glTF wheels retain a -90° X basis; Euler curves were previously ignored
# while their rotation mode remained QUATERNION. Rebuild from the baked path.
car=bpy.data.objects['BLUE • right priority']
wheels=[o for o in bpy.data.objects if any(o.name.endswith('/ '+n) for n in ('wheel_fl','wheel_fr','wheel_rl','wheel_rr'))]
for w in wheels:w.rotation_mode='XYZ'
previous=None;distance=0
for frame in range(S.frame_start,S.frame_end+1):
    S.frame_set(frame)
    position=car.location.copy()
    if previous is not None:distance+=(position-previous).length
    previous=position
    for w in wheels:
        w.rotation_euler=(-math.pi/2-distance/.36,0,0)
        w.keyframe_insert('rotation_euler',frame=frame)
S.render.threads_mode='FIXED';S.render.threads=4
S.render.use_persistent_data=True
S.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
