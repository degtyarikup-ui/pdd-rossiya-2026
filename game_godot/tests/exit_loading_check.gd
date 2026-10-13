## Exit while immutable mesh work is running: no invalid task IDs or orphaned GLB trees.
extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var before:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 900:
		if not Situation._tasks.is_empty(): break
		await process_frame
	var started: bool=not Situation._tasks.is_empty()
	world.queue_free()
	for i in 12: await process_frame
	var after:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var ok: bool=started and Situation._tasks.is_empty() and after<=before
	print("exit while loading: task started ",started,"; pending ",Situation._tasks.size(),"; orphan nodes ",before," -> ",after,"; ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
