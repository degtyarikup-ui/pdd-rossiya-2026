extends SceneTree
var checks := 0
var failures := 0
var player := {"p":Vector3(100,0,100),"yaw":0.0,"hw":.9,"hl":2.0}
func expect(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error(label)
func _initialize() -> void:
	call_deferred("run")
func fixture(state: String, legacy := false) -> Situation:
	var sit := Situation.new()
	sit.data={"spec":{"yieldTo":[],"maneuver":"straight"},"actors":[],"exits":{},"exitWidths":{},"approachW":8.4,"redWait":5,"requiredStop":null,"trafficLights":{"state":state}}
	for i in 2:
		var light := Node3D.new() if legacy else TrafficSignal.make({})
		if legacy:
			for colour in ["red","yellow","green"]:
				var lamp := Node3D.new();lamp.name="lamp_"+colour
				var disc := MeshInstance3D.new();disc.mesh=QuadMesh.new();lamp.add_child(disc);light.add_child(lamp)
		sit.add_child(light);sit.lights.append(light)
	root.add_child(sit)
	return sit
func lit(sit: Situation, colour: String) -> bool:
	var lamp := sit.lights[0].find_child("lamp_"+colour,true,false)
	return (lamp.get_meta("halo") as Node3D).visible
func run() -> void:
	for legacy in [false,true]:
		var sit := fixture("flashing_green",legacy)
		var before := JSON.stringify(sit.data)
		var junction := Junction.new(sit)
		expect(lit(sit,"green") and not lit(sit,"yellow") and not lit(sit,"red"),"initial green only")
		junction.update_actors(.51,player,0)
		expect(not lit(sit,"green") and junction._signal_state=="flashing_green","dark blink remains a green signal")
		junction.update_actors(0,player,0)
		expect(not lit(sit,"green"),"pause freezes the blink")
		junction.update_actors(.51,player,0)
		expect(lit(sit,"green"),"next green flash")
		junction.update_actors(120,player,0)
		expect(junction._signal_state=="flashing_green" and not lit(sit,"yellow"),"arbitrary question time never starts yellow")
		junction.release()
		expect(junction._signal_state=="yellow" and lit(sit,"yellow") and not lit(sit,"green"),"answer tap starts yellow immediately")
		junction.update_actors(0,player,0)
		expect(junction._answer_signal_elapsed==0,"pause freezes the answer transition")
		junction.update_actors(1.1,player,0)
		junction.resolve(Drive.new())
		junction.release()
		expect(is_equal_approx(junction._answer_signal_elapsed,1.1),"closing feedback/explanation never restarts yellow")
		junction.update_actors(1.899,player,0)
		expect(lit(sit,"yellow") and not lit(sit,"red"),"yellow remains for the full three seconds")
		junction.update_actors(.002,player,0)
		expect(lit(sit,"red") and not lit(sit,"yellow") and junction._signal_state=="red","yellow then steady red")
		junction.resolve(Drive.new())
		junction.update_resolution(100,Drive.new(),Vector3.ZERO)
		junction.update_actors(100,player,0)
		expect(junction._signal_state=="red","repeat resolve and an old redWait cannot reopen green")
		expect(JSON.stringify(sit.data)==before,"runtime phases never rewrite authored state")
		sit.free()
	var direct := fixture("flashing_green")
	var j := Junction.new(direct)
	j.resolve(Drive.new());expect(j._signal_state=="yellow","direct resolve uses the same answer gate")
	j.update_actors(4,player,0);expect(j._signal_state=="red","large frame delta reaches red")
	direct.free()
	for state in ["green","flashing_yellow"]:
		var sit := fixture(state);sit.data.redWait=null
		var old := Junction.new(sit);old.release();old.resolve(Drive.new());old.update_actors(10,player,0)
		expect(old._signal_state==state,"legacy "+state+" behaviour stays unchanged")
		sit.free()
	print("Flashing green runtime: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
