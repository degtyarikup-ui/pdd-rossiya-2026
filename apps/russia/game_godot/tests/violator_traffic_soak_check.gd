## Long run of the whole Violator junction (all phases, spawning, emergency vehicles, walkers) with the
## player idle. Checks what one frame cannot: no car drives through another car or a walker, nobody
## parks on a zebra, and traffic never locks up.
extends SceneTree

const ViolatorScript := preload("res://scripts/violator.gd")
const DT := 1.0 / 30.0
const SECONDS := 300.0

var failed := 0


func _init() -> void:
	_run.call_deferred()


func _check(desc: String, condition: bool) -> void:
	if condition:
		print("  [PASS] ", desc)
	else:
		failed += 1
		push_error("FAIL: " + desc)


func _run() -> void:
	# VIOLATOR_LEVEL=easy|medium soaks the other junctions (default: hard).
	ViolatorScript.forced_difficulty = OS.get_environment("VIOLATOR_LEVEL") if OS.get_environment("VIOLATOR_LEVEL") != "" else "hard"
	seed(int(OS.get_environment("VIOLATOR_SEED")) if OS.get_environment("VIOLATOR_SEED") != "" else 20261023)
	var game = ViolatorScript.new()
	root.add_child(game)
	await process_frame
	game.ready_for_play = true
	game._start_game()
	game.economy["lives"] = 9999
	game.lives = 9999
	game.seconds_left = 99999.0

	var car_overlaps := 0
	var walker_hits := 0
	var zebra_parked := 0
	var stuck_cars := 0
	var emergencies := 0
	var walkers_crossed := 0
	var walker_red_starts := 0
	var still_time := {}
	var zebra_time := {}
	var seen_emergency := {}
	var prev_state := {}
	var viol_seen := {}      # instance id -> type, for every scheduled violator
	var viol_active := {}    # instance id -> type, once its offence actually happened
	var frames := int(SECONDS / DT)
	for f in frames:
		game.lives = 9999
		# The middle minute and a half runs with the signals blinking yellow (night mode).
		if f == int(150.0 / DT):
			game.set_signal_mode("flashing")
		elif f == int(240.0 / DT):
			game.set_signal_mode("normal")
		game._process(DT)
		var cars: Array = game.cars.filter(func(c): return is_instance_valid(c))
		for vc in cars:
			if vc.is_violator:
				viol_seen[vc.get_instance_id()] = vc.violation_type
				if vc.violation_state in ["active", "missed", "detected"]:
					viol_active[vc.get_instance_id()] = vc.violation_type
		for i in cars.size():
			var a = cars[i]
			if a.is_emergency and not seen_emergency.has(a.get_instance_id()):
				seen_emergency[a.get_instance_id()] = true
				emergencies += 1
			# Car against car: oriented footprints 1.8 x 4.4 (a little under the 1.9 x 4.7 bodies).
			for j in range(i + 1, cars.size()):
				if _bodies_overlap(a, cars[j]):
					if car_overlaps < 6 or car_overlaps % 20 == 0:
						var b = cars[j]
						print("overlap t=%.1f A lane=%d %s (%.1f,%.1f) y%.2f v%.1f %s e%s | B lane=%d %s (%.1f,%.1f) y%.2f v%.1f %s e%s phase=%s" % [f * DT, a.lane, a.route, a.position.x, a.position.z, a.rotation.y, a.speed, a.violation_type, a.is_emergency, b.lane, b.route, b.position.x, b.position.z, b.rotation.y, b.speed, b.violation_type, b.is_emergency, game.light_phase])
					car_overlaps += 1
			for c in game.crossers:
				if c.state in ["cross", "wait", "approach", "leave"] and c.node.visible:
					var p: Vector3 = c.node.position
					var fwd := Vector3(sin(a.rotation.y), 0, cos(a.rotation.y))
					var d := Vector3(p.x - a.position.x, 0, p.z - a.position.z)
					if absf(d.dot(fwd)) < 2.2 and absf(d.dot(Vector3(fwd.z, 0, -fwd.x))) < 0.85:
						if walker_hits < 4:
							print("walker hit t=%.1f car lane=%d %s (%.1f,%.1f) y%.2f v%.1f viol=%s e=%s | walker %s %s s=%.1f" % [f * DT, a.lane, a.route, a.position.x, a.position.z, a.rotation.y, a.speed, a.violation_type, a.is_emergency, c.cw, c.state, c.s])
						walker_hits += 1
			var id: int = a.get_instance_id()
			still_time[id] = still_time.get(id, 0.0) + DT if a.speed < 0.05 else 0.0
			if still_time[id] > 60.0:
				var dl = (a.get_meta("debug_lead") if a.has_meta("debug_lead") else null)
				if is_instance_valid(dl):
					print("   lead: lane=%d %s (%.1f,%.1f) v%.1f" % [dl.lane, dl.route, dl.position.x, dl.position.z, dl.speed])
				print("   zebra limit: ", a.get_meta("debug_zebra", 0))
				print("stuck t=%.0f lane=%d route=%s pos=(%.1f,%.1f) yaw=%.2f turn=%.2f viol=%s/%s emerg=%s phase=%s" % [f * DT, a.lane, a.route, a.position.x, a.position.z, a.rotation.y, a.turn_t, a.violation_type, a.violation_state, a.is_emergency, game.light_phase])
				if stuck_cars == 0:
					for o in cars:
						print("   car lane=%d route=%s pos=(%.1f,%.1f) yaw=%.2f v=%.1f turn=%.2f viol=%s/%s emerg=%s yld=%s" % [o.lane, o.route, o.position.x, o.position.z, o.rotation.y, o.speed, o.turn_t, o.violation_type, o.violation_state, o.is_emergency, o.yielding])
						var ol = (o.get_meta("debug_lead") if o.has_meta("debug_lead") else null)
						print("      lead=", "(%.1f,%.1f)" % [ol.position.x, ol.position.z] if is_instance_valid(ol) else "-", " zl=%.1f tgt=%.1f" % [o.get_meta("debug_zebra", 999.0), o.target_speed])
					for c in game.crossers:
						if c.state != "hidden":
							print("   walker ", c.cw, " ", c.state, " s=%.1f" % c.s)
					print("   emergency_alert=", game.emergency_alert)
				stuck_cars += 1
				still_time[id] = -9999.0
			var on_zebra := false
			# Violators that ignore the stop line or the signs may end up stuck on a zebra: that is
			# their offence. Everyone else must never stand on one.
			var reckless: bool = a.is_violator and a.violation_type in [game.VIOLATION_WAFFLE_BLOCK, game.VIOLATION_RED_LIGHT, game.VIOLATION_PRIORITY_SIGN, game.VIOLATION_PEDESTRIAN_YIELD, game.VIOLATION_ARROW_YIELD, game.VIOLATION_SOLID_LINE, game.VIOLATION_WRONG_LANE_TURN]
			# Following an emergency vehicle that braked hard inside the junction is a real-life case.
			var behind_siren: bool = is_instance_valid((a.get_meta("debug_lead") if a.has_meta("debug_lead") else null)) and a.get_meta("debug_lead").is_emergency
			if a.speed < 0.05 and not reckless and not behind_siren:
				for cw in game.crosswalks.values():
					if _body_on_rect(a, cw.rect):
						on_zebra = true
			zebra_time[id] = zebra_time.get(id, 0.0) + DT if on_zebra else 0.0
			if zebra_time[id] > 1.0:
				var zl = (a.get_meta("debug_lead") if a.has_meta("debug_lead") else null)
				if is_instance_valid(zl):
					print("   zlead: lane=%d %s (%.1f,%.1f) v%.1f" % [zl.lane, zl.route, zl.position.x, zl.position.z, zl.speed])
				print("zebra t=%.0f lane=%d route=%s pos=(%.1f,%.1f) viol=%s" % [f * DT, a.lane, a.route, a.position.x, a.position.z, a.violation_type])
				for o in cars:
					print("   car lane=%d route=%s pos=(%.1f,%.1f) yaw=%.2f v=%.1f turn=%.2f viol=%s emerg=%s" % [o.lane, o.route, o.position.x, o.position.z, o.rotation.y, o.speed, o.turn_t, o.violation_type, o.is_emergency])
				for c in game.crossers:
					if c.state != "hidden":
						print("   walker ", c.cw, " ", c.state, " s=%.1f" % c.s)
				zebra_parked += 1
				zebra_time[id] = -9999.0
		for k in game.crossers.size():
			var c: Dictionary = game.crossers[k]
			var before: String = prev_state.get(k, "")
			if before == "wait" and c.state == "cross":
				if not bool(c.get("forced", false)) and game.ped_light(game.crosswalks[c.cw].group) not in ["green", "off"]:
					walker_red_starts += 1
			if before == "cross" and c.state == "leave":
				walkers_crossed += 1
			prev_state[k] = c.state

	print("level: ", game.difficulty)
	print("soak: %d s, emergencies %d, walkers crossed %d" % [int(SECONDS), emergencies, walkers_crossed])
	var by_type := {}
	for id in viol_seen:
		var ty: String = viol_seen[id]
		if not by_type.has(ty):
			by_type[ty] = [0, 0]
		by_type[ty][0] += 1
		if viol_active.has(id):
			by_type[ty][1] += 1
	print("violators scheduled / happened: ", by_type)
	_check("Scheduled violators mostly commit their offence (%d of %d)" % [viol_active.size(), viol_seen.size()], viol_seen.size() > 0 and float(viol_active.size()) / float(viol_seen.size()) >= 0.5)
	_check("Emergency vehicles appeared in the run (%d)" % emergencies, emergencies > 0 or game.two_way)   # none on the easy level
	_check("Walkers actually crossed (%d)" % walkers_crossed, walkers_crossed > 5 * game.crosswalks.size())
	_check("No car drives through another car (%d overlapping frames)" % car_overlaps, car_overlaps == 0)
	_check("No car drives through a walker (%d frames)" % walker_hits, walker_hits == 0)
	_check("Walkers start only on their green (%d red starts)" % walker_red_starts, walker_red_starts == 0)
	_check("Lawful drivers never roll onto a zebra with a walker on it (%d)" % game.unscripted_zebra_offences, game.unscripted_zebra_offences == 0)
	_check("No car stands on a zebra (%d cases)" % zebra_parked, zebra_parked == 0)
	_check("No car stays stuck for 60 s (2.5 signal cycles) (%d cases)" % stuck_cars, stuck_cars == 0)
	game.queue_free()
	await process_frame
	print("Violator soak: %s" % ("PASS" if failed == 0 else "FAIL (%d)" % failed))
	quit(0 if failed == 0 else 1)


func _corners(car) -> PackedVector2Array:
	var fwd := Vector2(sin(car.rotation.y), cos(car.rotation.y))
	var right := Vector2(fwd.y, -fwd.x)
	var c := Vector2(car.position.x, car.position.z)
	return PackedVector2Array([c + fwd * 2.2 + right * 0.9, c + fwd * 2.2 - right * 0.9, c - fwd * 2.2 - right * 0.9, c - fwd * 2.2 + right * 0.9])


func _bodies_overlap(a, b) -> bool:
	if Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length() > 5.0:
		return false
	return not Geometry2D.intersect_polygons(_corners(a), _corners(b)).is_empty()


func _body_on_rect(car, rect: Rect2) -> bool:
	var r := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	return not Geometry2D.intersect_polygons(_corners(car), r).is_empty()
