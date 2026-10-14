## Shared garage/NPC geometry, phone budgets, actor semantics and signal pivots.
extends SceneTree
var bad := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: bad += 1; print("FAIL ",label)
func bounds(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var xf := Transform3D.IDENTITY
		var cursor: Node = mi
		while cursor != model and cursor != null:
			if cursor is Node3D: xf=cursor.transform*xf
			cursor=cursor.get_parent()
		var box: AABB=xf*mi.get_aabb()
		result=box if first else result.merge(box)
		first=false
	return result
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var all_triangles := 0
	var all_vertices := 0
	for id in Models.CARS:
		var car := Models.player_car(id,Color("#C0392B"))
		var other := Models.player_car(id,Color("#4D7768"))
		var meshes := car.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==11,id+" eleven model parts instead of 27")
		check(car.find_children("wheel_*","",true,false).size()==4 and car.find_children("axle_front_*","",true,false).size()==2,id+" wheel spin and steering pivots")
		check(car.find_children("brake_*","MeshInstance3D",true,false).size()==2,id+" two brake lenses")
		for side in ["L","R"]:
			check(car.find_child("blink_"+side,true,false).find_children("*","MeshInstance3D",true,false).size()==2,id+" front/rear indicator hierarchy "+side)
		var batch := Models.traffic_mesh(id)
		check(batch==Models.mesh_of("res://models/traffic/%s.glb"%id) and batch==Models.traffic_mesh(id),id+" one cached shared NPC mesh")
		check(batch.get_surface_count()==1,id+" one instanced surface")
		check(batch.get_aabb().is_equal_approx(bounds(car)),id+" NPC and garage geometry have identical bounds")
		var a := batch.surface_get_arrays(0)
		var triangles: int=a[Mesh.ARRAY_INDEX].size()/3
		var vertices: int=a[Mesh.ARRAY_VERTEX].size()
		all_triangles+=triangles;all_vertices+=vertices
		check(triangles<=1300 and vertices<=2300,id+" phone geometry budget")
		var lamps := Models.traffic_lenses(id)
		check(lamps.size()==4 and lamps.filter(func(l):return l.side=="L").size()==2,id+" four actual indicator centres")
		var paint := car.find_child("body",true,false).get_active_material(0) as ShaderMaterial
		var other_paint := other.find_child("body",true,false).get_active_material(0) as ShaderMaterial
		check(paint!=other_paint and paint.get_shader_parameter("paint_colour")!=other_paint.get_shader_parameter("paint_colour"),id+" garage paints stay independent")
		car.free();other.free()
	check(all_vertices<14000 and all_triangles<7800,"all six shared cars remain below old traffic 28062 vertices / 9354 triangles")
	for kind in NpcVehicle.KINDS:
		var npc := NpcVehicle.make(kind,Color("#778FAD"))
		root.add_child(npc)
		npc.set_process(false)
		var meshes := npc.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==1,kind+" one NPC mesh")
		var mesh := (meshes[0] as MeshInstance3D).mesh
		var a := mesh.surface_get_arrays(0)
		var triangles: int=a[Mesh.ARRAY_INDEX].size()/3
		check(mesh.get_surface_count()==1 and triangles<=(2500 if kind=="train" else 1400),kind+" single surface and triangle budget")
		check(mesh.get_aabb().position.y>=-.001,kind+" wheels rest on the ground")
		var material := (meshes[0] as MeshInstance3D).material_override as ShaderMaterial
		check(not material.shader.code.contains("uniform sampler") and not material.shader.code.contains("ALPHA ="),kind+" opaque glass without texture lookups")
		npc.position.z+=.30;npc._process(.1)
		check(is_equal_approx(material.get_shader_parameter("wheel_distance"),.30),kind+" wheels follow movement")
		npc._process(.1)
		check(is_equal_approx(material.get_shader_parameter("wheel_distance"),.30),kind+" stopped wheels stay still")
		Fleet.add_blinkers(npc,"L",2,1)
		var signals := npc.get_node("vehicle_signals") as Fleet.Signals
		signals.set_process(false);signals._process(.1)
		check(signals.materials.size()==1 and material.get_shader_parameter("left_on")==true and material.get_shader_parameter("right_on")==false,kind+" signals share the body shader")
		var copy := npc.duplicate() as NpcVehicle
		root.add_child(copy);copy.set_process(false)
		check((copy.get_node("body") as MeshInstance3D).mesh==mesh and (copy.get_node("body") as MeshInstance3D).material_override!=material,kind+" clone reuses geometry with independent motion")
		copy.queue_free();npc.queue_free()
	var bike := NpcVehicle.make("motorcycle",Color("#B13939"),{"sidecar":true})
	root.add_child(bike);bike.set_process(false)
	check(bike.get_node_or_null("sidecar")!=null and bike.find_children("*","MeshInstance3D",true,false).size()==2,"sidecar adds only its own mesh")
	var lamps: Array=bike.get_meta("npc_lens_centres")
	check(lamps.filter(func(l):return l.side=="R").size()==2 and lamps.filter(func(l):return l.side=="L").size()==2,"sidecar retains anatomical indicator sides")
	var tank := NpcVehicle.make("tanker",Color("#F08032"),{"cabColor":"#F2F2EC","beacon":"amber"})
	root.add_child(tank);tank.set_process(false);tank._process(.1)
	var tank_mat := (tank.get_node("body") as MeshInstance3D).material_override as ShaderMaterial
	check(tank_mat.get_shader_parameter("cab_colour")!=tank_mat.get_shader_parameter("paint_colour") and tank_mat.get_shader_parameter("beacon_on")==true,"tanker preserves cab paint and amber beacon")
	var sit := Situation.load_scene("ticket_32_15",Scenery.new("summer"))
	check(sit.actors.all(func(actor):return actor is NpcVehicle),"ticket car, tram and motorcycle use shared models")
	check(sit.actors[2].get_node_or_null("sidecar")!=null,"ticket motorcycle keeps its authored sidecar")
	for i in sit.actors.size():check(sit.actors[i].scale.is_equal_approx(Situation._v(sit.data.actors[i].scale)),"ticket authored scale retained")
	sit.free();tank.queue_free();bike.queue_free()
	await process_frame
	print("vehicle models: ",checks," checks, ",bad," failures; shared cars ",all_vertices," vertices / ",all_triangles," triangles")
	quit(1 if bad else 0)
