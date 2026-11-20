## Run with rendering enabled: buildings reveal a stationary player without changing other pixels.
extends SceneTree

# Desktop QA may run behind another window. Keep the pause menu out of the pixel samples.
class CaptureWorld extends "res://scripts/world.gd":
	func _capturing() -> bool:
		return true

func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world = CaptureWorld.new()
	world.only_id = "ticket_18_9"
	world.bag = [world.only_id]
	root.add_child(world)
	# The loader reads the real question while it warms the card. Finish that
	# work before replacing world.current with the camera fixture below.
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		if world.loader == null and not world.staging: break
		await process_frame
	if world.loader != null or world.staging:
		push_error("Occlusion fixture timed out waiting for the city")
		quit(1)
		return
	world.set_process(false)
	# The street now owns separate instanced prop and parked-car pools.
	for pool in world.street.pools.values(): pool.node.visible=false
	for pool in world.street.parked.values(): pool.node.visible=false
	world.ui.visible=false
	world.controls.visible=false
	world.hud.visible=false
	world.drive.pos=Vector3.ZERO
	world.player.position=Vector3.ZERO
	world.player.rotation.y=0.0
	world.ground.visible=true
	world.camera.size=28.0
	world.camera.position=Vector3(0,18,-22)
	world.camera.look_at(Vector3(0,1,0))
	var wall := MultiMeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size=Vector3(10,12,6)
	var multi := MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	multi.use_colors=true
	multi.use_custom_data=true
	multi.mesh=mesh
	multi.instance_count=1
	multi.set_instance_color(0,Color.WHITE)
	multi.set_instance_custom_data(0,Color(1,1,1,0))
	multi.set_instance_transform(0,Transform3D(Basis(),Vector3(0,6,-8)))
	wall.multimesh=multi
	wall.material_override=world.scenery.material
	world.add_child(wall)
	world.scenery.register_building_pool(wall)
	var signs := Situation.new()
	signs.network=RoadNetwork.new()
	signs.network.data={"signs":[{"pos":[3.0,0.0],"yaw":PI}]}
	world.add_child(signs)
	world.current={"sit":signs}
	var sign := RoadBuild.sign_node("2.1")
	sign.position=Vector3(3,0,0)
	signs.add_child(sign)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var covered: Image = root.get_texture().get_image()
	for i in 30: world._update_occlusion(1.0/60.0)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var shown: Image = root.get_texture().get_image()
	var center: Vector2 = world.camera.unproject_position(Vector3(0,1.2,0))
	var changed := 0
	for y in range(int(center.y)-20,int(center.y)+20):
		for x in range(int(center.x)-20,int(center.x)+20):
			var a := covered.get_pixel(x,y)
			var b := shown.get_pixel(x,y)
			if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>0.06: changed+=1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var out := arg.trim_prefix("--out=")
			covered.save_png(out.path_join("building-covered.png"))
			shown.save_png(out.path_join("building-reveal.png"))
	var contacts = world.street.pools.get("tree_contact")
	var ok: bool = changed>100 and world.scenery.occluders[-1].fades.get(0,1.0)<0.26 and contacts!=null and contacts.node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("occlusion rendered: ",changed," changed pixels; batched ground contact ",contacts!=null,"; ","PASS" if ok else "FAIL")
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if ok else 1)
