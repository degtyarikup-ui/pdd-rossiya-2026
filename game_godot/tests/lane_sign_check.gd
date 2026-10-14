extends SceneTree

const Generator := preload("res://scripts/lane_sign.gd")


func _initialize() -> void:
	assert(Generator.normalize(null) == Generator.DEFAULT_LANES)
	assert(Generator.normalize([]) == Generator.DEFAULT_LANES)
	assert(Generator.normalize([[], ["invalid"], ["right", "left", "right"], "straight"]) == [["straight"], ["straight"], ["left", "right"], ["straight"]])
	assert(Generator.dimensions(Generator.DEFAULT_LANES).is_equal_approx(Vector2(3, 1.875)))
	var source := {"code": "5.15.1", "laneDirections": Generator.DEFAULT_LANES, "mount": "cantilever", "reach": 7, "pos": [12, 34], "yaw": PI}
	var saved := JSON.stringify(source)
	var restored: Dictionary = JSON.parse_string(saved)
	assert(Generator.svg(source.laneDirections) == Generator.svg(restored.laneDirections))
	var tex := Generator.texture(source.laneDirections)
	assert(tex != null and tex.get_width() == 640 and tex.get_height() == 400)
	assert(tex == Generator.texture(restored.laneDirections), "Equal saved signs must reuse the texture")
	assert(JSON.stringify(source) == saved, "Rendering must not mutate authored data")
	var image := tex.get_image()
	assert(image.get_pixel(128, 60).r > 0.9, "The left lane has an upward arrowhead")
	assert(image.get_pixel(44, 188).r > 0.9, "The left lane also has a left arrowhead")
	assert(image.get_pixel(512, 60).r > 0.9, "The right lane has an upward arrowhead")
	assert(image.get_pixel(596, 188).r > 0.9, "The right lane also has a right arrowhead")
	assert(image.get_pixel(88, 80).b > 0.7 and image.get_pixel(88, 80).r < 0.2, "Blue remains blue between the symbols")
	var single_turns := Generator.texture([["left"], ["right"]]).get_image()
	assert(single_turns.get_pixel(44, 80).r > 0.9, "Single left turn reaches the top")
	assert(single_turns.get_pixel(404, 80).r > 0.9, "Single right turn reaches the top")
	var cases := 0
	for count in range(1, 7):
		for mask in range(1, 8):
			var directions: Array = []
			for direction in 3:
				if mask & (1 << direction):
					directions.append(Generator.DIRECTIONS[direction])
			var lanes: Array = []
			for lane in count:
				lanes.append(directions.duplicate())
			var generated := Generator.texture(lanes)
			assert(generated != null)
			assert(generated.get_height() == 400)
			assert(generated.get_width() == (count * 48 + 16) * 4)
			assert(is_equal_approx(Generator.height(lanes), 1.875))
			cases += 1
	# Optional JS-generated cases make the native/browser parity assertion exact.
	var parity := "res://../scratch/editor-signs/lane-sign-parity.json"
	var parity_cases := 0
	if FileAccess.file_exists(parity):
		var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(parity))
		assert(fixtures.size() == cases)
		for fixture in fixtures:
			assert(Generator.svg(fixture.lanes) == fixture.svg, "Browser and Godot must generate identical SVG geometry")
			assert(is_equal_approx(Generator.width(fixture.lanes), float(fixture.width)))
			assert(is_equal_approx(Generator.height(fixture.lanes), float(fixture.height)))
			parity_cases += 1
	print("Lane sign constructor: %d combinations, native texture and persistence PASS; %d browser/native parity cases" % [cases, parity_cases])
	quit(0)
