extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var sit := Situation.new()
	sit.data = data
	var guide := sit._trajectory_guide()
	assert(guide.get_child_count() == 0, "Standalone letters create neither ribbons nor the fallback guide")
	assert(data.labels.size() == 2)
	for label in data.labels:
		var token := Situation._letter_node(label.letter, Situation.letter_colour(label.letter))
		assert(token.get_child_count() > 0, "Each letter has visible geometry")
		assert(label.pos[1] == .8)
		token.free()
	guide.free(); sit.free()
	print("Standalone letters runtime PASS")
	quit()
