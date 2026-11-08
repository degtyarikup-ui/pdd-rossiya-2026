## Connections are derived from saved roads. The editor's nodes, routes and objects are never rewritten.
class_name SceneStitch
extends RefCounted

const END_INSET := 24.0
const END_BLEND := 10.0
const SURFACE_BLEND := 2.5     # asphalt -> dirt colour fade at a contact (m)
const WALK_WIDTH := 3.2
const LANE_TRANSITION := 90.0
const _CLIPPED_MESH_META := "_scene_stitch_flat_normals_v1"

static func v(p) -> Vector3:
	return Vector3(float(p[0]), 0.0, float(p[1]))

static func right(t: Vector3) -> Vector3:
	return Vector3(t.z, 0.0, -t.x)

static func yaw(t: Vector3) -> float:
	return atan2(t.x, t.z)

static func along(points: Array, distance: float) -> Dictionary:
	var d := distance
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var length := a.distance_to(b)
		if length < 0.001:
			continue
		if d <= length or i == points.size() - 2:
			return {"p": a + (b - a).normalized() * d, "t": (b - a).normalized()}
		d -= length
	return {"p": points[0], "t": Vector3.FORWARD}

static func describe(data: Dictionary, built: Dictionary) -> Dictionary:
	var ports: Array = []
	var crop := float(data.get("crop", 90.0))
	var layout: Dictionary = data.get("layout", {})
	var nodes := {}
	for n in layout.get("nodes", []):
		nodes[n.id] = Vector3(n.x, 0.0, n.z)
	var degree := {}
	for street in layout.get("streets", []):
		degree[street.a] = int(degree.get(street.a, 0)) + 1
		degree[street.b] = int(degree.get(street.b, 0)) + 1
	for st in layout.get("streets", []):
		var a: Vector3 = nodes[st.a]
		var b: Vector3 = nodes[st.b]
		var line: Array = [a, b]
		if st.get("bend") != null:
			line.clear()
			var c := v(st.bend)
			for i in 25:
				var t := i / 24.0
				line.append(a * pow(1.0-t, 2) + c * 2.0*t*(1.0-t) + b * t*t)
		var length := 0.0
		for i in line.size() - 1:
			length += (line[i] as Vector3).distance_to(line[i + 1])
		for end in [0, 1]:
			var boundary: Vector3 = a if end == 0 else b
			var node_id = st.a if end == 0 else st.b
			var at_crop := maxf(absf(boundary.x), absf(boundary.z)) >= crop - 0.1
			if not at_crop and int(degree.get(node_id, 0)) != 1:
				continue
			var from_edge := line.duplicate()
			if end == 1:
				from_edge.reverse()
			# Short streets can end inside the saved crop. Joining at their real
			# endpoint preserves the junction instead of cutting 24 m past its centre.
			var inset := minf(END_INSET, maxf(0.0, length - 12.0)) if at_crop else 0.0
			var sample := along(from_edge, inset)
			var kind := str(st.get("kind", "street"))
			var median := float(st.get("median", 0.0)) if kind != "yard" else 0.0
			if kind == "highway" and median <= 0.0: median = 3.0
			var width: float = {"yard":5.0,"street":8.4,"avenue":14.0,"highway":21.0}.get(kind,8.4) + median
			var custom: Dictionary = st.get("lanes", {})
			var section := _custom_section(st, length, inset if end == 0 else length-inset,
				int(degree.get(st.a, 0)) == 1 and (absf(absf(a.x)-crop)<0.05 or absf(absf(a.z)-crop)<0.05),
				int(degree.get(st.b, 0)) == 1 and (absf(absf(b.x)-crop)<0.05 or absf(absf(b.z)-crop)<0.05))
			var positive: float = section.right if end == 0 else section.left
			var negative: float = section.left if end == 0 else section.right
			var lane_width: float = section.width
			if not custom.is_empty(): width = (positive + negative) * lane_width + median
			var port := _port(sample.p, -sample.t, width, built,
				-negative * lane_width - median * 0.5 if not custom.is_empty() else -INF,
				positive * lane_width + median * 0.5 if not custom.is_empty() else INF)
			# The built section is authoritative, including older saved highway scenes
			# that still end at 2+2 until the author resaves them in the editor.
			var lanes := 4 if kind == "avenue" else 2
			if kind == "highway":
				lanes = 6 if float(port.width)-float(port.median)>18.0 else 4
				median = float(port.median)
			port.merge({"id": str(st.id)+":"+str(end), "street": st.id, "node": st.a if end == 0 else st.b,
				"boundary":boundary, "lanes":lanes, "declared_median":median, "highway":kind=="highway",
				"walk":st.get("walk",true) and st.get("surface", "asphalt") != "sand", "edge":st.get("edge",true),
				"surface":st.get("surface", "asphalt"),"centre":"none" if st.get("manualMarks",false) else st.get("centre","none" if kind=="yard" else "double" if kind in ["avenue","highway"] else "dashed")}, true)
			if not custom.is_empty():
				var offset: float = (sample.p-port.p).dot(right(port.out))
				# The crop can cut the outermost lane of a very short diagonal. Keep
				# partial capacities instead of advertising a full lane outside asphalt.
				positive = _clean_capacity((float(port.width)*0.5-offset-float(port.median)*0.5)/lane_width)
				negative = _clean_capacity((float(port.width)*0.5+offset-float(port.median)*0.5)/lane_width)
				port.merge({"custom_lanes": true, "positive_lanes": positive, "negative_lanes": negative,
					"lanes": positive + negative, "lane_width": lane_width,
					"centre_offset": offset}, true)
			if not at_crop:
				# Finish after turning into a short branch, while the whole car is
				# still on its road. A minimum lead keeps the nose away from the edge.
				port["finish_distance"] = minf(maxf(20.0, port.p.dot(port.out) - 24.0), maxf(2.5, length - 12.0))
				# A road ending inside the scene is the author's dead end: it finishes the
				# question but never grows a continuation in front of the player.
				port["dead_end"] = true
			ports.append(port)
	# For traced scenes, derive connections from real carriageway sections at the crop.
	# Old exported route tails can be shortened or skewed; extrapolating them may land on the lawn.
	if ports.is_empty():
		for side in [Vector3.BACK,Vector3.FORWARD,Vector3.RIGHT,Vector3.LEFT]:
			var boundary_sections := _sections(side*(crop-0.05),side,built)
			for i in boundary_sections.size():
				var edge: Dictionary = boundary_sections[i]
				var inner := _nearest_section(edge.p-side*END_INSET,side,built)
				var deeper := _nearest_section(edge.p-side*(END_INSET+2.0),side,built)
				if inner.is_empty() or deeper.is_empty(): continue
				var out: Vector3 = (inner.p-deeper.p).normalized()
				if out.length()<0.9: out=side
				var boundary := _boundary(inner.p,out,crop)
				var port := _port(boundary-out*END_INSET,out,float(inner.width)*absf(out.dot(side)),built)
				port.merge({"id":"edge_"+str(side)+":"+str(i),"street":"","node":"","boundary":boundary,
					"lanes":4 if port.width>11.0 else 2,"declared_median":port.median,"walk":true,"edge":true,"surface":"asphalt","centre":"dashed"},true)
				if not ports.any(func(other): return other.p.distance_to(port.p)<4.0 and other.out.dot(port.out)>0.98): ports.append(port)
	var entry: Dictionary = {}
	var approach: Array = []
	for route in data.get("routes", []):
		if route.get("kind") == "approach": approach = route.points
	if approach.size() >= 2:
		entry = _best_port(ports, v(approach[0]), (v(approach[0])-v(approach[1])).normalized(), "")
	var exits := {}
	for route in data.get("routes", []):
		if route.get("kind") != "manoeuvre" or route.points.size()<2: continue
		var points: Array = route.points
		var key := str(route.get("exit","straight"))
		var exclude := "" if key == "uturn" else str(entry.get("id",""))
		var port := _best_port(ports,v(points[-1]),(v(points[-1])-v(points[-2])).normalized(),exclude)
		if not port.is_empty(): exits[key]=port
	return {"ports":ports,"entry":entry,"exits":exits}


