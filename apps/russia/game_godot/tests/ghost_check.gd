## Headless check of the street ghost (scripts/scenery.gd Pool.snapshot): the copy of a full
## pool (the street as it was before a turn) is made without a buffer error.
##   godot --headless --path game_godot --script res://tests/ghost_check.gd
## Exit status 1 when the copy has the wrong number of instances or the engine reports an error.
extends SceneTree


func _initialize() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var mesh := Models.mesh_of("res://scenery/street/lamp.glb")
	var pool := Scenery.Pool.new(parent, mesh, null, 12, 400, false)
	for slot in 12:
		pool.begin(slot)
		for i in 400:
			pool.put(slot, Transform3D(Basis(), Vector3(i * 3.0, 0, slot * 10.0)), Color.WHITE)
		pool.finish(slot)
	var ghost := Node3D.new()
	root.add_child(ghost)
	var t0 := Time.get_ticks_usec()
	pool.snapshot(ghost)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var copy := ghost.get_child(0) as MultiMeshInstance3D
	var ok := copy != null and copy.multimesh.instance_count == pool.multi.instance_count \
		and copy.multimesh.get_instance_transform(7).origin.is_equal_approx(pool.multi.get_instance_transform(7).origin)
	print("ghost check: %d instances, %.2f ms, %s" % [pool.multi.instance_count, ms, "PASS" if ok else "FAIL"])
	quit(0 if ok else 1)
