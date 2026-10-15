## Compare conservative clipping shortcuts with the pre-optimization polygon oracle.
## godot --headless --path game_godot --script res://tests/mesh_clip_check.gd
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func run() -> void:
	shortcuts()
	boundaries()
	differential()
	repeated_cuts()
	generated_flat_streets()
	fixture("ticket_20_15")
	fixture("ticket_12_14")
	print("mesh clipping: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func make_mesh(indexed := false) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface in 2:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_smooth_group(-1)
		var shift := Vector3(0.2 * surface, 0.35 * surface, 0.1 * surface)
		for vertex in [Vector3(-2, 0, -2), Vector3(-2, 0, 2), Vector3(2, 0, -2),
			Vector3(2, 0, -2), Vector3(-2, 0, 2), Vector3(2, 1, 2)]:
			var p: Vector3 = vertex + shift
			tool.set_uv(Vector2(p.x * 0.2, p.z * 0.3))
			tool.set_uv2(Vector2(p.y * 0.4, p.x * 0.5))
			tool.set_color(Color(0.4 + p.x * 0.1, 0.4 + p.y * 0.1, 0.4 + p.z * 0.1, 0.7))
			tool.add_vertex(p)
		tool.generate_normals()
		if indexed: tool.index()
		tool.commit(mesh)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.5, 0.6, 0.7)
		mesh.surface_set_material(surface, material)
	return mesh

func plane_mesh(z: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [Vector3(-1, -1, z), Vector3(1, -1, z), Vector3(0, 1, z)]:
		tool.add_vertex(vertex)
	tool.generate_normals()
	return tool.commit()

func mesh_state(mesh: Mesh) -> int:
	var state := []
	for surface in mesh.get_surface_count():
		state.append(mesh.surface_get_arrays(surface))
		state.append(mesh.surface_get_material(surface))
	return hash(state)

func shortcuts() -> void:
	var mesh := make_mesh(true)
	var before := mesh_state(mesh)
	var frame := Transform3D(Basis(), Vector3(0, 0, -20))
	var first := SceneStitch.clip_mesh(mesh, frame)
	expect(first != mesh, "first retained original still follows the normal-flattening oracle")
	compare(first, oracle(mesh, frame), "first retained indexed multisurface mesh")
	var first_state := mesh_state(first)
	var kept := SceneStitch.clip_mesh(first, frame)
	expect(kept == first, "subsequent fully retained mesh reuses the normalized resource")
	expect(mesh_state(kept) == first_state, "reuse preserves exact normals, UVs, colours, indices and materials")
	expect(SceneStitch.clip_mesh(mesh, Transform3D(Basis(), Vector3(0, 0, 20))) == null, "fully discarded mesh has no result")
	expect(mesh_state(mesh) == before, "discard does not mutate the input")
	var crossed := SceneStitch.clip_mesh(mesh, Transform3D())
	expect(crossed != null and crossed != mesh, "intersecting mesh uses an independent clipped resource")
	expect(mesh_state(mesh) == before, "intersection does not mutate the input")
	var primitive := BoxMesh.new()
	var normalized := SceneStitch.clip_mesh(primitive, frame)
	compare(normalized, oracle(primitive, frame), "first PrimitiveMesh is normalized")
	expect(SceneStitch.clip_mesh(normalized, frame) == normalized, "normalized PrimitiveMesh result can be reused")
	expect(SceneStitch.clip_mesh(ArrayMesh.new(), Transform3D(Basis(), Vector3(0, 0, -20))) == null, "empty mesh keeps the oracle null result")

func boundaries() -> void:
	# The original clipper has two distinct thresholds: kept <= 1e-5, crossing > 0.
	for z in [-0.00002, -0.000001, 0.0, 0.000001, 0.000005, 0.00001, 0.0000101, 0.00002]:
		var mesh := plane_mesh(z)
		compare(SceneStitch.clip_mesh(mesh, Transform3D()), oracle(mesh, Transform3D()), "plane boundary %.8f" % z)
	var mesh := SceneStitch.clip_mesh(plane_mesh(-0.000001), Transform3D(Basis(), Vector3(0, 0, -20)))
	expect(SceneStitch.clip_mesh(mesh, Transform3D()) != mesh, "rounding guard keeps near-plane vertices on the original path")
	# Large opposing translations amplify rounding of local AABB endpoints.
	var large := make_mesh(true)
	var large_frame := Transform3D(Basis(Vector3.UP, 0.37).scaled(Vector3(2.1, 0.7, -1.3)), Vector3(10000, -20000, -0.000001))
	compare(SceneStitch.clip_mesh(large, large_frame), oracle(large, large_frame), "scaled reflected near-plane transform")

func differential() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 70215
	for indexed in [false, true]:
		var mesh := make_mesh(indexed)
		var before := mesh_state(mesh)
		for i in 96:
			var rotation := Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)))
			var scale := Vector3(rng.randf_range(0.2, 3), rng.randf_range(0.2, 3), rng.randf_range(0.2, 3))
			if i % 3 == 0: scale.x *= -1
			var frame := Transform3D(rotation.scaled(scale), Vector3(rng.randf_range(-10, 10), rng.randf_range(-10, 10), rng.randf_range(-9, 9)))
			compare(SceneStitch.clip_mesh(mesh, frame), oracle(mesh, frame), "random %s/%d" % [indexed, i])
		expect(mesh_state(mesh) == before, "differential inputs stay immutable " + str(indexed))

