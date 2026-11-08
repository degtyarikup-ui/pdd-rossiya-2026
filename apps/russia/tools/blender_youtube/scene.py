"""Blender 5: a street-level, editable 82-second driving film.

Run from repository main: Blender -b --python apps/russia/tools/blender_youtube/scene.py
-- --preview. All geometry, cameras, lights and animation are stored in the blend.
"""
import bpy, bmesh, math, json, random, sys, argparse
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/blender_youtube/pilot_001'
OUT.mkdir(parents=True,exist_ok=True)
parser=argparse.ArgumentParser()
parser.add_argument('--preview',action='store_true')
parser.add_argument('--render',action='store_true')
parser.add_argument('--samples',type=int,default=48)
parser.add_argument('--cpu',action='store_true')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
random.seed(39)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
S=bpy.context.scene
S.render.engine='CYCLES'
S.cycles.samples=args.samples;S.cycles.use_denoising=True
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type='METAL';prefs.get_devices()
    for device in prefs.devices: device.use=device.type=='METAL'
    S.cycles.device='GPU'
except Exception: pass
if args.cpu:S.cycles.device='CPU'
S.cycles.max_bounces=6;S.cycles.diffuse_bounces=3;S.cycles.glossy_bounces=3
S.render.resolution_x=1920;S.render.resolution_y=1080
S.render.resolution_percentage=100;S.render.fps=24
S.render.threads_mode='FIXED';S.render.threads=4
S.frame_start=1;S.frame_end=82*24
S.render.image_settings.file_format='PNG';S.render.image_settings.color_mode='RGB'
S.render.film_transparent=False
S.view_settings.view_transform='AgX'
S.view_settings.look='AgX - Medium High Contrast'
S.view_settings.exposure=.1
S.render.use_file_extension=True

def rgb(h):
    c=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<.04045 else ((v+.055)/1.055)**2.4 for v in c)
def mat(name,color,rough=.5,metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*rgb(color),1)
    p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
    return m
def noise_mat(name,color,scale,rough=.7,strength=.1):
    m=mat(name,color,rough);n=m.node_tree.nodes;l=m.node_tree.links
    tex=n.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=scale
    coord=n.new('ShaderNodeTexCoord');l.new(coord.outputs['Object'],tex.inputs['Vector'])
    tex.inputs['Detail'].default_value=3
    bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=strength
    bump.inputs['Distance'].default_value=.045
    l.new(tex.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs['Normal'],n.get('Principled BSDF').inputs['Normal'])
    return m
asphalt=noise_mat('Dry asphalt • fine aggregate','444951',170,.88,.25)
concrete=noise_mat('Warm limestone curb','c4bfb3',36,.8,.17)
pavers=noise_mat('Sandstone pavement','c5bbaa',45,.85,.12)
grass=noise_mat('Grass lawn','677849',65,.86,.25)
earth=mat('Tree pit soil','493e2e',1)
ivory=mat('Painted warm white','eee7d7',.53)
trim=mat('Window frames / charcoal','293b42',.36,.35)
glass=mat('Architectural blue glass','78979b',.23,.42)
dark=mat('Road furniture graphite','263137',.4,.65)
wood=noise_mat('Oiled timber','895638',6,.48,.12)
mark=mat('Lane paint aged ivory','dfd8bd',.8)
leafm=[mat('Leaf '+str(i),c,.8) for i,c in enumerate(['738642','617c3c','84964c','a5ac5c','436746'])]
facades=[noise_mat('Facade '+str(i),c,11,.85,.08) for i,c in enumerate(['bd775a','d6c2a1','6d9592','d4aa73','a0a995','c9c4b8'])]
roof=mat('Zinc roofs','505e63',.56,.4)
redmat=mat('Vermilion pearl clearcoat','c52e24',.24,.55)
bluemat=mat('Ocean blue clearcoat','195d9b',.22,.55)
for m in [redmat,bluemat]:
    m.node_tree.nodes.get('Principled BSDF').inputs['Coat Weight'].default_value=.45
    m.node_tree.nodes.get('Principled BSDF').inputs['Coat Roughness'].default_value=.18
