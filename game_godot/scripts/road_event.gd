## One road question on the straight street (game_godot/roads/road_scenes.json, kind "speed"):
## the road signs beside the carriageway and the stop mark before them. The world (world.gd)
## asks the question at the stop mark and applies the zone's limit between its sign and end sign.
class_name RoadEvent
extends Node3D

const SIGN_WIDTH := 0.8       # m, the face of a road sign
const SIGN_TOP := 2.4         # m, the top of the pole

var id := ""
var entry: Dictionary         # the road_scenes.json entry: question, options, scene
var stop_z := 0.0             # the car stops here for the question
var limit_z := 0.0            # the zone's limit applies past this point (its first sign)
var end_sign_z := 0.0         # the zone's limit ends past this point (its end sign)
var end_z := 0.0              # the zone's stretch ends here
var limit_kmh := 0            # the zone's limit in km/h


## `z` is the stop mark, `half` the carriageway half-width at it.
static func make(item: Dictionary, z: float, half: float) -> RoadEvent:
	var ev := RoadEvent.new()
	ev.id = str(item.id)
	ev.entry = item
	ev.stop_z = z
	var sc: Dictionary = item.scene
	ev.limit_kmh = int(sc.get("limitKmH", 0))
	ev.end_z = z + float(sc.get("zoneLength", 0))
	ev.end_sign_z = ev.end_z - 6.0
	ev.limit_z = z + 12.0
	for sg in sc.get("signs", []):
		var at := z + float(sg.z)
		if float(sg.z) >= 0.0:
			ev.limit_z = at
			break
	for sg in sc.get("signs", []):
		ev._sign(str(sg.code), z + float(sg.z), str(sg.get("side", "right")), half)
	if sc.get("endSign") != null:
		ev._sign(str(sc.endSign), ev.end_sign_z, "right", half)
	return ev


## The text the question card shows: the question, its answers and the explanation.
func question_text() -> Dictionary:
	return { "id": id, "ticket": entry.ticket, "title": entry.title, "options": entry.options,
		"explanation": entry.get("explanation", ""), "pddRule": entry.get("pddRule", "") }


## Characters of the question, for the answer time (as for junction questions).
func text_length() -> int:
	var n: int = str(entry.title).length()
	for opt in entry.options:
		n += str(opt).length()
	return n


func _sign(code: String, z: float, side: String, half: float) -> void:
	var tex := load("res://signs/%s.svg" % code) as Texture2D
	if tex == null:
		push_warning("no picture for road sign %s" % code)
		return
	# The driver's right is -X; a sign stands beside the carriageway on its side.
	var x := -(half + 1.6) if side == "right" else half + 1.6
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#7A7F87")
	steel.roughness = 0.6
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = SIGN_TOP
	pole.mesh = cyl
	pole.material_override = steel
	pole.position = Vector3(x, SIGN_TOP * 0.5, z)
	add_child(pole)
	var h := SIGN_WIDTH * float(tex.get_height()) / float(tex.get_width())
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(SIGN_WIDTH, h)
	face.mesh = quad
	face.position = Vector3(x, SIGN_TOP - h * 0.5, z)
	# The face looks back at the oncoming driver (who drives towards +Z).
	face.rotation.y = PI
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	face.material_override = mat
	add_child(face)
