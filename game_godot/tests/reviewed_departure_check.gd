## Verify actual reviewed scenes depart along runtime roads without rewriting authored trajectories.
extends SceneTree

var failed := 0
var tested := 0
var preserved := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed += 1
		push_error(message)

func run() -> void:
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	for frame in 3:
		await process_frame
	world.set_process(false)
	world.insert_road = false
	world.traffic.clear()
	for frame in 600:
		if not world.staging:
			break
		await process_frame
	if world.staging:
		push_error("initial scene staging timeout")
		quit(1)
		return
	if world.staged_sit != null:
		world.staged_sit.free()
		world.staged_sit = null
	world.road_force = "departure-test"
	var ids: Array = world.playable_ids.duplicate()
	for id in ids:
		var sit := Situation.load_scene(str(id), world.scenery)
		if sit == null:
			check(false, "%s reviewed scene failed to load; import its authored GLB resources before running the check" % id)
			continue
		root.add_child(sit)
		sit.position = Vector3(0, 0, 600)
		var before := JSON.stringify(sit.data.actors)
		var junction := Junction.new(sit)
		junction.released = true
		junction.continuation = func(p, toward, hw, hl): return world._departure_path(sit.global_transform * p, sit.basis * toward, hw, hl, sit.global_transform)
		junction.cycle_continuation = func(p, toward, hw, hl): return world._cycle_departure_path(sit.global_transform * p, sit.basis * toward, hw, hl, sit.global_transform)
		world.current = {"sit": sit, "junction": junction, "zc": 600.0}
		world.blanks = [[400.0, 800.0]]
		world.drive.pos = sit.global_transform * Vector3(0, 0, -40)
		var all: Array[Junction.Motion] = junction.motions.duplicate()
		for m in all:
			if m.type == "pedestrian" or m.stays_put or m.max_speed <= 0.0 or m.path.length <= 0.1:
				if m.stays_put: preserved += 1
				continue
			tested += 1
			junction.motions.assign([m])
			m.distance = maxf(0.0, m.path.length - 8.0)
			var start := m.path.point_at(m.distance)
			m.node.position = start
			m.active = true
			m.waits_for_player = false
			m.dependencies = []
			m.hold_for = []
			m.stop_at = null
			m.stop_for = null
			m.speed = m.max_speed
			var end := m.path.point_at(m.path.length)
			var toward := m.path.tangent_at(m.path.length)
			var observing := end + SceneStitch.right(toward) * 30.0
			var player := {"p": observing, "yaw": 0.0, "hw": 0.86, "hl": 1.75}
			world.drive.pos = sit.global_transform * observing
			var on_road := true
			for i in 3600:
				junction.update_actors(1.0 / 30.0, player, 0.0)
				if m.distance > m.exported_length + 3.0 and not m.done:
					var box := m.footprint()
					for x in [-m.hw, m.hw]:
						for z in [-m.hl, m.hl]:
							var corner := m.pos + Vector3(x, 0, z).rotated(Vector3.UP, box.yaw)
							var supported: bool = world._cycle_departure_support(sit.global_transform * corner) if m.type == "cyclist" else world._departure_support(sit.global_transform * corner)
							if on_road and not supported:
								print("UNSUPPORTED ", id, "/", m.id, " at ", m.pos, " corner ", corner, " yaw ", box.yaw, " departure ", m.distance-m.exported_length)
							on_road = on_road and supported
				if m.done: break
			if not m.done:
				print("BLOCKED ", id, "/", m.id, " endpoint ", m.path.point_at(m.exported_length), " direction ", m.path.tangent_at(m.exported_length), " footprint ", m.hw, "/", m.hl)
			check(m.done, "%s/%s must leave its arrow and retire beyond view, stopped at %.1f/%.1fm" % [id, m.id, m.distance, m.path.length])
			check(on_road, "%s/%s runtime departure must stay on driveable road" % [id, m.id])
			check(not m.done or m.pos.distance_to(player.p) > 240.0, "%s/%s cannot retire while visible nearby" % [id, m.id])
			print("%s / %s (%s): departure %.1fm, retired %s, road %s" % [id, m.id, m.type, m.distance - m.exported_length, m.done, on_road])
		check(JSON.stringify(sit.data.actors) == before, "%s must keep authored actor data unchanged" % id)
		world.current = {}
		sit.free()
	world.queue_free()
	await process_frame
	print("Reviewed departures: %d scenes, %d moving vehicles, %d authored staysPut preserved, %d failures" % [ids.size(), tested, preserved, failed])
	quit(0 if failed == 0 and tested > 0 else 1)