rubber=noise_mat('Satin rubber','161b20',85,.7,.2)
chrome=mat('Brushed alloy','abb2b9',.23,.82)
carglass=mat('Smoked automotive glass','b7c9d2',.055,0)
carglass.node_tree.nodes.get('Principled BSDF').inputs['Transmission Weight'].default_value=.97
carglass.node_tree.nodes.get('Principled BSDF').inputs['IOR'].default_value=1.45
# Treat the original window shell as thin laminated glass, not a solid cabin volume.
gn=carglass.node_tree.nodes;gl=carglass.node_tree.links;gp=gn.get('Principled BSDF')
gp.inputs['Transmission Weight'].default_value=0;gp.inputs['Metallic'].default_value=1
transparent=gn.new('ShaderNodeBsdfTransparent');transparent.inputs[0].default_value=(.92,.96,1,1)
gmix=gn.new('ShaderNodeMixShader');gmix.inputs[0].default_value=.06
gl.new(transparent.outputs[0],gmix.inputs[1]);gl.new(gp.outputs[0],gmix.inputs[2]);gl.new(gmix.outputs[0],gn.get('Material Output').inputs['Surface'])
lamp=mat('Headlamp lenses','f4f7fa',.035,0)
lamp.node_tree.nodes.get('Principled BSDF').inputs['Transmission Weight'].default_value=1
lamp.node_tree.nodes.get('Principled BSDF').inputs['IOR'].default_value=1.45
stop=mat('Ruby tail lamp','9f1710',.25,.2)
amber=mat('Amber indicators','ed8216',.26)
amberlit=mat('Indicator illuminated','ffa322',.2)
amberlit.node_tree.nodes.get('Principled BSDF').inputs['Emission Color'].default_value=(*rgb('ff9e19'),1)
amberlit.node_tree.nodes.get('Principled BSDF').inputs['Emission Strength'].default_value=4

def cube(name,loc,scale,material,bevel=0):
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata([(x*scale[0]/2,y*scale[1]/2,z*scale[2]/2) for x,y,z in [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]],[],[tuple(reversed(f)) for f in [(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]])
    o=bpy.data.objects.new(name,mesh);S.collection.objects.link(o);o.location=loc
    o.data.materials.append(material)
    if bevel:
        b=o.modifiers.new('Soft manufactured edges','BEVEL');b.width=bevel;b.segments=3
        b=o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o
def cyl(name,loc,radius,depth,material,vertices=24):
    mesh=bpy.data.meshes.new(name)
    vs=[(radius*math.cos(i*math.tau/vertices),radius*math.sin(i*math.tau/vertices),z*depth/2) for z in [-1,1] for i in range(vertices)]
    faces=[tuple(reversed(range(vertices))),tuple(range(vertices,2*vertices))]+[(i,(i+1)%vertices,(i+1)%vertices+vertices,i+vertices) for i in range(vertices)]
    mesh.from_pydata(vs,[],faces)
    o=bpy.data.objects.new(name,mesh);S.collection.objects.link(o);o.location=loc;o.data.materials.append(material)
    b=o.modifiers.new('Edge highlights','BEVEL');b.width=.015;b.segments=2
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o
def bar(name,a,b,r,material):
    a,b=Vector(a),Vector(b);o=cyl(name,(a+b)/2,r,(b-a).length,material)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def ico(name,loc,scale,material,sub=2):
    if name=='Leaf cluster':
        # Thin leaves with a central fold; airy silhouettes and dappled shadows.
        rng=random.Random(round(loc[0]*500+loc[1]*70+loc[2]*900))
        verts=[];faces=[]
        for j in range(125):
            p=Vector(tuple(rng.uniform(-1,1)*s for s in scale))
            if sum((p[i]/scale[i])**2 for i in range(3))>1.1:continue
            a=rng.uniform(0,math.tau);tilt=rng.uniform(-.8,.8)
            u=Vector((math.cos(a),math.sin(a),tilt)).normalized()
            v=Vector((-math.sin(a),math.cos(a),0))
            length=rng.uniform(.16,.26);width=length*.43
            points=[p-u*length/2,p-u*length*.16+v*width/2,p+u*length*.25+v*width*.4,p+u*length/2,p+u*length*.25-v*width*.4,p-u*length*.16-v*width/2,p+Vector((0,0,.015))]
            k=len(verts);verts.extend(points)
            faces.extend([(k+6,k+i,k+(i+1)%6) for i in range(6)])
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces)
        o=bpy.data.objects.new(name,mesh);S.collection.objects.link(o);o.location=loc;mesh.materials.append(material)
        return o
    bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=sub,radius=1)
    mesh=bpy.data.meshes.new(name);bm.to_mesh(mesh);bm.free()
    o=bpy.data.objects.new(name,mesh);S.collection.objects.link(o);o.location=loc;o.scale=scale;o.data.materials.append(material)
    for p in o.data.polygons:p.use_smooth=True
    return o

