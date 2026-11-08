## Authentic 3D Traffic Police Officer (Регулировщик ДПС) for Godot.
## Three cached lightweight meshes; uniforms, face and baton use vertex colours.
class_name RegulatorOfficer
extends Node3D

var left_arm_pivot: Node3D
var right_arm_pivot: Node3D
var body_root: Node3D

var cur_gesture := RegulatorRules.Gesture.RIGHT_ARM_FORWARD
var cur_approach := RegulatorRules.Approach.LEFT

var target_left_arm := Vector3.ZERO
var target_right_arm := Vector3.ZERO
var cur_left_arm := Vector3.ZERO
var cur_right_arm := Vector3.ZERO

var target_body_yaw := 0.0
var cur_body_yaw := 0.0


func _init() -> void:
	_build_model()


func _ready() -> void:
	set_pose(cur_gesture, false)
	set_approach(cur_approach, false)


func set_pose(gesture: RegulatorRules.Gesture, animated := true) -> void:
	cur_gesture = gesture
	match gesture:
		RegulatorRules.Gesture.HANDS_DOWN:
			target_left_arm = Vector3.ZERO
			target_right_arm = Vector3.ZERO
		RegulatorRules.Gesture.HANDS_SIDES:
			target_left_arm = Vector3(0, 0, PI * 0.5)
			target_right_arm = Vector3(0, 0, -PI * 0.5)
		RegulatorRules.Gesture.RIGHT_ARM_FORWARD:
			target_left_arm = Vector3.ZERO
			target_right_arm = Vector3(-PI * 0.5, 0, 0)
		RegulatorRules.Gesture.ARM_UP:
			target_left_arm = Vector3.ZERO
			target_right_arm = Vector3(0, 0, PI)
	if not animated:
		cur_left_arm = target_left_arm
		cur_right_arm = target_right_arm
		if left_arm_pivot: left_arm_pivot.rotation = cur_left_arm
		if right_arm_pivot: right_arm_pivot.rotation = cur_right_arm


func set_approach(approach: RegulatorRules.Approach, animated := true) -> void:
	cur_approach = approach
	match approach:
		RegulatorRules.Approach.FRONT:
			target_body_yaw = 0.0
		RegulatorRules.Approach.BACK:
			target_body_yaw = PI
		RegulatorRules.Approach.LEFT:
			target_body_yaw = -PI * 0.5
		RegulatorRules.Approach.RIGHT:
			target_body_yaw = PI * 0.5
	if not animated:
		cur_body_yaw = target_body_yaw
		if body_root: body_root.rotation.y = cur_body_yaw


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-12.0 * delta)

	# Interpolate arm rotations
	cur_left_arm = cur_left_arm.lerp(target_left_arm, blend)
	cur_right_arm = cur_right_arm.lerp(target_right_arm, blend)
	if left_arm_pivot: left_arm_pivot.rotation = cur_left_arm
	if right_arm_pivot: right_arm_pivot.rotation = cur_right_arm

	# Interpolate body orientation
	var diff := fposmod(target_body_yaw - cur_body_yaw + PI, TAU) - PI
	cur_body_yaw += diff * blend
	if body_root: body_root.rotation.y = cur_body_yaw


func _build_model() -> void:
	body_root = Node3D.new()
	body_root.name = "BodyRoot"
	add_child(body_root)
	body_root.add_child(_part("body"))
	# Facing +Z: anatomical RIGHT is -X. Preserve the tested shoulder pivots
	# and rotation axes for all four signals in both games.
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArm"
	left_arm_pivot.position = Vector3(0.32, 1.5, 0)
	left_arm_pivot.add_child(_part("left_arm"))
	body_root.add_child(left_arm_pivot)
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArm"
	right_arm_pivot.position = Vector3(-0.32, 1.5, 0)
	right_arm_pivot.add_child(_part("right_arm"))
	body_root.add_child(right_arm_pivot)


static var _officer_material: ShaderMaterial

static func officer_material() -> ShaderMaterial:
	if _officer_material == null:
		_officer_material = ShaderMaterial.new()
		_officer_material.shader = load("res://shaders/officer.gdshader")
	return _officer_material


## Clothing, face and baton bands are baked vertex colours, one surface per part.
## Only the two shoulder pivots move; there is no skeleton or per-detail node.
func _part(part: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = part
	node.mesh = Models.mesh_of("res://models/people/officer_%s.glb" % part)
	node.material_override = officer_material()
	return node

