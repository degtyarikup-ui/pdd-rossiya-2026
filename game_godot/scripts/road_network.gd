## The road network of one junction scene (game_godot/network/<id>.json, written
## by the web editor and tools/network/migrate.py). This is the single source
## of truth for where the car may drive, which routes exist and what the road
## looks like: the drawn surfaces come from the build (tools/network/build.py),
## the driving checks from the polygons here. The two cannot disagree.
class_name RoadNetwork
extends RefCounted

const ASPHALT_LAYER := "asphalt"

var connections := {}
var stitch_bindings: Array = []

var id := ""
var data: Dictionary
var build: Dictionary             # build/<id>.json: surfaces and kerbs (derived)
var _roads: Array = []            # [{outer: PackedVector2Array, holes: Array, box: Rect2}]
var _routes := {}                 # id -> PackedVector2Array (local x, z)
var _cover := {}                  # Vector2i (COVER_CELL bucket) -> [[a, b, c]] drawn triangles, x/z
const COVER_CELL := 5.0


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
	# The drawn carriageway (its curb fillets) is what the car may drive on; the data outline is the fallback.
	if not net.build.is_empty() and net.build.has("carriageway"):
		net._roads.clear()
		for r in net.build.carriageway:
			var outer := _pts(r.outer)
			var holes := []
			for h in r.holes:
				holes.append(_pts(h))
			net._roads.append({ "outer": outer, "holes": holes, "box": _box(outer) })
	net.connections = SceneStitch.describe(net.data, net.build)
	if not net.build.is_empty() and not net.build.surfaces.any(func(surface): return surface.id == "ground"):
		# Old traced scenes use the same continuous lawn/texture grid as editor-built scenes.
		var c := float(net.data.get("crop",90.0))
		net.build.surfaces.append({"id":"ground","layer":"grass","colour":"#9ca66b","y":-0.03,
			"verts":[-c,-c,c,-c,c,c,-c,c],"idx":[0,1,2,0,2,3]})
	net._build_cover()
	return net


## The drawn surfaces bucketed by COVER_CELL, for `covers`.
func _build_cover() -> void:
	if build.is_empty():
		return
	for s in build.surfaces:
		var v: Array = s.verts
		var idx: Array = s.idx
		var k := 0
		while k + 2 < idx.size():
			var a := Vector2(v[idx[k] * 2], v[idx[k] * 2 + 1])
			var b := Vector2(v[idx[k + 1] * 2], v[idx[k + 1] * 2 + 1])
			var c := Vector2(v[idx[k + 2] * 2], v[idx[k + 2] * 2 + 1])
			var box := Rect2(a, Vector2.ZERO).expand(b).expand(c)
			for i in range(floori(box.position.x / COVER_CELL), floori(box.end.x / COVER_CELL) + 1):
				for j in range(floori(box.position.y / COVER_CELL), floori(box.end.y / COVER_CELL) + 1):
					var key := Vector2i(i, j)
					if not _cover.has(key):
						_cover[key] = []
					_cover[key].append([a, b, c])
			k += 3


## True when the local point (x, z) lies on a surface the network draws (asphalt,
## pavement, islands). Used to drop the scene's own copies of those surfaces.
func covers(p: Vector2) -> bool:
	for t in _cover.get(Vector2i(floori(p.x / COVER_CELL), floori(p.y / COVER_CELL)), []):
		var a: Vector2 = t[0]
		var b: Vector2 = t[1]
		var c: Vector2 = t[2]
		var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(d) < 1e-12:
			continue
		var w1 := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / d
		var w2 := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / d
		if w1 >= -1e-6 and w2 >= -1e-6 and 1.0 - w1 - w2 >= -1e-6:
			return true
	return false


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
	if not SceneStitch.contains(local, stitch_bindings) or SceneStitch.median_at(local,stitch_bindings):
		return false
	local = SceneStitch.warp(local, stitch_bindings, true)
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
## `uv_xf` (the junction's placement in the world) wins over `uv_z` when given: after a turn
## rebases the world the junction is rotated and the street's grid with it.
func surface_mesh(scenery: Scenery, uv_z := 0.0, uv_xf := Transform3D()) -> ArrayMesh:
	return surface_mesh_staged.call(scenery, null, uv_z, uv_xf)


