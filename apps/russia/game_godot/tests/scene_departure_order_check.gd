## Real saved lane-change lessons: posed traffic signals on approach and leaves in the authored order.
extends SceneTree
const DT := 1.0 / 60.0
var checks := 0
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func simulate(sid: String, first_id: String, second_id: String, correct: bool) -> void:
	var sit := Situation.load_scene(sid, Scenery.new("summer"))
	root.add_child(sit)
	var junction := Junction.new(sit)
	var first: Junction.Motion = junction.motions.filter(func(m): return m.id == first_id)[0]
	var second: Junction.Motion = junction.motions.filter(func(m): return m.id == second_id)[0]
	var player := Drive.new()
	player.pos = sit.network.stop_point()
	player.yaw = float(sit.network.data.stop.get("yaw", 0))
	var before := JSON.stringify(sit.network.data)
	var overtaking := sid == 'ticket_8_7'
	var passed_in_left_lane := false
	var returned_after_pass := false
	var return_before_pass := false
	var signal_phases := {"left":false,"off_between":false,"right":false,"off_after":false}
	var signal_phase_correct := true
	for m in [first, second]:
		var signals := m.node.get_node_or_null("vehicle_signals") as Fleet.Signals
		var actor: Dictionary = sit.data.actors.filter(func(a):return a.id==m.id)[0]
		var intended := Fleet.actor_signal_side(actor,0,sit.network.data)
		expect((signals == null and intended == "") or (signals != null and signals.side == intended),
			sid + ": saved indicator state visible before capture for " + m.id)
	for frame in 60: junction.update_actors(DT, player.footprint(), 0.0)
	expect(first.distance == 0.0 and second.distance == 0.0, sid + ": early indicators do not move posed actors")
	junction.begin_question_signals()
	if correct: junction.resolve(player)
	else: junction.release()
	var first_started := -1.0
	var second_started := -1.0
	var second_waited := true
	var collision := false
	for frame in 600:
		var was_first_clear := first.cleared
		var hit := junction.update_actors(DT, player.footprint(), 0.0)
		collision = collision or hit != null or Drive.overlap(first.footprint(), second.footprint(), .04)
		for a in junction.motions:
			for b in junction.motions:
				if a != b: collision = collision or Drive.overlap(a.footprint(), b.footprint(), .04)
		if first.distance > .02 and first_started < 0: first_started = frame * DT
		if second.distance > .02 and second_started < 0:
			second_started = frame * DT
			second_waited = was_first_clear
		if overtaking:
			var signals := second.node.get_node_or_null("vehicle_signals") as Fleet.Signals
			var phase := "left" if second.distance < 10 else "off_between" if second.distance > 23 and second.distance < 35 else "right" if second.distance > 48 and second.distance < 57 else "off_after" if second.distance > 75 else ""
			if phase != "":
				signal_phases[phase] = true
				var expected := "L" if phase == "left" else "R" if phase == "right" else ""
				signal_phase_correct = signal_phase_correct and signals != null and signals.side == expected
			if second.pos.x > -3.0 and second.pos.z > first.pos.z + first.hl + second.hl + 1.0:
				passed_in_left_lane = true
			if second.distance > 15 and second.pos.x < -4.0:
				return_before_pass = return_before_pass or not passed_in_left_lane
				returned_after_pass = passed_in_left_lane
		if frame == 5:
			expect(first.distance > .02 and (second.distance > .02 if overtaking else second.distance == 0),
				sid + ": both overtaking vehicles start promptly" if overtaking else sid + ": priority actor starts promptly while yielding actor waits")
	expect(first_started >= 0 and first_started < .2, sid + ": first actor starts within 0.2 seconds after answer")
	if overtaking:
		expect(second_started >= 0 and second_started < .2, sid + ": overtaking car starts within 0.2 seconds")
		expect(passed_in_left_lane and returned_after_pass and not return_before_pass, sid + ": car passes the moving truck fully before returning right")
		expect(signal_phases.values().all(func(seen):return seen) and signal_phase_correct,
			sid + ": left indicator cancels after lane change, right indicator announces the return then cancels")
	else:
		expect(second_started > first_started and second_started < 6.0 and second_waited, sid + ": second actor starts after priority clearance and within six seconds")
	expect(first.distance > 45 and second.distance > 35, sid + ": both drive away with player still at the question")
	expect(not collision, sid + ": departure order avoids participant/player collisions")
	expect(JSON.stringify(sit.network.data) == before, sid + ": simulation preserves saved scene")
	print(sid, ' ', 'correct' if correct else 'wrong', ': starts ', first_started, ' / ', second_started, '; distances ', first.distance, ' / ', second.distance)
	sit.free()
	Situation.forget(sid)
func run() -> void:
	for correct in [false, true]:
		simulate('ticket_6_8', 'car', 'truck', correct)
		simulate('ticket_12_8', 'changing_motorcycle', 'changing_car', correct)
		simulate('ticket_7_8', 'blue_car', 'truck', correct)
		simulate('ticket_39_8', 'blue_car', 'changing_car', correct)
		simulate('ticket_8_7', 'truck', 'changing_car', correct)
	# Arc distance, not number of control points, determines a straight actor's speed.
	var sparse := Junction.Path.new([[0,0],[0,60]])
	var points: Array = []
	for i in 121: points.append([0.0, i * .5])
	var dense := Junction.Path.new(points)
	for distance in [0.0, 1.0, 10.0, 35.0, 60.0]:
		expect(sparse.point_at(distance).distance_to(dense.point_at(distance)) < .001, 'straight path control-point count does not change metres travelled')
	print('Scene departure order: ', checks, ' checks, ', failures, ' failures')
	quit(0 if failures == 0 else 1)
