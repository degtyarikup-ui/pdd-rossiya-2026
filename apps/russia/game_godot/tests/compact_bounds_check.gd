## Compact mode hides retained scenery outside its footprint, without editing sources.
extends SceneTree

var checks := 0
var failures := 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", label)

func flat_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(65,0,0), Vector3(75,0,0), Vector3(75,0,10)]:
		tool.set_color(Color.WHITE)
		tool.add_vertex(point)
	tool.generate_normals()
	tool.index()
	return tool.commit()

func _initialize() -> void:
	var scenery := Scenery.new("summer")
	var sit := Situation.new()
	root.add_child(sit)
	var net := RoadNetwork.new()
	net.data = {"sceneFormat": "compact", "crop": 45.0}
	sit.network = net
	sit.data = {"sceneFormat": "compact", "crop": 45.0, "props": []}
	var tree: String = scenery.index.props.keys().filter(func(key): return str(key).begins_with("trees/"))[0]
	sit.data.props = [
		{"prop": tree, "pos": [0, 0, 0], "yaw": 0, "scale": [1,1,1]},
		{"prop": tree, "pos": [70, 0, 0], "yaw": 0, "scale": [1,1,1]},
		{"prop": tree, "pos": [43, 0, 0], "yaw": 0, "scale": [1,1,1]}]
	var saved := JSON.stringify(sit.data)
	sit._place_props.call(scenery)
	# A crown crosses the crop while its much smaller contact disc still fits.
	var crown := BoxMesh.new(); crown.size = Vector3(6,6,6)
	sit._pool_nodes[tree].multimesh.mesh = crown
	var prop := MultiMeshInstance3D.new()
	prop.multimesh = MultiMesh.new()
	prop.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new(); box.size = Vector3(8,4,8)
	prop.multimesh.mesh = box
	prop.multimesh.instance_count = 1
	var pose := Transform3D(Basis(), Vector3(44,0,0))
	prop.set_meta("authored_transforms", [pose])
	prop.set_meta("instance_transforms", [pose])
	prop.multimesh.set_instance_transform(0, pose)
	sit._pool_nodes["test-building"] = prop
	sit.add_child(prop)
	for x in [0.0, 70.0]:
		var light := Node3D.new(); light.position.x = x; sit.add_child(light); sit.lights.append(light)
		var sign := Node3D.new(); sign.position.x = x; sit.add_child(sign); sit._signs.append(sign)
	var actor := Node3D.new(); actor.position.x = 70; sit.add_child(actor); sit.actors.append(actor)
	sit._trim_end_props()
	await process_frame
	expect(sit.lights[0].visible and not sit.lights[1].visible, "only outside light hidden")
	expect(sit._signs[0].visible and not sit._signs[1].visible, "only outside sign hidden")
	expect(sit._pool_nodes[tree].multimesh.get_instance_transform(0).origin.y > -10, "inside tree remains")
	expect(sit._pool_nodes[tree].get_meta("instance_transforms")[1] == Scenery.Pool.HIDDEN, "outside retained tree hidden")
	expect(sit._pool_nodes.tree_contact.get_meta("instance_transforms")[1] == Scenery.Pool.HIDDEN, "outside tree shadow hidden with its tree")
	var contact: MultiMeshInstance3D = sit._pool_nodes.tree_contact
	var contact_box: AABB = contact.get_meta("authored_transforms")[2] * contact.multimesh.mesh.get_aabb()
	expect(contact_box.end.x < 45, "near-border contact disc fits inside the crop")
	expect(sit._pool_nodes[tree].get_meta("instance_transforms")[2] == Scenery.Pool.HIDDEN, "near-border crown extends beyond the crop")
	expect(contact.get_meta("instance_transforms")[2] == Scenery.Pool.HIDDEN, "small contact follows its hidden crown")
	expect(prop.get_meta("instance_transforms")[0] == Scenery.Pool.HIDDEN, "entire building must fit the compact footprint")
	expect(actor.visible, "authored actors keep their independent controls")
	expect(JSON.stringify(sit.data) == saved, "runtime visibility preserves exact authored data")
	expect(prop.get_meta("authored_transforms")[0] == pose, "hidden object keeps exact authored transform")
	var baked := flat_mesh()
	var vertices: PackedVector3Array = baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	expect(Situation._without_baked_ground(baked, net).get_surface_count() == 0, "obsolete opaque ground outside compact crop disappears")
	expect(Situation._without_covered_texture(baked, net).get_surface_count() == 0, "obsolete ground photograph outside compact crop disappears")
	expect(baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices, "source GLB mesh remains unchanged")
	net.data.erase("sceneFormat"); sit.data.erase("sceneFormat")
	sit._trim_end_props()
	await process_frame
	expect(sit.lights[1].visible and sit._signs[1].visible, "legacy format keeps previous visibility")
	expect(prop.get_meta("instance_transforms")[0] == pose, "restoring standard mode restores original transform")
	expect(sit._pool_nodes[tree].get_meta("instance_transforms")[1].origin.x == 70, "retained tree can be restored")
	expect(contact.get_meta("instance_transforms")[2].origin.x == 43, "restoring tree also restores its contact shadow")
	expect(Situation._without_baked_ground(baked, net).get_surface_count() == 1, "legacy baked ground filter remains unchanged")
	expect(Situation._without_covered_texture(baked, net).get_surface_count() == 1, "legacy ground photo filter remains unchanged")
	sit.free()
	print("Compact bounds: ", checks, " footprint/prop/mesh-preservation checks, ", failures, " failures")
	quit(1 if failures else 0)
