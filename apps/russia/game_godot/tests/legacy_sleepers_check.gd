## Audit every baked scene, including sleepers outside the edited road.
extends SceneTree

func _initialize() -> void: call_deferred("run")

func triangles(mesh: Mesh, layer: int) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var uv = arrays[Mesh.ARRAY_TEX_UV2]
		if uv == null: continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty(): indices = PackedInt32Array(range(uv.size()))
		for i in range(0, indices.size(), 3):
			if is_equal_approx(uv[indices[i]].x, float(layer)) and is_equal_approx(uv[indices[i+1]].x, float(layer)) and is_equal_approx(uv[indices[i+2]].x, float(layer)): count += 1
	return count

func run() -> void:
	var scenery := Scenery.new("summer")
	var layer := scenery.layer_of("sleeper")
	var affected := 0
	var removed := 0
	var failures := 0
	var example := false
	for id in DirAccess.get_directories_at("res://situations"):
		if not FileAccess.file_exists("res://situations/%s/scene.glb" % id): continue
		var scene := PackFiles.instance("res://situations/%s/scene.glb" % id)
		for node in scene.find_children("static", "MeshInstance3D", true, false):
			var before := triangles(node.mesh, layer)
			if before == 0: continue
			affected += 1
			removed += before
			example = example or id == "ticket_31_14"
			var clean := Situation._without_baked_ground(node.mesh, RoadNetwork.load_scene(id))
			if triangles(clean, layer) != 0 or triangles(node.mesh, layer) != before:
				push_error("Sleeper cleanup failed or mutated source: " + id)
				failures += 1
		scene.free()
	if not example or affected == 0:
		push_error("Audit must include the reported ticket_31_14 sleepers")
		failures += 1
	print("Legacy sleepers: %d affected scenes, %d removed triangles, %d failures" % [affected, removed, failures])
	quit(1 if failures else 0)
