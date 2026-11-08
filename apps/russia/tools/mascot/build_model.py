#!/usr/bin/env python3
"""Build the editable, skinned cone mascot in Blender 4.5 LTS.

Run: blender --background --factory-startup --python tools/mascot/build_model.py
The GLB contains real geometry, a bone rig and facial morph targets, no images.
"""
from pathlib import Path
import json
import math
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from blender_parts import make_glove

OUT = ROOT / "assets/mascot/3d"
REVIEW = ROOT / "output/mascot"
OUT.mkdir(parents=True, exist_ok=True)
REVIEW.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0


def linear(value):
    return value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4


def material(name, hex_color, roughness=.38, coat=.12):
    rgb = tuple(linear(int(hex_color[i:i+2], 16)/255) for i in (0, 2, 4))
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    node = mat.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = (*rgb, 1)
    node.inputs["Roughness"].default_value = roughness
    node.inputs["Coat Weight"].default_value = coat
    node.inputs["Coat Roughness"].default_value = .3
    mat.diffuse_color = (*rgb, 1)
    return mat


ORANGE = material("Orange_satin_vinyl", "FF7410", .4, .10)
WHITE = material("Warm_white_reflector", "FFF9EF", .36, .12)
BASE = material("Base_deep_orange", "DD5B0D", .44, .08)
BLUE = material("Iris_sky_blue", "078BE0", .16, .34)
NAVY = material("Pupil_midnight", "071F37", .2, .28)
BROWN = material("Brow_warm_brown", "583020", .5, 0)
MOUTH = material("Mouth_warm_cavity", "542021", .65, 0)
PINK = material("Tongue_coral", "F57680", .46, .04)
ASSETS = []
PROFILE = [(.245,.84),(.26,.9),(.29,.934),(.33,.94),(.39,.925),
           (.62,.852),(.89,.768),(1.2,.672),(1.6,.548),(2,.424),
           (2.03,.4147),(2.34,.3186),(2.54,.2566),(2.65,.215),
           (2.7,.181),(2.735,.13),(2.749,.07),(2.753,0)]


def radius(z):
    for (za, ra), (zb, rb) in zip(PROFILE, PROFILE[1:]):
        if z <= zb:
            t = max(0, (z-za)/(zb-za))
            return ra+(rb-ra)*t
    return 0


def on_cone(x, z, depth=0):
    r = max(radius(z), abs(x)+.001)
    radial = Vector((x, -math.sqrt(max(.00001, r*r-x*x)), 0)).normalized()
    normal = Vector((radial.x, radial.y, .31)).normalized()
    return Vector((x, -math.sqrt(max(.00001, r*r-x*x)), z))+normal*depth


def mesh(name, vertices, faces, mat):
    data = bpy.data.meshes.new(name+"_mesh")
    data.from_pydata(vertices, [], faces)
    data.materials.append(mat)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    for polygon in data.polygons:
        polygon.use_smooth = True
    ASSETS.append(obj)
    return obj


def apply(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def cube(name, dimensions, center, mat, bevel):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    apply(obj)
    obj.data.materials.append(mat)
    mod = obj.modifiers.new("Soft_manufactured_edges", "BEVEL")
    mod.width, mod.segments = bevel, 4
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in obj.data.polygons:
        p.use_smooth = True
    normals = obj.modifiers.new("Broad_flat_surfaces", "WEIGHTED_NORMAL")
    normals.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier=normals.name)
    ASSETS.append(obj)
    return obj


