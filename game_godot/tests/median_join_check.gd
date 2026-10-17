## Real divided-road scene contacts: the divider ends in the scene's own nose, no square block at the joint.
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
		var square := 0
		for p: Vector3 in vertices:
			var depth: float = -(p-port.p).dot(port.out)
			if absf(p.y-0.185)<0.003 and depth>=-0.01 and depth<4.0 and absf((p-port.p).dot(lateral))<1.5: square+=1
		check(square==0,net.id+" no square divider block at the contact")
		check(JSON.stringify([net.data,net.build])==before,net.id+" authored geometry unchanged")
	print("median joins: ",count," checks, ",bad," failures")
	quit(1 if bad else 0)
