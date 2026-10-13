## Movement uses the same clipped, widened triangles that are actually drawn.
## Markings have no collision area; raised islands override the road beneath them.
class_name GroundMap
extends RefCounted

const CELL := 5.0
const ROAD := 1
const WALK := 2
var buckets := {}

func _init(mesh: Mesh, scenery: Scenery) -> void:
	if mesh == null: return
	var road_layers := [roundi(scenery.layer_of("asphalt")), roundi(scenery.layer_of("dirt"))]
	var walk_layer := roundi(scenery.layer_of("pavement"))
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var layers: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if layers.size() != verts.size(): continue
		var count := indices.size() if not indices.is_empty() else verts.size()
		for i in range(0, count, 3):
			var ids := [i, i+1, i+2]
			if not indices.is_empty(): ids = [indices[i], indices[i+1], indices[i+2]]
			var layer := roundi(layers[ids[0]].x)
			if layer == 0: continue
			var a := Vector2(verts[ids[0]].x, verts[ids[0]].z)
			var b := Vector2(verts[ids[1]].x, verts[ids[1]].z)
			var c := Vector2(verts[ids[2]].x, verts[ids[2]].z)
			var denominator := (b-c).cross(a-c)
			if absf(denominator) < 0.000001: continue
			var y := (verts[ids[0]].y + verts[ids[1]].y + verts[ids[2]].y) / 3.0
			var kind := ROAD if layer in road_layers else WALK if layer == walk_layer else 0
			var triangle := [a, b, c, denominator, y, kind]
			var bounds := Rect2(a, Vector2.ZERO).expand(b).expand(c)
			for x in range(floori(bounds.position.x/CELL), floori(bounds.end.x/CELL)+1):
				for z in range(floori(bounds.position.y/CELL), floori(bounds.end.y/CELL)+1):
					var key := Vector2i(x,z)
					if not buckets.has(key): buckets[key] = []
					buckets[key].append(triangle)

func at(p: Vector3) -> int:
	var q := Vector2(p.x,p.z)
	var height := -INF
	var kind := 0
	for t in buckets.get(Vector2i(floori(q.x/CELL),floori(q.y/CELL)),[]):
		var a: Vector2 = t[0]; var b: Vector2 = t[1]; var c: Vector2 = t[2]
		var u := (b-c).cross(q-c)/float(t[3])
		var v := (q-c).cross(a-c)/float(t[3])
		if u < -0.00001 or v < -0.00001 or u+v > 1.00001: continue
		if float(t[4]) > height+0.0001:
			height = t[4]; kind = t[5]
		elif absf(float(t[4])-height)<0.0001: kind |= int(t[5])
	return kind
