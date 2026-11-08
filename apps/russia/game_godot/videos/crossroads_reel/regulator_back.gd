extends "res://videos/crossroads_reel/regulator_sides.gd"

## Episode 037. Signals are off; the officer holds both arms out to the sides,
## chest to the north. Red (south) faces his back and must stop; blue (east)
## is at his side and goes straight (6.10).

func _build_traffic_lights() -> void:pass

func _build_actors() -> void:
	super._build_actors()
	officer.set_pose(RegulatorRules.Gesture.HANDS_SIDES,false)
	# BACK = model turned to face −Z: chest north, back towards red.
	officer.set_approach(RegulatorRules.Approach.BACK,false)
