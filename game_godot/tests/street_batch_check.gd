## Ring batching must preserve every road attribute, prop and parked footprint.
## Run headless and native: the latter also reads back the actual packed GPU prefix.
extends SceneTree

var checks := 0
var failures := 0
var native := false

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", label)

func compare_mesh(a: ArrayMesh, b: ArrayMesh, label: String) -> void:
	expect((a == null) == (b == null), label + " blank road parity")
	if a == null or b == null: return
	expect(a.get_surface_count() == b.get_surface_count(), label + " surface count")
	for surface in mini(a.get_surface_count(), b.get_surface_count()):
		var aa := a.surface_get_arrays(surface)
		var bb := b.surface_get_arrays(surface)
		for attribute in Mesh.ARRAY_MAX:
			expect(aa[attribute] == bb[attribute], label + " road attribute " + str(attribute))
		expect(a.surface_get_material(surface) == b.surface_get_material(surface), label + " material")

func compare_pool(a: Scenery.Pool, b: Scenery.Pool, label: String) -> void:
	expect(a.transforms == b.transforms and a.tints == b.tints, label + " logical poses and paint")
	expect(a.render_slots == b.render_slots and a.render_index == b.render_index, label + " packed mapping")
	expect(a.render_transforms == b.render_transforms and a.render_tints == b.render_tints, label + " packed poses and paint")
	expect(a.node.multimesh.visible_instance_count == b.node.multimesh.visible_instance_count, label + " visible prefix")
	expect(a.node.multimesh.custom_aabb == b.node.multimesh.custom_aabb, label + " culling bounds")
	if native:
		for index in a.render_slots.size():
			expect(a.node.multimesh.get_instance_transform(index).is_equal_approx(b.node.multimesh.get_instance_transform(index)), label + " GPU pose " + str(index))
			expect(a.node.multimesh.get_instance_custom_data(index).is_equal_approx(b.node.multimesh.get_instance_custom_data(index)), label + " GPU paint " + str(index))

func exercise(season: String) -> void:
	var parent := Node3D.new(); root.add_child(parent)
	var sc := Scenery.new(season)
	var old := Street.new(parent, sc, 60.0, 5)
	var batched := Street.new(parent, sc, 60.0, 5)
	old.parked_chance = 1.0; batched.parked_chance = 1.0
	var ordinary := {"width": 8.4, "lanes": 2, "median": 0.0}
	var highway := {"width": 23.6, "lanes": 6, "median": 2.0, "walk": false, "centre": "double"}
	var dirt := {"width": 6.4, "lanes": 2, "median": 0.0, "surface": "sand", "walk": false}
	for pass_index in 4:
		var profile: Dictionary = [ordinary, highway, dirt, ordinary][pass_index]
		old.profile = profile; batched.profile = profile
		old.connector = {"start": 30.0, "end": 150.0, "from": highway, "to": ordinary} if pass_index == 3 else {}
		batched.connector = old.connector
		old.texture_frame = Transform3D(Basis(Vector3.UP, 0.4 * pass_index), Vector3(73.0 * pass_index, 0, -32.0))
		batched.texture_frame = old.texture_frame
		var meshes: Array = []
		for slot in 5:
			var spans: Array = [[5.0, 18.0], [23.0, 50.0]] if slot == 1 else [[0.0, 60.0]]
			meshes.append(old.build_chunk(slot, slot - 2, slot == 3, func(z: float): return float(old.profile_at(z).width) * 0.5, spans))
		var previous_slots := (batched.pools["tree_contact"] as Scenery.Pool).render_slots.duplicate()
		batched.begin_batch()
		for slot in 5:
			var spans: Array = [[5.0, 18.0], [23.0, 50.0]] if slot == 1 else [[0.0, 60.0]]
			var mesh := batched.build_chunk(slot, slot - 2, slot == 3, func(z: float): return float(batched.profile_at(z).width) * 0.5, spans)
			compare_mesh(meshes[slot], mesh, season + " pass " + str(pass_index) + " slot " + str(slot))
			expect((batched.pools["tree_contact"] as Scenery.Pool).render_slots == previous_slots, "no partial ring is published during a synchronous batch")
		batched.end_batch()
		expect(old.parked_spots == batched.parked_spots and old.parked_bodies == batched.parked_bodies, "parked visuals and collision footprints retain parity")
		for key in old.pools: compare_pool(old.pools[key], batched.pools[key], season + " props " + key)
		for key in old.parked: compare_pool(old.parked[key], batched.parked[key], season + " parked " + key)
	parent.free()

func run() -> void:
	native = DisplayServer.get_name() != "headless"
	exercise("autumn")
	exercise("winter")
	print("street batch: ", checks, " checks, ", failures, " failures; renderer=", DisplayServer.get_name())
	quit(1 if failures else 0)