## Mirrors Layout.customProfile, including a saved slice created by splitting a
## taper. Read the section at the actual cut, never its original endpoint counts.
static func _custom_section(st: Dictionary, total: float, distance: float, border_a: bool, border_b: bool) -> Dictionary:
	var raw: Dictionary = st.get("lanes", {})
	var span: Dictionary = raw.get("profile", {})
	var config: Dictionary = span.get("config", raw)
	var kind := str(st.get("kind", "street"))
	var count := 3 if kind == "highway" else 2 if kind == "avenue" else 1
	var default_width: float = {"yard": 2.5, "street": 4.2, "avenue": 3.5, "highway": 3.5}.get(kind, 4.2)
	var width := clampf(float(config.get("width", default_width)), 2.5, 4.5)
	var collar := minf(34.0, total*0.4)
	var plain_a := float(span.get("plainA", collar if border_a else 0.0))
	var plain_b := float(span.get("plainB", collar if border_b else 0.0))
	var original_length := float(span.get("length", total))
	if not span.is_empty(): distance = float(span.start)+(float(span.end)-float(span.start))*distance/maxf(0.001,total)
	var taper := maxf(0.001,minf(clampf(float(config.get("taper",40.0)),5.0,150.0),original_length-plain_a-plain_b))
	var result := {"width": width}
	for side in ["left", "right"]:
		var a := clampi(roundi(float(config.get("a", {}).get(side, count))), 1, 6)
		var b := clampi(roundi(float(config.get("b", {}).get(side, count))), 1, 6)
		var t := clampf((distance-plain_a)/taper if a < b else (distance-(original_length-plain_b-taper))/taper,0.0,1.0)
		result[side] = a+(b-a)*t*t*(3.0-2.0*t)
	return result