# A continuous T junction. The road ends in front of the driver, exactly as in AB 39/14.
cube('Ground',(0,0,-.45),(220,200,.6),grass)
cube('East–west carriageway',(0,0,-.11),(180,8,.22),asphalt)
cube('South approach',(0,-47,-.112),(8,86,.22),asphalt)
cube('North sidewalk',(0,6,-.02),(180,4,.4),pavers,.06)
cube('West south sidewalk',(-49,-6,-.02),(86,4,.4),pavers,.06)
cube('East south sidewalk',(49,-6,-.02),(86,4,.4),pavers,.06)
for x in [-6,6]:cube('Approach sidewalk',(x,-49,-.02),(4,82,.4),pavers,.02)
# Individually jointed curb stones, tiny bevels catch the low sun.
for x in range(-88,89):
    cube('North curb',(x,4.1,.13),(.975,.22,.3),concrete,.025)
    if abs(x)>5:cube('South curb',(x,-4.1,.13),(.975,.22,.3),concrete,.025)
for y in range(-89,-5):
    for x in [-4.1,4.1]:cube('Approach curb',(x,y,.13),(.22,.975,.3),concrete,.025)
# Quiet paved forecourts; no signs or zebra crossings that could change the question.
for x in range(-80,81,5):
    if abs(x)>8:cube('Centre dash',(x,0,.001),(2.3,.1,.0015),mark)
for y in range(-86,-10,5):cube('Approach centre dash',(0,y,.001),(.1,2.3,.0015),mark)
for side in [-1,1]:
    cube('Corner sidewalk infill',(side*5,-7,-.02),(2,2,.4),pavers)
    cube('Corner asphalt',(side*5,-5,-.09),(2,2,.18),asphalt)
    vs=[(side*6,-6,.18)]+[(side*(6-2*math.cos(i*math.pi/2/20)),-6+2*math.sin(i*math.pi/2/20),.18) for i in range(21)]
    mesh=bpy.data.meshes.new('Rounded sidewalk corner');mesh.from_pydata(vs,[],[(0,i+2,i+1) if side==1 else (0,i+1,i+2) for i in range(20)])
    o=bpy.data.objects.new('Rounded sidewalk corner',mesh);S.collection.objects.link(o);mesh.materials.append(pavers)
    for a,b in zip(vs[1:-1],vs[2:]):
        mid=(Vector(a)+Vector(b))/2
        c=cube('Curved curb segment',(mid.x,mid.y,.13),((Vector(a)-Vector(b)).length+.012,.22,.3),concrete,.018)
        c.rotation_euler.z=math.atan2(b[1]-a[1],b[0]-a[0])
# Pavement joints read in close street shots without noisy textures.
joint=mat('Paving joints','a99e8d',1)
for x in range(-45,46):cube('Paving seam north',(x,6,.185),(.014,3.55,.008),joint)
for y in range(-48,-6):
    for x in [-6,6]:cube('Paving seam approach',(x,y,.185),(3.55,.014,.008),joint)
for x in [-6.65,-5.35,5.35,6.65]:cube('Long paving seam',(x,-28,.186),(.014,42,.008),joint)

font=bpy.data.fonts.load(str(ROOT/'assets/fonts/Onest-Medium.ttf'))
def text_wall(body,loc,size,material,rotation=(math.pi/2,0,0)):
    c=bpy.data.curves.new(body,'FONT');c.body=body;c.font=font;c.size=size;c.align_x='CENTER';c.extrude=.002
    o=bpy.data.objects.new(body,c);S.collection.objects.link(o);o.location=loc;o.rotation_euler=rotation;c.materials.append(material);return o

