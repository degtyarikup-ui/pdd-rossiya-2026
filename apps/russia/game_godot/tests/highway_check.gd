## Saved highway end choices must match real six/four-lane sections and rendered joins.
extends SceneTree
func network(data: Dictionary) -> RoadNetwork:
	var net := RoadNetwork.new()
	net.id = data.id
	net.data = data
	net.build = data.build
	for r in net.build.carriageway:
		var outer := RoadNetwork._pts(r.outer)
		var holes := []
		for hole in r.holes: holes.append(RoadNetwork._pts(hole))
		net._roads.append({"outer":outer,"holes":holes,"box":RoadNetwork._box(outer)})
	net.connections = SceneStitch.describe(data,data.build)
	return net
func _initialize() -> void:
	var path := 'res://../scratch/highway-fixtures.json'
	assert(FileAccess.file_exists(path), 'Run tools/network/tests/highway_check.py first')
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	var scenery := Scenery.new('summer')
	var contacts := 0
	for fixture in fixtures:
		var net := network(fixture)
		for port in net.connections.ports:
			var expected: Dictionary = fixture.expectedPorts[port.node]
			var label := '%s / %s'%[fixture.testCase,port.node]
			assert(port.lanes == expected.lanes, label+': saved end choice controls lane count')
			assert(absf(port.width-expected.width)<.08, label+': measured width matches saved section')
			assert(absf(port.median-expected.median)<.08, label+': measured divider matches saved section')
			assert(absf(port.declared_median-expected.median)<.01, label+': default divider is present in metadata')
			# Equal profiles form a direct join. Mixed sections get a separate runtime
			# connector, checked in highway_run_check.gd instead of squeezing this cut.
			var profile := SceneStitch.joint_profile(port,port)
			assert(absf(profile.median-expected.median)<.01 and absf(profile.width-expected.width)<.08, label)
			var basis := Basis(Vector3.UP,-SceneStitch.yaw(port.out))
			var xf := Transform3D(basis,-(basis*port.p))
			var binding := {"port":port};binding.merge(profile,true);net.stitch_bindings=[binding]
			var mesh := net.surface_mesh(scenery,0,xf)
			var arrays := mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var layers: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var xs := []
			for i in verts.size():
				var p := xf*verts[i]
				if absf(p.z)<.01 and absf(p.y)<.001 and absf(layers[i].x-scenery.layer_of('asphalt'))<.01: xs.append(p.x)
			assert(not xs.is_empty(), label+': no asphalt at rendered cut')
			assert(absf(float(xs.min())+profile.width/2)<.08 and absf(float(xs.max())-profile.width/2)<.08,
				label+': rendered cut retains the entire section')
			if expected.median>0:
				assert(xs.all(func(x): return absf(x)>=expected.median/2-.08), label+': asphalt cannot cover the divider')
				assert(not net.is_drivable(xf.affine_inverse()*Vector3(0,0,-1)), label+': divider stays impassable')
			for i in int(expected.lanes/2):
				for sign in [-1,1]:
					var x: float = sign*(expected.median/2+1.75+3.5*i)
					assert(net.is_drivable(xf.affine_inverse()*Vector3(x,0,-1)), label+': every contact lane stays drivable')
			contacts += 1
	print('Highway: %d measured/rendered six/four-lane cuts, continuous medians and drivable lanes PASS'%contacts)
	quit()
