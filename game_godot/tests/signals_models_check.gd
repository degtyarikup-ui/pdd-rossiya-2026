## Legal silhouettes, original mounting anchors and independent signal sections.
extends SceneTree

var checks:=0
var bad:=0
const SQUARE := ["2.1","2.2","5.5","5.6","5.19.1","5.19.2","5.20","6.8.2","8.1.2","5.15.2","5.15.3","5.15.4","5.15.5","5.15.6","8.13"]

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		bad+=1
		if bad<15:print("FAIL ",label)

func relative(node: Node3D,root_node: Node3D) -> Transform3D:
	var xf:=Transform3D.IDENTITY
	var cursor: Node=node
	while cursor!=root_node and cursor!=null:
		if cursor is Node3D:xf=cursor.transform*xf
		cursor=cursor.get_parent()
	return xf

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var count:=0
	var texture_bytes:=0
	for file in DirAccess.get_files_at("res://signs"):
		if not file.ends_with(".svg"):continue
		count+=1
		var code:=file.trim_suffix(".svg")
		var texture:=SignFace.texture(code)
		check(texture!=null and texture==SignFace.texture(code),code+" official source/cache")
		var raster: Image=texture.get_image()
		texture_bytes+=(texture.atlas.get_image() if texture is AtlasTexture else raster).get_data().size()
		check(raster.has_mipmaps(),code+" mipmaps reduce distant shimmer")
		var visible:=raster.get_used_rect()
		check(maxi(visible.size.x,visible.size.y) in range(254,259),code+" bounded high quality 256px visible face")
		var sign:=RoadBuild.sign_node(code)
		check(sign!=null,code+" complete sign assembly")
		var board:=sign.get_node("sign_board") as Node3D
		var face:=board.get_node("face_top") as MeshInstance3D
		check(face.get_child_count()==0 and face.mesh.get_surface_count()==1,code+" front/reverse in one surface")
		check(face.material_override is ShaderMaterial and (face.material_override as ShaderMaterial).get_shader_parameter("picture")!=null,code+" official image and metal reverse shader")
		var dimensions: Vector2=(face.mesh as QuadMesh).size
		var image: Image=RoadBuild.main_road_plate([]).get_image() if code=="8.13" else texture.get_image()
		var alpha:=image.get_used_rect()
		var physical:=Vector2(alpha.size)*dimensions/Vector2(image.get_size())
		if code in SQUARE:
			check(absf(physical.x/physical.y-1)<.012,code+" actual visible board is square, excluding SVG padding")
		if code in ["3.1","3.24","4.1.1","4.3"]:
			check(absf(physical.x/physical.y-1)<.012,code+" circular aperture not flattened")
		var pole:=sign.get_node("sign_post") as MeshInstance3D
		var cylinder:=pole.mesh as CylinderMesh
		check(cylinder.radial_segments==8 and cylinder.rings==1,code+" mobile support budget")
		check(board.position.is_equal_approx(Vector3(0,2.2,-.16)) and absf(pole.position.z-.09)<.0001,code+" original support/board anchors")
		var other:=RoadBuild.sign_node(code)
		check(face.mesh==(other.get_node("sign_board/face_top") as MeshInstance3D).mesh and face.material_override==(other.get_node("sign_board/face_top") as MeshInstance3D).material_override,code+" immutable mesh/material reused")
		other.free();sign.free()
	check(count==70,"all available signs covered")
	check(texture_bytes<32*1024*1024,"all 67 decoded RGBA textures including mipmaps stay below 32 MiB")
	print("All sign textures with mipmaps: ",texture_bytes," bytes")
	var barrier:=RoadBuild.roadworks_barrier(3)
	var barrier_face:=barrier.get_child(barrier.get_child_count()-1) as MeshInstance3D
	var rect: Vector4=(barrier_face.material_override as ShaderMaterial).get_shader_parameter("outline_rect")
	var size: Vector2=(barrier_face.mesh as QuadMesh).size
	check(absf(size.x*rect.z/(size.y*rect.w)-1)<.012,"roadworks 4.2.2 stays circular despite padded SVG")
	barrier.free()
	var plate:=RoadBuild.main_road_plate(["north","east"],["north","south","east","west"])
	check(plate.get_width()==plate.get_height() and plate==RoadBuild.main_road_plate(["north","east"],["north","south","east","west"]),"square 8.13 and bounded texture cache")
	var pixels:=plate.get_image()
	check(pixels.get_pixel(128,45).r<.1 and pixels.get_pixel(195,128).r<.1,"8.13 thick main road points north/east")
	check(pixels.get_pixel(134,195).r>.9 and pixels.get_pixel(134,45).r<.1,"8.13 thin south versus thick north preserved")
	for kind in ["standard","left","right","straight","tram"]:
		var config:={"arrow":kind if kind in ["left","right","straight"] else null,"tram":"straight" if kind=="tram" else null}
		var light:=TrafficSignal.make(config)
		var duplicate:=TrafficSignal.make(config)
		var meshes:=light.find_children("*","MeshInstance3D",true,false).filter(func(m):return not m.has_meta("signal_glow"))
		var budget:=600 if kind=="tram" else 430 if kind!="standard" else 300
		var triangles:=0
		for mesh: MeshInstance3D in meshes:
			check(mesh.mesh.get_surface_count()==1,kind+" one surface per static body/aperture")
			var arrays:=mesh.mesh.surface_get_arrays(0)
			triangles+=(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3
			check(mesh.mesh==(duplicate.find_child(str(mesh.name),true,false) as MeshInstance3D).mesh,kind+" shared source meshes")
		check(meshes.size()==(8 if kind=="tram" else 4 if kind=="standard" else 5) and triangles<=budget,kind+" geometry and draw budget")
		check(light.find_children("*","Light3D",true,false).is_empty(),kind+" no dynamic lights")
		for state in ["red","yellow","green","flashing_yellow","off"]:
			for tram in ["straight","left","right","stop","all","off"]:
				TrafficSignal.set_state(light,state,tram)
				for name in ["red","yellow","green"]:
					var lamp:=light.find_child("lamp_"+name,true,false) as Node3D
					var aperture:=lamp.find_child("aperture_*",true,false) as MeshInstance3D
					var expected: bool=state==name or (state=="flashing_yellow" and name=="yellow")
					check((aperture.material_override as ShaderMaterial).get_shader_parameter("lit")==expected,kind+" "+state+" separate "+name)
					var halo:=lamp.get_meta("halo") as MeshInstance3D
					check(halo.visible==expected and (halo.material_override as ShaderMaterial).get_shader_parameter("front_only")==true,kind+" only front emits active signal")
					check(relative(lamp,light).origin.is_equal_approx(Vector3(0,3.85 if name=="red" else 3.4 if name=="yellow" else 2.95,.46)),kind+" original aperture centre")
				if kind=="tram":
					var enabled: Array=["bottom","mid"] if tram=="straight" else ["bottom","left"] if tram=="left" else ["bottom","right"] if tram=="right" else ["left","mid","right"] if tram=="stop" else TrafficSignal.TRAM if tram=="all" else []
					for role in TrafficSignal.TRAM:
						var aperture:=light.find_child("aperture_tram_"+role,true,false) as MeshInstance3D
						check((aperture.material_override as ShaderMaterial).get_shader_parameter("lit")==(role in enabled),"T.5 "+tram+" "+role)
		if kind in ["left","right","straight"]:
			var arrow:=light.find_child("lamp_arrow",true,false) as Node3D
			check(arrow.position.x<0 if kind=="left" else arrow.position.x>0,kind+" supplementary section on its proper side")
			var aperture:=arrow.find_child("aperture_arrow",true,false) as MeshInstance3D
			check((aperture.material_override as ShaderMaterial).get_shader_parameter("lit")==true,kind+" authored supplementary arrow remains enabled with main red")
			light.set_meta("arrow_active",false);TrafficSignal.set_state(light,"red")
			check((aperture.material_override as ShaderMaterial).get_shader_parameter("lit")==false,kind+" disabled arrow stays dark")
		light.free();duplicate.free()
	for arrow in ["","left","right","straight"]:
		var mini:=TrafficSignal.make_mini({"arrow":arrow,"arrowActive":true,"state":"red"})
		for name in ["red","yellow","green"]:
			var lamp:=mini.find_child("lamp_"+name,true,false) as Node3D
			check(lamp.position.is_equal_approx(Vector3(0,4.02 if name=="red" else 3.5 if name=="yellow" else 2.98,.42)),"mini original "+name+" centre")
		var duplicate:=TrafficSignal.make_mini({"arrow":arrow,"state":"green"})
		check((mini.find_child("body",true,false) as MeshInstance3D).mesh==(duplicate.find_child("body",true,false) as MeshInstance3D).mesh,"mini cached profile from same canonical source")
		mini.free();duplicate.free()
	# Compare every saved mast and main lamp to its archived local geometry.
	var authored:=0
	for id in DirAccess.get_directories_at("res://situations"):
		var path:="res://situations/%s/scene.json" % id
		if not FileAccess.file_exists(path):continue
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		var before:=JSON.stringify(data)
		for i in data.lights.size():
			var config: Dictionary=data.lights[i]
			var source: Node3D=load("res://situations/%s/light_%d.glb" % [id,i]).instantiate()
			var shared:=TrafficSignal.make(config)
			for name in ["lamp_red","lamp_yellow","lamp_green"]:
				check(relative(shared.find_child(name,true,false),shared).origin.distance_to(relative(source.find_child(name,true,false),source).origin)<.0001,id+" saved "+name+" anchor")
			shared=RoadBuild.light_with_signs(shared,config.get("mountedSigns",[]),config.get("mountedMainRoad",[]))
			shared.position=Situation._v(config.pos);shared.rotation.y=config.yaw;shared.scale=Vector3.ONE*float(config.scale)
			check(shared.position.is_equal_approx(Situation._v(config.pos)) and is_equal_approx(shared.rotation.y,config.yaw) and shared.scale.is_equal_approx(Vector3.ONE*float(config.scale)),id+" saved mast pos/yaw/scale")
			shared.free();source.free();authored+=1
		check(JSON.stringify(data)==before,id+" authored signals/rules untouched")
	check(authored>=42,"all saved lights covered")
	var sit:=Situation.new()
	sit.data={"spec":{},"actors":[],"trafficLights":{"state":"flashing_yellow"}}
	var flasher:=TrafficSignal.make({})
	sit.add_child(flasher);sit.lights.append(flasher)
	var junction:=Junction.new(sit)
	var yellow:=flasher.find_child("aperture_yellow",true,false) as MeshInstance3D
	var player:={"p":Vector3(30,0,30),"yaw":0.0,"hw":.9,"hl":2.0}
	check((yellow.material_override as ShaderMaterial).get_shader_parameter("lit")==true,"flashing yellow starts lit")
	junction.update_actors(.51,player,0)
	check((yellow.material_override as ShaderMaterial).get_shader_parameter("lit")==false,"flashing yellow dark phase at 0.51 s")
	junction.update_actors(0,player,0)
	check((yellow.material_override as ShaderMaterial).get_shader_parameter("lit")==false,"pause/zero simulation delta freezes phase")
	junction.update_actors(.51,player,0)
	check((yellow.material_override as ShaderMaterial).get_shader_parameter("lit")==true,"flashing yellow next cycle, 60 flashes per minute")
	sit.free()
	print("signals models: ",checks," checks, ",bad," failures; ",count," signs; ",authored," saved lights")
	quit(1 if bad else 0)
