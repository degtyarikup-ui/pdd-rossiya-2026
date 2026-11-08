## Native screenshot of the divided-road joint after the real world rebase, with shader world UVs.
extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("stitch shader visual check: run with native renderer");quit(0);return
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 3: await process_frame
	world.set_process(false)
	for i in 900:
		if not world.staging: break
		await process_frame
	if world.staging: push_error("staging timeout");quit(1);return
	if world.staged_sit!=null: world.staged_sit.free()
	world.staged_sit=null
	world.only_id="ticket_14_14"
	world.next_id=world.only_id
	world.spawn_after=-INF
	world.staged_sit=Situation.load_scene(world.only_id,world.scenery)
	world._maybe_spawn()
	var previous: Situation=world.current.sit
	var out: Dictionary=previous.network.connections.exits.straight
	world.drive.pos=previous.global_transform*(out.p-out.out*10.0-SceneStitch.right(out.out)*2.75)
	world.drive.yaw=SceneStitch.yaw(previous.basis*out.out)
	world._on_finished("straight",SceneStitch.yaw(out.out))
	world.only_id="ticket_13_14"
	world.next_id=world.only_id
	world.staged_sit=Situation.load_scene(world.only_id,world.scenery)
	world._maybe_spawn()
	world.ui.visible=false
	world.controls.visible=false
	world.hud.visible=false
	world.player.visible=false
	world.camera.size=42.0
	world.camera.position=Vector3(0,100,-0.01)
	world.camera.look_at(Vector3.ZERO,Vector3.BACK)
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("../output/median-rebased-grid.png")
	var grid: ShaderMaterial=world.current.sit.get_node("surfaces").material_override
	var ok: bool=grid.get_shader_parameter("grid_uv")==true and (grid.get_shader_parameter("surface_frame") as Transform3D).is_equal_approx(world.texture_frame)
	print("rebased median shader grid: ","PASS" if ok else "FAIL")
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if ok else 1)
