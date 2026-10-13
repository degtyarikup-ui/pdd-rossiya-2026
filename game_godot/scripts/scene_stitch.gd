## Connections are derived from saved roads. The editor's nodes, routes and objects are never rewritten.
class_name SceneStitch
extends RefCounted

const END_INSET := 24.0
const END_BLEND := 10.0
const WALK_WIDTH := 3.2

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
		for end in [0, 1]:
			var boundary: Vector3 = a if end == 0 else b
			if maxf(absf(boundary.x), absf(boundary.z)) < crop - 0.1:
				continue
			var from_edge := line.duplicate()
			if end == 1:
				from_edge.reverse()
			var sample := along(from_edge, END_INSET)
			var kind := str(st.get("kind", "street"))
			var median := float(st.get("median", 0.0)) if kind != "yard" else 0.0
			var width: float = {"yard":5.0,"street":8.4,"avenue":14.0}.get(kind,8.4) + median
			var port := _port(sample.p, -sample.t, width, built)
			port.merge({"id": str(st.id)+":"+str(end), "street": st.id, "node": st.a if end == 0 else st.b,
				"boundary":boundary, "lanes":4 if kind == "avenue" else 2, "declared_median":median,
				"walk":st.get("walk",true) and st.get("surface", "asphalt") != "sand", "edge":st.get("edge",true),
				"surface":st.get("surface", "asphalt"),"centre":"none" if st.get("manualMarks",false) else st.get("centre","none" if kind=="yard" else "double" if kind=="avenue" else "dashed")}, true)
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

static func _best_port(ports: Array, p: Vector3, t: Vector3, exclude: String) -> Dictionary:
	var best: Dictionary = {}
	var score := INF
	for port in ports:
		if port.id == exclude: continue
		var cost: float = (1.0-t.dot(port.out))*100.0 + p.distance_to(port.p)*0.01
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

static func _port(p: Vector3, out: Vector3, width: float, built: Dictionary) -> Dictionary:
	var lo := -width/2.0;var hi := width/2.0;var median := 0.0
	for road in built.get("carriageway", []):
		var xs := _crossings(road.outer,p,out)
		for i in range(0,xs.size()-1,2):
			if xs[i]<=0.5 and xs[i+1]>=-0.5:
				lo=xs[i];hi=xs[i+1]
		for hole in road.get("holes",[]):
			var hs := _crossings(hole,p,out)
			if hs.size()>=2 and hs[0]<0.5 and hs[-1]>-0.5: median=hs[-1]-hs[0]
	return {"p":p+right(out)*(lo+hi)/2.0,"out":out,"width":hi-lo,"median":median}

static func match_score(a: Dictionary, b: Dictionary) -> float:
	return (1000.0 if a.lanes!=b.lanes else 0.0) + (200.0 if a.surface!=b.surface else 0.0) + (50.0 if absf(a.declared_median-b.declared_median)>0.1 else 0.0) + absf(a.width-b.width) + (5.0 if a.walk!=b.walk else 0.0)

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
		var port: Dictionary = binding.port
		var d: float = -(p-port.p).dot(port.out)
		if d< -0.001 or d>END_BLEND: continue
		var r := right(port.out)
		var x: float = (p-port.p).dot(r)
		var source: float = port.width/2.0
		var target := lerpf(source,float(binding.width)/2.0,smoothstep(END_BLEND,0.0,d))
		if inverse:
			var swap := source;source=target;target=swap
		if absf(x)>source+WALK_WIDTH+2.0: continue
		var sm: float = maxf(float(port.get("median",0.0)),float(port.get("declared_median",0.0)))/2.0
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


static func joint_profile(a: Dictionary,b: Dictionary) -> Dictionary:
	return {"width":joint_width(a,b),"median":(float(a.declared_median)+float(b.declared_median))*0.5 if a.declared_median>0.01 and b.declared_median>0.01 else 0.0,
		"walk":a.walk and b.walk,"surface":a.surface if a.surface==b.surface else "blend"}

static func surface_blend(p: Vector3,bindings: Array) -> float:
	var blend := 0.0
	for binding in bindings:
		if binding.get("surface","")!="blend": continue
		var d: float = -(p-binding.port.p).dot(binding.port.out)
		if d>=-0.001 and d<END_BLEND: blend=maxf(blend,smoothstep(END_BLEND,0.0,d))
	return blend


static func median_at(p: Vector3,bindings: Array) -> bool:
	for binding in bindings:
		var median: float = binding.get("median",0.0)
		if median<=0.001: continue
		var d: float = -(p-binding.port.p).dot(binding.port.out)
		if d>=-0.001 and d<=END_BLEND and absf((p-binding.port.p).dot(right(binding.port.out)))<median/2.0-0.001: return true
	return false

## Trim a frozen street to the old side of a join, interpolating all texture/color attributes.
static func clip_mesh(mesh: Mesh, placement: Transform3D) -> ArrayMesh:
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