def tube(name, points, thickness, mat, sides=10):
    points = [Vector(p) for p in points]
    vertices, faces = [], []
    for i, point in enumerate(points):
        tangent = (points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
        axis = tangent.cross(Vector((0,1,0)))
        if axis.length < .01:
            axis = tangent.cross(Vector((1,0,0)))
        axis.normalize()
        other = tangent.cross(axis).normalized()
        rad = thickness[i] if isinstance(thickness, list) else thickness
        for j in range(sides):
            a = math.tau*j/sides
            vertices.append(point+rad*(math.cos(a)*axis+math.sin(a)*other))
    for i in range(len(points)-1):
        for j in range(sides):
            faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.extend([tuple(reversed(range(sides))), tuple((len(points)-1)*sides+j for j in range(sides))])
    return mesh(name, vertices, faces, mat)


def body_mesh():
    heights = sorted({round(z,6) for z in [p[0] for p in PROFILE[:-1]]+[.4+i*.1 for i in range(22)]})
    n = 64
    vertices, faces = [], []
    for z in heights:
        r = radius(z)
        for i in range(n):
            a=math.tau*i/n
            vertices.append((r*math.cos(a),r*math.sin(a),z))
    for j in range(len(heights)-1):
        for i in range(n):
            faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    faces.append(tuple(reversed(range(n))))
    tip=len(vertices)
    vertices.append((0,0,PROFILE[-1][0]))
    for i in range(n):
        faces.append(((len(heights)-1)*n+i,(len(heights)-1)*n+(i+1)%n,tip))
    obj=mesh("Cone_body_360", vertices, faces, ORANGE)
    obj.data.materials.append(WHITE)
    for polygon in obj.data.polygons:
        z=sum(obj.data.vertices[i].co.z for i in polygon.vertices)/len(polygon.vertices)
        polygon.material_index = int(.62 < z < .89 or 2.03 < z < 2.34)
    return obj


BASE_OBJ=cube("Rounded_square_base", (2.3,1.95,.245), (0,0,.1225), BASE, .105)
BODY=body_mesh()

# Sculpted shallow mouth relief and tooth ribbon conform to the round body.
# Mesh relief avoids Boolean shading artefacts while keeping every part editable.
def mouth_boundary(u):
    return 1.32+.055*u*u, 1.155+.22*(1-math.sqrt(max(0,1-u*u)))


boundary=[]
for i in range(25):
    u=-1+2*i/24
    boundary.append((.255*u,mouth_boundary(u)[0]))
for i in range(23,0,-1):
    u=-1+2*i/24
    boundary.append((.255*u,mouth_boundary(u)[1]))


def mouth_patch(name, top_fn, bottom_fn, depth, mat):
    vertices, faces=[],[]
    cols, rows=25,5
    for j in range(rows):
        t=j/(rows-1)
        for i in range(cols):
            u=-.99+1.98*i/(cols-1)
            z=top_fn(u)*(1-t)+bottom_fn(u)*t
            d=depth-.009*(1-u*u)*math.sin(t*math.pi)
            vertices.append(on_cone(.255*u,z,d))
    for j in range(rows-1):
        for i in range(cols-1):
            a=j*cols+i
            # Face normals point out of the front surface.
            faces.append((a,a+cols,a+cols+1,a+1))
    return mesh(name,vertices,faces,mat)


CAVITY=mouth_patch("Smile_soft_bowl",lambda u:mouth_boundary(u)[0],lambda u:mouth_boundary(u)[1],.018,MOUTH)
TOOTH=mouth_patch("Upper_tooth_ribbon",lambda u:mouth_boundary(u)[0]-.004,
                  lambda u:mouth_boundary(u)[0]-.004-.04*(1-u*u),.028,WHITE)
TONGUE=mouth_patch("Tongue_soft_patch",lambda u:mouth_boundary(u)[1]+.04*(1-u*u),
                  lambda u:mouth_boundary(u)[1]+.006,.031,PINK)
LIP=None


def eye_basis(x,z):
    center=on_cone(x,z,.002)
    theta=math.asin(x/radius(z))
    normal=Vector((math.sin(theta),-math.cos(theta),.31)).normalized()
    right=Vector((math.cos(theta),math.sin(theta),0))
    up=normal.cross(right).normalized()
    return center,right,up,normal


EYES={}
def eye(side,x):
    center,right,up,normal=eye_basis(x,1.655)
    def world(u,v,d):
        return center+right*u+up*v+normal*d
    # Complete shallow ellipsoid, with its rear sunk into the real cone shell.
    vertices=[]; faces=[]
    seg,rings=32,12
    for j in range(1,rings):
        phi=math.pi*j/rings
        for i in range(seg):
            a=math.tau*i/seg
            vertices.append(world(.195*math.sin(phi)*math.cos(a), .24*math.cos(phi),.085*math.sin(phi)*math.sin(a)))
    top=len(vertices);vertices.append(world(0,.24,0))
    bottom=len(vertices);vertices.append(world(0,-.24,0))
    for j in range(rings-2):
        for i in range(seg):
            a=j*seg+i
            faces.append((a,j*seg+(i+1)%seg,(j+1)*seg+(i+1)%seg,(j+1)*seg+i))
    for i in range(seg):
        faces.append((top,(i+1)%seg,i))
        a=(rings-2)*seg
        faces.append((bottom,a+i,a+(i+1)%seg))
    sclera=mesh(f"Eye_{side}_sclera",vertices,faces,WHITE)
    pieces=[sclera]
    iris_u,iris_v=-x*.19,-.028
    for label,rx,rz,mat,offset in (("iris",.121,.149,BLUE,.003),("pupil",.067,.096,NAVY,.006),("catchlight",.025,.03,WHITE,.013)):
        cu=iris_u-(.032 if label=="catchlight" else 0)
        cv=iris_v+(.055 if label=="catchlight" else 0)
        surface=lambda u,v:.085*math.sqrt(max(.001,1-(u/.195)**2-(v/.24)**2))
        verts=[world(cu,cv,surface(cu,cv)+offset)]; polys=[]
        for j in range(1,5):
            t=j/4
            for i in range(32):
                a=math.tau*i/32;u=cu+rx*t*math.cos(a);v=cv+rz*t*math.sin(a)
                d=surface(u,v)+offset
                verts.append(world(u,v,d))
        for i in range(32):polys.append((0,1+i,1+(i+1)%32))
        for j in range(3):
            for i in range(32):
                a=1+j*32+i;b=1+j*32+(i+1)%32
                polys.append((a,a+32,b+32,b))
        pieces.append(mesh(f"Eye_{side}_{label}",verts,polys,mat))
    # A sculpted orange cap actually covers the white dome when blinking.
    lid_vertices=[]; lid_faces=[]; closed_vertices=[]
    for j in range(6):
        t=j/5
        for i in range(25):
            u=.195*(-.995+1.99*i/24)
            half=math.sqrt(max(.00001,1-(u/.195)**2))
            v=(.165*(1-t)+.24*t)*half
            d=.085*math.sqrt(max(.00001,1-(u/.195)**2-(v/.24)**2))+.014
            lid_vertices.append(world(u,v,d))
            closed_v=(-.24*(1-t)+.24*t)*half
            closed_d=.085*math.sqrt(max(.00001,1-(u/.195)**2-(closed_v/.24)**2))+.02
            closed_vertices.append(world(u,closed_v,closed_d))
    for j in range(5):
        for i in range(24):
            a=j*25+i;lid_faces.append((a,a+1,a+26,a+25))
    eyelid=mesh(f"Eye_{side}_upper_lid",lid_vertices,lid_faces,ORANGE)
    pieces.append(eyelid)
    eyelid.shape_key_add(name="Basis")
    blink=eyelid.shape_key_add(name="BlinkLeft" if side=="L" else "BlinkRight")
    for point,closed in zip(blink.data,closed_vertices):point.co=closed
    eyelid["face_control"]=blink.name
    crease=[]
    for i in range(17):
        u=-.17+.34*i/16
        v=.005+.025*(1-(u/.17)**2)
        d=.085*math.sqrt(max(.001,1-(u/.195)**2-(v/.24)**2))+.033
        crease.append(world(u,v,d)-normal*.24)
    seam=tube(f"Eye_{side}_blink_crease",crease,
              [.003+.003*math.sin(math.pi*i/16) for i in range(17)],BROWN,6)
    seam.shape_key_add(name="Basis")
    seam_blink=seam.shape_key_add(name=blink.name)
    for original,point in zip(seam.data.vertices,seam_blink.data):point.co=original.co+normal*.24
    pieces.append(seam)
    EYES[side]=(center,pieces)
    # A simple soft eyebrow with a tapered cross-section, attached to the cone.
    brow=[]
    for i in range(17):
        t=i/16; xx=x+(t-.5)*.23
        zz=1.94+.035*math.sin(math.pi*t)+.018*(t if side=="L" else 1-t)
        brow.append(on_cone(xx,zz,.024))
    tube(f"Brow_{side}",brow,[.009+.014*math.sin(math.pi*i/16) for i in range(17)],BROWN,8)


eye("L",-.263)
eye("R",.263)

# Rounded limbs contain real vertex weights across the elbow and wrist.
ARM_POINTS={
    "L":[Vector(p) for p in [(-.59,0,1.25),(-.93,-.01,1.22),(-1.06,-.07,1.08),(-1.08,-.14,.98)]],
    "R":[Vector(p) for p in [(.59,0,1.3),(.95,-.01,1.25),(1.10,-.04,1.41),(1.15,-.09,1.57)]],
}
ARMS={}; GLOVES={}
for side,control in ARM_POINTS.items():
    curve=[]
    for i in range(17):
        t=i/16
        curve.append((1-t)**3*control[0]+3*(1-t)**2*t*control[1]+3*(1-t)*t*t*control[2]+t**3*control[3])
    ARMS[side]=tube(f"Arm_{side}_smooth",curve,[.083-.012*i/16 for i in range(17)],ORANGE,12)
    direction=Vector((.26 if side=="R" else -.18,-.10,1 if side=="R" else -1)).normalized()
    rotation=Vector((0,0,1)).rotation_difference(direction)
    palm,cuff=make_glove(f"Glove_{side}",control[3],rotation,WHITE,WHITE,thumb_side=-1 if side=="R" else 1)
    for obj in (palm,cuff):
        bpy.context.view_layer.objects.active=obj
        decimate=obj.modifiers.new("Mobile_geometry_budget","DECIMATE")
        decimate.ratio=.8 if obj==palm else .5
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        apply(obj)
        ASSETS.append(obj)
    GLOVES[side]=(palm,cuff,direction)

# A real Armature, exported as glTF skin joints, not just grouped scene objects.
armature_data=bpy.data.armatures.new("Cone_mascot_skeleton")
rig=bpy.data.objects.new("Mascot_Rig",armature_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
def bone(name,head,tail,parent=None):
    item=armature_data.edit_bones.new(name)
    item.head,item.tail=head,tail
    if parent:item.parent=armature_data.edit_bones[parent]
    return item
bone("Root",(0,0,0),(0,0,.24))
bone("Body",(0,0,.24),(0,0,1.8),"Root")
bone("Tip",(0,0,1.8),(0,0,2.74),"Body")
for side,control in ARM_POINTS.items():
    bone(f"UpperArm_{side}",control[0],control[1],"Body")
    bone(f"Forearm_{side}",control[1],control[3],f"UpperArm_{side}")
    wrist=control[3]; direction=GLOVES[side][2]
    bone(f"Hand_{side}",wrist,wrist+direction*.32,f"Forearm_{side}")
    center=EYES[side][0]
    bone(f"Eye_{side}",center,center+Vector((0,-.2,0)),"Body")
bpy.ops.object.mode_set(mode="OBJECT")
rig.show_in_front=True
rig["controls"]="Root, Body, Tip, UpperArm_L/R, Forearm_L/R, Hand_L/R, Eye_L/R"
rig["facial_morphs"]="BlinkLeft, BlinkRight, Smile"


def skin(obj,weights):
    groups={name:obj.vertex_groups.new(name=name) for name in weights}
    for vertex in obj.data.vertices:
        values=[max(0,float(fn(vertex.co))) for fn in weights.values()]
        total=sum(values)
        for group,value in zip(groups.values(),values):
            if value:group.add([vertex.index],value/total,"REPLACE")
    mod=obj.modifiers.new("Mascot_skin","ARMATURE")
    mod.object=rig
    # Scene-root skinned mesh nodes avoid non-root skin warnings in glTF.


for obj in ASSETS:
    if obj==BASE_OBJ:
        skin(obj,{"Root":lambda p:1})
    elif obj==BODY:
        tip=lambda p:max(0,min(1,(p.z-1.8)/.8))
        skin(obj,{"Body":lambda p:1-tip(p),"Tip":tip})
    elif obj in ARMS.values():
        side=next(k for k,v in ARMS.items() if v==obj)
        start,end=ARM_POINTS[side][0],ARM_POINTS[side][3]
        progress=lambda p:max(0,min(1,(abs(p.x)-abs(start.x))/(abs(end.x)-abs(start.x))))
        blend=lambda p:max(0,min(1,(progress(p)-.25)/.55))
        skin(obj,{f"UpperArm_{side}":lambda p:1-blend(p),f"Forearm_{side}":blend})
    elif any(obj in value[:2] for value in GLOVES.values()):
        side=next(k for k,v in GLOVES.items() if obj in v[:2])
        skin(obj,{f"Hand_{side}":lambda p:1})
    elif obj.name.startswith("Eye_"):
        side=obj.name.split("_")[1]
        skin(obj,{f"Eye_{side}":lambda p:1})
    else:
        skin(obj,{"Body":lambda p:1})
    if obj in (BODY,CAVITY,TOOTH,TONGUE,LIP):
        obj.shape_key_add(name="Basis")
        smile=obj.shape_key_add(name="Smile")
        for original,point in zip(obj.data.vertices,smile.data):
            p=original.co
            if 1.06<p.z<1.46 and p.y<-.3 and abs(p.x)<.31:
                influence=max(0,1-abs(p.z-1.29)/.23)
                point.co.z+=.035*(abs(p.x)/.31)**2*influence

# The authoring scene keeps a studio camera and real lights; GLB exports only
# the selected rig and meshes, never the studio or background.
scene=bpy.context.scene
scene.render.engine="CYCLES"
scene.cycles.samples=48
scene.cycles.use_denoising=True
scene.render.resolution_x=1000
scene.render.resolution_y=1000
scene.render.resolution_percentage=100
scene.render.film_transparent=True
scene.world.color=(.22,.22,.22)
scene.view_settings.view_transform="AgX"
scene.view_settings.look="AgX - Medium High Contrast"
scene.view_settings.exposure=-.25
def light(name,location,power,size,color):
    data=bpy.data.lights.new(name,"AREA")
    data.energy,data.shape,data.size,data.color=power,"DISK",size,color
    obj=bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.location=location
    obj.rotation_euler=(Vector((0,0,1.3))-obj.location).to_track_quat("-Z","Y").to_euler()
light("Studio_key",(-3.5,-4.5,6),550,4,(1,.91,.8))
light("Studio_fill",(4,-2,3.4),300,3,(.72,.84,1))
light("Studio_rim",(1,3,4.5),450,3,(1,.93,.82))
camera_data=bpy.data.cameras.new("Approval_camera")
camera=bpy.data.objects.new("Approval_camera",camera_data)
scene.collection.objects.link(camera)
camera.location=(3.5,-8,3.8)
camera.rotation_euler=(Vector((0,0,1.38))-camera.location).to_track_quat("-Z","Y").to_euler()
camera_data.type="ORTHO"
camera_data.ortho_scale=3.65
scene.camera=camera
scene.render.filepath=str(REVIEW/"real-3d-model.png")

bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
for obj in ASSETS:obj.select_set(True)
bpy.context.view_layer.objects.active=rig
scene["asset_stage"]="Static model approval; no loading animation or application integration."
scene["rebuild"]="tools/mascot/build_model.py + blender_parts.py; Blender 4.5 LTS"
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/"cone-mascot.blend"),compress=True)
bpy.ops.export_scene.gltf(filepath=str(OUT/"cone-mascot.glb"),export_format="GLB",
    use_selection=True,export_animations=False,export_skins=True,export_morph=True,
    export_morph_normal=True,export_cameras=False,export_lights=False,
    export_apply=False,export_extras=True,export_yup=True,export_texcoords=False)
stats={"mesh_objects":len(ASSETS),"joints":len(rig.data.bones),
       "triangles":sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in ASSETS),
       "materials":len({slot.material.name for o in ASSETS for slot in o.material_slots if slot.material}),"textures":0,
       "glb_bytes":(OUT/"cone-mascot.glb").stat().st_size,
       "morph_controls":["BlinkLeft","BlinkRight","Smile"],
       "animations":[],"source":"Blender 4.5 LTS; real geometry + Armature"}
(OUT/"model-info.json").write_text(json.dumps(stats,indent=2)+"\n")
print("MASCOT_MODEL",json.dumps(stats))
if "--render" in sys.argv:
    bpy.ops.render.render(write_still=True)
