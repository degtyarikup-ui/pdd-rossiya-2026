## Editor paint -> saved scene/legacy network -> independent body and cab shaders.
extends SceneTree
var bad := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		print("FAIL ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var original := {"id":"car_1", "config":{"color":"#778FAD", "cabColor":"#F2F2EC", "sidecar":true}}
	var before := original.duplicate(true)
	var source := {"actors":[{"id":"other", "paint":"#000000"}, {"id":"car_1", "paint":"#C0392B"}]}
	var config := Situation._actor_config(original, source)
	check(config.color == "#C0392B" and config.cabColor == "#C0392B", "saved paint overrides body and cab by actor id")
	check(config.sidecar == true and original == before, "other settings and source colours survive")
	var exported := original.duplicate(true)
	exported.paint = "#317ED4"
	check(Situation._actor_config(exported).color == "#317ED4", "exported paint works without a network")
	check(Situation._actor_config(exported, {"actors":[{"id":"car_1"}]}) == original.config, "cleared editor swatch restores original body and cab")
	check(Situation._actor_config(original, {"actors":[{"id":"car_1", "paint":"invalid"}]}) == original.config, "invalid swatch preserves model colours")
	var paints := 0
	for file in DirAccess.get_files_at("res://network"):
		if not file.ends_with(".json"): continue
		var net: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://network/" + file))
		var scene_path := "res://situations/" + file.get_basename() + "/scene.json"
		if not FileAccess.file_exists(scene_path): continue
		var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(scene_path))
		for actor in scene.get("actors", []):
			var authored := {}
			for item in net.get("actors", []):
				if str(item.id) == str(actor.id): authored = item; break
			if not authored.get("paint") or not actor.type in NpcVehicle.KINDS: continue
			config = Situation._actor_config(actor, net)
			var vehicle := NpcVehicle.make(actor.type, Color(config.color), config)
			var material := (vehicle.get_node("body") as MeshInstance3D).material_override as ShaderMaterial
			var colour := Color(authored.paint)
			var expected := Vector3(colour.r, colour.g, colour.b)
			check(material.get_shader_parameter("paint_colour").is_equal_approx(expected), file + "/" + str(actor.id) + " body")
			check(material.get_shader_parameter("cab_colour").is_equal_approx(expected), file + "/" + str(actor.id) + " cab")
			vehicle.free()
			paints += 1
	check(paints > 0, "checked saved editor choices")
	var situation := Situation.load_scene("ticket_8_13", Scenery.new("summer"))
	for i in situation.actors.size():
		var actor: Dictionary = situation.data.actors[i]
		var expected := Situation._actor_config(actor, situation.network.data)
		if actor.type in NpcVehicle.KINDS:
			var material := (situation.actors[i].get_node("body") as MeshInstance3D).material_override as ShaderMaterial
			var colour := Color(expected.color)
			check(material.get_shader_parameter("paint_colour").is_equal_approx(Vector3(colour.r, colour.g, colour.b)), "loaded scene " + str(actor.id))
	situation.free()
	print("Actor paints: ", checks, " checks; ", paints, " saved swatches; ", bad, " failures")
	quit(1 if bad else 0)
