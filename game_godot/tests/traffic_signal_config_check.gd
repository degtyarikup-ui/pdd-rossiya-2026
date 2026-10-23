## JSON null is an absent supplementary section, including during staged startup.
## Check selection before instantiation so a broken selector fails without hanging the runner.
extends SceneTree

const VARIANTS := ["standard", "left", "right", "straight", "tram"]
const City := preload("res://scripts/world.gd")
var checks := 0
var failures := 0
var saved_lights := 0
var playable_lights := 0
var null_arrows := 0

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func signal_config(config: Dictionary, expected: String, label: String) -> void:
	var before := JSON.stringify(config)
	var supported := TrafficSignal.supports(config)
	var variant := TrafficSignal.kind(config)
	expect(supported, label + ": canonical geometry supports the saved configuration")
	expect(variant == expected, label + ": selects " + expected + ", got " + variant)
	if not supported or variant not in VARIANTS: return
	var path := "res://models/street/traffic_light_%s.glb" % variant
	expect(ResourceLoader.exists(path), label + ": selected model exists")
	if not ResourceLoader.exists(path): return
	# Situation.load_scene_staged resumes before building every traffic light.
	await process_frame
	var light := TrafficSignal.make(config)
	expect(is_instance_valid(light), label + ": staged signal instantiates")
	if is_instance_valid(light):
		expect(light.get_meta("traffic_signal", false), label + ": canonical signal is initialized")
		expect(light.find_child("lamp_red", true, false) != null, label + ": main red aperture exists")
		expect((light.find_child("lamp_arrow", true, false) != null) == (expected in ["left", "right", "straight"]),
			label + ": supplementary section matches authored direction")
		Models.release_geometry(light)
		light.free()
	var mini := TrafficSignal.make_mini(config)
	expect(is_instance_valid(mini), label + ": mini-game uses the same normalized selector")
	if is_instance_valid(mini):
		Models.release_geometry(mini)
		mini.free()
	expect(JSON.stringify(config) == before, label + ": authored config stays unchanged")

func run() -> void:
	for fixture: Dictionary in [{}, {"arrow": null}, {"arrow": ""}, {"arrow": "none"}, {"arrow": null, "tram": null}]:
		await signal_config(fixture, "standard", JSON.stringify(fixture))
	for direction in ["left", "right", "straight"]:
		await signal_config({"arrow": direction}, direction, direction)
		await signal_config({"arrow": null, "tram": direction}, "tram", "tram " + direction)
	for invalid in ["up", "<null>", true, 123]:
		expect(not TrafficSignal.supports({"arrow": invalid}), "unsupported arrow stays on the archived-model path: " + str(invalid))
	for id in JSON.parse_string(FileAccess.get_file_as_string("res://situations/index.json")):
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://situations/%s/scene.json" % id))
		var authored_path := "res://network/%s.json" % id
		var playable := FileAccess.file_exists(authored_path) and City._scene_playable(JSON.parse_string(FileAccess.get_file_as_string(authored_path)))
		for index in data.get("lights", []).size():
			var config: Dictionary = data.lights[index]
			saved_lights += 1
			if playable: playable_lights += 1
			if config.has("arrow") and config.arrow == null: null_arrows += 1
			var arrow: Variant = config.get("arrow")
			var expected := "tram" if config.get("tram") else str(arrow) if arrow in ["left", "right", "straight"] else "standard"
			await signal_config(config, expected, "%s/light_%d" % [id, index])
	expect(saved_lights > 0 and playable_lights > 0 and null_arrows > 0, "real archived and playable null-arrow signals are covered")
	for frame in 3: await process_frame
	print("traffic signal configs: ", checks, " checks, ", failures, " failures; ", saved_lights,
		" saved, ", playable_lights, " playable, ", null_arrows, " explicit null arrows")
	quit(1 if failures else 0)