static func _clean_capacity(value: float) -> float:
	return float(roundi(value)) if absf(value-roundf(value)) < 0.02 else maxf(0.0, value)


## Teaching arrows may be short, edited, or omit a legal branch entirely.
## Their aliases stay intact; every physical road end still leaves the city scene.
static func departure_ports(profile: Dictionary) -> Dictionary:
	if profile.has("departures"):
		return profile.departures
	var result := {}
	var seen := {}
	for key in profile.get("exits", {}):
		var port: Dictionary = profile.exits[key]
		var id := str(port.get("id", key))
		if seen.has(id): continue
		result[key] = port
		seen[id] = true
	for port in profile.get("ports", []):
		var id := str(port.id)
		if seen.has(id): continue
		result["port:" + id] = port
		seen[id] = true
	profile["departures"] = result
	return result


static func _best_port(ports: Array, p: Vector3, t: Vector3, exclude: String) -> Dictionary:
	var best: Dictionary = {}
	var score := INF
	for port in ports:
		if port.id == exclude: continue
		var lateral := absf((p-port.p).dot(right(port.out)))
		var cost: float = (1.0-t.dot(port.out))*100.0 + lateral + p.distance_to(port.p)*0.01
		if cost<score:
			score=cost;best=port
	return best

static func _crossings(ring: Array, p: Vector3, out: Vector3) -> Array:
	var xs: Array = []
	var r := right(out)
	for i in ring.size():
		var a := v(ring[i]);var b := v(ring[(i+1)%ring.size()])
		var da := (a-p).dot(out);var db := (b-p).dot(out)
		if (da>0)==(db>0) or absf(da-db)<0.00001: continue
		xs.append((a.lerp(b,da/(da-db))-p).dot(r))
	xs.sort()
	return xs

