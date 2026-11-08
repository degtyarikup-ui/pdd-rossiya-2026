extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", msg)

func run() -> void:
	print("--- Snow Check: Falling Snow Particles ---")
	var snow := Snow.new(64)
	root.add_child(snow)
	expect(snow != null, "Snow instance created")
	expect(snow.multimesh != null, "MultiMesh created")
	expect(snow.multimesh.instance_count == 64, "Instance count is 64")
	expect(snow.flakes.size() == 64, "Flakes array size is 64")
	expect(snow.material_override is StandardMaterial3D, "Material override is StandardMaterial3D")
	var mat := snow.material_override as StandardMaterial3D
	expect(mat.vertex_color_use_as_albedo, "Vertex color used as albedo")
	expect(mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Snow is unshaded for crisp visibility")
	expect(mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Snow transparency enabled")

	# Test stepping
	snow.step(0.1, Vector3(0, 0, 0))
	for i in snow.flakes.size():
		var flake: Dictionary = snow.flakes[i]
		expect(flake.born, "Flake %d is born after step" % i)
		expect(flake.y >= 0.03, "Flake %d is above ground" % i)

	# Test stepping with camera offset
	snow.step(0.5, Vector3(10.0, 0.0, -15.0))
	var t0: Transform3D = snow.multimesh.get_instance_transform(0)
	expect(t0.origin.is_finite(), "Instance 0 transform has valid finite coordinates")

	snow.queue_free()
	print("Snow check: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)