def building(name,x,y,w,d,h,index,front=True):
    facade=facades[index%len(facades)]
    cube(name,(x,y,h/2+.18),(w,d,h),facade,.085)
    cube(name+' base',(x,y,.15),(w+.1,d+.1,.75),concrete,.03)
    cube(name+' cornice',(x,y,h-.22),(w+.3,d+.3,.28),ivory,.035)
    cube(name+' flat roof',(x,y,h+.02),(w+.2,d+.2,.2),roof,.03)
    # Parapets and discreet rooftop plant.
    for yy in [y-d/2,y+d/2]:cube('Parapet',(x,yy,h+.35),(w,.17,.6),facade,.025)
    cube('Rooftop ventilation',(x+w*.2,y,h+.55),(1.35,1.2,.8),roof,.04)
    cols=max(2,int(w/2.35));floors=max(2,int(h/2.95))
    for face in ['south','west','east']:
        span=w if face=='south' else d
        nc=max(2,int(span/2.35))
        for floor in range(floors):
            z=1.9+floor*2.75
            if z+1>h-.4:continue
            for c in range(nc):
                a=-span/2+(c+.5)*span/nc
                if face=='south':loc=(x+a,y-d/2-.035,z);dims=(1.22,.095,1.7)
                else:loc=(x+(-1 if face=='west' else 1)*(w/2+.035),y+a,z);dims=(.095,1.22,1.7)
                cube('Window reveal',loc,tuple(v+.16 if v>.2 else v+.03 for v in dims),ivory,.025)
                v=Vector(loc);v.y-=.065 if face=='south' else 0;v.x+=(-.065 if face=='west' else .065) if face!='south' else 0
                cube('Reflective window',v,dims,glass,.025)
                if face=='south':
                    cube('Window centre mullion',(v.x,v.y-.06,z),(.045,.045,1.7),trim,.005)
                    cube('Window sill',(v.x,v.y-.08,z-.9),(1.45,.3,.09),ivory,.015)
                else:cube('Window centre mullion',(v.x+(-.06 if face=='west' else .06),v.y,z),(.045,.045,1.7),trim,.005)
        if face=='south':
            for z in [3.1,5.95,8.7]:
                if z<h-.5:cube('Facade string course',(x,y-d/2-.11,z),(w+.1,.17,.1),ivory,.02)
    if front:
        # Ground-floor shop frontage with glazed door and striped canopy.
        sy=y-d/2-.16
        for dx in [-w*.29,0,w*.29]:cube('Shopfront',(x+dx,sy,1.6),(w*.22,.12,2.45),glass,.03)
        cube('Shop signboard',(x,sy-.15,3.25),(w*.87,.18,.65),trim,.03)
        text_wall(['АТЕЛЬЕ','КОФЕ','КНИГИ','ЦВЕТЫ'][index%4],(x,sy-.26,3.08),.35,ivory)
        for k in range(int(w/.45)):
            a=x-w/2+(k+.5)*.45
            o=cube('Canvas canopy',(a,sy-.75,2.75),(.43,1.4,.07),ivory if k%2 else facade,.015);o.rotation_euler.x=.12

for i,(x,w,h) in enumerate([(-41,12,14),(-28,12,11),(-15,12,13),(-1,14,10),(14,13,12),(28,12,15),(42,13,11)]):
    building('North block '+str(i),x,14,w,11,h,i)
for side in [-1,1]:
    for i,y in enumerate([-17,-32,-48,-65]):
        building('Approach block',side*16,y,13,12,9+(i%3)*3,(i+2+(side==1))%6,False)
# Far city silhouettes close sightlines along the cross street.
for side in [-1,1]:
    for i in range(5):building('Distant block',side*(57+i*13),13,12,12,10+i%3*3,i,False)
print('Architecture built:',len(bpy.data.objects),'objects',flush=True)

def tree(x,y,seed):
    rng=random.Random(seed);height=rng.uniform(5.3,6.8)
    cyl('Tree soil well',(x,y,.19),.85,.025,earth)
    trunk=noise_mat('Tree bark '+str(seed),'655747',13,.9,.3)
    bar('Tree trunk',(x,y,.2),(x+.15,y,height*.65),.15,trunk)
    for i in range(7):
        a=i*math.tau/7+rng.uniform(-.2,.2);r=rng.uniform(.65,1.45)
        end=(x+math.cos(a)*r,y+math.sin(a)*r,height*.7+rng.uniform(-.3,1))
        bar('Branch',(x+.1,y,height*.45),end,.055,trunk)
        # Clusters of fine lobes, not white architectural blobs.
        for j in range(8):
            p=(end[0]+rng.uniform(-.75,.75),end[1]+rng.uniform(-.75,.75),end[2]+rng.uniform(-.45,.65))
            ico('Leaf cluster',p,(rng.uniform(.55,.9),rng.uniform(.55,.9),rng.uniform(.65,.95)),rng.choice(leafm))