func repeated_cuts() -> void:
	var actual: Mesh = make_mesh(true)
	var reference: Mesh = actual
	var frames := [Transform3D(), Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 0, -0.2)),
		Transform3D(Basis(Vector3.UP, -PI / 3).scaled(Vector3(0.7, 1.3, 1.9)), Vector3(0, 0, -0.5)),
		Transform3D(Basis(), Vector3(0, 0, -100)), Transform3D(Basis(), Vector3(0, 0, 100))]
	for i in frames.size():
		actual = SceneStitch.clip_mesh(actual, frames[i]) if actual else null
		reference = oracle(reference, frames[i]) if reference else null
		compare(actual, reference, "accumulated cut " + str(i))

func generated_flat_streets() -> void:
	var holder := Node3D.new(); root.add_child(holder)
	var scenery := Scenery.new("summer")
	var street := Street.new(holder, scenery, 60.0, 1)
	for index in [-9, -1, 0, 1, 8, 15]:
		var mesh := street.build_chunk(0, index)
		var before := mesh_state(mesh)
		var frame := Transform3D(Basis(Vector3.UP, 0.43), Vector3(0, 0, -10000))
		var reference := oracle(mesh, frame)
		SceneStitch.mark_generated_flat_mesh(mesh)
		expect(SceneStitch.clip_mesh(mesh, frame) == mesh, "generated street reuses its first retained cut " + str(index))
		compare(mesh, reference, "generated street oracle " + str(index))
		for surface in mesh.get_surface_count():
			expect(mesh.surface_get_arrays(surface) == reference.surface_get_arrays(surface), "generated street exact raw attribute arrays " + str(index))
		expect(mesh_state(mesh) == before, "flat marker never mutates generated geometry " + str(index))
		compare(SceneStitch.clip_mesh(mesh, Transform3D()), oracle(mesh, Transform3D()), "generated crossing cut " + str(index))
	holder.free()

func expanded(mesh: Mesh, surface: int, slot: int) -> Array:
	var arrays := mesh.surface_get_arrays(surface)
	var values = arrays[slot]
	# A missing UV/colour array has the same shader default as the old clipper's
	# explicitly filled zero UVs/white colours; reuse preserves the absent array.
	if values == null or values.size() == 0:
		values = []
		var fallback: Variant = Color.WHITE if slot == Mesh.ARRAY_COLOR else Vector2.ZERO
		if slot not in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]: return []
		for i in mesh.surface_get_array_len(surface): values.append(fallback)
	var out := []
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		for value in values: out.append(value)
	else:
		for index in indices: out.append(values[index])
	return out

