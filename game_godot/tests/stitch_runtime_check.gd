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
	world.only_id="ticket_15_15"
	world.spawn_after=-INF
	world.current={}
	world._maybe_spawn()
	var previous: Situation = world.current.sit
	var saved := JSON.stringify(previous.network.data)
	var outgoing: Dictionary = previous.network.connections.exits.straight
	var r := SceneStitch.right(outgoing.out)
	world.drive.pos=previous.transform*(outgoing.p-outgoing.out*12.0-r*1.8)
	world.drive.yaw=SceneStitch.yaw(previous.basis*outgoing.out)
	world.only_id="ticket_17_6"
	world._on_finished("straight",SceneStitch.yaw(outgoing.out))
	# The frozen old street must never overlay the new scene past the joint.
	for node: MeshInstance3D in world.ghost.find_children("*","MeshInstance3D",true,false):
		for surface in node.mesh.get_surface_count():
			for point: Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if (node.global_transform*point).z>0.001: expect(false,"old street clipped at contact")
	var persistent: Transform3D = world.texture_frame
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
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var layers: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for i in verts.size():
			var layer := roundi(layers[i].x)-1
			if layer<0 or layers[i].y>0.5: continue
			var kind: String = world.scenery.layers[layer]
			var period: float = world.scenery.kinds[kind].period
			var p: Vector3 = persistent* (sit.transform*verts[i])
			if (uv[i]-Vector2(p.x,p.z)/period).length()>0.01:
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
	quit(1 if bad else 0)
