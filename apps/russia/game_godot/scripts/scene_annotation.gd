## Explanatory lines share no answer letters or vehicle paths. The two passes
## keep black dimensions legible on asphalt and white ones legible on markings.
extends RefCounted

static func clean(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if not p is Array or p.size() != 2: continue
		var point := Vector2(float(p[0]), float(p[1]))
		if not point.is_finite(): continue
		if out.is_empty() or point.distance_to(out[-1]) > .0001: out.append(point)
	return out

static func length_of(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()): total += points[i].distance_to(points[i-1])
	return total

static func trim(points: PackedVector2Array, metres: float) -> PackedVector2Array:
	var out := points.duplicate()
	while out.size() > 1:
		var size := out.size()
		var distance := out[size-1].distance_to(out[size-2])
		if distance > metres:
			out[size-1] = out[size-1].lerp(out[size-2], metres/distance)
			break
		metres -= distance
		out.remove_at(size-1)
	return out

static func triangle(out: PackedVector3Array, a: Vector2, b: Vector2, c: Vector2, y: float) -> void:
	for p in [a,b,c]: out.append(Vector3(p.x,y,p.y))

static func disk(out: PackedVector3Array, p: Vector2, half: float, y: float) -> void:
	for i in 16:
		triangle(out,p,p+Vector2(cos(i*PI/8),sin(i*PI/8))*half,
			p+Vector2(cos((i+1)*PI/8),sin((i+1)*PI/8))*half,y)

static func head(out: PackedVector3Array, points: PackedVector2Array, head_length: float,
		head_width: float, border: float, y: float) -> void:
	var tip := points[-1]
	var base := trim(points,head_length)[-1]
	if tip.distance_to(base)<.0001: return
	var forward := (tip-base).normalized()
	var side := Vector2(-forward.y,forward.x)*(head_width+border)
	triangle(out,tip+forward*border*2,base+side-forward*border,base-side-forward*border,y)

static func geometry(route: Dictionary, border := 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var points := clean(route.get("points",[]))
	if points.size()<2 or route.get("style", "") == "text": return out
	var style: String = route.get("style","line")
	var both := style=="both"
	var end := style!="line"
	var width: float = route.get("width",.16)
	var half := (width+border*2)/2
	var head_length := minf(.8,length_of(points)*.35)
	var head_width := maxf(.26,width*2)
	var y := .24 if border>0 else .245
	var line := trim(points,head_length) if end else points
	if both:
		line.reverse()
		line = trim(line,head_length)
		line.reverse()
	for i in range(1,line.size()):
		var a := line[i-1]
		var b := line[i]
		if a.distance_to(b)<.0001: continue
		var forward := (b-a).normalized()
		var side := Vector2(-forward.y,forward.x)*half
		triangle(out,a+side,a-side,b+side,y)
		triangle(out,b+side,a-side,b-side,y)
	for i in line.size():
		if (i>0 and i<line.size()-1) or (i==0 and not both) or (i==line.size()-1 and not end):
			disk(out,line[i],half,y)
	if end: head(out,points,head_length,head_width,border,y)
	if both:
		var reverse := points.duplicate()
		reverse.reverse()
		head(out,reverse,head_length,head_width,border,y)
	return out

static func create(route: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Annotation"
	var ink: String = route.get("colour","#20242b")
	for border in [.04,0.0]:
		var vertices := geometry(route,border)
		if vertices.is_empty(): continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for vertex in vertices: st.add_vertex(vertex)
		var mesh := MeshInstance3D.new()
		mesh.name = "Outline" if border>0 else "Ink"
		mesh.mesh = st.commit()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(("#20242b" if ink=="#ffffff" else "#ffffff") if border>0 else ink)
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)
	var text := str(route.get("text", ""))
	var points := clean(route.get("points", []))
	if not text.is_empty() and not points.is_empty():
		var label := preload("res://scripts/scene_text_label.gd").new()
		label.text = text
		label.font = preload("res://fonts/Onest-Bold.ttf")
		label.font_size = 64
		label.pixel_size = .018 * clampf(float(route.get("textSize",1)),.4,4)
		label.text_angle = float(route.get("textAngle",0))
		label.outline_size = 3
		label.modulate = Color("#20242b")
		label.outline_modulate = Color.WHITE
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		var at := (points[(points.size()-1)/2] + points[-1]) * .5
		label.position = Vector3(at.x, 1.0, at.y)
		root.add_child(label)
	return root
