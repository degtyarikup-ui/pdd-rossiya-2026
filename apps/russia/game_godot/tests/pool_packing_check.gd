## Streamed slots keep logical chunk IDs while only active GPU slots are drawn.
## Native additionally verifies actual buffers, colours and remapped transparency.
extends SceneTree
var checks := 0
var failures := 0
var native := false

func _initialize() -> void: run.call_deferred()
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", label)

func rendered_pose(pool: Scenery.Pool, index: int) -> Transform3D:
	return pool.node.multimesh.get_instance_transform(index) if native else pool.render_transforms[index]

func packed_slots() -> void:
	var parent := Node3D.new(); root.add_child(parent)
	var mesh := BoxMesh.new(); mesh.size = Vector3(2, 4, 6)
	var pool := Scenery.Pool.new(parent, mesh, null, 4, 3, true)
	expect(pool.multi.instance_count == 12, "logical source retains fixed chunk capacity")
	expect(pool.node.multimesh != pool.multi, "logical slots are separate from the draw buffer")
	expect(pool.node.multimesh.visible_instance_count == 0, "unused capacity submits zero instances")
	var far := Transform3D(Basis(Vector3.UP, 0.3).scaled(Vector3(1.2, 0.8, 1.1)), Vector3(80, 0, 100))
	var blue := Color(0.1, 0.2, 0.8, 1.0)
	pool.begin(3); pool.put(3, far, blue)
	expect(pool.node.multimesh.visible_instance_count == 1 and pool.render_slots[0] == 9, "put immediately admits a sparse logical slot into the active prefix")
	pool.finish(3)
	expect(rendered_pose(pool, 0).is_equal_approx(far), "packed pose preserves full rotation and nonuniform scale")
	expect(pool.transforms[9].is_equal_approx(far), "logical chunk position is unchanged")
	var box: AABB = far * mesh.get_aabb()
	expect(pool.node.multimesh.custom_aabb.position.is_equal_approx(box.position) and pool.node.multimesh.custom_aabb.size.is_equal_approx(box.size), "active bounds exclude hidden capacity at the origin")
	expect(not pool.node.multimesh.custom_aabb.has_point(Vector3(0,-50,0)), "unused marker cannot prevent distant batch culling")
	var near := Transform3D(Basis(Vector3.UP, -0.5), Vector3(-30, 0, 12))
	var red := Color(0.8, 0.2, 0.1, 0.0)
	pool.begin(0); pool.put(0, near, red); pool.finish(0)
	expect(pool.render_slots == [0, 9] and pool.render_index[9] == 1, "logical-to-render mapping survives prefix reordering")
	expect(rendered_pose(pool, 0).is_equal_approx(near) and rendered_pose(pool, 1).is_equal_approx(far), "both reordered props retain their visible poses")
	expect(pool.render_tints[0].is_equal_approx(red) and pool.render_tints[1].is_equal_approx(blue), "reordered tint and season channels follow the same prop")
	if native:
		expect(pool.multi.get_instance_transform(9).is_equal_approx(far), "logical native buffer retains chunk index")
		for i in 2:
			expect(pool.node.multimesh.get_instance_color(i).is_equal_approx(Color.WHITE), "Compatibility instance colour stays white")
			# Compatibility stores GPU colours at lower precision: 0.8 reads
			# back as 0.7998 in both buffers. Compare with the unchanged logical
			# buffer so this asserts that packing preserves the renderer's value.
			var original_gpu := pool.multi.get_instance_custom_data(pool.render_slots[i])
			expect(pool.node.multimesh.get_instance_custom_data(i).is_equal_approx(original_gpu), "native packed custom data matches logical GPU colour")
	pool.begin(0); pool.finish(0)
	expect(pool.render_slots == [9] and pool.node.multimesh.visible_instance_count == 1, "recycled sparse chunk disappears from the draw prefix")
	expect(rendered_pose(pool, 0).is_equal_approx(far), "swapped surviving prop retains its pose")
	expect(pool.render_transforms[1].origin.y < -10, "metadata tail stays hidden for collision readers")
	var ghost := Node3D.new(); parent.add_child(ghost); pool.snapshot(ghost)
	var copy := ghost.get_child(0) as MultiMeshInstance3D
	expect(copy.multimesh.instance_count == 1, "snapshot copies only active logical props")
	var pose: Transform3D = copy.multimesh.get_instance_transform(0) if native else copy.get_meta("instance_transforms")[0]
	expect(pose.is_equal_approx(far), "snapshot preserves surviving prop and authored scale")
	ghost.rotation.y = 0.7
	expect((copy.global_transform * pose).origin.is_equal_approx((ghost.global_transform * far).origin), "retained snapshot follows the world rebase")
	pool.begin(3); pool.finish(3)
	expect(pool.node.multimesh.visible_instance_count == 0 and pool.render_slots.is_empty(), "fully unused ring draws zero props")
	parent.free()

