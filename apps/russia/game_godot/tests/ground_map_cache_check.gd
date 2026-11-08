## A retained map follows immutable local geometry, not the world's rigid frame.
## godot --headless --path game_godot --script res://tests/ground_map_cache_check.gd
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func rectangle(layer: String, y: float, x0: float, z0: float, x1: float, z1: float) -> Dictionary:
	return {"id":layer,"layer":layer,"y":y,"colour":"#999999","verts":[x0,z0,x1,z0,x1,z1,x0,z1],"idx":[0,1,2,0,2,3]}

func compare_fresh(sit: Situation, scenery: Scenery, label: String) -> void:
	var surface := sit.get_node("surfaces") as MeshInstance3D
	var cached := sit.ground_map()
	var fresh := GroundMap.new(surface.mesh, scenery)
	expect(cached != null and sit._ground_maps.size() == 1, label + " has one current map")
	expect(sit._ground_maps.has(surface.mesh.get_instance_id()), label + " key matches current mesh")
	for x in [-5.0,-3.0,0.0,3.0,5.0,6.0,8.0]:
		for z in [-25.0,-19.0,-5.0,-0.01,0.01,5.0,19.0,25.0]:
			var p := Vector3(x, 0, z)
			expect(cached.at(p) == fresh.at(p), label + " exact road/walk coverage " + str(p))
			var a := cached.walk_height(p)
			var b := fresh.walk_height(p)
			expect(a == b, label + " exact walking height " + str(p))
			expect(sit.road_at(p) == (SceneStitch.contains(p, sit._cut_bindings) and (fresh.at(p) & GroundMap.ROAD) != 0), label + " road cut safety " + str(p))

func run() -> void:
	var scenery := Scenery.new("summer")
	var sit := Situation.new()
	sit._crop = 20.0
	sit._ground_scenery = scenery
	sit.network = RoadNetwork.new()
	sit.network.data = {"crop":20}
	sit.network.build = {"surfaces":[rectangle("asphalt",0,-4,-20,4,20),rectangle("pavement",0.18,4,-20,7,20)],"kerbs":{"segs":[],"y0":0,"y1":0.18}}
	sit.data = {"crop":20,"props":[],"actors":[],"spec":{}}
	var surface := MeshInstance3D.new()
	surface.name = "surfaces"
	sit.add_child(surface)
	root.add_child(sit)
	sit.refresh_uv(scenery)
	compare_fresh(sit,scenery,"initial")
	var initial_map := sit.ground_map()
	expect(sit.ground_map() == initial_map, "ordinary lookup preserves map identity")
	# The first clip can normalize normals and replace an otherwise unchanged mesh.
	sit.position.z = -100.0
	sit.trim_before_join(scenery,Transform3D())
	compare_fresh(sit,scenery,"first full retain")
	var retained_mesh := surface.mesh
	var retained_map := sit.ground_map()
	for frame in [Transform3D(Basis(),Vector3(0,0,-120)),Transform3D(Basis(Vector3.UP,PI/2),Vector3(0,0,-100))]:
		sit.transform = frame
		sit.trim_before_join(scenery,Transform3D())
		expect(surface.mesh == retained_mesh, "fully retained normalized mesh keeps identity")
		expect(sit.ground_map() == retained_map, "rigid rebase and no-op cut keep map identity")
		compare_fresh(sit,scenery,"rigid retained")
	# An actual cut changes the triangles and must invalidate the old raster.
	sit.transform = Transform3D()
	sit.trim_before_join(scenery,Transform3D())
	expect(surface.mesh != retained_mesh, "crossing cut replaces mesh")
	expect(sit._ground_maps.is_empty(), "changed geometry invalidates map before its next lookup")
	compare_fresh(sit,scenery,"crossing cut")
	expect(sit.ground_map() != retained_map, "crossing cut creates a fresh map")
	expect(sit.road_at(Vector3(0,0,-5)) and not sit.road_at(Vector3(0,0,5)), "road support follows the visible cut")
	expect(sit.pavement_at(Vector3(5,0,-5)) and not sit.pavement_at(Vector3(5,0,5)), "walking support follows the visible cut")
	var crossing_map := sit.ground_map()
	var crossing_mesh := surface.mesh
	sit.position.z = -1.0
	sit.trim_before_join(scenery,Transform3D())
	expect(surface.mesh == crossing_mesh and sit.ground_map() == crossing_map, "later less restrictive cut reuses clipped map")
	compare_fresh(sit,scenery,"repeated retained cut")
	# Surface variants can change outside trim_before_join (bind_end / warmed bindings).
	for width in [8.0,12.0,8.0]:
		var previous := sit.ground_map()
		var previous_mesh := surface.mesh
		var port := {"id":"entry","p":Vector3(0,0,-20),"out":Vector3.FORWARD,"width":8.0,"median":0.0}
		sit.network.stitch_bindings = Situation.bindings_with([],port,width)
		sit.refresh_uv(scenery)
		if surface.mesh != previous_mesh:
			expect(sit._ground_maps.is_empty(), "binding variant invalidates old map")
			expect(sit.ground_map() != previous, "binding variant creates independent current map")
		compare_fresh(sit,scenery,"binding variant " + str(width))
	# Direct surface replacement also bounds the cache and cannot return an old raster.
	var saved_mesh := surface.mesh
	var saved_map := sit.ground_map()
	surface.mesh = null
	expect(sit.ground_map() == null and sit._ground_maps.is_empty(), "direct null surface releases stale map")
	surface.mesh = saved_mesh
	expect(sit.ground_map() != saved_map, "restored direct surface receives a fresh map")
	sit._ground_scenery = null
	expect(sit.ground_map() == null and sit._ground_maps.is_empty(), "missing scenery releases unusable map")
	sit._ground_scenery = scenery
	compare_fresh(sit,scenery,"direct restored surface")
	sit.position.z = 100.0
	sit.trim_before_join(scenery,Transform3D())
	expect(surface.mesh == null and sit.ground_map() == null, "fully discarded surface has no movement map")
	expect(sit._ground_maps.is_empty(), "discarded geometry releases its cached map")
	sit.free()
	print("ground map cache: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
