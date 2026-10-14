## Generated six-lane sections must present a real four-lane contact to the city.
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
	var ordinary := network(fixtures.back())
	var contacts := 0
	for fixture in fixtures:
		var net := network(fixture)
		for port in net.connections.ports:
			assert(port.lanes == 4, 'Six-lane interiors join the city as 2+2')
			assert(absf(port.width-14)<.05 and port.median<.01 and port.declared_median==0, 'Four-lane contact has no phantom median')
		if fixture.get('reference',false): continue
		var out: Dictionary = net.connections.exits.straight
		var entry: Dictionary = ordinary.connections.entry
		var profile := SceneStitch.joint_profile(out,entry)
		assert(profile.median==0 and absf(profile.width-14)<.05)
		var basis := Basis(Vector3.UP,-SceneStitch.yaw(out.out))
		var xf := Transform3D(basis,-(basis*out.p))
		var binding := {"port":out};binding.merge(profile,true);net.stitch_bindings=[binding]
		var mesh := net.surface_mesh(scenery,0,xf)
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var layers: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var xs := []
		for i in verts.size():
			var p := xf*verts[i]
			if absf(p.z)<.01 and absf(p.y)<.001 and absf(layers[i].x-scenery.layer_of('asphalt'))<.01: xs.append(p.x)
		assert(not xs.is_empty())
		assert(absf(float(xs.min())+profile.width/2)<.05 and absf(float(xs.max())-profile.width/2)<.05,'Rendered contact aligns to the ordinary road')
		for x in [-5.25,-1.75,1.75,5.25]:
			assert(net.is_drivable(xf.affine_inverse()*Vector3(x,0,-1)), 'All four contact lanes are drivable')
		contacts += 1
	print('Highway: %d rendered four-lane joins, lane metadata, medians and drivable contact PASS'%contacts)
	quit()