func remapped_fades() -> void:
	var parent := Node3D.new(); root.add_child(parent)
	var scenery := Scenery.new("winter")
	var camera := Camera3D.new(); parent.add_child(camera)
	camera.position = Vector3(0,18,-22); camera.look_at(Vector3(0,1,0))
	var mesh := BoxMesh.new(); mesh.size = Vector3(10,12,6)
	var pool := Scenery.Pool.new(parent, mesh, scenery.material, 3, 2, false)
	scenery.register_building_pool(pool.node)
	var blocked := Transform3D(Basis(),Vector3(0,6,-8))
	pool.begin(2); pool.put(2,blocked,Color(1,1,1,1)); pool.finish(2)
	var targets: Array[Vector3] = [Vector3(0,1.2,0)]
	scenery.update_occluders(camera,targets,0.5)
	var state: Dictionary = scenery.occluders[0]
	expect(state.fades.has(0) and state.originals.has(0), "packed blocker enters the independent transparent batch")
	expect(state.fade_node != null and state.fade_node.multimesh.visible_instance_count == 1, "one transparent building is submitted")
	if native: expect(pool.multi.get_instance_transform(4).origin.y < -10, "logical source tracks the hidden opaque building")
	var far := Transform3D(Basis(),Vector3(100,6,100))
	pool.begin(0); pool.put(0,far,Color(0.2,0.4,0.8,0)); pool.finish(0)
	expect(pool.render_slots == [0,4], "earlier chunk reorders the drawn prefix")
	expect(state.fades.has(1) and not state.fades.has(0) and state.originals.has(1), "fade and original pose follow the remapped render index")
	expect(absf(float(state.fades[1])-0.25) < 0.0001, "repacking preserves fade progress")
	var faded_pose: Transform3D = state.fade_node.multimesh.get_instance_transform(0) if native else state.fade_node.get_meta("instance_transforms")[0]
	expect(faded_pose.is_equal_approx(blocked), "transparent prop keeps its original physical pose")
	if native:
		expect(pool.node.multimesh.get_instance_transform(1).origin.y < -10, "remapped opaque prop stays hidden")
		expect(absf(state.fade_node.multimesh.get_instance_custom_data(0).a-1.125) < 0.0001, "winter flag survives transparent buffer repacking")
	var ghost := Node3D.new(); parent.add_child(ghost); pool.snapshot(ghost)
	var copy := ghost.get_child(0) as MultiMeshInstance3D
	expect(copy.multimesh.instance_count == 2, "snapshot keeps the faded prop plus ordinary far prop")
	var poses: Array = copy.get_meta("instance_transforms")
	expect(poses[0].is_equal_approx(far) and poses[1].is_equal_approx(blocked), "snapshot uses logical original poses rather than hidden draw positions")
	pool.begin(0); pool.finish(0)
	expect(state.fades.has(0) and not state.fades.has(1) and pool.render_slots == [4], "removing a lower chunk remaps the surviving fade")
	var replacement := Transform3D(Basis(Vector3.UP,0.4),Vector3(120,6,100))
	pool.begin(2); pool.put(2,replacement,Color.WHITE); pool.finish(2)
	expect(state.originals.is_empty() and state.fades.is_empty(), "reusing a logical chunk clears its former fade")
	expect(state.fade_node.multimesh.visible_instance_count == 0 and not state.fade_node.visible, "recycle hides the obsolete transparent building immediately")
	if native: expect(pool.multi.get_instance_transform(4).is_equal_approx(replacement), "logical native buffer receives the replacement")
	parent.free()

func run() -> void:
	native = DisplayServer.get_name() != "headless"
	packed_slots()
	remapped_fades()
	print("pool packing: ",checks," checks, ",failures," failures; renderer=",DisplayServer.get_name())
	quit(1 if failures else 0)
