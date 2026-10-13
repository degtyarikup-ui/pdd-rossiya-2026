## Run with rendering enabled: buildings reveal a stationary player without changing other pixels.
extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 3: await process_frame
	world.set_process(false)
	while world.staging: await process_frame
	world._set_street_objects(false)
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
	var covered: Image = root.get_texture().get_image()
	for i in 30: world._update_occlusion(1.0/60.0)
	for i in 3: await process_frame
	var shown: Image = root.get_texture().get_image()
	var center: Vector2 = world.camera.unproject_position(Vector3(0,1.2,0))
	var changed := 0
	for y in range(int(center.y)-20,int(center.y)+20):
		for x in range(int(center.x)-20,int(center.x)+20):
			var a := covered.get_pixel(x,y)
			var b := shown.get_pixel(x,y)
			if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>0.06: changed+=1
	covered.save_png("../output/building-covered.png")
	shown.save_png("../output/building-reveal.png")
	var contacts = world.street.pools.get("tree_contact")
	var ok: bool = changed>100 and world.scenery.occluders[-1].fades.get(0,1.0)<0.26 and contacts!=null and contacts.node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("occlusion rendered: ",changed," changed pixels; batched ground contact ",contacts!=null,"; ","PASS" if ok else "FAIL")
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if ok else 1)