static func _port(p: Vector3, out: Vector3, width: float, built: Dictionary, minimum := -INF, maximum := INF) -> Dictionary:
	var bound_lo := -width/2.0 if minimum == -INF else minimum
	var bound_hi := width/2.0 if maximum == INF else maximum
	var lo := bound_lo;var hi := bound_hi;var median := 0.0
	var left: Array = [];var opposite: Array = []
	var spanning := false;var measured := false
	for road in built.get("carriageway", []):
		var xs := _crossings(road.outer,p,out)
		for i in range(0,xs.size()-1,2):
			# A parallel street can share the polygon's outer ring. Measure only
			# this saved street's corridor, never the grass gap and its neighbour.
			var start := maxf(float(xs[i]), bound_lo)
			var end := minf(float(xs[i+1]), bound_hi)
			if end <= start: continue
			measured=true
			if start<=0.5 and end>=-0.5:
				lo=start;hi=end
				spanning=true
			elif end<0.5:
				left.append([start,end])
			elif start>-0.5:
				opposite.append([start,end])
		for hole in road.get("holes",[]):
			var hs := _crossings(hole,p,out)
			if hs.size()>=2 and hs[0]<0.5 and hs[-1]>-0.5: median=hs[-1]-hs[0]
	# A divider continued to the edge splits the built carriageway into two
	# polygons instead of making a hole. Measure the two nearest road sections.
	if not spanning and not left.is_empty() and not opposite.is_empty():
		left.sort_custom(func(a,b): return a[1]>b[1])
		opposite.sort_custom(func(a,b): return a[0]<b[0])
		lo=float(left[0][0]);hi=float(opposite[0][1])
		median=maxf(0.0,float(opposite[0][0])-float(left[0][1]))
	return {"p":p+right(out)*(lo+hi)/2.0,"out":out,"width":hi-lo,"median":median,"measured":measured}

## The divider really present at the contact. A divided street narrows back to the plain
## width before the scene's edge (its own rounded nose and taper), so the declared strip
## must not reappear there as a square block; only an unmeasured contact falls back to it.
static func contact_median(port: Dictionary) -> float:
	if port.get("measured",false): return float(port.get("median",0.0))
	return maxf(float(port.get("median",0.0)),float(port.get("declared_median",0.0)))

static func match_score(a: Dictionary, b: Dictionary) -> float:
	var difference := absf(float(a.lanes)-float(b.lanes))
	if a.get("custom_lanes", false) or b.get("custom_lanes", false):
		difference = absf(side_capacity(a, 1)-side_capacity(b, -1)) + absf(side_capacity(a, -1)-side_capacity(b, 1))
	return 500.0*difference + (200.0 if a.surface!=b.surface else 0.0) + (50.0 if absf(a.declared_median-b.declared_median)>0.1 else 0.0) + absf(a.width-b.width) + (5.0 if a.walk!=b.walk else 0.0)

static func side_lanes(profile: Dictionary, side: int) -> int:
	return maxi(1, ceili(side_capacity(profile, side)))

static func side_capacity(profile: Dictionary, side: int) -> float:
	return float(profile.get("positive_lanes" if side > 0 else "negative_lanes", maxi(1, int(profile.get("lanes", 2)) / 2)))

## Entrance ports face out of their scene, opposite to travel along the connector.
## Reverse only new directional fields; legacy symmetric profiles stay byte-for-byte equal.
static func reverse_profile(profile: Dictionary) -> Dictionary:
	var result := profile.duplicate(true)
	if not profile.get("custom_lanes", false): return result
	result.positive_lanes = side_capacity(profile, -1)
	result.negative_lanes = side_capacity(profile, 1)
	result.centre_offset = -float(profile.get("centre_offset", 0.0))
	return result

