## Paint at real divided-road scene contacts: narrow continuous borders, no stretched end caps.
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
	check(profile.median>0.01,"actual divided-road pair")
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
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var lateral := SceneStitch.right(port.out)
		var paint: Array[PackedVector2Array]=[]
		for i in range(0,vertices.size(),3):
			if colors[i].r<0.9 or colors[i].g<0.9 or colors[i].b<0.9: continue
			if vertices[i].y<0.035 or vertices[i].y>0.045: continue
			var poly:=PackedVector2Array()
			for p: Vector3 in [vertices[i],vertices[i+1],vertices[i+2]]:
				poly.append(Vector2((p-port.p).dot(lateral),-(p-port.p).dot(port.out)))
			paint.append(poly)
		for depth in [0.05,0.51,1.01,1.91,3.1,5.1,7.1,9.9]:
			for side in [-1.0,1.0]:
				var center: float = side*(float(profile.median)*0.5+0.2)
				var widths := 0
				for pixel in range(-20,21):
					var hits := 0
					var at:=Vector2(center+pixel*0.01,depth)
					for poly in paint:
						if Geometry2D.is_point_in_polygon(at,poly): hits+=1
					if hits>0: widths+=1
					check(hits<=1,net.id+" no duplicate median border")
				check(widths>=14 and widths<=16,net.id+" continuous 0.15m median border")
		check(JSON.stringify([net.data,net.build])==before,net.id+" authored geometry unchanged")
	print("median joins: ",count," checks, ",bad," failures")
	quit(1 if bad else 0)
