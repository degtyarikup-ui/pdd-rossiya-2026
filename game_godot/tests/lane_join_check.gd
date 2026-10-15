## Revalidate prefetched tickets against the physical exit; preserve finite bags.
## Real 2↔4 transitions stay outside the authored junctions and support the whole car.
extends SceneTree

var checks := 0
var failures := 0

func expect(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL ",label)

func selection() -> void:
	var world=load("res://scripts/world.gd").new()
	var mixed:=Situation.new()
	mixed.network=RoadNetwork.load_scene("ticket_10_14")
	mixed.data={"spec":{"maneuver":"straight"}}
	world.current={"sit":mixed}
	world.bag=["ticket_13_13","ticket_17_6"]
	world.next_id=world._next_id()
	expect(world.next_id=="ticket_17_6","prefetch follows the prescribed two-lane exit")
	var unused:=Situation.new()
	unused.id=world.next_id
	world.staged_sit=unused
	world.pending_connection={"port":mixed.network.connections.exits.left}
	world.staging=true
	world._prestage()
	expect(world.next_id=="ticket_17_6" and world.staged_sit==unused,"physical exit waits for in-flight preparation before replacing it")
	world.staging=false
	world._reselect_for_departure()
	expect(world.next_id=="ticket_13_13","actual four-lane departure selects ticket 13 question 13")
	expect(world.staged_sit==null and unused.is_queued_for_deletion(),"unused prefetched scene cannot activate")
	expect(world.bag==["ticket_17_6"],"unused reservation is preserved once in the remaining bag")
	world._reselect_for_departure()
	expect(world.next_id=="ticket_13_13" and world.bag==["ticket_17_6"],"compatible reservation stays stable")
	expect(world._next_id()=="ticket_17_6" and world.bag.is_empty(),"finite bag still reaches the deferred ticket without replaying used tickets")
	world.pending_connection={"port":mixed.network.connections.exits.straight}
	world._reselect_for_departure()
	expect(world.next_id=="ticket_13_13" and world.bag.is_empty(),"exhausted compatible pool keeps the final question instead of restarting the bag")
	world.bag=["ticket_17_6"]
	world._reselect_for_departure()
	expect(world.next_id=="ticket_17_6" and world.bag==["ticket_13_13"],"ticket 13 question 13 is deferred when the physical exit has only two lanes")
	world.next_id="ticket_13_13"
	world.bag=["ticket_17_6"]
	world.only_id="ticket_13_13"
	world._reselect_for_departure()
	expect(world.next_id==world.only_id and world.bag==["ticket_17_6"],"forced scene selection is preserved")
	mixed.free()
	world.free()

func spawn(world, id: String) -> Situation:
	world.only_id=id
	world.staged_sit=Situation.load_scene(id,world.scenery)
	world.spawn_after=-INF
	world._maybe_spawn()
	return world.current.sit

func finish(world) -> void:
	var sit: Situation=world.current.sit
	var port: Dictionary=sit.network.connections.exits.straight
	var contact: Vector3=world._route_contact(sit.network.route("manoeuvre_straight"),port)
	world.drive.pos=sit.global_transform*(contact-port.out*12.0)
	world.drive.yaw=SceneStitch.yaw(sit.basis*port.out)
	world._on_finished("straight",SceneStitch.yaw(port.out))

func check_connector(world, previous: Situation, label: String) -> void:
	var sit: Situation=world.current.sit
	var connector: Dictionary=world.street_connector
	expect(not connector.is_empty(),label+" creates a separate road transition")
	if connector.is_empty(): return
	expect(absf(float(connector.end)-float(connector.start)-90.0)<0.001,label+" has a full 90 m transition")
	var entry: Dictionary=sit.network.connections.entry
	var exit: Dictionary=previous.network.connections.exits.straight
	expect(absf(float(sit.network.stitch_bindings[0].width)-float(entry.width))<0.001,label+" preserves authored entry width")
	expect(absf(float(previous.network.stitch_bindings[-1].width)-float(exit.width))<0.001,label+" preserves authored exit width")
	var old_width: float=world.street.profile_at(float(connector.start)).width
	var max_step: float=absf(float(connector.from.width)-float(connector.to.width))*1.5/90.0+0.002
	for step in range(0,91):
		var z: float=float(connector.start)+step
		var profile: Dictionary=world.street.profile_at(z)
		expect(absf(float(profile.width)-old_width)<max_step,label+" smoothly changes width")
		old_width=profile.width
		if step<4 or step>86: continue
		var x: float=lerpf(float(connector.from_x),float(connector.to_x),smoothstep(float(connector.start),float(connector.end),z))
		for along in [-2.4,0.0,2.4]:
			for side in [-0.95,0.95]:
				expect(world.road_supports(Vector3(x+side,0,z+along)),label+" supports the whole chassis on rendered asphalt")

func screenshot(world, filename: String, centre_z: float, extent: float) -> void:
	if DisplayServer.get_name()=="headless": return
	world.ui.visible=false
	world.hud.visible=false
	world.controls.visible=false
	if world.loader!=null: world.loader.visible=false
	world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size=extent
	world.camera.position=Vector3(0,140,centre_z-0.01)
	world.camera.look_at(Vector3(0,0,centre_z),Vector3.BACK)
	for i in 4:
		if world.paused: world._on_resume()
		if world.pause_menu!=null: world.pause_menu.visible=false
		await process_frame
	var directory:=ProjectSettings.globalize_path("res://../output/lane-joins")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(filename+".png"))

func _initialize() -> void:
	selection()
	var world=load("res://main.tscn").instantiate()
	world.only_id="ticket_17_6"
	world.bag=[world.only_id]
	root.add_child(world)
	await process_frame
	await process_frame
	world.set_process(false)
	for i in 600:
		if not world.staging: break
		await process_frame
	if world.staging:
		push_error("Lane join fixture initial staging timeout")
		quit(1)
		return
	if world.staged_sit!=null:
		world.staged_sit.free()
		world.staged_sit=null
	world.current={}
	world.road_force=""
	world.pending_connection={}
	var two:=spawn(world,"ticket_17_6")
	var saved_two:=JSON.stringify(two.network.data)
	finish(world)
	var four:=spawn(world,"ticket_13_13")
	var saved_four:=JSON.stringify(four.network.data)
	check_connector(world,two,"two to four")
	await screenshot(world,"ticket-13-13-two-to-four",45.0,155.0)
	finish(world)
	var another_four:=spawn(world,"ticket_13_13")
	expect(world.street_connector.is_empty(),"four-lane roads join directly without narrowing")
	expect((four.global_transform*four.network.connections.exits.straight.p).distance_to(another_four.global_transform*another_four.network.connections.entry.p)<0.001,"four-lane sections have exact physical contact")
	await screenshot(world,"ticket-13-13-four-to-four",0.0,85.0)
	finish(world)
	spawn(world,"ticket_17_6")
	check_connector(world,another_four,"four to two")
	expect(JSON.stringify(two.network.data)==saved_two,"runtime joining preserves the two-lane source")
	expect(JSON.stringify(four.network.data)==saved_four,"runtime joining preserves ticket 13 question 13 source")
	print("Lane joins: ",checks," checks, ",failures," failures")
	world.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
