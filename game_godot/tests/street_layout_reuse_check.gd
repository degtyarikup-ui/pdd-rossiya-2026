## A texture-frame change may rebuild the road without rerolling the same plots.
## Compare against a full rebuild, including parking, fades and native buffers.
extends SceneTree

class TestWorld extends "res://scripts/world.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

class CountingStreet extends Street:
	var plots := 0
	func _plot(slot: int, rng: RandomNumberGenerator, side: float, z: float, style: int, row: int) -> void:
		plots += 1
		super._plot(slot, rng, side, z, style, row)

var checks := 0
var failures := 0
var native := false

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", label)

func make_world(sc: Scenery, count := 2) -> TestWorld:
	var world := TestWorld.new()
	root.add_child(world)
	world.L = 60.0
	world.chunk_count = count
	world.scenery = sc
	world.street_half = 4.2
	world.street = CountingStreet.new(world, sc, world.L, count)
	world.street.parked_chance = 1.0
	world.street.profile = {"width": 8.4, "lanes": 2, "median": 0.0, "walk": true, "centre": "dashed"}
	world.chunk_index.resize(count)
	for slot in count:
		var road := MeshInstance3D.new()
		world.add_child(road)
		world.road_nodes.append(road)
	return world

func connect_scene(world: TestWorld) -> void:
	var sit := Situation.new()
	sit.network = RoadNetwork.new()
	sit.network.connections = {"entry": {"width": 8.4}}
	world.add_child(sit)
	world.current = {"sit": sit}

func rebuild(world: TestWorld, oracle := false, base_index := 2) -> void:
	if oracle: world.chunk_signatures.clear()
	world.street.texture_frame = world.texture_frame
	world.street.connector = world.street_connector
	world.street.begin_batch()
	for slot in world.chunk_count: world._place_chunk(slot, slot + base_index)
	world.street.end_batch()

func compare_pool(a: Scenery.Pool, b: Scenery.Pool, label: String) -> void:
	expect(a.transforms == b.transforms and a.tints == b.tints, label + " logical poses/paint")
	expect(a.used == b.used and a.render_slots == b.render_slots, label + " logical/packed slots")
	expect(a.render_transforms == b.render_transforms and a.render_tints == b.render_tints, label + " packed poses/paint")
	expect(a.render_multi.custom_aabb == b.render_multi.custom_aabb, label + " culling bounds")
	expect(a.node.get_meta("occlusion_originals", {}) == b.node.get_meta("occlusion_originals", {})
		and a.node.get_meta("occlusion_fades", {}) == b.node.get_meta("occlusion_fades", {}), label + " fade state")
	if native:
		for i in a.multi.instance_count:
			expect(a.multi.get_instance_transform(i) == b.multi.get_instance_transform(i), label + " native logical pose")
		for i in a.render_slots.size():
			expect(a.render_multi.get_instance_transform(i) == b.render_multi.get_instance_transform(i)
				and a.render_multi.get_instance_custom_data(i) == b.render_multi.get_instance_custom_data(i), label + " native draw pose/paint")

func compare(a: TestWorld, b: TestWorld, label: String) -> void:
	expect(a.street.parked_spots == b.street.parked_spots and a.street.parked_bodies == b.street.parked_bodies, label + " exact parked collision footprints")
	for slot in a.chunk_count:
		var am := a.road_nodes[slot].mesh
		var bm := b.road_nodes[slot].mesh
		expect((am == null) == (bm == null), label + " blank parity")
		if am == null or bm == null: continue
		expect(am.surface_get_arrays(0) == bm.surface_get_arrays(0), label + " all road attributes")
		expect(am.surface_get_material(0) == bm.surface_get_material(0), label + " road material")
	for key in a.street.pools: compare_pool(a.street.pools[key], b.street.pools[key], label + " " + key)
	for key in a.street.parked: compare_pool(a.street.parked[key], b.street.parked[key], label + " " + key)

