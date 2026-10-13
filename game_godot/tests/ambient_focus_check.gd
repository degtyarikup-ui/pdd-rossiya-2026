## Background traffic reserves exam views before capture and anticipates parking far from the player.
extends SceneTree
var bad := 0
func check(ok: bool, text: String) -> void:
	if not ok: bad += 1; push_error(text)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	for i in 900:
		if not world.staging: break
		await process_frame
	check(world.traffic.size() == 2, "Four times fewer ordinary moving vehicles")
	check(world.street.parked_chance == 0.02, "Parking chance reduced from 25% to 2%")
	var saved: Array[Dictionary] = world.traffic
	world.current = {}
	world.blanks.clear()
	world.street_half = 4.2
	world.street.profile = {"centre":"dashed", "median":0.0, "lanes":2}
	world.camera.position = Vector3(0, 45, -10)
	world.camera.look_at(Vector3.ZERO)
	world.camera.size = 55
	# Actual parked model dimensions are observed even 100 m from the player.
	world.drive.pos = Vector3(12, 0, 100)
	for direction in [1.0, -1.0]:
		for length in [4.4, 11.0]:
			var car: Dictionary = saved[0].duplicate()
			car.merge({"dir":direction,"x":-direction*2.1,"z":-direction*65.0,
				"yaw":0.0 if direction>0 else PI,"len":length,"hw":1.2 if length>5 else 0.95,"base":12.0,"spd":12.0,"shove":0.0,"contact_cooldown":0.0},true)
			car.erase("sheltered");car.erase("hazards_left")
			var one: Array[Dictionary] = [car]
			world.traffic = one
			var parked := {"p":Vector3(-direction*3.75,0,0),"yaw":0.0,"hw":0.9,"hl":2.25}
			world.street.parked_bodies = {0:[parked]}
			var parked_seen := false
			for obstacle in world.obstacles():
				if "car" in obstacle and obstacle.car.get("parked",false): parked_seen=true
			check(parked_seen,"NPC sees parking independently of player distance")
			var overlap := false
			var max_shift := 0.0
			var max_jump := 0.0
			for frame in 1000:
				var before := Vector3(car.x,0,car.z)
				world._update_traffic(1.0/60.0)
				var after := Vector3(car.x,0,car.z)
				max_shift=maxf(max_shift,absf(car.x+direction*2.1))
				max_jump=maxf(max_jump,before.distance_to(after))
				overlap=overlap or Drive.overlap({"p":after,"yaw":car.yaw,"hw":car.hw,"hl":length*0.5},parked)
				if car.z*direction > 65: break
			check(car.z*direction>60,"Car/bus passes the parked body in both directions")
			check(not overlap and float(car.get("hazards_left",0))==0,"Parking causes no collision or emergency flashing")
			check(max_shift>0.3 and max_jump<0.25,"Passing uses continuous steering, never a lateral teleport")
			check(absf(car.x+direction*2.1)<0.15,"NPC returns to its lane after clearing the whole tail")
	# A narrow passing envelope must wait for the oncoming car, then complete the manoeuvre.
	world.street_half = 3.2
	var parked := {"p":Vector3(-2.75,0,0),"yaw":0.0,"hw":0.9,"hl":2.25}
	world.street.parked_bodies = {0:[parked]}
	var bus: Dictionary = saved[0].duplicate()
	bus.merge({"dir":1.0,"x":-1.6,"z":-65.0,"yaw":0.0,"len":11.0,"hw":1.2,"base":12.0,"spd":12.0,"shove":0.0},true)
	bus.erase("sheltered");bus.erase("hazards_left")
	var opposite: Dictionary = saved[1].duplicate()
	opposite.merge({"dir":-1.0,"x":1.6,"z":45.0,"yaw":PI,"len":4.4,"hw":0.95,"base":12.0,"spd":12.0,"shove":0.0},true)
	opposite.erase("sheltered")
	var pair: Array[Dictionary] = [bus,opposite];world.traffic=pair
	check(world._ambient_park_plan(bus).wait_gap < INF,"Passing waits for oncoming traffic on a narrow road")
	var collision := false
	for frame in 2500:
		world._update_traffic(1.0/60.0)
		collision=collision or Drive.overlap({"p":Vector3(bus.x,0,bus.z),"yaw":bus.yaw,"hw":bus.hw,"hl":5.5},parked)
		if bus.z>60: break
	print("narrow parking: bus=",Vector3(bus.x,bus.yaw,bus.z)," speed=",bus.spd," collision=",collision," hazards=",bus.get("hazards_left",0)," opposite=",opposite.z)
	check(bus.z>60 and not collision and float(bus.get("hazards_left",0))==0,"Bus passes after oncoming traffic clears without hitting parking")
	# With a solid centre line and insufficient space it stops safely rather than crossing it.
	world.street.profile.centre="solid"
	bus.x=-1.6;bus.z=-40.0;bus.yaw=0.0;bus.spd=12.0
	var solo: Array[Dictionary]=[bus];world.traffic=solo
	for frame in 600:world._update_traffic(1.0/60.0)
	check(bus.z < -10.0 and bus.spd < 0.1,"An impossible legal passing gap causes a safe wait")
	world.street_half=4.2;world.street.profile.centre="dashed"
	# A staged view admits no new traffic, in any question phase. A visible car remains visible.
	world.street.parked_bodies.clear()
	world.drive.pos = Vector3(-1.8,0,0)
	var sit := Situation.new()
	sit.data={"crop":90.0,"stopZ":0.0,"playerStartX":-1.8,"spec":{},"actors":[]}
	sit._crop = 0.0 # Control-only fixture: the existing filler street supplies driving support.
	world.add_child(sit)
	world.current={"sit":sit,"junction":Junction.new(sit),"zc":0.0}
	for phase in ["driving","question","explained","resolving"]:
		world.phase=phase
		var car: Dictionary=saved[1].duplicate()
		car.merge({"dir":-1.0,"x":2.1,"z":240.0,"yaw":PI,"len":4.4,"base":12.0,"spd":12.0,"shove":0.0},true)
		car.erase("sheltered")
		var one: Array[Dictionary]=[car];world.traffic=one
		for frame in 1000: world._update_traffic(1.0/60.0)
		check(car.z>=190.0 and not world._ambient_visible(car),"Reserved exam view remains empty: "+phase)
		check(world._ambient_stage_clear(),"Background does not block question capture: "+phase)
	var visible: Dictionary=saved[0].duplicate()
	visible.merge({"x":2.1,"z":12.0,"dir":-1.0,"len":4.4,"yaw":PI},true);visible.erase("sheltered")
	var visible_list: Array[Dictionary]=[visible];world.traffic=visible_list
	check(world._ambient_visible(visible) and not world._ambient_stage_clear(),"An already visible car clears before question timer starts")
	var before := Vector3(visible.x,0,visible.z)
	world._update_traffic(0.0)
	check(not visible.get("sheltered",false) and Vector3(visible.x,0,visible.z).is_equal_approx(before),"Visible cars are neither hidden nor teleported at the question transition")
	var follower: Dictionary=saved[0].duplicate()
	follower.merge({"x":-2.1,"z":-25.0,"dir":1.0,"len":4.4,"yaw":0.0,"spd":12.0,"base":12.0,"shove":0.0},true)
	follower.erase("sheltered")
	var following: Array[Dictionary]=[follower];world.traffic=following
	world.phase="driving"
	world.drive.pos=Vector3(-1.8,0,0)
	for frame in 240:
		world.drive.pos.z += 0.2
		world._update_traffic(1.0/60.0)
	check(follower.has("quiet_stop_z") and follower.spd<0.1 and follower.z < 0,"A visible follower brakes and falls behind before question capture")
	world.traffic=saved
	world.current={}
	sit.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	print("ambient focus: ",bad," failures")
	quit(1 if bad else 0)