func surface_mesh_staged(scenery: Scenery, frames: SceneTree = null, uv_z := 0.0, uv_xf := Transform3D()) -> ArrayMesh:
	if uv_xf == Transform3D():
		uv_xf = Transform3D(Basis(), Vector3(0, 0, uv_z))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # Keep pavement/asphalt normals separate from kerb walls.
	for s in build.surfaces:
		if frames:
			await _add_triangles(st, s, scenery, uv_xf, frames)
		else:
			_add_triangles.call(st, s, scenery, uv_xf)
	_add_kerbs(st, scenery, uv_z)
	_add_end_medians(st,scenery,uv_xf)
	_add_join_marks(st)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, scenery.material)
	return mesh


func _add_triangles(st: SurfaceTool, s: Dictionary, scenery: Scenery, uv_xf: Transform3D, frames: SceneTree = null) -> void:
	# The street's own colours (street.gd), so the junction and the street meet without a seam.
	var colour := Color(s.colour)
	if s.layer == "pavement":
		colour = scenery.color("sidewalk")
	elif s.layer == "asphalt":
		colour = Color("#2C2F36")
	elif s.layer == "grass":
		colour = scenery.color("ground")    # lawns in the season's colour, with the grass detail
	var layer := scenery.layer_of(s.layer)  # 0 (plain paint) for markings: layer ""
	var period: float = scenery.kinds[s.layer].period if scenery.kinds.has(s.layer) else 1.0
	var v: Array = s.verts
	var idx: Array = s.idx
	var y: float = s.y
	st.set_color(Color(colour.r, colour.g, colour.b, 0.0))
	var k := 0
	var slice := Time.get_ticks_usec()
	while k < idx.size():
		if frames and Time.get_ticks_usec()-slice > 2000:
			await frames.process_frame
			slice = Time.get_ticks_usec()
		var triangle: Array = []
		for c in 3:
			var i: int = idx[k + c] * 2
			triangle.append(Vector3(v[i],y,v[i+1]))
		for poly in SceneStitch.render_pieces(triangle,stitch_bindings):
			if s.layer == "" and _join_collar(poly): continue
			if s.layer=="grass" and s.y>0.16 and _join_median(poly): continue
			for fan in range(1, poly.size()-1):
				for p: Vector3 in [poly[0],poly[fan],poly[fan+1]]:
					var w := uv_xf * p
					st.set_uv(Vector2(w.x / period, w.z / period))
					var blend := SceneStitch.surface_blend(p,stitch_bindings) if s.layer in ["asphalt","sand"] else 0.0
					var tint := colour.lerp(Color("#776a53"),blend)
					st.set_color(Color(tint.r,tint.g,tint.b,0.0))
					st.set_uv2(Vector2(layer,-blend))
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
		if _join_median([a,b,u,t]):
			j+=4
			continue
		for triangle in [[a,b,u],[a,u,t]]:
			for poly in SceneStitch.render_pieces(triangle,stitch_bindings):
				for fan in range(1,poly.size()-1):
					for p: Vector3 in [poly[0],poly[fan],poly[fan+1]]:
						st.set_uv(Vector2.ZERO)
						st.set_uv2(Vector2(0,1))
						st.add_vertex(p)
		j += 4