func exercise(season: String) -> void:
	var sc := Scenery.new(season)
	var cached := make_world(sc)
	var oracle := make_world(sc)
	connect_scene(cached); connect_scene(oracle)
	rebuild(cached); rebuild(oracle, true)
	var plots: int = (cached.street as CountingStreet).plots
	var old_uv: PackedVector2Array = cached.road_nodes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var spots: Array = cached.street.parked_spots[0]
	var bodies: Array = cached.street.parked_bodies[0]
	# Force a real building through the normal occlusion/fade lifecycle.
	var building_at := Vector3.ZERO
	var found := false
	for key in cached.street.pools:
		if not key.begins_with("buildings/"): continue
		var pool: Scenery.Pool = cached.street.pools[key]
		if pool.render_slots.is_empty(): continue
		building_at = pool.transforms[pool.render_slots[0]].origin + Vector3(0, 2, 0)
		found = true
		break
	expect(found, "fixture contains a building to fade")
	var camera := Camera3D.new(); root.add_child(camera)
	camera.position = building_at + Vector3(0, 0, -40)
	camera.look_at(building_at)
	sc.update_occluders(camera, [building_at], 0.1)
	var faded := false
	for pool in cached.street.pools.values():
		if not (pool.node.get_meta("occlusion_originals", {}) as Dictionary).is_empty(): faded = true
	expect(faded, "fixture owns an active faded building before the rebase")
	for world in [cached, oracle]:
		world.texture_frame = Transform3D(Basis(Vector3.UP, 0.7), Vector3(21, 0, -173))
		world.street.profile.p = Vector3(0, 0, -90)
		world.street.profile.out = Vector3.FORWARD
		world.blanks = [[-300.0, -200.0]] # Cannot affect a connected road's width or these ranges.
	rebuild(cached); rebuild(oracle, true)
	expect((cached.street as CountingStreet).plots == plots, "UV/port placement alone does not reroll plots")
	expect(cached.road_nodes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] != old_uv, "road UVs still follow the changed texture frame")
	expect(is_same(spots, cached.street.parked_spots[0]) and is_same(bodies, cached.street.parked_bodies[0]), "reuse retains parking array identities")
	compare(cached, oracle, season + " texture-only")
	sc.update_occluders(camera, [building_at], 0.1)
	compare(cached, oracle, season + " next fade update")
	var ca := Node3D.new(); root.add_child(ca)
	var cb := Node3D.new(); root.add_child(cb)
	cached.street.snapshot(ca); oracle.street.snapshot(cb)
	expect(ca.get_child_count() == cb.get_child_count(), "snapshot pool count")
	for i in ca.get_child_count():
		var a := ca.get_child(i) as MultiMeshInstance3D
		var b := cb.get_child(i) as MultiMeshInstance3D
		expect(a.get_meta("instance_transforms") == b.get_meta("instance_transforms")
			and a.get_meta("instance_tints") == b.get_meta("instance_tints"), "snapshot restores the exact opaque poses/paint")
	ca.free(); cb.free(); camera.free()
	# Each dependency change must take the ordinary full layout path.
	for pass_index in 8:
		plots = (cached.street as CountingStreet).plots
		for world in [cached, oracle]:
			match pass_index:
				0: world.street.parked_chance = 0.0
				1: world.street.profile.width = 14.0; world.street_half = 7.0
				2: world.blanks = [[140.0, 150.0]]
				3: world.current.clear(); world.blanks = [[300.0, 320.0]]
				4: world.blanks = [[270.0, 290.0]] # Same visible ranges, different legacy taper.
				5: world.street_connector = {"start": 120.0, "end": 240.0,
					"from": {"width": 14.0, "lanes": 4}, "to": {"width": 8.4, "lanes": 2}}
				6: world.blanks = [[120.0, 240.0]]
				7: world.blanks.clear()
		rebuild(cached); rebuild(oracle, true)
		if pass_index == 6:
			expect(cached.road_nodes[0].mesh == null and cached.road_nodes[1].mesh == null
				and cached.street.parked_bodies[0].is_empty(), "a newly blank chunk clears its previous road and parking")
		else:
			expect((cached.street as CountingStreet).plots > plots, "layout dependency invalidates reuse " + str(pass_index))
		compare(cached, oracle, season + " invalidation " + str(pass_index))
	plots = (cached.street as CountingStreet).plots
	rebuild(cached, false, 3); rebuild(oracle, true, 3)
	expect((cached.street as CountingStreet).plots > plots, "recycling a slot to a different index reruns its exact seeded layout")
	compare(cached, oracle, season + " recycled index")
	cached.free(); oracle.free()

func benchmark() -> void:
	var sc := Scenery.new("autumn")
	var cached := make_world(sc, 9)
	var oracle := make_world(sc, 9)
	connect_scene(cached); connect_scene(oracle)
	rebuild(cached); rebuild(oracle, true)
	var cached_us := 0
	var oracle_us := 0
	var before: int = (cached.street as CountingStreet).plots
	for pass_index in 12:
		for world in [cached, oracle]:
			world.texture_frame = Transform3D(Basis(Vector3.UP, (pass_index + 1) * 0.1), Vector3(0, 0, -(pass_index + 1) * 120.0))
		var start := Time.get_ticks_usec()
		rebuild(cached)
		cached_us += Time.get_ticks_usec() - start
		start = Time.get_ticks_usec()
		rebuild(oracle, true)
		oracle_us += Time.get_ticks_usec() - start
	expect((cached.street as CountingStreet).plots == before, "nine-chunk benchmark performs zero new plot layouts")
	print("street layout timing: nine chunks, 12 texture changes; reused_ms=", cached_us / 12000.0,
		" full_ms=", oracle_us / 12000.0, "; no timing threshold")
	cached.free(); oracle.free()

func run() -> void:
	native = DisplayServer.get_name() != "headless"
	exercise("autumn")
	exercise("winter")
	benchmark()
	print("street layout reuse: ", checks, " checks, ", failures, " failures; renderer=", DisplayServer.get_name())
	quit(1 if failures else 0)
