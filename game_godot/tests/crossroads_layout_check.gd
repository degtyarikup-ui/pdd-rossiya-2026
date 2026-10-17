## Every authored Crossroads situation: building footprints never cut into
## each other, and no building or tree stands on a carriageway or sidewalk
## of the junction (open arms, their sidewalks and the junction square).
extends SceneTree

const Junction := preload("res://scripts/crossroads_junction.gd")
const TOLERANCE := 0.25   # metres: touching walls are fine, interpenetration is not
const NEAR := 200.0       # the distant skyline (~340 m) is a deliberately packed silhouette
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	var scenarios: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/crossroads_scenarios.json"))
	for season in ["summer", "autumn", "winter"]:
		var junction := Junction.new(season)
		root.add_child(junction)
		for scenario: Dictionary in scenarios:
			junction.configure_scenario(scenario)
			await process_frame
			check_layout(junction, "%s/%s" % [season, scenario.id])
		junction.queue_free()
		await process_frame
	print("crossroads layout: %d checks, %d failures (%d scenarios)" % [checks, failures, scenarios.size()])
	quit(1 if failures else 0)

## World-space XZ footprint of a mesh bounding box, shrunk by the tolerance.
func footprint(bounds: AABB, xf: Transform3D) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var lo := bounds.position
	var hi := bounds.end
	for c in [Vector3(lo.x, 0, lo.z), Vector3(hi.x, 0, lo.z), Vector3(hi.x, 0, hi.z), Vector3(lo.x, 0, hi.z)]:
		var w: Vector3 = xf * c
		poly.append(Vector2(w.x, w.z))
	return Geometry2D.offset_polygon(poly, -TOLERANCE)[0] if Geometry2D.offset_polygon(poly, -TOLERANCE).size() > 0 else poly

func collect(junction: Node3D) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for prop: String in junction.pools:
		if not (prop.begins_with("buildings/") or prop.begins_with("trees/")): continue
		var pool = junction.pools[prop]
		var node: MultiMeshInstance3D = pool.node
		if node == null or not node.is_visible_in_tree(): continue
		var bounds: AABB = pool.multi.mesh.get_aabb()
		for i in pool.transforms.size():
			var local: Transform3D = pool.transforms[i]
			if local.origin.y < -10.0: continue
			var xf := node.global_transform * local
			if Vector2(xf.origin.x, xf.origin.z).length() > NEAR: continue
			items.append({"name": "%s#%d@(%.0f,%.0f)" % [prop, i, xf.origin.x, xf.origin.z], "poly": footprint(bounds, xf), "building": prop.begins_with("buildings/")})
	for block in junction.closed_root.get_children():
		for b in block.get_children():
			var mi := b as MeshInstance3D
			if mi == null or mi.mesh == null: continue
			var is_building := str(mi.get_meta("prop", "")).begins_with("buildings/")
			items.append({"name": "%s/%s@(%.0f,%.0f)" % [block.name, mi.get_meta("prop", mi.name), mi.global_position.x, mi.global_position.z], "poly": footprint(mi.mesh.get_aabb(), mi.global_transform), "building": is_building})
	return items

## Paved strips of the junction: each open arm with its sidewalks, and the square.
func paved(junction: Node3D) -> Array[PackedVector2Array]:
	var w: float = Junction.HALF_ROAD + Junction.SIDEWALK_WIDTH
	var far := 140.0
	var strips: Array[PackedVector2Array] = [rect(-w, -w, w, w)]
	for side in ["south", "north", "east", "west"]:
		if side == junction.closed_side: continue
		match side:
			"south": strips.append(rect(-w, 0, w, far))
			"north": strips.append(rect(-w, -far, w, 0))
			"east": strips.append(rect(0, -w, far, w))
			"west": strips.append(rect(-far, -w, 0, w))
	return strips

func rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])

func check_layout(junction: Node3D, id: String) -> void:
	var items := collect(junction)
	var strips := paved(junction)
	for a in items.size():
		var ia: Dictionary = items[a]
		for strip in strips:
			check(Geometry2D.intersect_polygons(ia.poly, strip).is_empty(), "%s %s stands on the road or sidewalk" % [id, ia.name])
		if not ia.building: continue
		for b in range(a + 1, items.size()):
			var ib: Dictionary = items[b]
			if not ib.building: continue
			check(Geometry2D.intersect_polygons(ia.poly, ib.poly).is_empty(), "%s %s overlaps %s" % [id, ia.name, ib.name])
