extends SceneTree

var bad := 0
var checks := 0
func expect(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		bad+=1
		print("FAIL ",label)

func _initialize() -> void:
	var ids: Array = JSON.parse_string(FileAccess.get_file_as_string("res://situations/index.json"))
	# Include every saved scene, even disabled ones: they must remain usable when reviewed later.
	var dir := DirAccess.open("res://network")
	for file in dir.get_files():
		if file.ends_with(".json") and not ids.has(file.trim_suffix(".json")): ids.append(file.trim_suffix(".json"))
	var profiles := {}
	for id in ids:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://network/%s.json"%id))
		# Standalone mini-games do not enter the city question stream.
		if not str(data.get("miniGame","")).is_empty(): continue
		var built: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://network/build/%s.json"%id))
		var profile := SceneStitch.describe(data,built)
		profiles[id]=profile
		var network := RoadNetwork.load_scene(id)
		expect(not profile.entry.is_empty(),str(id)+" entrance")
		if not profile.entry.is_empty(): expect(SceneStitch.contains(Vector3(data.stop.x,0,data.stop.z),[{"port":profile.entry,"width":profile.entry.width}]),str(id)+" question stays inside scene")
		for port in profile.ports:
			expect(port.width>2.5 and port.width<30.0,str(id)+" width "+str(port.width))
			var lane: Vector3 = port.p-port.out*0.05-SceneStitch.right(port.out)*(float(port.width)/2.0-1.2)
			expect(network.is_drivable(lane),str(id)+" real carriageway at "+str(port.id))
			expect(absf(port.out.length()-1.0)<0.001,str(id)+" tangent")
			var inner: Vector3 = port.p-port.out*SceneStitch.END_BLEND-SceneStitch.right(port.out)*1.7
			var binding := [{"port":port,"width":float(port.width)+1.5}]
			expect(SceneStitch.warp(inner,binding).distance_to(inner)<0.001,str(id)+" inner road untouched")
			var edge: Vector3 = port.p+SceneStitch.right(port.out)*float(port.width)/2.0
			var moved := SceneStitch.warp(edge,binding)
			expect(SceneStitch.warp(moved,binding,true).distance_to(edge)<0.001,str(id)+" collision inverse")
	var pairs := 0
	for id in profiles:
		for out: Dictionary in SceneStitch.departure_ports(profiles[id]).values():
			for other in profiles:
				var entry: Dictionary = profiles[other].entry
				if entry.is_empty() or out.lanes!=entry.lanes: continue
				pairs+=1
				var xf := SceneStitch.placement(entry,out)
				expect((xf*entry.p).distance_to(out.p)<0.001,"join centres "+str(id)+"->"+str(other))
				expect((xf.basis*entry.out).dot(out.out)<-0.9999,"join tangents")
				var width := SceneStitch.joint_width(out,entry)
				var oa := SceneStitch.warp(out.p+SceneStitch.right(out.out)*out.width/2.0,[{"port":out,"width":width}])
				var ib := SceneStitch.warp(entry.p-SceneStitch.right(entry.out)*entry.width/2.0,[{"port":entry,"width":width}])
				if (xf*ib).distance_to(oa)>0.01:
					expect(false,"join edges "+str(id)+"->"+str(other))
	# Profile changes are local, and road/pavement UVs use one persistent world frame across a turn.
	var net := RoadNetwork.load_scene("ticket_15_15")
	expect(net.connections.exits.size()>0,"skew junction exits")
	var world_script=load("res://scripts/world.gd")
	var world=world_script.new()
	world.L=60.0
	world.blanks=[[83.2,216.7]]
	expect(world._street_ranges(1).size()==1 and absf(world._street_ranges(1)[0][1]-23.2)<0.001,"partial chunk before scene")
	expect(world._street_ranges(2).is_empty(),"full blank")
	var tail: Array = world._street_ranges(3)
	expect(tail.size()==1 and absf(tail[0][0]-36.7)<0.001 and tail[0][1]==60.0,"partial chunk after scene")
	# An explicit curved/skew fixture also runs against clean checkouts whose saved tickets are still straight.
	var curve := {"crop":90.0,"layout":{"nodes":[{"id":"s","x":0,"z":-90},{"id":"c","x":0,"z":0},{"id":"n","x":60,"z":90}],
		"streets":[{"id":"a","a":"s","b":"c","kind":"avenue","median":3},{"id":"b","a":"c","b":"n","kind":"avenue","median":3,"bend":[15,40]}]},
		"routes":[{"kind":"approach","id":"approach","points":[[-5.25,-90],[-5.25,-13]]},{"kind":"manoeuvre","id":"turn","exit":"straight","points":[[-5.25,-13],[14,28],[30,50]]}]}
	var custom := SceneStitch.describe(curve,{})
	expect(custom.exits.straight.out.x>0.3,"curve tangent is not an invented cardinal exit")
	var xf := SceneStitch.placement(custom.entry,custom.exits.straight)
	expect((xf*custom.entry.p).distance_to(custom.exits.straight.p)<0.001,"curved road joint")
	var joint := SceneStitch.joint_profile(custom.entry,custom.exits.straight)
	expect(joint.median==3.0 and joint.width==17.0,"wider four-lane profile with divider")
	expect(SceneStitch.median_at(custom.entry.p,[{"port":custom.entry,"median":3.0}]),"divider stays non-drivable at contact")
	world.free()
	print("stitching: ",profiles.size()," scenes, ",pairs," compatible directed pairs, ",checks," checks, ",bad," failures")
	quit(1 if bad else 0)
