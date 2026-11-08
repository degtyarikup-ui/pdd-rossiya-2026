extends "res://videos/crossroads_reel/regulator_sides.gd"

## Episode 021. No signals. The officer faces south with his right arm
## stretched forward (south). Blue (east) is at his left side and may go;
## red (west) is at his right side and must wait (6.10).

func _build_traffic_lights() -> void:pass

func _build_actors() -> void:
	super._build_actors()
	officer.set_pose(RegulatorRules.Gesture.RIGHT_ARM_FORWARD,false)
	officer.set_approach(RegulatorRules.Approach.FRONT,false)

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(-D+distance,0,L))
	return super._pose_car(i,distance)

func _chest_camera() -> void:
	# From red's side (west): his right flank, the arm pointing forward to the south.
	_camera(Vector3(-9.0,2.2,3.4),Vector3(0,1.4,.4),36)
