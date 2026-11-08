## Real engine mesh/navigation from pocket_geometry_check.py disposable fixtures.
extends SceneTree

func _initialize() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://../scratch/pocket-fixtures.json"))
	assert(fixtures.size() == 11)
	var scenery := Scenery.new("summer")
	for fixture: Dictionary in fixtures:
		var net := RoadNetwork.new()
		net.data = fixture.scene
		net.build = fixture.build
		for poly: Dictionary in net.build.carriageway:
			var outer := RoadNetwork._pts(poly.outer)
			var holes: Array = []
			for hole: Array in poly.holes:
				holes.append(RoadNetwork._pts(hole))
			net._roads.append({"outer": outer, "holes": holes, "box": RoadNetwork._box(outer)})
		var mesh := net.surface_mesh(scenery)
		assert(mesh.get_surface_count() == 1, "Pockets stay in the existing batched road mesh")
		var ground := GroundMap.new(mesh, scenery)
		var drive := Vector3(fixture.drive[0], 0, fixture.drive[1])
		var walk := Vector3(fixture.walk[0], 0, fixture.walk[1])
		assert(net.is_drivable(drive), "Native carriageway includes the pocket")
		assert(not net.is_drivable(walk), "Raised sidewalk remains outside carriageway")
		assert((ground.at(drive) & GroundMap.ROAD) != 0)
		assert((ground.at(drive) & GroundMap.WALK) == 0)
		assert(absf(ground.walk_height(walk) - .18) < .001)
		for vertex: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			assert(vertex.is_finite())
		print("PASS native pocket terrain/navigation: ", fixture.name)
	quit()
