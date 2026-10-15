## Exit while immutable mesh work is running: no invalid task IDs or orphaned GLB trees.
extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var before:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	for i in 900:
		if not Situation._tasks.is_empty(): break
		await process_frame
	var started: bool=not Situation._tasks.is_empty()
	var exchange:=ProjectSettings.globalize_path("res://../scratch/exit-loading-check")
	DirAccess.make_dir_recursive_absolute(exchange)
	var path:=exchange.path_join("summary.json")
	DirAccess.remove_absolute(path)
	Host.io=exchange
	world._on_exit()
	for i in 1800:
		await process_frame
		if FileAccess.file_exists(path): break
	var delivered:=FileAccess.file_exists(path)
	world.queue_free()
	Host.reset_exit(self)
	Host.io=""
	paused=false
	for i in 12: await process_frame
	var after:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var ok: bool=started and delivered and Situation._tasks.is_empty() and after<=before
	print("exit while loading: task started ",started,"; summary ",delivered,"; pending ",Situation._tasks.size(),"; orphan nodes ",before," -> ",after,"; ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
