## Canonical signal geometry, independent sections, original mast/main aperture anchors.
class_name TrafficSignal
extends RefCounted

static var _body: StandardMaterial3D
static var _materials := {}
static var _scenes := {}
static var _mini_bodies := {}
const VEHICLE := {
	"red": [Color("#FF3838"),Color("#351719")],
	"yellow": [Color("#FFD52A"),Color("#352D14")],
	"green": [Color("#36FF88"),Color("#123126")],
	"arrow": [Color("#36FF88"),Color("#123126")],
}
const TRAM := ["bottom","mid","left","right"]

static func supports(config: Dictionary) -> bool:
	return str(config.get("arrow", "") if config.get("arrow") != null else "") in ["","left","right","straight"]

static func kind(config: Dictionary) -> String:
	if config.get("tram"): return "tram"
	var a := str(config.get("arrow", ""))
	if a != "" and a != "none": return a
	return "standard"

static func make(config: Dictionary) -> Node3D:
	var variant:=kind(config)
	if not _scenes.has(variant): _scenes[variant]=load("res://models/street/traffic_light_%s.glb" % variant)
	var node: Node3D=_scenes[variant].instantiate()
	node.set_meta("traffic_signal",true)
	node.set_meta("arrow_active",bool(config.get("arrowActive",true)))
	if _body==null:
		_body=StandardMaterial3D.new()
		_body.vertex_color_use_as_albedo=true
		_body.roughness=.85
		_body.metallic_specular=0
	for mesh: MeshInstance3D in node.find_children("body","MeshInstance3D",true,false):
		mesh.material_override=_body
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_state(node,"red",str(config.get("tram","straight")))
	return node

## Same source, retaining the mini-game's original mast and aperture centres.
static func make_mini(config: Dictionary) -> Node3D:
	var values:=config.duplicate()
	values.arrowActive=bool(config.get("arrowActive",false))
	var node:=make(values)
	var variant:=kind(values)
	if variant=="tram":return node
	var body:=node.find_child("body",true,false) as MeshInstance3D
	if not _mini_bodies.has(variant):
		var arrays:=body.mesh.surface_get_arrays(0)
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL].duplicate()
		var roles: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
		for i in points.size():
			var scale:=Vector3.ONE
			if roles[i].x<1.5:
				scale.y=4.6/4.2
				points[i].y*=scale.y
			elif roles[i].x<2.5:
				scale=Vector3(.68/.65,.52/.45,.38/.4)
				points[i]=Vector3(points[i].x*scale.x,3.5+(points[i].y-3.4)*scale.y,.22+(points[i].z-.25)*scale.z)
			else:
				scale=Vector3(.56/.64,.56/.64,.34/.4)
				var side: float=-1 if variant=="left" else 1
				points[i]=Vector3(side*.62+(points[i].x-side*.70)*scale.x,2.98+(points[i].y-2.95)*scale.y,.22+(points[i].z-.25)*scale.z)
			normals[i]=(normals[i]/scale).normalized()
		arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals
		var importer:=ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},_body)
		importer.generate_lods(60,25,[])
		_mini_bodies[variant]=importer.get_mesh()
	body.mesh=_mini_bodies[variant]
	for lamp: Node3D in node.find_children("lamp_*","Node3D",true,false):
		var name:=str(lamp.name)
		lamp.position=Vector3(0,4.02 if name=="lamp_red" else 3.5 if name=="lamp_yellow" else 2.98,.42)
		lamp.scale=Vector3(.20/.21,.20/.21,1)
		if name=="lamp_arrow":
			lamp.position=Vector3(-.62 if variant=="left" else .62,2.98,.40)
			lamp.scale=Vector3(.18/.21,.18/.21,1)
	var state:=str(config.get("state","red"))
	node.set_meta("mini_flashing",state=="flashing_yellow")
	set_state(node,state)
	return node

static func lens_material(name: String,lit: bool) -> ShaderMaterial:
	var key:=name+str(lit)
	if not _materials.has(key):
		var palette: Array=VEHICLE.get(name,[Color("#F0F6FF"),Color("#20252C")])
		var material:=ShaderMaterial.new()
		material.shader=preload("res://shaders/traffic_lens.gdshader")
		material.set_shader_parameter("lamp_colour",palette[0])
		material.set_shader_parameter("dark_colour",palette[1])
		material.set_shader_parameter("lit",lit)
		_materials[key]=material
	return _materials[key]

static func in_assembly(root: Node3D) -> Node3D:
	if root.has_meta("traffic_signal"): return root
	for child: Node3D in root.find_children("*","Node3D",true,false):
		if child.has_meta("traffic_signal"): return child
	return null

static func set_state(node: Node3D,state: String,tram: String="straight",flash_on := true) -> void:
	if tram not in ["straight","left","right","stop","all","off"]: tram="straight"
	for lamp: Node3D in node.find_children("lamp_*","Node3D",true,false):
		var name:=str(lamp.name).trim_prefix("lamp_")
		var on:=false
		if name.begins_with("tram_"):
			var role:=name.trim_prefix("tram_")
			on=(role in ["bottom","mid"] if tram=="straight" else role in ["bottom","left"] if tram=="left" else role in ["bottom","right"] if tram=="right" else role!="bottom" if tram=="stop" else tram=="all")
		else:
			on=bool(node.get_meta("arrow_active",true)) if name=="arrow" else state==name or (name=="yellow" and state=="flashing_yellow")
			if state=="flashing_yellow" and name=="yellow": on=flash_on
		for aperture: MeshInstance3D in lamp.find_children("aperture_*","MeshInstance3D",true,false):
			aperture.material_override=lens_material(name,on)
			aperture.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not lamp.has_meta("halo"):
			var palette: Array=VEHICLE.get(name,[Color("#F0F6FF")])
			var halo:=Glow.halo(palette[0],.55 if name.begins_with("tram_") else .70,true)
			# A sideways supplementary aperture uses its arrow glyph, without round bloom.
			if name=="arrow": halo.visible=false
			lamp.add_child(halo)
			lamp.set_meta("halo",halo)
		(lamp.get_meta("halo") as Node3D).visible=on and name!="arrow"
