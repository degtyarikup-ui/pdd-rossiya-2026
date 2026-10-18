## Real divided-road scene contacts: no square block of the declared width at the joint; the lawn
## is bridged from the contact into each scene's own nose, so the divider runs on unbroken.
extends SceneTree
var bad := 0
var count := 0
func check(ok: bool, what: String) -> void:
	count+=1
	if not ok: bad+=1;print("FAIL ",what)
func _initialize() -> void:
	var scenery := Scenery.new("summer")
	var a := RoadNetwork.load_scene("ticket_14_14")
	var b := RoadNetwork.load_scene("ticket_13_14")
	var exit: Dictionary = a.connections.exits.straight
	var entry: Dictionary = b.connections.entry
	var profile := SceneStitch.joint_profile(exit,entry)
	# Both dividers end in a rounded nose before the contact (the plain-width ends of the
	# editor's layout): the joint must not bring back a square strip of the declared width.
	check(exit.declared_median>0.01 and entry.declared_median>0.01,"divided streets on both sides")
	check(profile.median<0.01,"no divider at a contact where both scenes have none")
	for pair in [[a,exit],[b,entry]]:
		var net: RoadNetwork = pair[0]
		var port: Dictionary = pair[1]
		var before := JSON.stringify([net.data,net.build])
		var binding := {"port":port}
		binding.merge(profile,true)
		net.stitch_bindings=[binding]
		var mesh := net.surface_mesh(scenery)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var lateral := SceneStitch.right(port.out)
		var reach := 0.0
		var nearest := INF
		for p: Vector3 in vertices:
			var depth: float = -(p-port.p).dot(port.out)
			var x := absf((p-port.p).dot(lateral))
			if absf(p.y-0.187)<0.0015 and x<1.5 and depth>=-0.01:
				reach=maxf(reach,depth);nearest=minf(nearest,depth)
		var bridge := net.median_bridge(binding)
		check(profile.bridge>1.5 and not bridge.is_empty(),net.id+" divided joint bridges its lawn")
		check(nearest<0.01,net.id+" bridged lawn starts right at the contact")
		check(not bridge.is_empty() and reach>=float(bridge.depth)-0.01 and reach>6.5,net.id+" bridged lawn reaches into the nose")
		check(not net.is_drivable(port.p-port.out*2.0),net.id+" the bridged lawn is not carriageway")
		check(net.is_drivable(port.p-port.out*2.0+lateral*4.0),net.id+" the lanes beside it stay drivable")
		check(JSON.stringify([net.data,net.build])==before,net.id+" authored geometry unchanged")
	print("median joins: ",count," checks, ",bad," failures")
	quit(1 if bad else 0)
