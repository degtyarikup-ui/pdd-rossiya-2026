## A newly installed divided-road scene must not strand filler traffic on its median.
extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 3: await process_frame
	world.set_process(false)
	for i in 600:
		if not world.staging: break
		await process_frame
	if world.staging: push_error("staging timeout");quit(1);return
	if world.staged_sit!=null: world.staged_sit.free()
	world.current={}
	world.only_id="ticket_10_13"
	world.next_id=world.only_id
	world.staged_sit=Situation.load_scene(world.only_id,world.scenery)
	world.spawn_after=-INF
	world.drive.pos=Vector3(-1.8,0,5)
	var car: Dictionary=world.traffic[0]
	car.x=-1.8;car.z=203.0;car.yaw=0.0;car.dir=1.0
	car.spd=car.base;car.len=4.4;car.shove=0.0
	car.erase("sheltered")
	var single: Array[Dictionary]=[car]
	world.traffic=single
	world._maybe_spawn()
	# This fixture checks road following after the question; live questions reserve an empty view.
	world.retired.append(world.current)
	world.current={}
	world._update_traffic(0.0)
	var clear: bool=world._departure_clear(Vector3(car.x,0,car.z),Vector3.BACK,0.95,2.2)
	world.drive.pos=Vector3(-2.75,0,190)
	world.drive.speed=0.0
	world.phase="explained"
	var min_speed := INF
	for i in 1200:
		world._update_traffic(1.0/60.0)
		if car.z>215.0 and car.z<350.0: min_speed=minf(min_speed,float(car.spd))
	var moving: bool=car.z>365.0 and car.spd>1.0 and min_speed>1.0
	print("ambient lane: road footprint ",clear,"; z=",car.z," speed=",car.spd," minimum_scene_speed=",min_speed,"; ","PASS" if clear and moving else "FAIL")
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if clear and moving else 1)
