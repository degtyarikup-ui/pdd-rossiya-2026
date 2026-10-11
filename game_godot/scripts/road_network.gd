## The road network of one junction scene (game_godot/network/<id>.json, written
## by the web editor and tools/network/migrate.py). This is the single source
## of truth for where the car may drive, which routes exist and what the road
## looks like: the drawn surfaces come from the build (tools/network/build.py),
## the driving checks from the polygons here. The two cannot disagree.
class_name RoadNetwork
extends RefCounted

const ASPHALT_LAYER := "asphalt"

var id := ""
var data: Dictionary
var build: Dictionary             # build/<id>.json: surfaces and kerbs (derived)
var _roads: Array = []            # [{outer: PackedVector2Array, holes: Array, box: Rect2}]
var _routes := {}                 # id -> PackedVector2Array (local x, z)


static func load_scene(scene_id: String) -> RoadNetwork:
	var net := RoadNetwork.new()
	net.id = scene_id
	var path := "res://network/%s.json" % scene_id
	if not FileAccess.file_exists(path):
		return null
	net.data = JSON.parse_string(FileAccess.get_file_as_string(path))
	var built := "res://network/build/%s.json" % scene_id
	if FileAccess.file_exists(built):
		net.build = JSON.parse_string(FileAccess.get_file_as_string(built))
	for r in net.data.roads:
		var outer := _pts(r.outer)
		var holes := []
		for h in r.get("holes", []):
			holes.append(_pts(h))
		net._roads.append({ "outer": outer, "holes": holes, "box": _box(outer) })
	for rt in net.data.routes:
		net._routes[rt.id] = _pts(rt.points)
	return net


static func _pts(list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in list:
		out.append(Vector2(p[0], p[1]))
	return out


static func _box(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## True when the local point (x, z) of the junction lies on the carriageway:
## inside a road outline and outside every island in it.
func is_drivable(local: Vector3) -> bool:
	var p := Vector2(local.x, local.z)
	for road in _roads:
		if not road.box.has_point(p):
			continue
		if not Geometry2D.is_point_in_polygon(p, road.outer):
			continue
		var island := false
		for h in road.holes:
			if Geometry2D.is_point_in_polygon(p, h):
				island = true
				break
		if not island:
			return true
	return false


func has_route(route_id: String) -> bool:
	return _routes.has(route_id)


## A route as local points (x, z) of the junction.
func route(route_id: String) -> PackedVector2Array:
	return _routes.get(route_id, PackedVector2Array())


func stop_point() -> Vector3:
	return Vector3(data.stop.x, 0.0, data.stop.z)


## The drawn surfaces (asphalt, islands, pavement, kerbs) as one ArrayMesh.
## `scenery` supplies the detail-map layers and the shared material. `uv_z` is the
## junction's world z: the detail map is laid on the world grid, the same grid the
## street uses (scripts/street.gd), so the texture carries across the junction edge.
func surface_mesh(scenery: Scenery, uv_z := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in build.surfaces:
		_add_triangles(st, s, scenery, uv_z)
	_add_kerbs(st, scenery, uv_z)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, scenery.material)
	return mesh


func _add_triangles(st: SurfaceTool, s: Dictionary, scenery: Scenery, uv_z: float) -> void:
	# The street's own colours (street.gd), so the junction and the street meet without a seam.
	var colour := Color(s.colour)
	if s.layer == "pavement":
		colour = scenery.color("sidewalk")
	elif s.layer == "asphalt":
		colour = Color("#2C2F36")
	var layer := scenery.layer_of(s.layer)
	var period: float = scenery.kinds[s.layer].period
	var v: Array = s.verts
	var idx: Array = s.idx
	var y: float = s.y
	st.set_color(Color(colour.r, colour.g, colour.b, 0.0))
	var k := 0
	while k < idx.size():
		for c in 3:
			var i: int = idx[k + c] * 2
			var p := Vector3(v[i], y, v[i + 1])
			st.set_uv(Vector2(p.x / period, (p.z + uv_z) / period))
			st.set_uv2(Vector2(layer, 0))
			st.add_vertex(p)
		k += 3


## Kerbs: vertical walls between the carriageway and the raised ground, one set for the
## whole network. Along a wall the texture runs on the world grid too (x + z), so the
## stones line up from one wall to the next.
func _add_kerbs(st: SurfaceTool, scenery: Scenery, uv_z: float) -> void:
	var kerbs: Dictionary = build.kerbs
	var kc := scenery.color("sidewalk")
	st.set_color(Color(kc.r, kc.g, kc.b, 0.0))
	# Plain colour, as the street's kerbs (scripts/street.gd _kerb): an 18 cm wall shows no detail.
	var segs: Array = kerbs.segs
	var j := 0
	while j < segs.size():
		var a := Vector3(segs[j], kerbs.y0, segs[j + 1])
		var b := Vector3(segs[j + 2], kerbs.y0, segs[j + 3])
		var t := Vector3(a.x, kerbs.y1, a.z)
		var u := Vector3(b.x, kerbs.y1, b.z)
		for p in [a, b, u, a, u, t]:
			st.set_uv(Vector2(0, 0))
			st.set_uv2(Vector2(0, 1))
			st.add_vertex(p)
		j += 4
