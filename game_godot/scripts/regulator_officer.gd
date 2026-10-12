## Authentic 3D Traffic Police Officer (Регулировщик ДПС) for Godot.
## Models anatomically correct posture, uniforms, gestures and baton.
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

	# Materials
	var dark_uniform := StandardMaterial3D.new()
	dark_uniform.albedo_color = Color("#1E293B")
	dark_uniform.roughness = 0.8

	var vest_lime := StandardMaterial3D.new()
	vest_lime.albedo_color = Color("#84CC16")
	vest_lime.roughness = 0.5

	var stripe_silver := StandardMaterial3D.new()
	stripe_silver.albedo_color = Color("#F1F5F9")
	stripe_silver.roughness = 0.3

	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color("#E2A76F")
	skin_mat.roughness = 0.7

	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color("#0F172A")
	cap_mat.roughness = 0.7

	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color("#FFFFFF")

	var black_mat := StandardMaterial3D.new()
	black_mat.albedo_color = Color("#111827")
	black_mat.roughness = 0.4

	var hair_mat := StandardMaterial3D.new()
	hair_mat.albedo_color = Color("#2E1B14")

	var cockade_mat := StandardMaterial3D.new()
	cockade_mat.albedo_color = Color("#F59E0B")
	cockade_mat.emission_enabled = true
	cockade_mat.emission = Color("#F59E0B") * 0.3

	var eye_iris_mat := StandardMaterial3D.new()
	eye_iris_mat.albedo_color = Color("#102A45")

	var lip_mat := StandardMaterial3D.new()
	lip_mat.albedo_color = Color("#9B4D3C")

	# Boots
	for x in [-0.14, 0.14]:
		var boot := _box(Vector3(0.18, 0.16, 0.32), black_mat)
		boot.position = Vector3(x, 0.08, 0.04)
		body_root.add_child(boot)

	# Legs
	for x in [-0.14, 0.14]:
		var leg := _cylinder(0.1, 0.11, 0.85, dark_uniform)
		leg.position = Vector3(x, 0.58, 0.0)
		body_root.add_child(leg)

	# Torso with high-visibility vest
	var torso := _box(Vector3(0.5, 0.65, 0.3), vest_lime)
	torso.position = Vector3(0.0, 1.28, 0.0)
	body_root.add_child(torso)

	# Horizontal reflective stripe
	var h_stripe := _box(Vector3(0.52, 0.08, 0.32), stripe_silver)
	h_stripe.position = Vector3(0.0, 1.18, 0.0)
	body_root.add_child(h_stripe)

	# Vertical reflective stripes
	for x in [-0.15, 0.15]:
		var v_stripe := _box(Vector3(0.06, 0.45, 0.32), stripe_silver)
		v_stripe.position = Vector3(x, 1.38, 0.0)
		body_root.add_child(v_stripe)

	# Neck & Shirt Collar
	var neck := _cylinder(0.075, 0.085, 0.12, skin_mat)
	neck.position = Vector3(0.0, 1.62, 0.0)
	body_root.add_child(neck)

	for x in [-0.055, 0.055]:
		var collar := _box(Vector3(0.065, 0.042, 0.024), white_mat)
		collar.position = Vector3(x, 1.58, 0.148)
		collar.rotation.z = 0.38 if x < 0 else -0.38
		body_root.add_child(collar)

	var tie := _box(Vector3(0.045, 0.13, 0.018), dark_uniform)
	tie.position = Vector3(0.0, 1.52, 0.152)
	body_root.add_child(tie)

	# Head base
	var head := _box(Vector3(0.24, 0.26, 0.24), skin_mat)
	head.position = Vector3(0.0, 1.73, 0.0)
	body_root.add_child(head)

	# Eyes
	for x in [-0.056, 0.056]:
		var sclera := _box(Vector3(0.052, 0.030, 0.012), white_mat)
		sclera.position = Vector3(x, 1.745, 0.124)
		body_root.add_child(sclera)

		var pupil := _box(Vector3(0.028, 0.028, 0.010), eye_iris_mat)
		pupil.position = Vector3(x, 1.745, 0.129)
		body_root.add_child(pupil)

		var glint := _box(Vector3(0.010, 0.010, 0.008), white_mat)
		glint.position = Vector3(x + 0.007, 1.753, 0.133)
		body_root.add_child(glint)

		var brow := _box(Vector3(0.060, 0.016, 0.018), hair_mat)
		brow.position = Vector3(x, 1.776, 0.127)
		brow.rotation.z = -0.08 if x < 0 else 0.08
		body_root.add_child(brow)

	# Nose
	var nose := _box(Vector3(0.038, 0.056, 0.042), skin_mat)
	nose.position = Vector3(0.0, 1.705, 0.138)
	body_root.add_child(nose)

	# Mouth & Lips
	var lips := _box(Vector3(0.070, 0.018, 0.016), lip_mat)
	lips.position = Vector3(0.0, 1.644, 0.125)
	body_root.add_child(lips)

	# Chin
	var chin := _box(Vector3(0.090, 0.032, 0.024), skin_mat)
	chin.position = Vector3(0.0, 1.612, 0.125)
	body_root.add_child(chin)

	# Ears
	for x in [-0.124, 0.124]:
		var ear := _box(Vector3(0.016, 0.052, 0.032), skin_mat)
		ear.position = Vector3(x, 1.722, -0.015)
		body_root.add_child(ear)

	# Hair
	for x in [-0.122, 0.122]:
		var sideburn := _box(Vector3(0.012, 0.055, 0.032), hair_mat)
		sideburn.position = Vector3(x, 1.762, 0.030)
		body_root.add_child(sideburn)

	var fringe := _box(Vector3(0.18, 0.018, 0.012), hair_mat)
	fringe.position = Vector3(0.0, 1.822, 0.122)
	body_root.add_child(fringe)

	# Police Cap
	var cap_band := _cylinder(0.15, 0.15, 0.08, cap_mat)
	cap_band.position = Vector3(0.0, 1.86, 0.0)
	body_root.add_child(cap_band)

	var cap_crown := _cylinder(0.18, 0.15, 0.06, cap_mat)
	cap_crown.position = Vector3(0.0, 1.92, 0.0)
	body_root.add_child(cap_crown)

	var visor := _box(Vector3(0.22, 0.02, 0.14), black_mat)
	visor.position = Vector3(0.0, 1.84, 0.18)
	visor.rotation.x = 0.2
	body_root.add_child(visor)

	var cockade := _box(Vector3(0.055, 0.065, 0.025), cockade_mat)
	cockade.position = Vector3(0.0, 1.88, 0.155)
	body_root.add_child(cockade)

	# Left and Right Arm Pivots
	# The officer faces +Z: anatomical RIGHT is -X, LEFT is +X.
	left_arm_pivot = _make_arm(0.32, dark_uniform, stripe_silver, white_mat)
	body_root.add_child(left_arm_pivot)

	right_arm_pivot = _make_arm(-0.32, dark_uniform, stripe_silver, white_mat)
	body_root.add_child(right_arm_pivot)

	# Police Baton attached to right hand
	var baton := Node3D.new()
	baton.name = "Baton"
	var shaft := _cylinder(0.025, 0.025, 0.44, white_mat)
	shaft.position.y = -0.8
	baton.add_child(shaft)

	for i in range(3):
		var ring := _cylinder(0.026, 0.026, 0.07, black_mat)
		ring.position.y = -0.65 - i * 0.12
		baton.add_child(ring)

	right_arm_pivot.add_child(baton)


func _make_arm(x: float, sleeve_mat: Material, cuff_mat: Material, hand_mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 1.5, 0.0)

	var sleeve := _cylinder(0.065, 0.055, 0.5, sleeve_mat)
	sleeve.position.y = -0.25
	pivot.add_child(sleeve)

	var cuff := _cylinder(0.06, 0.06, 0.055, cuff_mat)
	cuff.position.y = -0.44
	pivot.add_child(cuff)

	var hand := _box(Vector3(0.085, 0.1, 0.085), hand_mat)
	hand.position.y = -0.54
	pivot.add_child(hand)

	return pivot


func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	m.mesh = box
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return m


func _cylinder(top: float, bottom: float, height: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top
	cyl.bottom_radius = bottom
	cyl.height = height
	cyl.radial_segments = 12
	cyl.material = mat
	m.mesh = cyl
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return m