func compare(actual: Mesh, reference: Mesh, label: String, normals := true) -> void:
	expect((actual == null) == (reference == null), label + " presence")
	if actual == null or reference == null: return
	expect(actual.get_surface_count() == reference.get_surface_count(), label + " surfaces")
	if actual.get_surface_count() != reference.get_surface_count(): return
	var slots := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]
	if normals: slots.append(Mesh.ARRAY_NORMAL)
	for surface in actual.get_surface_count():
		expect(actual.surface_get_material(surface) == reference.surface_get_material(surface), label + " material " + str(surface))
		for slot in slots:
			var a := expanded(actual, surface, slot)
			var b := expanded(reference, surface, slot)
			var equal := a.size() == b.size()
			if equal:
				for i in a.size():
					if not a[i].is_equal_approx(b[i]):
						equal = false
						break
			expect(equal, label + " attribute %d surface %d" % [slot, surface])

func fixture(id: String) -> void:
	var source := load("res://situations/%s/scene.glb" % id) as PackedScene
	expect(source != null, "real fixture exists " + id)
	if source == null: return
	var scene := source.instantiate()
	for node in scene.find_children("static", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		var before := mesh_state(mesh)
		var bounds := mesh.get_aabb()
		var distance := maxf(bounds.position.length(), bounds.end.length()) * 2.0 + 10.0
		for kind in ["retained", "removed", "intersecting"]:
			var frame := Transform3D(Basis(Vector3.UP, 0.43), Vector3(0, 0, -distance if kind == "retained" else distance if kind == "removed" else 0.0))
			var actual := SceneStitch.clip_mesh(mesh, frame)
			var reference := oracle(mesh, frame)
			compare(actual, reference, id + " " + kind)
			if kind == "retained":
				expect(actual != mesh, id + " first original follows normal flattening")
				expect(SceneStitch.clip_mesh(actual, frame) == actual, id + " reuses normalized retained geometry")
			if kind == "removed": expect(actual == null, id + " rejects removed real geometry")
			var timed_mesh: Mesh = actual if kind == "retained" else mesh
			var repetitions := 3
			var started := Time.get_ticks_usec()
			for i in repetitions: SceneStitch.clip_mesh(timed_mesh, frame)
			var optimized_us := Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			for i in repetitions: oracle(timed_mesh, frame)
			var oracle_us := Time.get_ticks_usec() - started
			print("[mesh-clip] ", id, " ", kind, " normalized_input=", kind == "retained", " input_vertices=", vertex_count(timed_mesh), " output_vertices=", vertex_count(actual), " optimized_us=", optimized_us / repetitions, " oracle_us=", oracle_us / repetitions)
		expect(mesh_state(mesh) == before, id + " real input remains immutable")
	scene.free()

func vertex_count(mesh: Mesh) -> int:
	var count := 0
	if mesh:
		for surface in mesh.get_surface_count(): count += mesh.surface_get_array_len(surface)
	return count

## The complete original implementation is kept independent of the AABB decision.
func oracle(mesh: Mesh, placement: Transform3D) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2]!=null else PackedVector2Array()
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
		if indices.is_empty(): indices=PackedInt32Array(range(verts.size()))
		var tool := SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_smooth_group(-1)
		var count := 0
		for k in range(0,indices.size(),3):
			var poly: Array = []
			for i in [indices[k],indices[k+1],indices[k+2]]:
				poly.append({"p":verts[i],"u":uvs[i] if not uvs.is_empty() else Vector2.ZERO,
					"v":uv2[i] if not uv2.is_empty() else Vector2.ZERO,"c":colours[i] if not colours.is_empty() else Color.WHITE})
			var kept: Array = []
			for i in 3:
				var a: Dictionary = poly[i];var b: Dictionary = poly[(i+1)%3]
				var da: float = (placement*a.p).z;var db: float = (placement*b.p).z
				if da<=0.00001: kept.append(a)
				if (da>0)!=(db>0):
					var t := da/(da-db)
					kept.append({"p":a.p.lerp(b.p,t),"u":a.u.lerp(b.u,t),"v":a.v.lerp(b.v,t),"c":a.c.lerp(b.c,t)})
			for fan in range(1,kept.size()-1):
				for point in [kept[0],kept[fan],kept[fan+1]]:
					tool.set_uv(point.u);tool.set_uv2(point.v);tool.set_color(point.c);tool.add_vertex(point.p);count+=1
		if count:
			tool.generate_normals();tool.commit(result)
			result.surface_set_material(result.get_surface_count()-1,mesh.surface_get_material(surface))
	return result if result.get_surface_count()>0 else null