## First selection tier: matching physical sections need only a straight seam.
## Other same-lane profiles remain valid fallbacks, with their existing end blend.
static func directly_compatible(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty(): return false
	return not needs_lane_transition(a, b) \
		and str(a.get("surface","asphalt")) == str(b.get("surface","asphalt")) \
		and absf(float(a.get("median",0.0))-float(b.get("median",0.0))) <= 0.1 \
		and absf(float(a.get("width",8.4))-float(b.get("width",8.4))) <= 0.15 \
		and bool(a.get("walk",true)) == bool(b.get("walk",true)) \
		and bool(a.get("edge",true)) == bool(b.get("edge",true)) \
		and str(a.get("centre","dashed")) == str(b.get("centre","dashed"))

static func needs_lane_transition(a: Dictionary,b: Dictionary) -> bool:
	if a.get("custom_lanes", false) or b.get("custom_lanes", false):
		return absf(side_capacity(a, 1)-side_capacity(b, -1)) > 0.01 or absf(side_capacity(a, -1)-side_capacity(b, 1)) > 0.01
	return int(a.get("lanes",2))!=int(b.get("lanes",2))

## Place the next entrance exactly against the previous exit, with tangents opposed.
static func placement(entry: Dictionary, exit: Dictionary, previous := Transform3D()) -> Transform3D:
	var out: Vector3 = previous.basis*exit.out
	var angle := yaw(out)-yaw(-entry.out)
	var basis := Basis(Vector3.UP,angle)
	return Transform3D(basis,previous*exit.p-basis*entry.p)

static func joint_width(a: Dictionary,b: Dictionary) -> float:
	return (float(a.width)+float(b.width))*0.5

static func clip_polygon(points: Array, bindings: Array) -> Array:
	var poly := points
	for binding in bindings:
		if poly.is_empty(): break
		var port: Dictionary = binding.port
		var next: Array = []
		for i in poly.size():
			var a: Vector3 = poly[i];var b: Vector3 = poly[(i+1)%poly.size()]
			var da: float = (a-port.p).dot(port.out);var db: float = (b-port.p).dot(port.out)
			if da<=0.00001: next.append(a)
			if (da>0)!=(db>0): next.append(a.lerp(b,da/(da-db)))
		poly=next
	return poly

static func contains(p: Vector3,bindings: Array) -> bool:
	for binding in bindings:
		if (p-binding.port.p).dot(binding.port.out)>0.001: return false
	return true

## Only the last END_BLEND metres of a road change width. Its centre and every saved node stay put.
static func warp(p: Vector3,bindings: Array,inverse := false) -> Vector3:
	for binding in bindings:
		# Asphalt meeting a dirt road keeps both widths: the asphalt ends in a straight edge on
		# the dirt. Bending only the paved middle of the dirt left its soft sides as torn ears.
		if binding.get("surface","")=="blend": continue
		var port: Dictionary = binding.port
		var d: float = -(p-port.p).dot(port.out)
		if d< -0.001 or d>END_BLEND: continue
		var r := right(port.out)
		var x: float = (p-port.p).dot(r)
		if port.get("custom_lanes", false) or binding.get("custom_lanes", false):
			p = _warp_directional(p, x, d, binding, inverse)
			continue
		var source: float = port.width/2.0
		var target := lerpf(source,float(binding.width)/2.0,smoothstep(END_BLEND,0.0,d))
		if inverse:
			var swap := source;source=target;target=swap
		if absf(x)>source+WALK_WIDTH+2.0: continue
		var sm: float = contact_median(port)/2.0
		var tm: float = lerpf(sm,float(binding.get("median",sm*2.0))/2.0,smoothstep(END_BLEND,0.0,d))
		if inverse:
			var swap := sm;sm=tm;tm=swap
		var ax := absf(x)
		var nx: float
		if ax<=sm and sm>0.001:
			nx=ax*tm/sm
		elif ax<=source:
			nx=tm+(ax-sm)*(target-tm)/maxf(0.01,source-sm)
		else:
			var sw := WALK_WIDTH if port.get("walk",true) else 0.0
			var tw := lerpf(sw,WALK_WIDTH if binding.get("walk",port.get("walk",true)) else 0.0,smoothstep(END_BLEND,0.0,d))
			if inverse:
				var swap := sw;sw=tw;tw=swap
			var offset := ax-source
			nx=target+(offset*tw/sw if sw>0.001 and offset<=sw else offset+tw-sw)
			if not inverse and p.y>0.16 and sw>0.001 and tw<sw: p.y *= tw/sw
		p += r*(signf(x)*nx-x)

	return p


static func _warp_directional(p: Vector3, x: float, d: float, binding: Dictionary, inverse: bool) -> Vector3:
	var port: Dictionary = binding.port
	var t := smoothstep(END_BLEND, 0.0, d)
	var source := float(port.width) * 0.5
	var target := lerpf(source, float(binding.width) * 0.5, t)
	var sm := contact_median(port) * 0.5
	var tm := lerpf(sm, float(binding.get("median", sm * 2.0)) * 0.5, t)
	var sc := float(port.get("centre_offset", 0.0))
	var tc := lerpf(sc, float(binding.get("centre_offset", sc)), t)
	var sw := WALK_WIDTH if port.get("walk", true) else 0.0
	var tw := lerpf(sw, WALK_WIDTH if binding.get("walk", port.get("walk", true)) else 0.0, t)
	if inverse:
		var swap := source; source = target; target = swap
		swap = sm; sm = tm; tm = swap
		swap = sc; sc = tc; tc = swap
		swap = sw; sw = tw; tw = swap
	if absf(x) > source + WALK_WIDTH + 2.0: return p
	var nx: float
	if absf(x) > source:
		var offset := absf(x) - source
		nx = signf(x) * (target + (offset * tw / sw if sw > 0.001 and offset <= sw else offset + tw - sw))
		if not inverse and p.y > 0.16 and sw > 0.001 and tw < sw: p.y *= tw / sw
	elif x < sc - sm:
		nx = lerpf(-target, tc - tm, (x + source) / maxf(0.001, sc - sm + source))
	elif x > sc + sm:
		nx = lerpf(tc + tm, target, (x - sc - sm) / maxf(0.001, source - sc - sm))
	else:
		nx = tc + (x - sc) * tm / sm if sm > 0.001 else tc
	return p + right(port.out) * (nx - x)


static func joint_profile(a: Dictionary,b: Dictionary) -> Dictionary:
	var ma := contact_median(a);var mb := contact_median(b)
	# Both streets are divided but end their dividers in a nose before the contact: the lawn
	# is bridged nose to nose (RoadNetwork._add_median_bridge), so the divider runs on unbroken.
	var da := float(a.get("declared_median",0.0));var db := float(b.get("declared_median",0.0))
	var bridge := minf(da,db) if da>0.01 and db>0.01 and not (ma>0.01 and mb>0.01) else 0.0
	var result := {"width":joint_width(a,b),"median":(ma+mb)*0.5 if ma>0.01 and mb>0.01 else 0.0,
		"bridge":bridge,"walk":a.walk and b.walk,"surface":a.surface if a.surface==b.surface else "blend"}
	if a.get("custom_lanes", false) or b.get("custom_lanes", false):
		result.merge({"custom_lanes": true, "positive_lanes": side_capacity(a, 1), "negative_lanes": side_capacity(a, -1),
			"centre_offset": (float(a.get("centre_offset", 0.0)) - float(b.get("centre_offset", 0.0))) * 0.5}, true)
	return result

## Asphalt tone fading into a dirt road over the last SURFACE_BLEND metres before the contact.
static func surface_blend(p: Vector3,bindings: Array) -> float:
	var blend := 0.0
	for binding in bindings:
		if binding.get("surface","")!="blend": continue
		var d: float = -(p-binding.port.p).dot(binding.port.out)
		if d>=-0.001 and d<SURFACE_BLEND: blend=maxf(blend,smoothstep(SURFACE_BLEND,0.0,d))
	return blend


static func median_at(p: Vector3,bindings: Array) -> bool:
	for binding in bindings:
		var median: float = binding.get("median",0.0)
		var d: float = -(p-binding.port.p).dot(binding.port.out)
		if int(binding.port.get("lanes",2))==6 and binding.port.get("highway",false):
			median=lerpf(float(binding.port.get("median",0.0)),median,smoothstep(END_BLEND,0.0,d))
		if median<=0.001: continue
		var offset := 0.0
		if binding.port.get("custom_lanes", false) or binding.get("custom_lanes", false):
			offset = lerpf(float(binding.port.get("centre_offset", 0.0)), float(binding.get("centre_offset", binding.port.get("centre_offset", 0.0))), smoothstep(END_BLEND, 0.0, d))
			median = lerpf(float(binding.port.get("median", 0.0)), median, smoothstep(END_BLEND, 0.0, d))
		if d>=-0.001 and d<=END_BLEND and absf((p-binding.port.p).dot(right(binding.port.out)) - offset)<median/2.0-0.001: return true
	return false

## Only generated triangle meshes with SurfaceTool.set_smooth_group(-1) and
## generate_normals after all vertices are emitted may opt into first-cut reuse.
## Imported/smoothed geometry must still pass through the normal-flattening oracle.
static func mark_generated_flat_mesh(mesh: ArrayMesh) -> ArrayMesh:
	if mesh != null: mesh.set_meta(_CLIPPED_MESH_META, true)
	return mesh

## Trim a frozen street to the old side of a join, interpolating all texture/color attributes.
static func clip_mesh(mesh: Mesh, placement: Transform3D) -> Mesh:
	if mesh.get_surface_count() == 0: return null
	# The cut is an affine plane, so the transformed AABB's eight corners bound
	# every vertex. Most retained street pieces are wholly behind/ahead of it.
	# Only reuse our own immutable results: imported meshes still need the old
	# normal flattening on their first cut, even when no triangles are removed.
	# The old polygon clipper keeps z <= 1e-5 but crosses edges at z == 0.
	# Leave that entire boundary band, plus real_t rounding, on its existing path.
	var bounds := mesh.get_aabb()
	var magnitude := bounds.position.abs() + bounds.size.abs()
	var roundoff := (absf(placement.origin.z) + absf(placement.basis.x.z) * magnitude.x
		+ absf(placement.basis.y.z) * magnitude.y + absf(placement.basis.z.z) * magnitude.z) * 0.000001 + 0.000001
	var minimum := INF
	var maximum := -INF
	var finite_bounds := is_finite(roundoff)
	for i in 8:
		var z := (placement * bounds.get_endpoint(i)).z
		if not is_finite(z):
			finite_bounds = false
			break
		minimum = minf(minimum, z)
		maximum = maxf(maximum, z)
	if finite_bounds:
		if maximum < -roundoff and mesh.get_meta(_CLIPPED_MESH_META, false): return mesh
		if minimum > 0.00001 + roundoff: return null
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
			var ia := indices[k]; var ib := indices[k + 1]; var ic := indices[k + 2]
			var da: float = (placement * verts[ia]).z
			var db: float = (placement * verts[ib]).z
			var dc: float = (placement * verts[ic]).z
			# Most triangles of a crossing mesh lie wholly on one side. Preserve
			# the oracle's emitted order/default attributes without per-point dictionaries.
			# The asymmetric 0 / 1e-5 boundary band still uses the original polygon path.
			if da <= 0.0 and db <= 0.0 and dc <= 0.0:
				for i in [ia, ib, ic]:
					tool.set_uv(uvs[i] if not uvs.is_empty() else Vector2.ZERO)
					tool.set_uv2(uv2[i] if not uv2.is_empty() else Vector2.ZERO)
					tool.set_color(colours[i] if not colours.is_empty() else Color.WHITE)
					tool.add_vertex(verts[i])
				count += 3
				continue
			if da > 0.00001 and db > 0.00001 and dc > 0.00001: continue
			var poly: Array = []
			for i in [indices[k],indices[k+1],indices[k+2]]:
				poly.append({"p":verts[i],"u":uvs[i] if not uvs.is_empty() else Vector2.ZERO,
					"v":uv2[i] if not uv2.is_empty() else Vector2.ZERO,"c":colours[i] if not colours.is_empty() else Color.WHITE})
			var kept: Array = []
			for i in 3:
				var a: Dictionary = poly[i];var b: Dictionary = poly[(i+1)%3]
				var edge_a: float = (placement*a.p).z;var edge_b: float = (placement*b.p).z
				if edge_a<=0.00001: kept.append(a)
				if (edge_a>0)!=(edge_b>0):
					var t := edge_a/(edge_a-edge_b)
					kept.append({"p":a.p.lerp(b.p,t),"u":a.u.lerp(b.u,t),"v":a.v.lerp(b.v,t),"c":a.c.lerp(b.c,t)})
			for fan in range(1,kept.size()-1):
				for point in [kept[0],kept[fan],kept[fan+1]]:
					tool.set_uv(point.u);tool.set_uv2(point.v);tool.set_color(point.c);tool.add_vertex(point.p);count+=1
		if count:
			tool.generate_normals();tool.commit(result)
			result.surface_set_material(result.get_surface_count()-1,mesh.surface_get_material(surface))
	result.set_meta(_CLIPPED_MESH_META, true)
	return result if result.get_surface_count()>0 else null

## Split coarse triangles at the end collar before deforming them. Otherwise an end's width
## would interpolate across the whole road, or freshly clipped edge vertices would keep the old width.
static func render_pieces(triangle: Array,bindings: Array) -> Array:
	var initial := clip_polygon(triangle,bindings)
	if initial.size()<3: return []
	var pieces: Array = [initial]
	for binding in bindings:
		for depth in [2.0,4.0,6.0,8.0,END_BLEND]:
			var origin: Vector3 = binding.port.p-binding.port.out*depth
			var normal: Vector3 = binding.port.out
			var next: Array = []
			for poly in pieces:
				var positive := false;var negative := false
				for p: Vector3 in poly:
					var distance := (p-origin).dot(normal)
					positive=positive or distance>0.00001;negative=negative or distance< -0.00001
				if not positive or not negative:
					next.append(poly)
					continue
				for side in [1.0,-1.0]:
					var kept: Array = []
					for i in poly.size():
						var a: Vector3=poly[i];var b: Vector3=poly[(i+1)%poly.size()]
						var da: float = (a-origin).dot(normal)*side;var db: float = (b-origin).dot(normal)*side
						if da<=0.00001: kept.append(a)
						if (da>0)!=(db>0): kept.append(a.lerp(b,da/(da-db)))
					if kept.size()>=3: next.append(kept)
			pieces=next
	var result: Array = []
	for poly in pieces:
		var warped: Array = []
		for p: Vector3 in poly: warped.append(warp(p,bindings))
		var clipped := clip_polygon(warped,bindings)
		if clipped.size()>=3: result.append(clipped)
	return result


static func _sections(p: Vector3,out: Vector3,built: Dictionary) -> Array:
	var result: Array = []
	for road in built.get("carriageway",[]):
		var xs := _crossings(road.outer,p,out)
		for i in range(0,xs.size()-1,2):
			if xs[i+1]-xs[i]<2.0: continue
			result.append({"p":p+right(out)*(xs[i]+xs[i+1])/2.0,"width":xs[i+1]-xs[i]})
	return result

static func _nearest_section(p: Vector3,out: Vector3,built: Dictionary) -> Dictionary:
	var result := {};var distance := INF
	for section in _sections(p,out,built):
		var d: float = section.p.distance_to(p)
		if d<distance: distance=d;result=section
	return result

static func _boundary(p: Vector3,t: Vector3,crop: float) -> Vector3:
	var distance := INF
	if absf(t.x)>0.001: distance=minf(distance,((crop if t.x>0 else -crop)-p.x)/t.x)
	if absf(t.z)>0.001: distance=minf(distance,((crop if t.z>0 else -crop)-p.z)/t.z)
	return p+t*maxf(0.0,distance)
