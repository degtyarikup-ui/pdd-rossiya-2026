extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size()==2)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	for item in fixtures:
		var result := Pedestrian.pose_vertex(Vector3(item.point[0],item.point[1],item.point[2]),Vector3(item.normal[0],item.normal[1],item.normal[2]),item.amp,item.pivotY,item.pivotX,item.pose,item.arm)
		var expected: Array = item.result.point
		assert(result.point.distance_to(Vector3(expected[0],expected[1],expected[2]))<.00001)
		assert(absf(result.amp-float(item.result.amp))<.00001)
	for look in Models.WALKERS:
		var base := Pedestrian.posed_mesh(look,"stand","right")
		var original: PackedVector3Array = base.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var tags: PackedVector2Array = base.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
		for pose in ["hail","forward","raised"]:
			for arm in ["left","right"]:
				var mesh := Pedestrian.posed_mesh(look,pose,arm)
				assert(mesh==Pedestrian.posed_mesh(look,pose,arm),"Posed mesh is cached")
				var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var posed_tags: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
				var changed := 0
				for i in vertices.size():
					var selected: bool = absf(tags[i].x)>.1 and absf(tags[i].x)<.21 and ((tags[i].x>0)==(arm=="right"))
					if selected:
						assert(posed_tags[i].x==0,"The posed arm cannot swing with the gait")
						if vertices[i].distance_to(original[i])>.01: changed+=1
					else: assert(vertices[i]==original[i],"Legs, body and other arm retain their geometry")
				assert(changed>10)
	var config := Situation._actor_config({"id":"moto","config":{"sidecar":true}},{"actors":[{"id":"moto","sidecar":false}]})
	assert(config.sidecar==false,"Explicit no-sidecar overrides archived models")
	for has_sidecar in [false,true]:
		var motorcycle := NpcVehicle.make("motorcycle",Color("#4D7768"),{"sidecar":has_sidecar})
		assert((motorcycle.get_node_or_null("sidecar")!=null)==has_sidecar)
		motorcycle.free()
	var plain := SignFace.texture("5.33_plain")
	assert(plain!=null)
	var red := 0
	var image := plain.get_image()
	for y in image.get_height():
		for x in image.get_width():
			var colour := image.get_pixel(x,y)
			if colour.a>.5 and colour.r>.6 and colour.g<.2 and colour.b<.2: red+=1
	assert(red==0,"Plain pedestrian-zone sign has no time-restriction star")
	var sign := RoadBuild.sign_node("5.33","","",[],[],true,{"zoneVariant":"plain"})
	assert(sign.get_child_count()>0);sign.free()
	var exported: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var person: Dictionary = exported.actors.filter(func(a):return a.type=="pedestrian")[0]
	assert(person.pedestrianPose=="hail" and person.poseArm=="left")
	var pedestrian := Pedestrian.new()
	pedestrian.configure(person.pedestrianLook,Color("#0574F8"),person.pedestrianPose,person.poseArm)
	assert(pedestrian.get_child(0).mesh==Pedestrian.posed_mesh(0,"hail","left"));pedestrian.free()
	print("Actor appearance runtime PASS: 12 walker models, all poses/arms, independent gait, sidecar composition and plain 5.33")
	quit()
