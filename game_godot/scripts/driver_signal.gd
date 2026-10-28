## A driver's arm outside the left window. Vehicle-local +X is left.
class_name DriverSignal
extends Node3D

static func supports(kind: String) -> bool:
	return kind in ["car","truck","bus","van","tanker","special"]

static func _glass(c: Color) -> bool:
	return c.r>=.125 and c.r<=.265 and c.g>=.205 and c.g<=.365 and c.b>=.275 and c.b<=.455

static func window_anchor(mesh: Mesh) -> Variant:
	var faces: Array = []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
		if colours.is_empty(): continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty(): indices=PackedInt32Array(range(vertices.size()))
		for i in range(0,indices.size(),3):
			var ids := [indices[i],indices[i+1],indices[i+2]]
			if not ids.all(func(j): return _glass(colours[j])): continue
			var v: Array[Vector3] = [vertices[ids[0]],vertices[ids[1]],vertices[ids[2]]]
			var normal := (v[1]-v[0]).cross(v[2]-v[0]).normalized()
			if v.all(func(p): return p.x>0) and absf(normal.x)>.7 and absf(normal.z)<.35: faces.append(v)
	if faces.is_empty(): return null
	faces.sort_custom(func(a,b): return a[0].z+a[1].z+a[2].z>b[0].z+b[1].z+b[2].z)
	var pane: Array = faces.pop_front()
	var joined := true
	while joined:
		joined=false
		for i in range(faces.size()-1,-1,-1):
			if faces[i].any(func(p): return pane.any(func(q): return p.distance_squared_to(q)<1e-8)):
				pane.append_array(faces.pop_at(i));joined=true
	var unique: Array[Vector3] = []
	for p: Vector3 in pane:
		if not unique.any(func(q): return p.distance_squared_to(q)<1e-8): unique.append(p)
	unique.sort_custom(func(a,b): return a.y<b.y)
	if unique.size()!=4: return null
	var low: Array[Vector3] = [unique[0],unique[1]]
	var high: Array[Vector3] = [unique[2],unique[3]]
	low.sort_custom(func(a,b): return a.z<b.z);high.sort_custom(func(a,b): return a.z<b.z)
	return low[0].lerp(low[1],.35).lerp(high[0].lerp(high[1],.35),.45)

static func points(pose: String, width: float, height: float, window: Variant = null) -> Array[Vector3]:
	var anchor: Vector3 = window if window is Vector3 else Vector3(width-.28,height*.78,.12)
	return [anchor+Vector3(-.14,0,0),anchor+Vector3(.38,-.035,0),anchor+Vector3(.86,-.035,0) if pose=="extended" else anchor+Vector3(.38,.445,0)]

static func make(pose: String, width: float, height: float, window: Variant = null) -> DriverSignal:
	var root := DriverSignal.new()
	root.name = "driver_signal"
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("e8b18d")
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color("42648a")
	var p := points(pose,width,height,window)
	root.segment(p[0],p[0].lerp(p[1],.42),.075,sleeve)
	root.segment(p[0].lerp(p[1],.4),p[1],.06,skin)
	root.segment(p[1],p[2],.05,skin)
	var direction := (p[2]-p[1]).normalized()
	var across := Vector3.BACK
	var tip := p[2]+direction*.13
	root.segment(p[2],tip,.062,skin)
	for i in 4:
		var start := tip+across*(i-1.5)*.029
		root.segment(start,start+direction*(.11-absf(i-1.5)*.017),.014,skin)
	var thumb := p[2]+direction*.05
	root.segment(thumb,thumb+across*.1+direction*.04,.022,skin)
	return root

func segment(a: Vector3,b: Vector3,radius: float,material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=a.distance_to(b);mesh.radial_segments=10
	var node := MeshInstance3D.new()
	node.mesh=mesh;node.material_override=material
	node.position=(a+b)*.5
	var direction := (b-a).normalized()
	var axis := Vector3.UP.cross(direction)
	if axis.length_squared()>.000001: node.quaternion=Quaternion(axis.normalized(),Vector3.UP.angle_to(direction))
	elif direction.y<0: node.rotation.x=PI
	add_child(node)

func retract() -> void:
	if has_meta("retracting"): return
	set_meta("retracting",true)
	var motion := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(self,"position",Vector3(-.6,-.3,0),.35)
	motion.tween_property(self,"scale",Vector3.ONE*.01,.35)
	motion.chain().tween_callback(hide)
