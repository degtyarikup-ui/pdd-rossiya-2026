## A driver's arm outside the left window. Vehicle-local +X is left.
class_name DriverSignal
extends Node3D

static func supports(kind: String) -> bool:
	return kind in ["car","truck","bus","van","tanker","special"]

static func points(pose: String, width: float, height: float) -> Array[Vector3]:
	return [Vector3(width-.16,height*.69,.35),Vector3(width+.32,height*.7,.35),Vector3(width+.8,height*.7,.35) if pose=="extended" else Vector3(width+.32,height*.7+.48,.35)]

static func make(pose: String, width: float, height: float) -> DriverSignal:
	var root := DriverSignal.new()
	root.name = "driver_signal"
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("e8b18d")
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color("42648a")
	var p := points(pose,width,height)
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
