extends SceneTree
func _initialize() -> void:
	var net := RoadNetwork.new()
	net.data={"roads":[],"routes":[],"markings":[]}
	net.build=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var mesh := net.surface_mesh(Scenery.new("summer"))
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var count := 0
	var yellow := Color("#f5b025")
	var lo := INF
	var hi := -INF
	for i in vertices.size():
		if absf(vertices[i].y-.055)<.001 and Vector3(colours[i].r,colours[i].g,colours[i].b).distance_to(Vector3(yellow.r,yellow.g,yellow.b))<.01:
			count+=1;lo=minf(lo,vertices[i].x);hi=maxf(hi,vertices[i].x)
	assert(count>60,"Actual road mesh contains the yellow zigzag triangles")
	assert(hi-lo<1.5,"The runtime paint remains a narrow strip")
	print("Bus stop runtime PASS: yellow triangles, height and narrow footprint in the real Godot mesh")
	quit()
