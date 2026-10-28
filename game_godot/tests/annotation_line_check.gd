extends SceneTree

const Annotation := preload("res://scripts/scene_annotation.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size()==2,"Pass disposable geometry fixtures and the exported scene")
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	for fixture in fixtures:
		var geometry := Annotation.geometry(fixture.route,float(fixture.border))
		assert(geometry.size()==fixture.geometry.size(),"JS and Godot produce the same annotation mesh")
		for i in geometry.size():
			var expected: Array = fixture.geometry[i]
			assert(Vector2(geometry[i].x,geometry[i].z).distance_to(Vector2(expected[0],expected[1]))<.00001)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var sit := Situation.new()
	sit.data=data
	sit._build_evidence("res://no-legacy-annotation-fixture/")
	assert(sit._evidence.size()==data.labels.size(),"No annotation becomes an answer token")
	assert(sit._guide.get_child_count()==data.trajectories.size()+data.annotations.size())
	for node in sit._guide.get_children():
		if node.name=="Annotation":
			assert(node.get_child_count()==2,"Ink and contrasting outline survive export")
	sit.free()
	# Annotations remain visible independently of guide visibility and never replace its fallback.
	for visible in [true,false]:
		var plain := Situation.new()
		plain.data={"trajectories":[],"labels":[],"annotations":data.annotations,"showPlayerGuide":visible,"playerGuidePoints":[[0,0],[0,8]]}
		plain._build_evidence("res://no-legacy-annotation-fixture/")
		assert(plain._guide.get_child_count()==data.annotations.size()+(1 if visible else 0))
		assert(plain._evidence.is_empty())
		plain.free()
	print("Annotation runtime PASS: geometry parity, outlined lines/arrows, no letters and independent guide visibility")
	quit()