func _add_end_medians(st: SurfaceTool,scenery: Scenery,uv_xf: Transform3D) -> void:
	for binding in stitch_bindings:
		var median: float = binding.get("median",0.0)
		if median<=0.001: continue
		var port: Dictionary = binding.port
		var r := SceneStitch.right(port.out)
		var a: Vector3 = port.p-r*median/2.0
		var b: Vector3 = port.p+r*median/2.0
		var c: Vector3 = b-port.out*SceneStitch.END_BLEND
		var d: Vector3 = a-port.out*SceneStitch.END_BLEND
		var colour := scenery.color("ground")
		var period: float = scenery.kinds.grass.period
		st.set_color(Color(colour.r,colour.g,colour.b,0.0))
		for p: Vector3 in [a,b,c,a,c,d]:
			p.y=0.185
			var w := uv_xf*p
			st.set_uv(Vector2(w.x,w.z)/period)
			st.set_uv2(Vector2(scenery.layer_of("grass"),0))
			st.add_vertex(p)
		colour=scenery.color("sidewalk")
		st.set_color(Color(colour.r,colour.g,colour.b,0.0))
		for edge in [[a,d],[b,c]]:
			var x: Vector3 = edge[0];var y: Vector3 = edge[1]
			for p: Vector3 in [x,y,y+Vector3.UP*0.18,x,y+Vector3.UP*0.18,x+Vector3.UP*0.18]:
				st.set_uv(Vector2.ZERO);st.set_uv2(Vector2(0,1));st.add_vertex(p)


## Replace the last two metres of old paint: rounded endcaps and coincident middle strokes
## must not stretch into two white wedges when two islands are joined. Saved surfaces stay untouched.
func _join_collar(poly: Array) -> bool:
	var centre := Vector3.ZERO
	for p: Vector3 in poly: centre += p
	centre /= poly.size()
	for binding in stitch_bindings:
		var transverse: Array[float]=[]
		for p: Vector3 in poly: transverse.append((p-binding.port.p).dot(SceneStitch.right(binding.port.out)))
		# Wide transverse paint is a crossing/stop line, never a median-border endcap.
		if float(transverse.max())-float(transverse.min())>1.0: continue
		var distance: float = -(centre-binding.port.p).dot(binding.port.out)
		var x: float = absf((centre-binding.port.p).dot(SceneStitch.right(binding.port.out)))
		var median: float = binding.get("median", 0.0)
		if median>0.01 and distance>=-0.001 and distance<SceneStitch.END_BLEND and x<median*0.5+1.0: return true
		var lane_dash: bool = int(binding.port.get("lanes", 2)) == 4 and absf(x-median*0.5-3.5) < 0.4
		var centre_dash: bool = median < 0.01 and binding.port.get("centre", "") == "dashed" and x < 0.4
		if distance >= -0.001 and distance < 2.001 and not lane_dash and not centre_dash: return true
	return false

func _add_join_marks(st: SurfaceTool) -> void:
	st.set_color(Color("#F2F4F8"))
	st.set_uv2(Vector2.ZERO)
	st.set_uv(Vector2.ZERO)
	for binding in stitch_bindings:
		var port: Dictionary = binding.port
		if port.get("surface", "asphalt") == "sand": continue
		var lateral := SceneStitch.right(port.out)
		var half: float = binding.width * 0.5
		var median: float = binding.get("median", 0.0)
		var strokes: Array[float] = []
		if port.get("edge", true): strokes.append_array([-half+0.25,half-0.25])
		if median > 0.01: strokes.append_array([-median*0.5-0.2,median*0.5+0.2])
		elif port.get("centre", "") == "solid": strokes.append(0.0)
		elif port.get("centre", "") == "double": strokes.append_array([-0.15,0.15])
		for x in strokes:
			var a: Vector3 = port.p + lateral * (x-0.075) + Vector3.UP * 0.04
			var b: Vector3 = port.p + lateral * (x+0.075) + Vector3.UP * 0.04
			var length: float=SceneStitch.END_BLEND if median>0.01 and absf(x)<median*0.5+0.5 else 2.0
			var c: Vector3 = b-port.out*length
			var d: Vector3 = a-port.out*length
			for p: Vector3 in [a,b,c,a,c,d]: st.add_vertex(p)


func _join_median(poly: Array) -> bool:
	var centre:=Vector3.ZERO
	for p: Vector3 in poly: centre+=p
	centre/=poly.size()
	for binding in stitch_bindings:
		var median: float=binding.get("median",0.0)
		var distance: float=-(centre-binding.port.p).dot(binding.port.out)
		var x: float=absf((centre-binding.port.p).dot(SceneStitch.right(binding.port.out)))
		if median>0.01 and distance>=-0.001 and distance<SceneStitch.END_BLEND and x<median*0.5+1.0: return true
	return false
