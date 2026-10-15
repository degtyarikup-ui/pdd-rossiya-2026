## Real editor/export fixtures and vehicle lenses. Generate fixtures with the matching Python test.
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func lenses(signals: Fleet.Signals, left: bool, right: bool) -> bool:
	if signals.materials.is_empty(): return false
	for material in signals.materials:
		if bool(material.get_shader_parameter("left_on")) != left: return false
		if bool(material.get_shader_parameter("right_on")) != right: return false
	for side in signals.glows:
		for glow in signals.glows[side]:
			if glow.visible != (left if side == "L" else right if side == "R" else left or right): return false
	return true

func run() -> void:
	var file := ProjectSettings.globalize_path("res://../scratch/actor-turn-signals-check/fixture.json")
	if not FileAccess.file_exists(file):
		check(false, "Run tools/network/tests/actor_turn_signals_check.py first")
		quit(1)
		return
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(file))
	for fixture in fixtures:
		var actor: Dictionary = fixture.actor
		var before := JSON.stringify(actor)
		check(Fleet.actor_signal_side(actor) == fixture.side, fixture.name + ": exported intention")
		check(Fleet.actor_signal_side(actor, 0, fixture.source) == fixture.side, fixture.name + ": network source agrees with export")
		check(JSON.stringify(actor) == before, fixture.name + ": lookup never mutates authored data")
	var actor := {"id":"bus", "type":"bus", "way":"straight", "length":100, "clearDistance":40,
		"turnSignal":"left", "signalPlan":[{"from":10,"to":20,"side":"right"}]}
	check(Fleet.actor_signal_side(actor) == "L", "Manual left starts immediately even when old plan starts later")
	check(Fleet.actor_signal_side(actor,25) == "L", "Manual left ignores a conflicting old plan interval")
	check(Fleet.actor_signal_side(actor,40) == "", "Manual signal cancels after clearing the manoeuvre")
	actor.clearDistance = null
	check(Fleet.actor_signal_side(actor,99) == "L" and Fleet.actor_signal_side(actor,100) == "", "Missing clearance cancels at route end")
	actor.staysPut = true
	actor.clearDistance = 0
	check(Fleet.actor_signal_side(actor,1000) == "L", "Stationary manual signal has no route or clearance timeout")
	actor.staysPut = false
	check(Fleet.actor_signal_side(actor) == "L", "A stale zero clearance from a parked template cannot suppress the manual lamp")
	check(Fleet.actor_signal_side(actor,0,{"actors":[{"id":"other","behaviour":{"turnSignal":"left"}},
		{"id":"bus","way":"right","behaviour":{"turnSignal":"off"}}]}) == "", "Manual off is matched by id and overrides stale export")
	actor.signalPlan = null
	actor.clearDistance = 40
	check(Fleet.actor_signal_side(actor,0,{"actors":[{"id":"bus","way":"right","behaviour":{}}]}) == "R", "Returning source to Auto clears a stale manual export")
	check(Fleet.actor_signal_side({"id":"person","type":"pedestrian","turnSignal":"left"}) == "", "Unsupported participants never acquire vehicle lamps")
	for kind in Fleet.SIGNAL_KINDS:
		var vehicle := Fleet.dps_car() if kind == "special" else NpcVehicle.make(kind,Color("#AF4D42"))
		root.add_child(vehicle)
		Fleet.add_blinkers(vehicle,"",2.1,.95)
		var signals: Fleet.Signals = vehicle.get_node("vehicle_signals")
		signals.set_process(false)
		for mode in ["left","right","off"]:
			var side := Fleet.actor_signal_side({"type":kind,"turnSignal":mode})
			signals.set_side(side)
			signals.clock = 0
			signals._process(0)
			check(lenses(signals,mode == "left",mode == "right"), kind + ": actual manual " + mode + " lenses and glows")
			signals._process(.4)
			check(lenses(signals,false,false),kind + ": manual signal pulses off")
		signals.set_side("L")
		signals.set_hazards(true)
		signals.clock = 0
		signals._process(0)
		check(lenses(signals,true,true),kind + ": hazards override manual side")
		signals.set_hazards(false)
		check(lenses(signals,true,false),kind + ": disabling hazards restores selected turn")
		vehicle.free()
	# Actual scene loading + question capture + answer release use the same resolver.
	var sit := Situation.load_scene("ticket_19_13",Scenery.new("summer"))
	root.add_child(sit)
	sit.data.actors[0].turnSignal = "right"
	var source: Dictionary = sit.network.data.actors.filter(func(a): return a.id == sit.data.actors[0].id)[0]
	source.behaviour.turnSignal = "right"
	var junction := Junction.new(sit)
	var signals: Fleet.Signals = sit.actors[0].get_node("vehicle_signals")
	signals.set_process(false)
	check(signals.side == "", "Loading prepares lamps without starting the question signal early")
	junction.begin_question_signals()
	check(signals.side == "R" and lenses(signals,false,true), "Actual question capture lights manual right instead of automatic left")
	junction.release()
	junction._update_signals()
	check(signals.side == "R", "Answer release preserves the manual signal")
	source.behaviour.turnSignal = "off"
	junction._update_signals()
	check(signals.side == "" and lenses(signals,false,false), "Manual off clears actual scene lamps")
	source.behaviour.erase("turnSignal")
	junction._update_signals()
	check(signals.side == "L", "Auto restores the selected left manoeuvre")
	sit.free()
	print("actor turn signals: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
