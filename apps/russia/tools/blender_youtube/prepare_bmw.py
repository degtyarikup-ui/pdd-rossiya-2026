"""Bake Mike Pan's Blender demo car into a portable, metre-scale vehicle asset.
Invoke with the downloaded bmw27_cpu.blend already open, --disable-autoexec.
"""
import bpy, math
from pathlib import Path
from mathutils import Matrix, Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/blender_youtube/pilot_001/assets'
deps=bpy.context.evaluated_depsgraph_get()
parts=[]
for instance in deps.object_instances:
    obj=instance.object
    if obj.type!='MESH' or obj.name in ['Floor','Light','carRigArrow','carRigOutline']:continue
    if instance.is_instance and instance.parent.name=='1M':continue
    mesh=bpy.data.meshes.new_from_object(obj,preserve_all_data_layers=True,depsgraph=deps)
    mesh.transform(instance.matrix_world)
    wheel=instance.parent.name if instance.is_instance and instance.parent.name.startswith('Tire') else None
    parts.append((obj.name,mesh,wheel))
coords=[v.co for _,m,_ in parts for v in m.vertices]
lo=Vector(tuple(min(v[i] for v in coords) for i in range(3)));hi=Vector(tuple(max(v[i] for v in coords) for i in range(3)))
center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
factor=4.48/(hi.x-lo.x)
transform=Matrix.Rotation(math.pi/2,4,'Z')@Matrix.Scale(factor,4)@Matrix.Translation(-center)
for obj in list(bpy.data.objects):bpy.data.objects.remove(obj,do_unlink=True)
root=bpy.data.objects.new('BMW • front -Y',None);bpy.context.scene.collection.objects.link(root)
wheels={}
for name,mesh,wheel in parts:
    mesh.transform(transform)
    obj=bpy.data.objects.new('BMW / '+name,mesh);bpy.context.scene.collection.objects.link(obj)
    obj.parent=root
    if wheel:
        wheels.setdefault(wheel,[]).append(obj)
for key,objects in wheels.items():
    coords=[v.co for o in objects for v in o.data.vertices]
    pivot=Vector(tuple((min(v[i] for v in coords)+max(v[i] for v in coords))/2 for i in range(3)))
    empty=bpy.data.objects.new('wheel_'+key,None);bpy.context.scene.collection.objects.link(empty);empty.parent=root;empty.location=pivot
    for obj in objects:
        obj.data.transform(Matrix.Translation(-pivot));obj.parent=empty
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bmw_prepared.blend'))
print('Prepared BMW',factor,'dimensions',tuple((hi-lo)*factor),'parts',len(parts),flush=True)
