## Participant poses have yaw but no ring-traffic dir. Exercise the real
## camera path used to retire departures, including a rotated retained scene.
extends SceneTree
var checks := 0
var failures := 0

class VisibilityWorld extends "res://scripts/world.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

func _initialize() -> void: run.call_deferred()
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", label)

func run() -> void:
	root.size = Vector2i(800, 600)
	var world = load("res://main.tscn").instantiate()
	world.set_script(VisibilityWorld)
	root.add_child(world)
	world.camera = Camera3D.new()
	world.add_child(world.camera)
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 42.0
	world.camera.near = 0.1; world.camera.far = 1000.0
	world.camera.position = Vector3(0, 42, -44)
	world.camera.look_at(Vector3.ZERO)
	world.camera.current = true
	await process_frame

	var participant := {"x": 0.0, "z": 0.0, "len": 4.4, "yaw": 0.0}
	expect(world._ambient_visible(participant), "participant yaw without dir remains visible")
	expect(not participant.has("dir"), "visibility does not mutate a participant into ring traffic")
	for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
		var visible: Dictionary = participant.duplicate()
		visible.yaw = yaw
		expect(world._ambient_visible(visible), "participant visible at yaw " + str(yaw))
		visible.z = -300.0
		expect(not world._ambient_visible(visible), "participant behind camera at yaw " + str(yaw))
		visible.z = 0.0; visible.x = 300.0
		expect(not world._ambient_visible(visible), "participant outside side frustum at yaw " + str(yaw))

	# Preserve ordinary traffic's dir-based heading when no explicit yaw exists.
	for direction in [-1.0, 1.0]:
		for p in [Vector3.ZERO, Vector3(300, 0, 0), Vector3(0, 0, -300)]:
			var traffic := {"x": p.x, "z": p.z, "len": 4.4, "dir": direction}
			var explicit := traffic.duplicate()
			explicit.yaw = 0.0 if direction > 0 else PI
			expect(world._ambient_visible(traffic) == world._ambient_visible(explicit), "ring heading default " + str(direction) + " at " + str(p))
	expect(world._ambient_visible({"x": 0.0, "z": 0.0, "len": 4.4}), "generic pose safely defaults to forward heading")

	# A long turned body can still overlap the view while its centre is outside.
	var edge := 0.0
	while edge < 100.0 and world.camera.is_position_in_frustum(Vector3(edge, 0, 0)): edge += 0.25
	var partial := {"x": edge + 3.0, "z": 0.0, "len": 20.0, "yaw": PI * 0.5}
	expect(not world.camera.is_position_in_frustum(Vector3(partial.x, 0, 0)), "partial-body fixture centre outside view")
	expect(world._ambient_visible(partial), "visible tail of sideways bus prevents premature retirement")

	var sit := Situation.new()
	world.add_child(sit)
	var motion := Junction.Motion.new()
	motion.node = Node3D.new()
	motion.hw = 0.9; motion.hl = 2.1; motion.type = "police"
	sit.add_child(motion.node)
	for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
		sit.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(17, 0, 23))
		motion.node.position = sit.to_local(Vector3.ZERO)
		motion.node.rotation.y = 0.31
		expect(not world._motion_out_of_view(sit, motion), "real departure remains visible in scene frame " + str(yaw))
		motion.node.position = sit.to_local(Vector3(300, 0, 0))
		expect(world._motion_out_of_view(sit, motion), "real departure can retire beyond view in scene frame " + str(yaw))
	# This callback executes every frame for moving ticket participants. Repeated
	# valid checks must neither fail nor silently treat the participant as hidden.
	motion.node.position = sit.to_local(Vector3.ZERO)
	var all_visible := true
	for frame in 240: all_visible = not world._motion_out_of_view(sit, motion) and all_visible
	expect(all_visible, "participant stays visible through repeated per-frame callbacks")
	world.queue_free()
	await process_frame
	print("actor visibility: ", checks, " checks, ", failures, " failures; renderer=", DisplayServer.get_name())
	quit(1 if failures else 0)