for i,(x,y) in enumerate([(-33,6),(-21,6),(-9,6),(9,6),(24,6),(38,6),(-6,-22),(6,-25),(-6,-39),(6,-45),(-33,-6),(29,-6)]):tree(x,y,100+i)

def street_lamp(x,y,arm_sign=1):
    cyl('Streetlamp base',(x,y,.4),.18,.45,dark)
    bar('Streetlamp upright',(x,y,.2),(x,y,6.7),.075,dark)
    bar('Streetlamp arm',(x,y,6.7),(x,y-arm_sign*1.5,6.7),.065,dark)
    cube('LED lantern',(x,y-arm_sign*1.4,6.64),(.52,.85,.12),dark,.08)
    cube('LED diffuser',(x,y-arm_sign*1.4,6.57),(.38,.68,.025),ivory,.03)
for x in [-39,-15,17,42]:street_lamp(x,7.35)
for x in [-7.35,7.35]:
    for y in [-16,-44]:street_lamp(x,y,-1)
def bench(x,y):
    for dx in [-.8,.8]:
        cube('Bench leg',(x+dx,y,.47),(.08,.5,.55),dark,.025)
        bar('Bench back support',(x+dx,y+.17,.5),(x+dx,y+.4,1.05),.035,dark)
    for i in range(4):cube('Bench seat',(x,y-.22+i*.14,.72),(2,.115,.06),wood,.02)
    for i in range(3):cube('Bench back',(x,y+.36,.87+i*.12),(2,.07,.1),wood,.018)
for x in [-17,19]:bench(x,6.25)
for x in [-12,12]:
    cube('Planter',(x,6.3,.5),(1.8,.8,.65),concrete,.08)
    for k in range(6):ico('Planter shrub',(x-.7+k*.28,6.3,1.02),(.36,.34,.42),leafm[k%5])
for x in [-26,33]:
    cyl('Litter bin',(x,6,.65),.28,.9,dark)
    cyl('Bin rim',(x,6,1.11),.3,.05,chrome)
print('Street and trees built',flush=True)

# Detailed external cars; sources and licences are recorded in assets.json.
def detailed_vehicle(kind,name,paint):
    parent=bpy.data.objects.new(name,None);S.collection.objects.link(parent)
    if kind=='bmw':
        with bpy.data.libraries.load(str(OUT/'assets/bmw_prepared.blend'),link=False) as (source,dest):dest.objects=source.objects
        imported=[o for o in dest.objects if o]
        for o in imported:S.collection.objects.link(o)
    else:
        before=set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(OUT/'assets/ferrari.glb'))
        imported=list(set(bpy.data.objects)-before)
    imported_set=set(imported)
    wheels=[]
    for o in imported:
        if o.parent not in imported_set:
            o.parent=parent
            if kind=='ferrari':o.matrix_basis=Matrix.Rotation(math.pi,4,'Z')@o.matrix_basis
        original_name=o.name
        if (kind=='bmw' and o.name.startswith('wheel_Tire')) or (kind=='ferrari' and o.name in ['wheel_fl','wheel_fr','wheel_rl','wheel_rr']):wheels.append(o)
        if o.type=='MESH':
            for slot in o.material_slots:
                label=slot.material.name.lower() if slot.material else ''
                if 'carshell' in label or 'body_color' in label:slot.material=paint
                elif 'glass' in label:
                    slot.material=carglass if ('window' in original_name.lower() or 'glass_gray' in label) else lamp
                elif 'tire' in label:slot.material=rubber
                elif 'chrome' in label or 'silver' in label:slot.material=chrome
                elif 'taillight' in label or 'tailight' in label:slot.material=stop
                elif 'black' in label or 'plastic' in label:slot.material=dark
                elif 'interior' in label or 'leather' in label or 'carpet' in label:slot.material=dark
        o.name=name+' / '+original_name
    indicators=[]
    if kind=='bmw':
        source=next(o for o in imported if o.type=='MESH' and o.name.endswith('/ BMW / lightsBulb'))
        mesh=source.data.copy();bm=bmesh.new();bm.from_mesh(mesh)
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.x<=0],context='VERTS');bm.to_mesh(mesh);bm.free()
        o=bpy.data.objects.new('Integrated left indicator',mesh);S.collection.objects.link(o);o.parent=parent;o.location.y=-.003
        indicators.append(o)
    parent.rotation_euler.z=math.pi
    return parent,wheels,indicators
