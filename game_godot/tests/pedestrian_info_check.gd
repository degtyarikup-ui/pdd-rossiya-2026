extends SceneTree
var failures := 0
var checks := 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: run.call_deferred()
func lit(light: Node3D, side: String) -> bool:
	var aperture := light.find_child("aperture_info_" + side, true, false) as MeshInstance3D
	return bool((aperture.material_override as ShaderMaterial).get_shader_parameter("lit"))
func run() -> void:
	var plain := TrafficSignal.make({})
	expect(plain.find_child("lamp_info_left",true,false)==null,"legacy signal has no extra geometry")
	plain.free()
	var config := {"pedestrianSections":{"left":"off","right":"flashing"},"arrow":"left"}
	var before := JSON.stringify(config)
	var light := TrafficSignal.make(config)
	expect(not lit(light,"left") and lit(light,"right"),"independent initial states")
	expect(light.find_child("lamp_info_right",true,false).position.y < 2.6,"panels below main body")
	TrafficSignal.set_state(light,"red")
	expect(lit(light,"right"),"main red does not extinguish information panel")
	TrafficSignal.set_pedestrian_phase(light,false)
	expect(not lit(light,"right") and not lit(light,"left"),"flashing dark phase")
	TrafficSignal.set_pedestrian_phase(light,true)
	expect(lit(light,"right") and not lit(light,"left"),"flashing bright phase")
	expect(JSON.stringify(config)==before,"authored config unchanged")
	var assembly := RoadBuild.light_with_signs(light,["2.4","8.13"])
	expect(TrafficSignal.in_assembly(assembly)==light,"sections work with mounted signs")
	var sit := Situation.new()
	sit.data={"spec":{"yieldTo":[],"maneuver":"straight"},"actors":[],"exits":{},"exitWidths":{},"approachW":8.4,"redWait":null,"requiredStop":null,"trafficLights":{"state":"green"}}
	sit.add_child(assembly);sit.lights.append(assembly);root.add_child(sit)
	var junction := Junction.new(sit)
	junction._update_light_cycle(.51)
	expect(not lit(light,"right"),"information blinks even with steady main green")
	junction._update_light_cycle(0)
	expect(not lit(light,"right"),"pause freezes information phase")
	junction._update_light_cycle(.51)
	expect(lit(light,"right"),"information returns to bright phase")
	junction.release();junction._update_light_cycle(.51)
	expect(not lit(light,"right"),"answer does not reset information setting")
	sit.free()
	var single := TrafficSignal.make({"pedestrianSections":{"left":"on"}})
	expect(lit(single,"left"),"steady left")
	expect(not single.find_child("info_body_right",true,false).visible,"absent right housing hidden")
	TrafficSignal.set_pedestrian_phase(single,false)
	expect(lit(single,"left"),"steady panel does not flash")
	single.free()
	var tram := TrafficSignal.make({"tram":"straight","pedestrianSections":{"left":"on"}})
	expect(tram.find_child("lamp_info_left",true,false)==null,"tram configuration safely suppresses vehicle panels")
	tram.free()
	print("Pedestrian information: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
