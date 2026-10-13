## Assert contact widths on the actual rendered triangles, including unequal widths and medians.
extends SceneTree
var bad := 0
var checks := 0
func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok: bad+=1;print("FAIL ",label)
func _initialize() -> void:
	var scenery := Scenery.new("summer")
	for fixture in [["ticket_15_15","straight","ticket_17_6"],["ticket_10_13","straight","ticket_14_14"],["ticket_14_14","straight","ticket_13_13"]]:
		var a := RoadNetwork.load_scene(fixture[0]);var b := RoadNetwork.load_scene(fixture[2])
		var out: Dictionary = a.connections.exits[fixture[1]];var entry: Dictionary = b.connections.entry
		var profile := SceneStitch.joint_profile(out,entry)
		var basis := Basis(Vector3.UP,-SceneStitch.yaw(out.out))
		var axf := Transform3D(basis,-(basis*out.p))
		var bxf := SceneStitch.placement(entry,out,axf)
		var ab := {"port":out};ab.merge(profile,true);a.stitch_bindings=[ab]
		var bb := {"port":entry};bb.merge(profile,true);b.stitch_bindings=[bb]
		for item in [[a,axf],[b,bxf]]:
			var net: RoadNetwork = item[0];var xf: Transform3D=item[1]
			var mesh := net.surface_mesh(scenery,0.0,xf)
			var arrays := mesh.surface_get_arrays(0)
			var verts: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var layer: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
			var xs: Array = []
			for i in verts.size():
				var p: Vector3=xf*verts[i]
				if absf(p.z)<0.01 and absf(p.y)<0.001 and absf(p.x)<profile.width/2.0+1.0 and absf(layer[i].x-scenery.layer_of("asphalt"))<0.01: xs.append(p.x)
			expect(not xs.is_empty(),net.id+" rendered contact exists")
			if not xs.is_empty():
				expect(absf(float(xs.min())+profile.width/2.0)<0.01,net.id+" left contact edge")
				expect(absf(float(xs.max())-profile.width/2.0)<0.01,net.id+" right contact edge")
			var point: Vector3 = xf.affine_inverse()*Vector3(-profile.width/2.0+1.3,0,0)
			expect(net.is_drivable(point),net.id+" contact is drivable")
			if profile.median>0.001: expect(not net.is_drivable(xf.affine_inverse()*Vector3.ZERO),net.id+" divider blocks the centre")
	print("rendered joins: ",checks," checks, ",bad," failures")
	quit(1 if bad else 0)
