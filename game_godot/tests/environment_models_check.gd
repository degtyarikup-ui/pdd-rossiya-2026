## Archived local envelopes and authored transforms: changing a prop must not move a location.
extends SceneTree

const ENVELOPES := {
	"trees/round_0": [Vector3(-1.5,0,-1.2),Vector3(1.6,4.05,1.2),300],
	"trees/birch_0": [Vector3(-.8,0,-.75),Vector3(.87,4.865,.75),300],
	"trees/pine_0": [Vector3(-1.4,0,-1.4),Vector3(1.4,4.45,1.4),220],
	"street/bush": [Vector3(-.76,-.55,-.55),Vector3(.8,.55,.55),150],
	"street/fence_12": [Vector3(-.05,0,-6.05),Vector3(.16,1,6.05),230],
	"street/fence_14": [Vector3(-.05,0,-7.05),Vector3(.16,1,7),260],
	"street/lamp": [Vector3(-1.5,0,-.17),Vector3(.17,5.2,.17),110],
	"street/kiosk_0": [Vector3(-1.4,0,-1),Vector3(1.4,2.4,1.795906782),90],
	"street/kiosk_1": [Vector3(-1.4,0,-1),Vector3(1.4,2.4,1.795906782),90],
	"street/kiosk_2": [Vector3(-1.4,0,-1),Vector3(1.4,2.4,1.795906782),90],
}
var checks := 0
var bad := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		if bad<=12: print("FAIL ",label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var sc := Scenery.new("summer")
	var vertices_total := 0
	var triangles_total := 0
	for prop: String in ENVELOPES:
		var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
		var aabb := mesh.get_aabb()
		var expected := AABB(ENVELOPES[prop][0],ENVELOPES[prop][1]-ENVELOPES[prop][0])
		check(aabb.position.distance_to(expected.position)<.0001 and aabb.end.distance_to(expected.end)<.0001,prop+" original local min/max and pivot")
		check(aabb.size.distance_to(sc.size_of(prop))<.0001,prop+" index placement/footprint unchanged")
		check(mesh.get_surface_count()==1,prop+" one batched surface")
		var packed := load("res://scenery/%s.glb" % prop) as PackedScene
		var model := packed.instantiate()
		var nodes := model.find_children("*","MeshInstance3D",true,false)
		check(nodes.size()==1,prop+" one mesh, no separate branches/pickets")
		check(model.find_children("*","Light3D",true,false).is_empty(),prop+" no extra lights")
		check((nodes[0] as MeshInstance3D).transform.is_equal_approx(Transform3D.IDENTITY),prop+" mesh has no hidden transform")
		model.free()
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var triangles := indices.size()/3
		vertices_total += vertices.size()
		triangles_total += triangles
		check(not indices.is_empty() and triangles<=ENVELOPES[prop][2],prop+" indexed mobile triangle budget")
		check(colors.size()==vertices.size() and uv2.size()==vertices.size(),prop+" tint/detail channels retained")
		var seasonal := false
		var fixed := false
		var finite := true
		for i in vertices.size():
			seasonal=seasonal or colors[i].a>.75
			fixed=fixed or colors[i].a<.25
			finite=finite and vertices[i].is_finite() and absf(normals[i].length()-1)<.001
		check(finite,prop+" finite positions and unit normals")
		if prop.begins_with("trees/"):
			var foot := AABB()
			var first := true
			for v in vertices:
				if v.y>.0001: continue
				foot=AABB(v,Vector3.ZERO) if first else foot.expand(v)
				first=false
			check(not first and Vector2(foot.get_center().x,foot.get_center().z).length()<.0001,prop+" trunk stays rooted at original origin")
		if prop.begins_with("trees/") or prop=="street/bush": check(seasonal,prop+" seasonal foliage")
		if prop!="street/bush": check(fixed,prop+" un-tinted trunk/street furniture")
		# Rotation and nonuniform editor scales preserve exactly the same occupied box.
		for yaw in [0.0,.73,PI,-PI/2]:
			var xf := Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(1.3,.8,2.1)),Vector3(9.1,1.4,-17.2))
			var actual: AABB=xf*aabb
			var old: AABB=xf*expected
			check(actual.position.distance_to(old.position)<.001 and actual.size.distance_to(old.size)<.001,prop+" rotated/scaled footprint preserved")
	check(vertices_total<4000 and triangles_total<1800,"total budget below archived 15318 vertices / 5106 triangles")
	# Exercise the real placement path on every saved scene, without loading the whole road.
	var dir:=DirAccess.open("res://situations")
	var authored := 0
	for id in dir.get_directories():
		var path := "res://situations/%s/scene.json" % id
		if not FileAccess.file_exists(path): continue
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		var props: Array=data.get("props",[]).filter(func(p): return ENVELOPES.has(str(p.prop)))
		if props.is_empty(): continue
		var sit:=Situation.new()
		sit.data={"props":props}
		sit._place_props(sc)
		for prop: String in sit._pools:
			var list: Array=props.filter(func(p): return p.prop==prop)
			var multi: MultiMesh=sit._pools[prop]
			check(multi.instance_count==list.size(),id+" "+prop+" authored instance count")
			check((sit._pool_nodes[prop] as MultiMeshInstance3D).material_override==sc.material,id+" shared material/pool")
			var poses: Array=sit._pool_nodes[prop].get_meta("instance_transforms")
			for i in list.size():
				var p: Dictionary=list[i]
				var expected:=Transform3D(Basis(Vector3.UP,p.yaw).scaled(Situation._v(p.scale)),Situation._v(p.pos))
				# Dummy headless RenderingServer cannot read MultiMesh transforms back.
				var actual: Transform3D=poses[i] if DisplayServer.get_name()=="headless" else multi.get_instance_transform(i)
				check(actual.is_equal_approx(expected),id+" saved pos/yaw/scale unchanged")
				authored+=1
		sit.free()
	check(authored>100,"real authored environment instances covered")
	print("environment models: ",checks," checks, ",bad," failures; ",vertices_total," vertices, ",triangles_total," triangles; ",authored," authored placements")
	quit(1 if bad else 0)