red,rw,rb=detailed_vehicle('bmw','RED • driver',redmat)
blue,bw,bb=detailed_vehicle('ferrari','BLUE • right priority',bluemat)
wheel_bases={w:w.matrix_basis.to_euler('XYZ') for w in rw+bw}
for w in rw+bw:
    w.rotation_mode='XYZ'
    w.rotation_euler=wheel_bases[w]
print('Cars imported',flush=True)

# World lighting: broad sky fill, low warm sun, a large soft reflection source.
world=bpy.data.worlds.new('Late-afternoon clear sky');world.use_nodes=True;S.world=world
n=world.node_tree.nodes;l=world.node_tree.links
sky=n.new('ShaderNodeTexSky');sky.sky_type='MULTIPLE_SCATTERING';sky.sun_elevation=math.radians(26);sky.sun_rotation=math.radians(138)
sky.altitude=.15;sky.air_density=1.1
if hasattr(sky,'aerosol_density'):sky.aerosol_density=1.6
l.new(sky.outputs['Color'],n.get('Background').inputs['Color']);n.get('Background').inputs['Strength'].default_value=.22
bpy.ops.object.light_add(type='SUN',location=(10,-15,20));sun=bpy.context.object;sun.name='Warm afternoon key';sun.data.energy=2.3;sun.data.angle=math.radians(4)
sun.rotation_euler=(math.radians(44),math.radians(-22),math.radians(-35));sun.data.color=(1,.86,.7)
bpy.ops.object.light_add(type='AREA',location=(-7,-7,11));fill=bpy.context.object;fill.name='Soft sky reflection';fill.data.energy=1500;fill.data.shape='DISK';fill.data.size=12;fill.data.color=(.72,.84,1)
fill.rotation_euler=(Vector((0,-4,0))-fill.location).to_track_quat('-Z','Y').to_euler()

def smooth(v):return max(0,min(1,v))**2*(3-2*max(0,min(1,v)))
def redpose(t):
    if t<18:return (2,-34+26*smooth(t/18)),0
    if t<62:return (2,-8),0
    d=27*smooth((t-62)/10) if t<72 else 27+3*(t-72)
    if d<5:return (2,-8+d),0
    if d<5+math.pi*2.5:
        a=(d-5)/5;return (-3+5*math.cos(a),-3+5*math.sin(a)),a
    return (-3-(d-5-math.pi*2.5),2),math.pi/2
def bluepose(t):
    if t<21:return (27-16*smooth(t/21),2),math.pi/2
    if t<53:return (11,2),math.pi/2
    x=11-45*smooth((t-53)/9) if t<62 else -34-4*(t-62)
    return (x,2),math.pi/2
def camera(name,lens):
    data=bpy.data.cameras.new(name);data.lens=lens;data.sensor_width=36
    data.clip_end=500;data.dof.use_dof=True;data.dof.aperture_fstop=4.5
    o=bpy.data.objects.new(name,data);S.collection.objects.link(o)
    target=bpy.data.objects.new(name+' focus',None);S.collection.objects.link(target);data.dof.focus_object=target
    return o,target
# Every camera stays between 0.6 and 3.2 m: no overhead or diagram shots.
shots=[
    (0,6,'01 • travelling hero',42),
    (6,12,'02 • follow to junction',38),
    (12,18,'03 • indicator / approach',55),
    (18,25,'04 • street establishing',32),
    (25,32,'05 • blue arrival portrait',60),
    (32,42,'06 • equal roads',32),
    (42,53,'07 • driver looks right',32),
    (53,59,'08 • blue crosses',42),
    (59,62,'09 • red waits',65),
    (62,68,'10 • left turn',35),
    (68,74,'11 • follow through',45),
    (74,82,'12 • departure',55),
]
cams=[]
for a,b,name,lens in shots:
    c,target=camera(name,lens);cams.append((c,target))
    marker=S.timeline_markers.new(name,frame=round(a*24)+1);marker.camera=c
