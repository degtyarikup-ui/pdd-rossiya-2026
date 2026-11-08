## A whole ring update must match sequential slot commits, including unrelated fades.
extends SceneTree
var checks := 0
var failed := 0
class CountPool extends Scenery.Pool:
	var syncs := 0
	func _sync_draw() -> void:
		syncs += 1
		super._sync_draw()
func _initialize() -> void: run.call_deferred()
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1; print("FAIL ", label)
func pose(slot: int, item: int) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, slot * 0.31).scaled(Vector3(1.0 + item * 0.1, 1.2, 0.8)), Vector3(item * 3, 0, slot * 20))
func tint(slot: int, item: int) -> Color:
	return Color(0.3 + slot * 0.1, 0.2 + item * 0.1, 0.7, float(slot % 2))
func populate(pool) -> void:
	for slot in 4:
		pool.begin(slot)
		for item in [3, 2, 1, 2][slot]: pool.put(slot, pose(slot, item), tint(slot, item))
		pool.finish(slot)
func fades(pool, scenery: Scenery) -> void:
	scenery.register_building_pool(pool.node)
	var faded := MultiMeshInstance3D.new()
	faded.multimesh = MultiMesh.new()
	faded.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	faded.multimesh.use_colors = true; faded.multimesh.use_custom_data = true
	faded.multimesh.mesh = pool.multi.mesh; faded.multimesh.instance_count = 8
	faded.multimesh.visible_instance_count = 0
	faded.material_override = scenery.building_material
	pool.node.add_child(faded)
	pool.node.set_meta("occlusion_fade_node", weakref(faded))
	for logical in [1, 5]:
		var rendered: int = pool.render_index[logical]
		pool.node.get_meta("occlusion_originals")[rendered] = pool.transforms[logical]
		pool.node.get_meta("occlusion_fades")[rendered] = 0.25
		Scenery.set_opaque_pose(pool.node, rendered, Scenery.Pool.HIDDEN)
	Scenery.sync_pool_bounds(pool.node)
	Scenery.sync_fade_batch(pool.node)
func replace_slots(pool) -> void:
	for slot in [0, 2, 3]:
		pool.begin(slot)
		for item in [2, 0, 1][[0, 2, 3].find(slot)]: pool.put(slot, pose(slot, item) * Transform3D(Basis(), Vector3(0, 0, 2)), tint(slot, item))
		pool.finish(slot)
func compare(a, b, label: String) -> void:
	expect(a.transforms == b.transforms and a.tints == b.tints, label + " logical transforms and seasonal colours")
	expect(a.used == b.used and a.render_slots == b.render_slots and a.render_index == b.render_index, label + " stable logical-to-packed mapping")
	expect(a.render_transforms == b.render_transforms and a.render_tints == b.render_tints, label + " complete render metadata")
	expect(a.render_multi.visible_instance_count == b.render_multi.visible_instance_count and a.render_multi.custom_aabb == b.render_multi.custom_aabb, label + " exact prefix and bounds")
	expect(a.node.get_meta("occlusion_originals") == b.node.get_meta("occlusion_originals") and a.node.get_meta("occlusion_fades") == b.node.get_meta("occlusion_fades"), label + " untouched fades follow repacking")
	for i in a.multi.instance_count:
		expect(a.multi.get_instance_transform(i) == b.multi.get_instance_transform(i), label + " public logical pose " + str(i))
	for i in a.render_multi.visible_instance_count:
		expect(a.render_multi.get_instance_transform(i) == b.render_multi.get_instance_transform(i) and a.render_multi.get_instance_custom_data(i) == b.render_multi.get_instance_custom_data(i), label + " actual render buffer " + str(i))
	var fa: MultiMeshInstance3D = a.node.get_meta("occlusion_fade_node").get_ref()
	var fb: MultiMeshInstance3D = b.node.get_meta("occlusion_fade_node").get_ref()
	expect(fa.multimesh.visible_instance_count == fb.multimesh.visible_instance_count and fa.multimesh.custom_aabb == fb.multimesh.custom_aabb, label + " transparent prefix and bounds")
	for i in fa.multimesh.visible_instance_count:
		expect(fa.multimesh.get_instance_transform(i) == fb.multimesh.get_instance_transform(i) and fa.multimesh.get_instance_custom_data(i) == fb.multimesh.get_instance_custom_data(i), label + " transparent pose/opacity " + str(i))
func run() -> void:
	var holder := Node3D.new(); root.add_child(holder)
	var scenery := Scenery.new("summer")
	var mesh := BoxMesh.new(); mesh.size = Vector3(2, 4, 2)
	var sequential := CountPool.new(holder, mesh, scenery.material, 4, 5, true)
	var batched := CountPool.new(holder, mesh, scenery.material, 4, 5, true)
	populate(sequential); populate(batched)
	fades(sequential, scenery); fades(batched, scenery)
	sequential.syncs = 0; batched.syncs = 0
	var prefix: int = batched.render_multi.visible_instance_count
	batched.begin_batch(); batched.begin_batch()
	replace_slots(sequential); replace_slots(batched)
	expect(batched.syncs == 0 and batched.render_multi.visible_instance_count == prefix, "atomic batch keeps old draw prefix until outer commit")
	batched.end_batch()
	expect(batched.syncs == 0, "nested inner commit cannot upload a partial ring")
	batched.end_batch()
	expect(sequential.syncs == 3 and batched.syncs == 1, "three slot replacements require one complete repack")
	compare(sequential, batched, "batch")
	expect(batched.node.get_meta("occlusion_fades").size() == 1 and batched.node.get_meta("occlusion_originals").size() == 1, "changed fade cleared while unrelated fade preserved")
	var first := Node3D.new(); var second := Node3D.new(); holder.add_child(first); holder.add_child(second)
	sequential.snapshot(first); batched.snapshot(second)
	var a := first.get_child(0) as MultiMeshInstance3D; var b := second.get_child(0) as MultiMeshInstance3D
	expect(a.multimesh.instance_count == b.multimesh.instance_count and a.multimesh.custom_aabb == b.multimesh.custom_aabb, "frozen snapshots preserve prefix and bounds")
	for i in a.multimesh.instance_count:
		expect(a.multimesh.get_instance_transform(i) == b.multimesh.get_instance_transform(i) and a.multimesh.get_instance_custom_data(i) == b.multimesh.get_instance_custom_data(i), "frozen snapshot slot " + str(i))
	batched.begin_batch(); batched.end_batch()
	expect(batched.syncs == 1, "empty batch does not repack")
	# Capacity can be reused after every logical slot was emptied in one batch.
	for pool in [sequential, batched]:
		pool.begin_batch()
		for slot in 4: pool.begin(slot); pool.finish(slot)
		# Repeat a still-pending empty slot: its old packed index has not vanished yet.
		pool.begin(0); pool.finish(0)
		pool.end_batch()
		expect(pool.render_multi.visible_instance_count == 0 and pool.transforms.all(func(xf): return xf == Scenery.Pool.HIDDEN), "empty slots remain hidden across repeated finish before repacking")
		pool.begin_batch()
		for slot in 4: pool.begin(slot); pool.finish(slot)
		pool.end_batch()
		expect(pool.render_multi.visible_instance_count == 0 and pool.node.get_meta("occlusion_fades").is_empty(), "already-empty reserved capacity keeps no draw slots or fades")
		pool.begin_batch(); populate(pool); pool.end_batch()
	compare(sequential, batched, "reuse")
	holder.free()
	print("pool batch: ",checks," checks, ",failed," failures")
	quit(1 if failed else 0)
