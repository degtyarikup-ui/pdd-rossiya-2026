## Headless check of the junction surfaces (scripts/situation.gd _without_baked_ground):
##   godot --headless --path game_godot --script res://tests/surface_check.gd
## For every junction with a network: the scene's own road copy under the network's surfaces
## is gone, and the network's ground stays. Prints the numbers; exit status 1 on a failure.
extends SceneTree


func _initialize() -> void:
	var ids: Array = JSON.parse_string(FileAccess.get_file_as_string("res://situations/index.json"))
	var only := OS.get_cmdline_user_args()
	if not only.is_empty():
		ids = only
	var bad := 0
	var checked := 0
	var copies := 0
	for id in ids:
		if not FileAccess.file_exists("res://network/build/%s.json" % id):
			continue
		var t0 := Time.get_ticks_msec()
		var net := RoadNetwork.load_scene(id)
		print("net ", id, " ", Time.get_ticks_msec() - t0, " ms")
		if net == null:
			continue
		checked += 1
		var mesh := _baked_static(id)
		if mesh == null:
			continue
		t0 = Time.get_ticks_msec()
		var kept := Situation._without_baked_ground(mesh, net)
		print("filter ", Time.get_ticks_msec() - t0, " ms")
		var left := _count_copies(kept, net)
		copies += left
		if left > 0:
			bad += 1
			print("copies left: ", id, " ", left)
	print("junctions: ", checked, " with copies left: ", bad, " copy triangles left: ", copies)
	quit(1 if bad > 0 else 0)


func _baked_static(id: String) -> Mesh:
	var scene: Node3D = (load("res://situations/%s/scene.glb" % id) as PackedScene).instantiate()
	var found: Mesh = null
	for node in scene.find_children("static", "MeshInstance3D", true, false):
		found = (node as MeshInstance3D).mesh
	scene.free()
	return found


## Flat copies of the road level (0..3.5 cm) whose centre the network draws.
func _count_copies(mesh: Mesh, net: RoadNetwork) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(verts.size()))
		for k in range(0, idx.size(), 3):
			var a := verts[idx[k]]
			var b := verts[idx[k + 1]]
			var c := verts[idx[k + 2]]
			if absf(a.y - b.y) < 0.001 and absf(a.y - c.y) < 0.001 and a.y >= -0.001 and a.y < 0.035:
				if net.covers(Vector2((a.x + b.x + c.x) / 3.0, (a.z + b.z + c.z) / 3.0)):
					n += 1
	return n