S.camera=cams[0][0]
def view(i,t):
    (rx,ry),ra=redpose(t);(bx,by),ba=bluepose(t)
    if i==0:return (rx-5.8,ry+6.8,1.15),(rx,ry,.85)
    if i==1:return (rx-4.9,ry-7,2.4),(rx,ry+3,1.05)
    if i==2:return (rx-3.2,ry+4.8,1.05),(rx,ry+.8,.85)
    if i==3:return (-8.8+.6*smooth((t-18)/7),-14,2.5),(4,-3.5,1.2)
    if i==4:return (bx-7+.6*smooth((t-25)/7),by-4.2,1.3),(bx,by,.75)
    if i==5:return (-8+.8*smooth((t-32)/10),-12,2.5),(3.5,-.5,1.25)
    if i==6:
        u=smooth((t-42)/2);return (1.62,-8.15,1.16),(3+8*u,3-u,1.1)
    if i==7:return (bx-6,by-6.5,1.15),(bx,by,.9)
    if i==8:return (-2.8,-3.8,1.35),(2,-8,.9)
    if i==9:return (-10,-10,2.6),(rx,ry,1)
    if i==10:return (rx+7,ry-4.5,1.6),(rx-1,ry,1)
    return (-15,-4,1.15),(rx,ry,.95)

prev_r=prev_b=None;rd=bd=0
print('Baking directed animation',flush=True)
for frame in range(1,S.frame_end+1):
    t=(frame-1)/24
    for obj,wheels,pose,isred in [(red,rw,redpose(t),True),(blue,bw,bluepose(t),False)]:
        (x,y),angle=pose
        obj.location=(x,y,.03);obj.rotation_euler.z=math.pi+angle
        obj.keyframe_insert('location',frame=frame);obj.keyframe_insert('rotation_euler',frame=frame)
        prev=prev_r if isred else prev_b
        delta=0 if prev is None else math.dist((x,y),prev)
        if isred:rd+=delta;prev_r=(x,y);dist=rd
        else:bd+=delta;prev_b=(x,y);dist=bd
        for w in wheels:
            w.rotation_euler.x=wheel_bases[w].x+(1 if isred else -1)*dist/(.354 if isred else .36)
            if isred and ('Tire1' in w.name or 'Tire2' in w.name):
                w.rotation_euler.z=.5*smooth((t-64.25)/.5)*(1-smooth((t-67)/.5))
            w.keyframe_insert('rotation_euler',frame=frame)
    for i,(start,end,name,lens) in enumerate(shots):
        if start<=t<=end:
            c,target=cams[i];pos,aim=view(i,t);c.location=pos;target.location=aim
            c.rotation_euler=(Vector(aim)-Vector(pos)).to_track_quat('-Z','Y').to_euler()
            for o in [c,target]:o.keyframe_insert('location',frame=frame)
            c.keyframe_insert('rotation_euler',frame=frame)
# Shared left indicator material: on before stopping, off after completing turn.
for o in rb:
    o.data.materials.clear();o.data.materials.append(amberlit)
    for p in o.data.polygons:p.material_index=0
em=amberlit.node_tree.nodes.get('Principled BSDF').inputs['Emission Strength']
for frame in range(1,S.frame_end+1):
    t=(frame-1)/24;em.default_value=5 if 12<=t<71 and int(t*2.5)%2==0 else 0
    em.keyframe_insert('default_value',frame=frame)

# All constraints and paths are baked for portable editing and rendering.
S.frame_set(1);S.camera=cams[0][0]
S['source_question']='AB • ticket 39 • question 14'
S['rule']='13.11 — yield to traffic approaching from the right at equal-priority junctions'
S['direction']='Street-level cinematic film, colorful city. No overhead shots or countdown.'
S['car_sources']='BMW 1M by Mike Pan, Blender demo; Ferrari 458 Italia by vicent091036, three.js example. See asset credits.'
S.render.filepath=str(OUT/'frames/frame_')
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'pdd_youtube_001.blend'))
manifest={'duration':82,'fps':24,'resolution':[1920,1080],'shots':[{'start':a,'end':b,'name':n,'lens':l} for a,b,n,l in shots]}
(OUT/'shots.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
if args.preview:
    for sec in [3,20,47,65]:
        S.frame_set(round(sec*24)+1)
        for i,(a,b,n,l) in enumerate(shots):
            if a<=sec<b:S.camera=cams[i][0];break
        S.render.filepath=str(OUT/f'preview_{sec:02d}.png')
        bpy.ops.render.render(write_still=True)
if args.render:
    S.render.filepath=str(OUT/'frames/frame_');bpy.ops.render.render(animation=True)
