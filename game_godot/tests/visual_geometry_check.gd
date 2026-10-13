## Flat surface lighting and the shape of direction guides: regression checks for visible seams.
extends SceneTree

func _initialize() -> void:
	var sc := Scenery.new("autumn")
	var parent := Node3D.new()
	var street := Street.new(parent, sc, 60, 1)
	_check_tops(street.build_chunk(0, 0), "street")
	for id in ["ticket_10_13", "ticket_10_15", "ticket_11_8"]:
		_check_tops(RoadNetwork.load_scene(id).surface_mesh(sc), id)
	parent.free()
	var sit := Situation.new()
	sit.data = {"trajectories": [{"label": "А", "points": [[0, 0], [0, 10]]}]}
	var guide := sit._trajectory_guide()
	var mesh: Mesh = guide.get_child(0).mesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rounded := false
	for p in verts:
		if p.z >= 9.999:
			assert(absf(p.x) < 0.001, "Only the pointed apex may reach the end of an arrow")
		rounded = rounded or p.z < -0.24
	assert(rounded, "The route starts with a round cap")
	guide.free()
	sit.free()
	print("Surface normals and pointed / rounded direction guides: PASS")
	quit(0)

func _check_tops(mesh: Mesh, label: String) -> void:
	var a := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty(): idx = PackedInt32Array(range(v.size()))
	for k in range(0, idx.size(), 3):
		if (v[idx[k + 1]] - v[idx[k]]).cross(v[idx[k + 2]] - v[idx[k]]).length() < 0.00001:
			continue
		if absf(v[idx[k]].y - v[idx[k + 1]].y) > 0.001 or absf(v[idx[k]].y - v[idx[k + 2]].y) > 0.001:
			continue
		for i in [idx[k], idx[k + 1], idx[k + 2]]:
			assert(n[i].y > 0.999, label + ": horizontal surface must have an upward normal, without kerb smoothing")
