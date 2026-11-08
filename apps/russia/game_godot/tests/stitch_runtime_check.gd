extends SceneTree

var bad := 0
var checks := 0
func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok: bad+=1;print("FAIL ",label)

func _initialize() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	world.set_process(false)
	for i in 600:
		if not world.staging: break
		await process_frame
	if world.staging:
		push_error("stitch fixture initial staging timeout")
		quit(1);return
	if world.staged_sit != null:
		world.staged_sit.free()
		world.staged_sit=null
	world.road_force=""
	world.only_id="ticket_15_15"
	world.spawn_after=-INF
	world.current={}
	world.staged_sit=Situation.load_scene(world.only_id,world.scenery)
	world._maybe_spawn()
	var previous: Situation = world.current.sit
	var saved := JSON.stringify(previous.network.data)
	var outgoing: Dictionary = previous.network.connections.exits.straight
	var r := SceneStitch.right(outgoing.out)
	world.drive.pos=previous.transform*(outgoing.p-outgoing.out*12.0-r*1.8)
	world.drive.yaw=SceneStitch.yaw(previous.basis*outgoing.out)
	world.only_id="ticket_17_6"
	world._on_finished("straight",SceneStitch.yaw(outgoing.out))
	expect(world.player.position.is_equal_approx(world.drive.pos),"visual player rebased in same frame")
	expect(absf(world.player.rotation.y-world.drive.yaw)<0.001,"visual heading rebased in same frame")
	# The frozen old street must never overlay the new scene past the joint.
	for node: MeshInstance3D in world.ghost.find_children("*","MeshInstance3D",true,false):
		for surface in node.mesh.get_surface_count():
			for point: Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if (node.global_transform*point).z>0.001: expect(false,"old street clipped at contact")
	var persistent: Transform3D = world.texture_frame
	world.staged_sit=Situation.load_scene(world.only_id,world.scenery)
	world._maybe_spawn()
	var next: Situation = world.current.sit
	var entry: Dictionary = next.network.connections.entry
	expect((previous.transform*outgoing.p).distance_to(next.transform*entry.p)<0.001,"skew scene direct contact")
	expect((previous.basis*outgoing.out).dot(next.basis*entry.out)<-0.9999,"skew exit and next entrance oppose")
	expect(JSON.stringify(previous.network.data)==saved,"saved hand-tuned scene unchanged")
	expect(world.drive.pos.z<0 and world.drive.pos.z>-20,"rebase keeps car before the joint")
	expect(absf(world.drive.yaw)<0.01,"rebased car aligned with new road")
	var samples := 0
	for sit in [previous,next]:
		var mesh: ArrayMesh = sit.get_node("surfaces").mesh
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var layers: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var material: ShaderMaterial=sit.get_node("surfaces").material_override
		var shader_frame: Transform3D=material.get_shader_parameter("surface_frame")
		expect(material.get_shader_parameter("grid_uv")==true,"shader world grid enabled "+sit.id)
		expect(shader_frame.is_equal_approx(persistent),"shader persistent frame "+sit.id)
		var periods: PackedFloat32Array=material.get_shader_parameter("texture_periods")
		for i in verts.size():
			var layer := roundi(layers[i].x)-1
			if layer<0 or layers[i].y>0.5: continue
			var kind: String = world.scenery.layers[layer]
			var period: float = world.scenery.kinds[kind].period
			var p: Vector3 = persistent* (sit.transform*verts[i])
			var effective: Vector3=shader_frame*(sit.global_transform*verts[i])
			var actual_uv:=Vector2(effective.x,effective.z)/periods[layer]
			if (actual_uv-Vector2(p.x,p.z)/period).length()>0.01:
				expect(false,"persistent UV "+sit.id)
				break
			samples+=1
	# Selection honours lane count instead of inserting an arbitrary two-lane approach.
	world.only_id=""
	world.pending_connection={"port":previous.network.connections.exits.straight}
	world.bag=["ticket_13_13","ticket_17_6"]
	var selected: String = world._next_id()
	var chosen: Dictionary = world._scene_connections(selected).entry
	expect(chosen.lanes==previous.network.connections.exits.straight.lanes,"next scene matches lane count")
	print("runtime joining: ",checks," checks, ",samples," textured vertices, ",bad," failures")
	world.queue_free()
	await process_frame
	await process_frame
	quit(1 if bad else 0)
