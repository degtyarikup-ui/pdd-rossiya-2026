extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1, "Pass the disposable build fixture path")
	var net := RoadNetwork.new()
	net.data = {"roads":[],"routes":[],"markings":[]}
	net.build = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var scenery := Scenery.new("summer")
	var mesh := net.surface_mesh(scenery)
	assert(mesh.get_surface_count() == 1)
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var paint_count := 0
	for vertex in vertices:
		if absf(vertex.y - .055) < .001: paint_count += 1
	assert(paint_count > 60, "Exported arrow triangles reach the runtime road mesh")
	print("Direction arrow runtime PASS: exported paint is present in the real road mesh")
	quit()
